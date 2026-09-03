import UIKit
import WebKit

// Legacy setup and WebView controllers are retained as the compatibility layer.
final class LegacyMainViewController: UIViewController {
    private let appState = AppState()
    private var currentChild: UIViewController?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        render()
    }

    private func render() {
        removeCurrentChild()

        if let endpoint = appState.endpointURL {
            let controller = HarnessViewController(url: endpoint)
            addChildController(controller)
            navigationItem.title = "Harness"
            navigationItem.leftBarButtonItem = UIBarButtonItem(
                image: UIImage(systemName: "gearshape"),
                style: .plain,
                target: self,
                action: #selector(openSettings)
            )
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .refresh,
                target: controller,
                action: #selector(HarnessViewController.reloadPage)
            )
        } else {
            let controller = SetupViewController(initialValue: appState.endpointString)
            controller.onSave = { [weak self] value in
                guard let self, self.appState.saveEndpoint(value) else { return }
                self.dismiss(animated: true)
                self.render()
            }
            addChildController(controller)
            navigationItem.title = "DeepSeek Harness"
            navigationItem.leftBarButtonItem = nil
            navigationItem.rightBarButtonItem = nil
        }
    }

    private func addChildController(_ controller: UIViewController) {
        currentChild = controller
        addChild(controller)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controller.view)
        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: view.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        controller.didMove(toParent: self)
    }

    private func removeCurrentChild() {
        guard let child = currentChild else { return }
        child.willMove(toParent: nil)
        child.view.removeFromSuperview()
        child.removeFromParent()
        currentChild = nil
    }

    @objc private func openSettings() {
        let controller = SetupViewController(initialValue: appState.endpointString)
        controller.onSave = { [weak self, weak controller] value in
            guard let self, self.appState.saveEndpoint(value) else { return }
            controller?.dismiss(animated: true)
            self.render()
        }
        controller.onClearSession = { [weak self, weak controller] in
            guard let self else { return }
            WKWebsiteDataStore.default().removeData(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                modifiedSince: Date(timeIntervalSince1970: 0)
            ) { [weak self, weak controller] in
                DispatchQueue.main.async {
                    self?.appState.clearEndpoint()
                    controller?.dismiss(animated: true)
                    self?.render()
                }
            }
        }
        let navigationController = UINavigationController(rootViewController: controller)
        navigationController.modalPresentationStyle = .formSheet
        present(navigationController, animated: true)
    }
}

final class SetupViewController: UIViewController {
    var onSave: ((String) -> Void)?
    var onClearSession: (() -> Void)?

    private let initialValue: String
    private let endpointField = UITextField()
    private let errorLabel = UILabel()
    private let saveButton = UIButton(type: .system)
    private let clearButton = UIButton(type: .system)

    init(initialValue: String) {
        self.initialValue = initialValue
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        buildView()
    }

