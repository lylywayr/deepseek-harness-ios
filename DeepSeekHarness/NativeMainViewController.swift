import UIKit
import WebKit

@main
final class DeepSeekHarnessAppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private let appState = AppState()
    private let nativeUIStore = NativeUIStore()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        let root = MainViewController(appState: appState, nativeUIStore: nativeUIStore)
        let navigation = UINavigationController(rootViewController: root)
        navigation.navigationBar.prefersLargeTitles = false
        window.rootViewController = navigation
        window.backgroundColor = .systemBackground
        self.window = window
        window.makeKeyAndVisible()
        return true
    }
}

/// Native-first application shell. The legacy WebView is only used by the
/// compatibility surface and by AutoNativeAdapter; it is never the main UI.
final class MainViewController: UIViewController {
    private let appState: AppState
    private let nativeUIStore: NativeUIStore
    private var currentChild: UIViewController?
    private var nativeTransport: NativeUITransport?

    init(appState: AppState, nativeUIStore: NativeUIStore) {
        self.appState = appState
        self.nativeUIStore = nativeUIStore
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        render()
    }

    private func render() {
        removeCurrentChild()

        guard let endpoint = appState.endpointURL else {
            let setup = SetupViewController(initialValue: appState.endpointString)
            setup.onSave = { [weak self] value in
                guard let self, self.appState.saveEndpoint(value) else { return }
                self.render()
            }
            addChildController(setup)
            navigationItem.title = "DeepSeek Harness"
            navigationItem.leftBarButtonItem = nil
            navigationItem.rightBarButtonItem = nil
            return
        }

        let transport = NativeUITransport(baseURL: endpoint)
        nativeTransport = transport
        let home = NativeHomeViewController(
            appState: appState,
            nativeUIStore: nativeUIStore,
            transport: transport,
            onSettings: { [weak self] in self?.openSettings() }
        )
        addChildController(home)
        navigationItem.title = "Harness"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "sidebar.left"),
            style: .plain,
            target: home,
            action: #selector(NativeHomeViewController.toggleSidebar)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "gearshape"),
            style: .plain,
            target: self,
            action: #selector(openSettings)
        )
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
        let navigation = UINavigationController(rootViewController: controller)
        navigation.modalPresentationStyle = .formSheet
        present(navigation, animated: true)
    }
}

final class NativeHomeViewController: UIViewController {
    private let appState: AppState
    private let store: NativeUIStore
    private let transport: NativeUITransport
    private let onSettings: () -> Void

    private let conversationContainer = UIView()
    private let sidebar = UIView()
    private let sidebarContent = UIStackView()
    private let adapterHost = UIView()
    private let statusLabel = UILabel()
    private var isSidebarVisible = false
    private var stopObserving: (() -> Void)?
    private var autoAdapter: AutoNativeAdapter?
    private var didStartAdapter = false

    init(
        appState: AppState,
        nativeUIStore: NativeUIStore,
        transport: NativeUITransport,
        onSettings: @escaping () -> Void
    ) {
        self.appState = appState
        self.store = nativeUIStore
        self.transport = transport
        self.onSettings = onSettings
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        buildLayout()
        renderSidebar()
        stopObserving = store.observe { [weak self] in
            DispatchQueue.main.async { self?.renderSidebar() }
        }
        loadNativeManifest()
        startAutoAdapterIfNeeded()
    }

    deinit {
        stopObserving?()
    }

