import Foundation
import WebKit

/// Best-effort runtime projection for existing dsh.client pages.
/// It runs the unchanged web plugin in an isolated, hidden compatibility view,
/// then converts an accessible DOM snapshot into NativeUINode values. This is
/// deliberately incremental: unsupported DOM/CSS is reported and can fall
/// back to the legacy surface without affecting the native app shell.
final class AutoNativeAdapter: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    let baseURL: URL
    private(set) var webView: WKWebView!
    var onSnapshot: ((Result<NativeUINode, Error>) -> Void)?
    var onStatus: ((String) -> Void)?

    private var mounted = false
    private var loaded = false
    private var snapshotWorkItem: DispatchWorkItem?

    init(baseURL: URL) {
        self.baseURL = baseURL
        super.init()

        let contentController = WKUserContentController()
        contentController.addUserScript(WKUserScript(
            source: Self.bridgeScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        contentController.add(self, name: "dshNative")

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.userContentController = contentController
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isHidden = true
        webView.alpha = 0.01
        webView.accessibilityElementsHidden = true
    }

    deinit {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "dshNative")
        snapshotWorkItem?.cancel()
    }

    func mount(in host: UIView) {
        guard !mounted else { return }
        mounted = true
        webView.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            webView.topAnchor.constraint(equalTo: host.topAnchor),
            webView.bottomAnchor.constraint(equalTo: host.bottomAnchor)
        ])
    }

    func start() {
        onStatus?("自动原生适配器：正在读取现有 dsh.client 页面")
        webView.load(URLRequest(url: baseURL))
    }

    func dispatch(nodeID: String, event: String, value: String?) {
        let node = Self.jsonString(nodeID)
        let eventName = Self.jsonString(event)
        let jsonValue = value.map(Self.jsonString) ?? "null"
        let script = "window.__dshNativeDispatch && window.__dshNativeDispatch(\(node), \(eventName), \(jsonValue));"
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "ready":
            onStatus?("自动原生适配器：页面已加载，正在生成原生投影")
            requestSnapshot()
        case "snapshot":
            guard let raw = body["root"],
                  JSONSerialization.isValidJSONObject(raw),
                  let data = try? JSONSerialization.data(withJSONObject: raw) else {
                onSnapshot?(.failure(NativeUITransportError.invalidManifest))
                return
            }
            do {
                onSnapshot?(.success(try JSONDecoder().decode(NativeUINode.self, from: data)))
            } catch {
                onSnapshot?(.failure(error))
            }
        default:
            break
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loaded = false
        onStatus?("自动原生适配器：正在载入插件页面")
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        loaded = true
        requestSnapshot()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded = true
        onStatus?("自动原生适配器：已生成页面投影")
        requestSnapshot()
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        onStatus?("自动原生适配器失败，保留兼容层：\(error.localizedDescription)")
        onSnapshot?(.failure(error))
    }

    private func requestSnapshot() {
        guard loaded else { return }
        snapshotWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.webView.evaluateJavaScript(
                "window.__dshNativeSnapshot ? window.__dshNativeSnapshot() : null",
                completionHandler: { [weak self] value, error in
                    guard let self else { return }
                    if let error { self.onSnapshot?(.failure(error)); return }
                    guard let value, JSONSerialization.isValidJSONObject(value),
                          let data = try? JSONSerialization.data(withJSONObject: value) else {
                        self.onSnapshot?(.failure(NativeUITransportError.invalidManifest)); return
                    }
                    do {
                        self.onSnapshot?(.success(try JSONDecoder().decode(NativeUINode.self, from: data)))
                    } catch { self.onSnapshot?(.failure(error)) }
                }
            )
        }
        snapshotWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: item)
    }

    private static func jsonString(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let encoded = String(data: data, encoding: .utf8) else { return "\"\"" }
        return String(encoded.dropFirst().dropLast())
    }

    private static let bridgeScript = #"""
    (function () {
      if (window.__dshNativeInstalled) return;
      window.__dshNativeInstalled = true;
      var counter = 0, maxDepth = 16, maxChildren = 100;
      function post(value) { window.webkit.messageHandlers.dshNative.postMessage(value); }
      function textOf(el) {
        var text = (el.innerText || el.textContent || '').replace(/\\s+/g, ' ').trim();
        return text ? text.slice(0, 2000) : null;
      }
      function directLabel(el) {
        return el.getAttribute('aria-label') || el.getAttribute('title') ||
          el.getAttribute('placeholder') || textOf(el);
      }
      function actionFor(el) {
        if (!el || !el.addEventListener) return null;
        var id = el.getAttribute('data-testid') || el.id || el.getAttribute('name');
        if (!id) { id = 'dom-' + (++counter); el.setAttribute('data-dsh-native-id', id); }
        return id;
      }
      function convert(el, depth) {
        if (!el || depth > maxDepth || el.nodeType !== 1) return null;
        var tag = (el.tagName || '').toLowerCase();
        var children = [], nodes = el.children || [];
        for (var i = 0; i < Math.min(nodes.length, maxChildren); i++) {
          var child = convert(nodes[i], depth + 1); if (child) children.push(child);
        }
        var id = el.getAttribute('data-dsh-native-id') || el.id || ('dom-' + (++counter));
        el.setAttribute('data-dsh-native-id', id);
        var label = directLabel(el), node;
        if (tag === 'button' || tag === 'summary' || el.getAttribute('role') === 'button') {
          node = {type:'button', id:id, title:label || '按钮', action:'dom.click'};
        } else if (tag === 'input' || tag === 'textarea') {
          node = {type:'textField', id:id, title:label || '输入', value:el.value || '', placeholder:el.placeholder || '', action:'dom.input'};
        } else if (tag === 'img') {
          node = {type:'image', id:id, title:label || '图片'};
        } else if (tag === 'hr') {
          node = {type:'divider', id:id};
        } else if (tag === 'h1' || tag === 'h2' || tag === 'h3') {
          node = {type:'text', id:id, text:label || ''};
        } else if (tag === 'a' && el.href) {
          node = {type:'button', id:id, title:label || el.href, action:'dom.click', url:el.href};
        } else {
          node = {type:'stack', id:id, axis:'vertical', children:children};
          if (!children.length && label) node = {type:'text', id:id, text:label};
        }
        if (children.length && node.type !== 'stack') node.children = children;
        return node;
      }
      window.__dshNativeSnapshot = function () { return convert(document.body, 0) || {type:'text',text:'页面为空'}; };
      window.__dshNativeDispatch = function (id, event, value) {
        var el = document.querySelector('[data-dsh-native-id="' + CSS.escape(id) + '"]') || document.getElementById(id);
        if (!el) return;
        if (event === 'dom.input') { el.value = value == null ? '' : value; el.dispatchEvent(new Event('input', {bubbles:true})); }
        else { el.click(); }
        setTimeout(function () { post({type:'snapshot', root:window.__dshNativeSnapshot()}); }, 50);
      };
      var observer = new MutationObserver(function () {
        clearTimeout(window.__dshNativeTimer);
        window.__dshNativeTimer = setTimeout(function () { post({type:'snapshot',root:window.__dshNativeSnapshot()}); }, 250);
      });
      function boot() { observer.observe(document.documentElement || document, {subtree:true,childList:true,attributes:true,characterData:true}); post({type:'ready'}); post({type:'snapshot',root:window.__dshNativeSnapshot()}); }
      if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot); else boot();
    })();
    ""#
}
