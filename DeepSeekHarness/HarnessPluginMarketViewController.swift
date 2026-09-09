import CryptoKit
import UIKit
import WebKit

/// The only WKWebView container in the application. It is deliberately
/// isolated from native Harness traffic: a non-persistent store and process
/// pool are owned by this controller and are not shared with setup/session UI.
final class HarnessPluginMarketViewController: UIViewController {
    typealias ExternalNavigationHandler = (URL) -> Void
    typealias VerificationHandler = (String) -> Void
    typealias RouteFailureHandler = (String) -> Void

    private let marketURL: URL
    private let marketOrigin: MarketOrigin
    private let externalNavigationHandler: ExternalNavigationHandler
    private let verificationHandler: VerificationHandler?
    private let routeFailureHandler: RouteFailureHandler?
    private let bootstrapClient: MarketBootstrapClient?
    private let webView: WKWebView
    private let configuration: WKWebViewConfiguration
    private let cssBundle: MarketCSSBundle
    private var observation: NSKeyValueObservation?
    private var loadTask: Task<Void, Never>?
    private var hasLoadedDocument = false
    private var lastInjectedPageKey: String?
    private var currentMarketVersion: String?
    private var lastReportedVersion: String?
    private var hasRequestedMarketRoute = false

    init(
        marketURL: URL,
        bootstrapClient: MarketBootstrapClient? = nil,
        externalNavigationHandler: @escaping ExternalNavigationHandler = { url in
            UIApplication.shared.open(url, options: [:])
        },
        verificationHandler: VerificationHandler? = nil,
        routeFailureHandler: RouteFailureHandler? = nil,
        bundle: Bundle = .main
    ) throws {
        guard let origin = MarketOrigin(url: marketURL) else {
            throw MarketMarketError.invalidMarketURL
        }
        let cssBundle: MarketCSSBundle
        do {
            cssBundle = try MarketCSSBundle(bundle: bundle)
        } catch let error as MarketMarketError {
            throw error
        } catch {
            throw MarketMarketError.missingCSSResource
        }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.processPool = WKProcessPool()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        self.marketURL = marketURL
        self.marketOrigin = origin
        self.externalNavigationHandler = externalNavigationHandler
        self.verificationHandler = verificationHandler
        self.routeFailureHandler = routeFailureHandler
        self.bootstrapClient = bootstrapClient
        self.configuration = configuration
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        self.cssBundle = cssBundle
        super.init(nibName: nil, bundle: nil)
        self.webView.navigationDelegate = self
        self.webView.uiDelegate = self
        self.webView.allowsBackForwardNavigationGestures = true
        if #available(iOS 16.4, *) {
            self.webView.isInspectable = false
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        observation?.invalidate()
        loadTask?.cancel()
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "插件市场"
        view.backgroundColor = DHTheme.background
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(close)
        )
        observeDocumentProgress()
        loadMarket()
    }

    /// Copies only same-origin cookies into this controller's non-persistent
    /// WKWebView store. Values never enter source strings, logs or JavaScript.
    func syncSameOriginCookies(_ cookies: [HTTPCookie], completion: (() -> Void)? = nil) {
        let accepted = cookies.filter { cookie in
            let cookieDomain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            let marketHost = marketOrigin.host.lowercased()
            let domainMatches = cookieDomain == marketHost || marketHost.hasSuffix(".\(cookieDomain)")
            let transportMatches = marketOrigin.scheme != "https" || cookie.isSecure
            return domainMatches && transportMatches
        }
        guard !accepted.isEmpty else { completion?(); return }
        configuration.websiteDataStore.httpCookieStore.setCookies(accepted) {
            DispatchQueue.main.async { completion?() }
        }
    }

    func cancelLoading() {
        loadTask?.cancel()
        loadTask = nil
        webView.stopLoading()
    }

    @objc private func close() { dismiss(animated: true) }

    private func loadMarket() {
        cancelLoading()
        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try Task.checkCancellation()
                if let client = self.bootstrapClient {
                    let status = try await client.fetchStatus()
                    switch MarketInstallationPolicy(
                        verifiedPackageVersion: client.verifiedPackageVersion
                    ).decision(for: status) {
                    case .skipInstalledCompatible:
                        break
                    case .installMissing:
                        let response = try await client.install(
                            MarketInstallRequest(version: client.verifiedPackageVersion)
                        )
                        let job = try await client.pollInstallJob(jobID: response.jobID)
                        guard job.state == .succeeded else {
                            throw MarketBootstrapError.transport(
                                job.error?.message ?? job.message ?? "插件市场安装未成功。"
                            )
                        }
                    case .needsDecision:
                        throw MarketBootstrapError.noInstallDecision
                    }
                }
                try Task.checkCancellation()
                self.hasRequestedMarketRoute = false
                self.hasLoadedDocument = false
                self.webView.load(URLRequest(url: self.marketURL))
            } catch is CancellationError {
                return
            } catch {
                self.showError(error.localizedDescription)
            }
        }
    }

    private func observeDocumentProgress() {
        observation = webView.observe(\WKWebView.url, options: [.new]) { [weak self] _, change in
            guard let self, let url = change.newValue as? URL else { return }
            guard self.marketOrigin.matches(url) else { return }
            self.hasLoadedDocument = true
            self.lastInjectedPageKey = nil
        }
    }

    private func routeToPluginMarketIfNeeded() {
        guard hasLoadedDocument, !hasRequestedMarketRoute else { return }
        hasRequestedMarketRoute = true
        evaluateRouteAttempt(remainingAttempts: 50)
    }

    private func evaluateRouteAttempt(remainingAttempts: Int) {
        guard hasLoadedDocument else { return }
        webView.evaluateJavaScript(Self.pluginMarketRouteScript) { [weak self] result, error in
            guard let self else { return }
            if error == nil, let routed = result as? Bool, routed {
                self.verifyPageAndInjectCSS()
                return
            }
            guard remainingAttempts > 0 else {
                self.hasRequestedMarketRoute = false
                self.routeFailureHandler?("未找到插件市场入口，页面路由失败。")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.evaluateRouteAttempt(remainingAttempts: remainingAttempts - 1)
            }
        }
    }

    private func verifyPageAndInjectCSS() {
        webView.evaluateJavaScript(Self.versionDetectionScript) { [weak self] result, _ in
            guard let self else { return }
            let version = result as? String
            self.currentMarketVersion = version
            guard version == MarketBootstrapContract.verifiedPageVersion else {
                self.cssBundle.removeStyles(from: self.webView)
                self.lastInjectedPageKey = nil
                if self.lastReportedVersion != version {
                    self.lastReportedVersion = version
                    self.verificationHandler?(version ?? "未提供版本")
                }
                return
            }
            self.lastReportedVersion = version
            self.injectPageScopedCSS()
        }
    }

    private func injectPageScopedCSS() {
        guard currentMarketVersion == MarketBootstrapContract.verifiedPageVersion else { return }
        let script = cssBundle.injectionScript()
        webView.evaluateJavaScript(script) { [weak self] _, _ in
            guard let self else { return }
            // The page key is maintained by the JS function from real DOM
            // state. This marker is read-only native bookkeeping only.
            self.lastInjectedPageKey = "verified:\(self.currentMarketVersion ?? "")"
        }
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "插件市场", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "知道了", style: .default))
        present(alert, animated: true)
    }

    private static let pluginMarketRouteScript = """
    (() => {
      const stateKey = '__dshMarketNativeRoute';
      const state = window[stateKey] || (window[stateKey] = {
        openedSettings: false,
        clickedMarket: false
      });
      const marketRoot = document.querySelector('.nUhMVa_root');
      const versionNode = document.querySelector('.nUhMVa_version');
      if (state.clickedMarket && (marketRoot || versionNode)) return true;
      if (!state.openedSettings) {
        const trigger = document.querySelector('.VOzbGW_trigger');
        if (!trigger) return false;
        state.openedSettings = true;
        trigger.click();
        return false;
      }
      if (!state.clickedMarket) {
        const button = Array.from(document.querySelectorAll('button')).find(
          node => (node.textContent || '').trim() === '插件市场'
        );
        if (!button) return false;
        state.clickedMarket = true;
        button.click();
        return false;
      }
      return false;
    })()
    """

    private static let versionDetectionScript = """
    (() => {
      const root = document.querySelector('.nUhMVa_root') || document.documentElement;
      const attr = root.getAttribute('data-dsh-market-version')
        || document.documentElement.getAttribute('data-dsh-market-version');
      if (attr && attr.trim()) return attr.trim();
      const versionNode = root.querySelector('.nUhMVa_version');
      return versionNode && typeof versionNode.textContent === 'string'
        ? versionNode.textContent.trim() || null
        : null;
    })()
    """
}