    private func buildLayout() {
        conversationContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(conversationContainer)
        NSLayoutConstraint.activate([
            conversationContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            conversationContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            conversationContainer.topAnchor.constraint(equalTo: view.topAnchor),
            conversationContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let conversation = NativeConversationViewController { [weak self] text in
            self?.showNotice("原生聊天输入已接收：\n\(text)\n\n会话 Remote 接入将在下一阶段接入官方 Harness 契约。")
        }
        addChild(conversation)
        conversation.view.translatesAutoresizingMaskIntoConstraints = false
        conversationContainer.addSubview(conversation.view)
        NSLayoutConstraint.activate([
            conversation.view.leadingAnchor.constraint(equalTo: conversationContainer.leadingAnchor),
            conversation.view.trailingAnchor.constraint(equalTo: conversationContainer.trailingAnchor),
            conversation.view.topAnchor.constraint(equalTo: conversationContainer.topAnchor),
            conversation.view.bottomAnchor.constraint(equalTo: conversationContainer.bottomAnchor)
        ])
        conversation.didMove(toParent: self)

        adapterHost.translatesAutoresizingMaskIntoConstraints = false
        adapterHost.isHidden = false
        adapterHost.alpha = 0.01
        view.addSubview(adapterHost)
        NSLayoutConstraint.activate([
            adapterHost.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            adapterHost.topAnchor.constraint(equalTo: view.topAnchor),
            adapterHost.widthAnchor.constraint(equalToConstant: 2),
            adapterHost.heightAnchor.constraint(equalToConstant: 2)
        ])

        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebar.backgroundColor = .secondarySystemBackground
        sidebar.layer.shadowColor = UIColor.black.cgColor
        sidebar.layer.shadowOpacity = 0.16
        sidebar.layer.shadowRadius = 12
        sidebar.isHidden = true
        view.addSubview(sidebar)
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: view.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 310)
        ])

