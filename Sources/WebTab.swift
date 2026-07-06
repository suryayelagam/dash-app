// WKWebView tab with the native sensor bridge: pushes compass heading + pitch
// into the page ~8x/sec as window.__nativeOri(headingDeg, pitchDeg).
// The flights page prefers this over the (HTTPS-gated) web sensor API.
import SwiftUI
import WebKit
import CoreMotion
import CoreLocation

final class MotionBridge: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let motion = CMMotionManager()
    private let loc = CLLocationManager()
    private(set) var heading: Double? = nil   // degrees, 0 = true north
    private(set) var pitch: Double? = nil     // degrees, 0 = horizon, +90 = zenith
    private var running = false

    func start() {
        guard !running else { return }
        running = true
        loc.delegate = self
        loc.requestWhenInUseAuthorization()
        loc.headingFilter = 2
        loc.startUpdatingHeading()
        if motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = 1.0 / 15.0
            motion.startDeviceMotionUpdates(to: .main) { [weak self] dm, _ in
                guard let g = dm?.gravity else { return }
                // elevation of the back-camera axis: flat on table = -90, horizon = 0, sky = +90
                self?.pitch = asin(max(-1, min(1, g.z))) * 180 / .pi
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading h: CLHeading) {
        heading = h.trueHeading >= 0 ? h.trueHeading : h.magneticHeading
    }
}

struct WebTab: View {
    let urlString: String
    let motion: MotionBridge
    var body: some View {
        DashWebView(urlString: urlString, motion: motion)
            .ignoresSafeArea(edges: .bottom)
            .onAppear { motion.start() }
    }
}

struct DashWebView: UIViewRepresentable {
    let urlString: String
    let motion: MotionBridge

    func makeCoordinator() -> Coordinator { Coordinator(motion: motion) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.websiteDataStore = .default()   // shared across tabs -> one HA login
        // flag so pages know native sensors exist
        let flag = WKUserScript(source: "window.__dashNative=true;",
                                injectionTime: .atDocumentStart, forMainFrameOnly: false)
        config.userContentController.addUserScript(flag)

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

        if let url = URL(string: urlString) { wv.load(URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData)) }
        context.coordinator.startPushing(into: wv); context.coordinator.armForeground(wv)
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate {
        let motion: MotionBridge
        private var timer: Timer?
        init(motion: MotionBridge) { self.motion = motion }

        weak var web: WKWebView?
        func armForeground(_ wv: WKWebView) {
            web = wv
            NotificationCenter.default.addObserver(self, selector: #selector(fg),
                name: UIApplication.willEnterForegroundNotification, object: nil)
        }
        @objc func fg() { web?.reloadFromOrigin() }
        func startPushing(into wv: WKWebView) {
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak wv, weak self] _ in
                guard let wv, let self, let h = self.motion.heading else { return }
                let p = self.motion.pitch ?? 0
                wv.evaluateJavaScript("window.__nativeOri && window.__nativeOri(\(h),\(p))", completionHandler: nil)
            }
        }

        // still grant web sensor APIs for anything HTTPS (e.g. tunnel URL)
        func webView(_ webView: WKWebView,
                     requestDeviceOrientationAndMotionPermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(.grant)
        }
        func webView(_ webView: WKWebView,
                     requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo,
                     type: WKMediaCaptureType,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(.grant)
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url { webView.load(URLRequest(url: url)) }
            return nil
        }
        @objc func refresh(_ sender: UIRefreshControl) {
            if let wv = sender.superview?.superview as? WKWebView { wv.reloadFromOrigin() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { sender.endRefreshing() }
        }
        deinit { timer?.invalidate() }
    }
}