private struct MarketOrigin {
    let scheme: String
    let host: String
    let port: Int?

    init?(url: URL) {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else { return nil }
        self.scheme = scheme
        self.host = host
        self.port = url.port
    }

    func matches(_ url: URL) -> Bool {
        url.scheme?.lowercased() == scheme &&
        url.host?.lowercased() == host.lowercased() &&
        url.port == port
    }
}

enum MarketMarketError: LocalizedError, Equatable {
    case invalidMarketURL
    case missingCSSResource
    case cssIntegrityFailed(resource: String)

    var errorDescription: String? {
        switch self {
        case .invalidMarketURL: return "插件市场地址无效。"
        case .missingCSSResource: return "插件市场样式资源缺失。"
        case let .cssIntegrityFailed(resource): return "插件市场样式完整性校验失败（\(resource)）。"
        }
    }
}

private struct MarketCSSBundle {
    static let expectedBaseHash = "6c7f0f4adb2cd369d96bbed792b36453e7b30cafc340feb18c5f9ac0b3dd62fc"
    static let expectedThemeHash = "1f0866dc2b26325b03781f2c167a9a4b6a66a3d2b3f6d4b3ec3958f5a3f59677"
    static let expectedRenderingHash = "cf20a28838edf915dd851bd520c0cfc620f1d4478fe986fad8fd0473a5f7d1ed"

