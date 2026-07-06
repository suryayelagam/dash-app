// Tasks — native to-do list on Apple Reminders (EventKit).
// Zero accounts, syncs with Siri/watch/family shared lists.
import SwiftUI
import EventKit

struct TaskItem: Identifiable {
    let id: String
    var title: String
    var done: Bool
    var due: Date?
    let reminder: EKReminder
}

@MainActor
final class TasksStore: ObservableObject {
    private let store = EKEventStore()
    @Published var items: [TaskItem] = []
    @Published var denied = false

    func load() async {
        do {
            let ok = try await store.requestFullAccessToReminders()
            guard ok else { denied = true; return }
            let cal = store.defaultCalendarForNewReminders()
            let predicate = store.predicateForIncompleteReminders(
                withDueDateStarting: nil, ending: nil,
                calendars: cal.map { [$0] })
            let reminders: [EKReminder] = await withCheckedContinuation { cont in
                store.fetchReminders(matching: predicate) { cont.resume(returning: $0 ?? []) }
            }
            items = reminders.map {
                TaskItem(id: $0.calendarItemIdentifier, title: $0.title ?? "",
                         done: $0.isCompleted, due: $0.dueDateComponents?.date, reminder: $0)
            }.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
        } catch { denied = true }
    }

    func add(_ title: String) {
        let r = EKReminder(eventStore: store)
        r.title = title
        r.calendar = store.defaultCalendarForNewReminders()
        try? store.save(r, commit: true)
        Task { await load() }
    }

    func toggle(_ item: TaskItem) {
        item.reminder.isCompleted.toggle()
        try? store.save(item.reminder, commit: true)
        Task { await load() }
    }
}

struct TasksView: View {
    @StateObject private var store = TasksStore()
    @State private var newTask = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Add a task…", text: $newTask)
                            .onSubmit { submit() }
                        Button { submit() } label: { Image(systemName: "plus.circle.fill") }
                            .disabled(newTask.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                Section {
                    if store.denied {
                        Text("Allow Reminders access in Settings → Dash.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.items) { item in
                        Button { store.toggle(item) } label: {
                            HStack {
                                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(item.done ? .green : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).foregroundStyle(.primary)
                                    if let due = item.due {
                                        Text(due, style: .date)
                                            .font(.caption)
                                            .foregroundStyle(due < Date() ? .red : .secondary)
                                    }
                                }
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Tasks")
            .refreshable { await store.load() }
            .task { await store.load() }
        }
    }

    private func submit() {
        let t = newTask.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        store.add(t)
        newTask = ""
    }
}
