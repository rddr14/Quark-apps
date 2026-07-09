import SwiftUI
import WebKit
import UIKit
import CoreLocation

final class WebViewViewModel: NSObject, ObservableObject {
    private var locationManager: CLLocationManager?
    private weak var webView: WKWebView?
    private var injectedLocation = false
    private var didEnterBackgroundAt: Date?

    // Force refresh only after long inactivity to avoid stale data while preserving normal UX.
    private let refreshAfterBackgroundInterval: TimeInterval = 15 * 60

    func attach(webView: WKWebView) {
        self.webView = webView
    }

    func requestLocationPermissionIfNeeded() {
        let manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager = manager

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .restricted, .denied:
            break
        @unknown default:
            break
        }
    }

    func markDidEnterBackground() {
        didEnterBackgroundAt = Date()
    }

    func reloadIfAppWasBackgroundedForLongTime() {
        guard let didEnterBackgroundAt else { return }
        let inactiveTime = Date().timeIntervalSince(didEnterBackgroundAt)
        guard inactiveTime >= refreshAfterBackgroundInterval else { return }

        webView?.reloadFromOrigin()
        self.didEnterBackgroundAt = nil
    }

    private func injectGeolocation(latitude: Double, longitude: Double) {
        guard let webView else { return }
        guard !injectedLocation else { return }

        let js = """
        (function() {
            if (!navigator.geolocation) { return; }

            const fixedPosition = {
                coords: {
                    latitude: \(latitude),
                    longitude: \(longitude),
                    accuracy: 50,
                    altitude: null,
                    altitudeAccuracy: null,
                    heading: null,
                    speed: null
                },
                timestamp: Date.now()
            };

            navigator.geolocation.getCurrentPosition = function(success, error) {
                if (typeof success === 'function') {
                    success(fixedPosition);
                } else if (typeof error === 'function') {
                    error({ code: 2, message: 'No success callback provided.' });
                }
            };

            navigator.geolocation.watchPosition = function(success) {
                if (typeof success === 'function') {
                    success(fixedPosition);
                }
                return 1;
            };

            navigator.geolocation.clearWatch = function() {};
        })();
        """

        webView.evaluateJavaScript(js)
        injectedLocation = true
    }
}

extension WebViewViewModel: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .notDetermined, .restricted, .denied:
            break
        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        injectGeolocation(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    }
}

struct WebViewContainer: UIViewRepresentable {
    let url: URL
    let allowedHost: String
    @ObservedObject var viewModel: WebViewViewModel

    static let processPool = WKProcessPool()

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        HTTPCookieStorage.shared.cookieAcceptPolicy = .always

        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true

        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences = preferences
        config.websiteDataStore = .default()
        config.processPool = Self.processPool

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic

        viewModel.attach(webView: webView)
        viewModel.requestLocationPermissionIfNeeded()
        webView.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy))

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private let parent: WebViewContainer

        init(_ parent: WebViewContainer) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let requestedURL = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            if requestedURL.host?.contains(parent.allowedHost) == true {
                decisionHandler(.allow)
            } else {
                UIApplication.shared.open(requestedURL)
                decisionHandler(.cancel)
            }
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if let response = navigationResponse.response as? HTTPURLResponse, response.statusCode == 419 {
                // Laravel returns 419 when CSRF/session token is stale. Force a clean reload.
                let freshRequest = URLRequest(url: parent.url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
                webView.load(freshRequest)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            webView.reload()
        }
    }
}