    let version: String
    let baseCSS: String
    let themeCSS: String
    let renderingCSS: String
    let baseHash: String
    let themeHash: String
    let renderingHash: String

    init(bundle: Bundle) throws {
        let files: [(String, String, String)] = [
            ("market-mobile-v1.41.0", "css", "market-mobile-v1.41.0.css"),
            ("theme-mobile-v1.41.0", "css", "theme-mobile-v1.41.0.css"),
            ("market-rendering-v1.41.0", "css", "market-rendering-v1.41.0.css")
        ]
        guard let baseURL = bundle.url(forResource: files[0].0, withExtension: files[0].1),
              let themeURL = bundle.url(forResource: files[1].0, withExtension: files[1].1),
              let renderingURL = bundle.url(forResource: files[2].0, withExtension: files[2].1),
              let baseCSS = try? String(contentsOf: baseURL, encoding: .utf8),
              let themeCSS = try? String(contentsOf: themeURL, encoding: .utf8),
              let renderingCSS = try? String(contentsOf: renderingURL, encoding: .utf8),
              !baseCSS.isEmpty, !themeCSS.isEmpty, !renderingCSS.isEmpty else {
            throw MarketMarketError.missingCSSResource
        }
        let baseHash = Self.sha256(baseCSS)
        let themeHash = Self.sha256(themeCSS)
        let renderingHash = Self.sha256(renderingCSS)
        guard baseHash == Self.expectedBaseHash else { throw MarketMarketError.cssIntegrityFailed(resource: files[0].2) }
        guard themeHash == Self.expectedThemeHash else { throw MarketMarketError.cssIntegrityFailed(resource: files[1].2) }
        guard renderingHash == Self.expectedRenderingHash else { throw MarketMarketError.cssIntegrityFailed(resource: files[2].2) }
        version = MarketBootstrapContract.verifiedPageVersion
        self.baseCSS = baseCSS
        self.themeCSS = themeCSS
        self.renderingCSS = renderingCSS
        self.baseHash = baseHash
        self.themeHash = themeHash
        self.renderingHash = renderingHash
    }

