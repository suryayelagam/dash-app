// Skyview — a tiny native shell for Home Assistant that grants the sensor
// permissions Apple gates behind an app-side callback (compass/orientation),
// so the flights "point me at the plane" finder works in-app.
import SwiftUI
import WebKit

@main
struct SkyviewApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    @AppStorage("haURL") private var haURL = "http://homeassistant.local:8123"
    @State private var showSettings = false
    @State private var webView: WKWebView? = nil

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            HAWebView(urlString: haURL, webView: $webView)
                .ignoresSafeArea(edges: .bottom)
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary.opacity(0.55))
                    .padding(10)
            }
            .padding(.trailing, 6)
            .padding(.bottom, 2)
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(haURL: $haURL) {
                if let url = URL(string: haURL) { webView?.load(URLRequest(url: url)) }
            }
            .presentationDetents([.height(260)])
        }
        .statusBarHidden(false)
    }
}

struct SettingsSheet: View {
    @Binding var haURL: String
    var onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

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
                    Button("Save & Reload") { onSave(); dismiss() }
                        .bold()
                }
            }
            .navigationTitle("Skyview")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct HAWebView: UIViewRepresentable {
    let urlString: String
    @Binding var webView: WKWebView?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        // persistent store: HA login + tokens survive relaunches
        config.websiteDataStore = .default()

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.uiDelegate = context.coordinator
        wv.navigationDelegate = context.coordinator
        wv.allowsBackForwardNavigationGestures = true
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        wv.isOpaque = false
        wv.backgroundColor = .systemBackground

        let refresh = UIRefreshControl()
        refresh.addTarget(context.coordinator, action: #selector(Coordinator.refresh(_:)), for: .valueChanged)
        wv.scrollView.refreshControl = refresh

        if let url = URL(string: urlString) { wv.load(URLRequest(url: url)) }
        DispatchQueue.main.async { webView = wv }
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate {
        // THE reason this app exists: grant compass/orientation to the web content.
        func webView(_ webView: WKWebView,
                     requestDeviceOrientationAndMotionPermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(.grant)
        }

        // future-proof: camera/mic for HA features that want them
        func webView(_ webView: WKWebView,
                     requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo,
                     type: WKMediaCaptureType,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(.grant)
        }

        // open target=_blank links in the same webview instead of dropping them
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url { webView.load(URLRequest(url: url)) }
            return nil
        }

        @objc func refresh(_ sender: UIRefreshControl) {
            if let wv = sender.superview?.superview as? WKWebView { wv.reload() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { sender.endRefreshing() }
        }
    }
}
