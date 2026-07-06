// Dash — Surya's all-in-one life-admin app.
// Home = full Home Assistant · Sky = flights map with NATIVE compass bridge
// (web DeviceOrientation needs HTTPS; native CoreMotion/CoreLocation doesn't)
// · Tasks = Apple Reminders.
import SwiftUI

@main
struct DashApp: App {
    @StateObject private var motion = MotionBridge()
    init() {
        // No HTTP response caching — web-side edits (dashboards, the flights UI)
        // must appear on a refresh, never requiring an app reinstall.
        // Login/cookies/localStorage survive separately via WKWebsiteDataStore.
        URLCache.shared = URLCache(memoryCapacity: 0, diskCapacity: 0, directory: nil)
    }
    var body: some Scene {
        WindowGroup { RootView().environmentObject(motion).onAppear { motion.start() } }
    }
}

struct RootView: View {
    @AppStorage("haURL") private var haURL = "http://homeassistant.local:8123"
    @EnvironmentObject private var motion: MotionBridge

    var body: some View {
        TabView {
            WebTab(urlString: haURL, motion: motion)
                .tabItem { Label("Home", systemImage: "house.fill") }
                .onAppear { motion.start() }
            WebTab(urlString: haURL + "/local/skyview/flights.html", motion: motion)
                .tabItem { Label("Sky", systemImage: "airplane") }
            TasksView()
                .tabItem { Label("Tasks", systemImage: "checklist") }
            SettingsTab(haURL: $haURL)
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
    }
}

struct SettingsTab: View {
    @Binding var haURL: String
    var body: some View {
        NavigationStack {
            Form {
                Section("Home Assistant URL") {
                    TextField("http://homeassistant.local:8123", text: $haURL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                Section {
                    Text("Dash v2.0 · made with Claude for the Yelagam house")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Dash")
        }
    }
}
