import Foundation
import Combine
import Network
import SwiftUI
import UIKit
@preconcurrency import WebKit

final class WebViewStore: NSObject, ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var networkStatus = "检查网络中…"
    @Published private(set) var lastError: String?
    @Published var lastDownloadedURL: URL?

    private weak var webView: WKWebView?
    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "DeepSeekHarness.NetworkMonitor")
    private var currentURL: URL?

    override init() {
        super.init()
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let status: String
            switch path.status {
            case .satisfied:
                status = "网络已连接"
            case .requiresConnection:
                status = "等待网络连接"
            case .unsatisfied:
                status = "网络未连接"
            @unknown default:
                status = "网络状态未知"
            }
            DispatchQueue.main.async {
                self?.networkStatus = status
            }
        }
        pathMonitor.start(queue: monitorQueue)
    }

    deinit {
        pathMonitor.cancel()
    }

    func attach(_ webView: WKWebView) {
        self.webView = webView
        updateNavigationState()
    }

    func load(_ url: URL) {
        guard currentURL != url || webView?.url == nil else { return }
        currentURL = url
        webView?.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy))
    }

    func reload() {
        lastError = nil
        webView?.reload()
    }

    func goBack() {
        webView?.goBack()
    }

    func goForward() {
        webView?.goForward()
    }

    func clearError() {
        lastError = nil
    }

    func didStartLoading() {
        isLoading = true
        lastError = nil
        updateNavigationState()
    }

    func didFinishLoading() {
        isLoading = false
        updateNavigationState()
    }

    func didFail(_ error: Error) {
        isLoading = false
        lastError = error.localizedDescription
        updateNavigationState()
    }

    func updateNavigationState() {
        canGoBack = webView?.canGoBack ?? false
        canGoForward = webView?.canGoForward ?? false
    }
}

struct HarnessWebView: UIViewRepresentable {
    let url: URL
    @ObservedObject var store: WebViewStore

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = false
        store.attach(webView)
        store.load(url)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        store.attach(webView)
        store.load(url)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
        private let store: WebViewStore

        init(store: WebViewStore) {
            self.store = store
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            store.didStartLoading()
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            store.didStartLoading()
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            store.didFinishLoading()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            store.didFail(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            store.didFail(error)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let targetURL = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            guard let scheme = targetURL.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
                decisionHandler(.cancel)
                UIApplication.shared.open(targetURL)
                return
            }

            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            guard let targetURL = navigationAction.request.url else { return nil }
            if navigationAction.targetFrame == nil {
                webView.load(URLRequest(url: targetURL))
            }
            return nil
        }

        @available(iOS 14.0, *)
        func webView(
            _ webView: WKWebView,
            navigationAction: WKNavigationAction,
            didBecome download: WKDownload
        ) {
            download.delegate = self
        }

        @available(iOS 14.0, *)
        func webView(
            _ webView: WKWebView,
            navigationResponse: WKNavigationResponse,
            didBecome download: WKDownload
        ) {
            download.delegate = self
        }

        @available(iOS 14.0, *)
        func download(
            _ download: WKDownload,
            decideDestinationUsing response: URLResponse,
            suggestedFilename: String,
            completionHandler: @escaping (URL?) -> Void
        ) {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let safeName = suggestedFilename.isEmpty ? "Harness-download" : suggestedFilename
            let destination = documents.appendingPathComponent(safeName)
            try? FileManager.default.removeItem(at: destination)
            completionHandler(destination)
        }

        @available(iOS 14.0, *)
        func downloadDidFinish(_ download: WKDownload) {
            // WKDownload does not expose its final URL; the file remains in Documents.
            // A future native downloads screen can enumerate that directory.
        }

        @available(iOS 14.0, *)
        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
            store.didFail(error)
        }
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