        sidebarContent.axis = .vertical
        sidebarContent.spacing = 8
        sidebarContent.alignment = .fill
        sidebarContent.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(sidebarContent)
        NSLayoutConstraint.activate([
            sidebarContent.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 16),
            sidebarContent.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -16),
            sidebarContent.topAnchor.constraint(equalTo: sidebar.safeAreaLayoutGuide.topAnchor, constant: 18),
            sidebarContent.bottomAnchor.constraint(lessThanOrEqualTo: sidebar.bottomAnchor, constant: -18)
        ])
    }

    private func renderSidebar() {
        sidebarContent.arrangedSubviews.forEach { subview in
            sidebarContent.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }

        let title = UILabel()
        title.text = "工作区与功能"
        title.font = .preferredFont(forTextStyle: .headline)
        sidebarContent.addArrangedSubview(title)

        sidebarContent.addArrangedSubview(sidebarButton(title: "新建会话", icon: "plus.bubble") { [weak self] in
            self?.showNotice("已创建原生会话入口；实际提交通道待接入 Harness Session Remote。")
        })
        sidebarContent.addArrangedSubview(sidebarButton(title: "插件中心", icon: "puzzlepiece.extension") { [weak self] in
            self?.openPluginCenter()
        })
        sidebarContent.addArrangedSubview(separator())

        let surfaces = store.surfaces(at: "sidebar")
        if surfaces.isEmpty {
            let empty = UILabel()
            empty.text = "正在发现插件界面…\n\n服务端没有 Native UI 清单时，自动适配器会读取现有 dsh.client 页面并尝试转换。"
            empty.textColor = .secondaryLabel
            empty.numberOfLines = 0
            empty.font = .preferredFont(forTextStyle: .footnote)
            sidebarContent.addArrangedSubview(empty)
        } else {
            surfaces.forEach { surface in
                sidebarContent.addArrangedSubview(
                    sidebarButton(title: surface.title, icon: surface.icon) { [weak self] in
                        self?.open(surface: surface)
                    }
                )
            }
        }

        sidebarContent.addArrangedSubview(UIView())
        statusLabel.text = autoAdapter == nil ? "原生模式" : "自动原生适配器已运行"
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0
        statusLabel.font = .preferredFont(forTextStyle: .caption1)
        sidebarContent.addArrangedSubview(statusLabel)
        sidebarContent.addArrangedSubview(sidebarButton(title: "设置", icon: "gearshape", action: onSettings))
    }

    private func loadNativeManifest() {
        transport.loadManifest { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case let .success(manifest):
                    self.store.replace(manifest)
                    self.statusLabel.text = "已连接 Native UI 服务"
                case let .failure(error):
                    self.statusLabel.text = error.localizedDescription
                }
            }
        }
    }

    private func startAutoAdapterIfNeeded() {
        guard !didStartAdapter, let endpoint = appState.endpointURL else { return }
        didStartAdapter = true

        let adapter = AutoNativeAdapter(baseURL: endpoint)
        autoAdapter = adapter
        adapter.mount(in: adapterHost)
        adapter.onStatus = { [weak self] status in
            DispatchQueue.main.async {
                self?.statusLabel.text = status
            }
        }
        adapter.onSnapshot = { [weak self] result in
            DispatchQueue.main.async {
                self?.applyAutoSnapshot(result, endpoint: endpoint)
            }
        }
        adapter.start()
        renderSidebar()
    }

    private func applyAutoSnapshot(
        _ result: Result<NativeUINode, Error>,
        endpoint: URL
    ) {
        let pluginID = "auto.projected.harness"
        let surfaceID = "auto.projected.harness.main"
        let plugin = NativeUIPlugin(
            id: pluginID,
            name: "自动原生化界面",
            version: "runtime",
            enabled: true,
            nativeMode: "dom-projection",
            legacyURL: endpoint.absoluteString
        )

        let root: NativeUINode
        switch result {
        case let .success(node):
            root = node
            statusLabel.text = "已生成原生投影；不支持的区域可进入兼容模式"
        case let .failure(error):
            root = NativeUINode(
                type: "legacy",
                id: "auto-fallback",
                title: "Harness 兼容页面",
                subtitle: error.localizedDescription,
                url: endpoint.absoluteString
            )
            statusLabel.text = "自动转换失败，已保留兼容层"
        }

        let surface = NativeUISurface(
            id: surfaceID,
            pluginID: pluginID,
            title: "自动转换界面",
            subtitle: "现有 dsh.client 页面投影到原生控件",
            icon: "wand.and.stars",
            placement: "sidebar",
            root: root,
            legacyURL: endpoint.absoluteString,
            order: -1000
        )

        let current = store.manifest
        var plugins = current.plugins.filter { $0.id != pluginID }
        plugins.append(plugin)
        var surfaces = current.surfaces.filter { $0.id != surfaceID }
        surfaces.append(surface)
        store.replace(NativeUIManifest(
            protocolVersion: current.protocolVersion,
            generatedAt: current.generatedAt,
            plugins: plugins,
            surfaces: surfaces,
            diagnostics: current.diagnostics
        ))
    }

    private func makeActionHandler() -> NativeUIActionHandler {
        { [weak self] surfaceID, nodeID, action, payload, completion in
            guard let self else {
                completion(.failure(NativeUITransportError.message("Native UI 页面已退出。")))
                return
            }
            if action.hasPrefix("dom.") {
                let event: String
                switch action {
                case "dom.input": event = "dom.input"
                case "dom.toggle": event = "dom.toggle"
                default: event = "dom.click"
                }
                self.autoAdapter?.dispatch(nodeID: nodeID, event: event, value: payload["value"])
                completion(.success(NativeUIActionResponse(ok: true, message: nil, manifest: nil)))
                return
            }
            self.transport.perform(
                surfaceID: surfaceID,
                nodeID: nodeID,
                action: action,
                payload: payload,
                completion: completion
            )
        }
    }

    private func openPluginCenter() {
        let controller = NativePluginCenterViewController(
            store: store,
            transport: transport,
            actionHandler: makeActionHandler(),
            fallbackHandler: { [weak self] url in self?.openLegacy(url: url) }
        )
        navigationController?.pushViewController(controller, animated: true)
    }

    private func open(surface: NativeUISurface) {
        if surface.isLegacyOnly {
            openLegacy(url: surface.legacyURL ?? surface.root.url)
            return
        }
        let controller = NativeUISurfaceViewController(
            surface: surface,
            store: store,
            transport: transport,
            actionHandler: makeActionHandler(),
            fallbackHandler: { [weak self] url in self?.openLegacy(url: url) }
        )
        navigationController?.pushViewController(controller, animated: true)
    }

    private func openLegacy(url rawURL: String?) {
        guard let rawURL, let url = URL(string: rawURL) else {
            showNotice("此区域需要兼容层，但没有可用的页面地址。")
            return
        }
        let controller = HarnessViewController(url: url)
        navigationController?.pushViewController(controller, animated: true)
    }

    @objc func toggleSidebar() {
        isSidebarVisible.toggle()
        sidebar.isHidden = !isSidebarVisible
    }

    private func sidebarButton(title: String, icon: String?, action: @escaping () -> Void) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.image = icon.flatMap { UIImage(systemName: $0) }
        configuration.imagePadding = 10
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 8, bottom: 10, trailing: 8)
        configuration.titleAlignment = .leading
        let button = UIButton(configuration: configuration)
        button.contentHorizontalAlignment = .leading
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    private func separator() -> UIView {
        let line = UIView()
        line.backgroundColor = .separator
        line.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
        return line
    }

    private func showNotice(_ message: String) {
        let alert = UIAlertController(title: "DeepSeek Harness", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
}

/// Minimal native chat shell for phase one. It is intentionally independent of
/// the Web UI; the official session Remote contract will populate messages in
/// the next transport milestone.
final class NativeConversationViewController: UIViewController, UITableViewDataSource, UITextViewDelegate {
    private let onSend: (String) -> Void
    private var messages: [(String, Bool)] = [
        ("已进入原生客户端。聊天、侧边栏、设置和插件入口均由 iOS 控件绘制。", false)
    ]
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let input = UITextView()
    private let sendButton = UIButton(type: .system)
    private let stateLabel = UILabel()

    init(onSend: @escaping (String) -> Void) {
        self.onSend = onSend
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "message")
        tableView.separatorStyle = .none
        tableView.keyboardDismissMode = .interactive
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        stateLabel.text = "Native-first · 自动原生适配器"
        stateLabel.textColor = .secondaryLabel
        stateLabel.font = .preferredFont(forTextStyle: .caption1)
        stateLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stateLabel)

        input.font = .preferredFont(forTextStyle: .body)
        input.layer.cornerRadius = 10
        input.layer.borderWidth = 1
        input.layer.borderColor = UIColor.separator.cgColor
        input.text = ""
        input.textContainerInset = UIEdgeInsets(top: 9, left: 9, bottom: 9, right: 9)
        input.delegate = self
        input.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(input)

        sendButton.setTitle("发送", for: .normal)
        sendButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        sendButton.addTarget(self, action: #selector(send), for: .touchUpInside)
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sendButton)

        NSLayoutConstraint.activate([
            stateLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stateLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            stateLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: stateLabel.bottomAnchor, constant: 6),
            tableView.bottomAnchor.constraint(equalTo: input.topAnchor, constant: -10),
            input.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            input.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            input.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            input.heightAnchor.constraint(lessThanOrEqualToConstant: 100),
            sendButton.leadingAnchor.constraint(equalTo: input.trailingAnchor, constant: 8),
            sendButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            sendButton.centerYAnchor.constraint(equalTo: input.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 54)
        ])
    }

    @objc private func send() {
        let text = input.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messages.append((text, true))
        input.text = ""
        tableView.reloadData()
        tableView.scrollToRow(at: IndexPath(row: messages.count - 1, section: 0), at: .bottom, animated: true)
        onSend(text)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        messages.count
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "message", for: indexPath)
        let message = messages[indexPath.row]
        var configuration = cell.defaultContentConfiguration()
        configuration.text = message.0
        configuration.textProperties.numberOfLines = 0
        configuration.textProperties.alignment = message.1 ? .right : .left
        configuration.textProperties.color = message.1 ? .systemBlue : .label
        cell.contentConfiguration = configuration
        cell.selectionStyle = .none
        return cell
    }
}