    /// The script contains no URL, Cookie, token or message bridge. Every
    /// Swift string becomes a JSON string literal, so quotes/newlines/backslash
    /// in CSS cannot break out of the JavaScript source.
    func injectionScript() -> String {
        let base = Self.javascriptStringLiteral(baseCSS)
        let theme = Self.javascriptStringLiteral(themeCSS)
        let rendering = Self.javascriptStringLiteral(renderingCSS)
        let version = Self.javascriptStringLiteral(version)
        return """
        (() => {
          const verifiedVersion = \(version);
          const baseCSS = \(base);
          const themeCSS = \(theme);
          const renderingCSS = \(rendering);
          const root = document.querySelector('.nUhMVa_root') || document.documentElement;
          const versionFromDOM = () => {
            const attr = root.getAttribute('data-dsh-market-version')
              || document.documentElement.getAttribute('data-dsh-market-version');
            if (attr && attr.trim()) return attr.trim();
            const node = root.querySelector('.nUhMVa_version');
            return node && typeof node.textContent === 'string'
              ? node.textContent.trim() || null
              : null;
          };
          const activeTabText = () => {
            const active = root.querySelector(
              '.nUhMVa_tab[aria-selected="true"], .nUhMVa_tab.active, .nUhMVa_tab._active'
            );
            return active ? (active.textContent || '').trim().toLowerCase() : '';
          };
          const pageKey = () => {
            const themeCard = !!root.querySelector('.nUhMVa_themeCard');
            const tabText = activeTabText();
            const themeTab = themeCard || /theme|主题|主题库/.test(tabText);
            const diagnostic = !!root.querySelector('.nUhMVa_diag, .nUhMVa_diagnostics');
            const operationPanel = !!root.querySelector('.nUhMVa_opPanel');
            return [tabText, themeTab ? 'theme' : 'base', diagnostic ? 'diag' : 'normal', operationPanel ? 'op' : 'no-op'].join(':');
          };
          const remove = (slot) => root.ownerDocument.querySelectorAll('style[data-dsh-market-css="' + slot + '"]').forEach(node => node.remove());
          const add = (slot, css) => {
            if (root.ownerDocument.querySelector('style[data-dsh-market-css="' + slot + '"]')) return;
            const node = root.ownerDocument.createElement('style');
            node.setAttribute('data-dsh-market-css', slot);
            node.textContent = css;
            root.ownerDocument.head.appendChild(node);
          };
          const apply = () => {
            if (versionFromDOM() !== verifiedVersion) {
              root.ownerDocument.querySelectorAll('style[data-dsh-market-css]').forEach(node => node.remove());
              return;
            }
            add('base', baseCSS);
            add('rendering', renderingCSS);
            if (pageKey().split(':')[1] === 'theme') add('theme', themeCSS);
            else remove('theme');
            root.setAttribute('data-dsh-market-css-page', pageKey());
            root.setAttribute('data-dsh-market-css-version', verifiedVersion);
          };
          apply();
          if (!root.__dshMarketObserver) {
            let scheduled = false;
            const schedule = () => {
              if (scheduled) return;
              scheduled = true;
              root.ownerDocument.defaultView.requestAnimationFrame(() => { scheduled = false; apply(); });
            };
            const relevant = (record) => {
              if (record.target && record.target.closest && record.target.closest('style[data-dsh-market-css]')) return false;
              if (record.type === 'characterData') return true;
              return Array.from(record.addedNodes || []).some(node => node.nodeType !== 1 || node.tagName !== 'STYLE')
                || Array.from(record.removedNodes || []).some(node => node.nodeType !== 1 || node.tagName !== 'STYLE');
            };
            const observer = new MutationObserver(records => { if (records.some(relevant)) schedule(); });
            const observed = [root.ownerDocument.documentElement, root.ownerDocument.head, root.ownerDocument.body]
              .filter((node, index, values) => node && values.indexOf(node) === index);
            observed.forEach(node => observer.observe(node, { childList: true, subtree: true, characterData: true }));
            root.__dshMarketObserver = observer;
          }
        })();
        """
    }

    func removeStyles(from webView: WKWebView) {
        webView.evaluateJavaScript("document.querySelectorAll('style[data-dsh-market-css]').forEach(node => node.remove()); document.documentElement.removeAttribute('data-dsh-market-css-version'); document.documentElement.removeAttribute('data-dsh-market-css-page');")
    }

    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func javascriptStringLiteral(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
              let literal = String(data: data, encoding: .utf8) else { return "\"\"" }
        return literal
    }
}

extension HarnessPluginMarketViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if marketOrigin.matches(url) {
            decisionHandler(.allow)
            return
        }
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.user == nil, url.password == nil else {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.cancel)
        externalNavigationHandler(url)
    }

    @available(iOS 14.0, *)
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(.allow)
    }

    @available(iOS 14.5, *)
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
        download.cancel()
        showError("下载已拦截：请在系统浏览器中打开外部下载链接。")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        hasLoadedDocument = true
        lastInjectedPageKey = nil
        routeToPluginMarketIfNeeded()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { showError(error.localizedDescription) }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { showError(error.localizedDescription) }
    }
}

extension HarnessPluginMarketViewController: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = navigationAction.request.url,
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              !marketOrigin.matches(url), url.user == nil, url.password == nil else { return nil }
        externalNavigationHandler(url)
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: "插件市场", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "知道了", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }
}

@available(iOS 14.5, *)
extension HarnessPluginMarketViewController: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        completionHandler(nil)
    }
}