    private func buildView() {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let content = UIStackView()
        content.axis = .vertical
        content.spacing = 16
        content.alignment = .fill
        content.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(content)

        let icon = UIImageView(image: UIImage(systemName: "sparkles.rectangle.stack"))
        icon.tintColor = .systemBlue
        icon.contentMode = .scaleAspectFit
        icon.heightAnchor.constraint(equalToConstant: 56).isActive = true

        let title = UILabel()
        title.text = "连接你的 Harness 服务"
        title.font = .preferredFont(forTextStyle: .title2)
        title.textAlignment = .center

        let description = UILabel()
        description.text = "输入已部署的 DeepSeek Harness 地址，即可使用现有会话、模型、Plugins、Skills 和文件能力。"
        description.font = .preferredFont(forTextStyle: .body)
        description.textColor = .secondaryLabel
        description.numberOfLines = 0
        description.textAlignment = .center

        endpointField.borderStyle = .roundedRect
        endpointField.placeholder = "http://192.168.31.250:端口"
        endpointField.text = initialValue
        endpointField.keyboardType = .URL
        endpointField.autocapitalizationType = .none
        endpointField.autocorrectionType = .no
        endpointField.clearButtonMode = .whileEditing
        endpointField.returnKeyType = .done
        endpointField.delegate = self
        endpointField.heightAnchor.constraint(equalToConstant: 46).isActive = true

        saveButton.setTitle("保存并连接", for: .normal)
        saveButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        saveButton.backgroundColor = .systemBlue
        saveButton.tintColor = .white
        saveButton.layer.cornerRadius = 10
        saveButton.heightAnchor.constraint(equalToConstant: 46).isActive = true
        saveButton.addTarget(self, action: #selector(save), for: .touchUpInside)

        errorLabel.font = .preferredFont(forTextStyle: .footnote)
        errorLabel.textColor = .systemRed
        errorLabel.numberOfLines = 0
        errorLabel.textAlignment = .center
        errorLabel.isHidden = true

        let help = UILabel()
        help.text = "支持 HTTP 和 HTTPS。公网访问请优先使用 HTTPS 或 VPN/组网。不要把密码或 Token 写入地址。"
        help.font = .preferredFont(forTextStyle: .footnote)
        help.textColor = .secondaryLabel
        help.numberOfLines = 0
        help.textAlignment = .center

        [icon, title, description, endpointField, saveButton, errorLabel, help].forEach(content.addArrangedSubview)

        if onClearSession != nil {
            clearButton.setTitle("清除本机网页会话", for: .normal)
            clearButton.setTitleColor(.systemRed, for: .normal)
            clearButton.addTarget(self, action: #selector(clearSession), for: .touchUpInside)
            content.addArrangedSubview(clearButton)
        }

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 24),
            content.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -24),
            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 32),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -32),
            content.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -48)
        ])
    }

    @objc private func save() {
        view.endEditing(true)
        let value = endpointField.text ?? ""
        guard AppState.makeURL(from: value) != nil else {
            errorLabel.text = "地址无效，请填写完整的 HTTP 或 HTTPS 地址。"
            errorLabel.isHidden = false
            return
        }
        errorLabel.isHidden = true
        onSave?(value)
    }

    @objc private func clearSession() {
        onClearSession?()
    }
}

extension SetupViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        save()
        return true
    }
}

final class HarnessViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    private let url: URL
    private var webView: WKWebView!
    private let errorContainer = UIView()
    private let errorLabel = UILabel()
    private let retryButton = UIButton(type: .system)

    init(url: URL) {
        self.url = url
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        buildErrorView()
        webView.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy))
    }

    private func buildErrorView() {
        errorContainer.translatesAutoresizingMaskIntoConstraints = false
        errorContainer.backgroundColor = .systemBackground
        errorContainer.isHidden = true
        view.addSubview(errorContainer)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        errorContainer.addSubview(stack)

        let icon = UIImageView(image: UIImage(systemName: "wifi.exclamationmark"))
        icon.tintColor = .systemOrange
        icon.contentMode = .scaleAspectFit
        icon.heightAnchor.constraint(equalToConstant: 36).isActive = true

        errorLabel.font = .preferredFont(forTextStyle: .body)
        errorLabel.textColor = .secondaryLabel
        errorLabel.numberOfLines = 0
        errorLabel.textAlignment = .center

        retryButton.setTitle("重新加载", for: .normal)
        retryButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        retryButton.addTarget(self, action: #selector(reloadPage), for: .touchUpInside)

        [icon, errorLabel, retryButton].forEach(stack.addArrangedSubview)
        NSLayoutConstraint.activate([
            errorContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            errorContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            errorContainer.topAnchor.constraint(equalTo: view.topAnchor),
            errorContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: errorContainer.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: errorContainer.trailingAnchor, constant: -24),
            stack.centerXAnchor.constraint(equalTo: errorContainer.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: errorContainer.centerYAnchor)
        ])
    }

    @objc func reloadPage() {
        errorContainer.isHidden = true
        webView.reload()
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        errorContainer.isHidden = true
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        errorContainer.isHidden = true
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        showError(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showError(error)
    }

    private func showError(_ error: Error) {
        errorLabel.text = "无法加载 Harness 服务。\n\(error.localizedDescription)"
        errorContainer.isHidden = false
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
        let scheme = targetURL.scheme?.lowercased()
        guard scheme == "http" || scheme == "https" else {
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
        if let targetURL = navigationAction.request.url {
            webView.load(URLRequest(url: targetURL))
        }
        return nil
    }
}
