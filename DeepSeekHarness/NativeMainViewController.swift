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
        navigation.navigationBar.tintColor = DHTheme.accent
        navigation.navigationBar.standardAppearance = DHNavigationAppearance.make()
        navigation.navigationBar.scrollEdgeAppearance = DHNavigationAppearance.make()
        window.rootViewController = navigation
        window.backgroundColor = DHTheme.background
        self.window = window
        window.makeKeyAndVisible()
        return true
    }
}

final class MainViewController: UIViewController {
    private let appState: AppState
    private let nativeUIStore: NativeUIStore
    private var currentChild: UIViewController?

    init(appState: AppState, nativeUIStore: NativeUIStore) {
        self.appState = appState
        self.nativeUIStore = nativeUIStore
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DHTheme.background
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
        guard let endpoint = appState.endpointURL else {
            openConnectionSettings()
            return
        }
        let center = HarnessSettingsCenterViewController(appState: appState) { [weak self] in
            self?.dismiss(animated: true) { self?.openConnectionSettings() }
        }
        let navigation = UINavigationController(rootViewController: center)
        navigation.navigationBar.tintColor = DHTheme.text
        navigation.navigationBar.standardAppearance = DHNavigationAppearance.make()
        navigation.modalPresentationStyle = .pageSheet
        if #available(iOS 15.0, *) {
            navigation.sheetPresentationController?.detents = [.large()]
            navigation.sheetPresentationController?.prefersGrabberVisible = true
        }
        present(navigation, animated: true)
        _ = endpoint
    }

    private func openConnectionSettings() {
        let setup = SetupViewController(initialValue: appState.endpointString)
        setup.onSave = { [weak self, weak setup] value in
            guard let self, self.appState.saveEndpoint(value) else { return }
            setup?.dismiss(animated: true)
            self.render()
        }
        setup.onClearSession = { [weak self, weak setup] in
            WKWebsiteDataStore.default().removeData(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                modifiedSince: Date(timeIntervalSince1970: 0)
            ) { [weak self, weak setup] in
                DispatchQueue.main.async {
                    self?.appState.clearEndpoint()
                    setup?.dismiss(animated: true)
                    self?.render()
                }
            }
        }
        let navigation = UINavigationController(rootViewController: setup)
        navigation.navigationBar.tintColor = DHTheme.accent
        navigation.navigationBar.standardAppearance = DHNavigationAppearance.make()
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
    private let sidebarScrim = UIControl()
    private let adapterHost = UIView()
    private var runtime: HarnessRuntime!
    private let connectionBadge = DHBadgeLabel(text: "在线", color: DHTheme.success)
    private var sidebarWidthConstraint: NSLayoutConstraint!
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
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DHTheme.background
        buildLayout()
        renderSidebar()
        stopObserving = store.observe { [weak self] in
            DispatchQueue.main.async { self?.renderSidebar() }
        }
        loadNativeManifest()
        startAutoAdapterIfNeeded()
    }

    deinit { stopObserving?() }

    private func buildLayout() {
        conversationContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(conversationContainer)
        NSLayoutConstraint.activate([
            conversationContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            conversationContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            conversationContainer.topAnchor.constraint(equalTo: view.topAnchor),
            conversationContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        runtime = HarnessRuntime(baseURL: appState.endpointURL!)
        let conversation = PolishedConversationViewController(runtime: runtime)
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
        adapterHost.alpha = 0.01
        view.addSubview(adapterHost)
        runtime.mount(in: adapterHost)
        runtime.onNavigationChange = { [weak self] in self?.renderSidebar() }
        runtime.start()

        sidebarScrim.backgroundColor = UIColor.black.withAlphaComponent(0.25)
        sidebarScrim.alpha = 0
        sidebarScrim.isHidden = true
        sidebarScrim.addTarget(self, action: #selector(toggleSidebar), for: .touchUpInside)
        sidebarScrim.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sidebarScrim)
        NSLayoutConstraint.activate([
            sidebarScrim.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sidebarScrim.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sidebarScrim.topAnchor.constraint(equalTo: view.topAnchor),
            sidebarScrim.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebar.dhApplyCard(backgroundColor: DHTheme.surface, cornerRadius: 0, shadow: true)
        sidebar.isHidden = true
        view.addSubview(sidebar)
        sidebarWidthConstraint = sidebar.widthAnchor.constraint(equalToConstant: 304)
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: view.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sidebarWidthConstraint
        ])

        sidebarContent.axis = .vertical
        sidebarContent.spacing = 8
        sidebarContent.alignment = .fill
        sidebarContent.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(sidebarContent)
        NSLayoutConstraint.activate([
            sidebarContent.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 18),
            sidebarContent.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -18),
            sidebarContent.topAnchor.constraint(equalTo: sidebar.safeAreaLayoutGuide.topAnchor, constant: 16),
            sidebarContent.bottomAnchor.constraint(lessThanOrEqualTo: sidebar.bottomAnchor, constant: -18)
        ])
    }

    private func renderSidebar() {
        sidebarContent.arrangedSubviews.forEach {
            sidebarContent.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let brand = UIView()
        brand.translatesAutoresizingMaskIntoConstraints = false
        let icon = dhIconView(systemName: "sparkles", size: 44, symbolSize: 19)
        let title = UILabel()
        title.text = "Harness"
        title.font = DHTheme.font(.title3, weight: .bold)
        let subtitle = UILabel()
        subtitle.text = "原生工作台"
        subtitle.font = DHTheme.font(.caption1)
        subtitle.textColor = DHTheme.secondaryText
        let labels = UIStackView(arrangedSubviews: [title, subtitle])
        labels.axis = .vertical
        labels.spacing = 2
        labels.translatesAutoresizingMaskIntoConstraints = false
        brand.addSubview(icon)
        brand.addSubview(labels)
        NSLayoutConstraint.activate([
            brand.heightAnchor.constraint(equalToConstant: 52),
            icon.leadingAnchor.constraint(equalTo: brand.leadingAnchor),
            icon.centerYAnchor.constraint(equalTo: brand.centerYAnchor),
            labels.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 11),
            labels.centerYAnchor.constraint(equalTo: brand.centerYAnchor),
            labels.trailingAnchor.constraint(equalTo: brand.trailingAnchor)
        ])
        sidebarContent.addArrangedSubview(brand)
        sidebarContent.addArrangedSubview(dhSeparator())

        sidebarContent.addArrangedSubview(sidebarButton(title: "新建会话", icon: "square.and.pencil", prominent: true) { [weak self] in
            let workspace = self?.runtime.workspaces.first?.id
            self?.runtime.createSession(workspaceID: workspace)
            self?.toggleSidebar()
        })

        let workspaceTitle = UILabel()
        workspaceTitle.text = runtime.workspaces.first.map { "工作区 · \($0.title)" } ?? "会话"
        workspaceTitle.font = DHTheme.font(.caption1, weight: .semibold)
        workspaceTitle.textColor = DHTheme.tertiaryText
        sidebarContent.addArrangedSubview(workspaceTitle)

        for session in runtime.sessions.filter({ !$0.blank }).prefix(12) {
            let title = session.title.isEmpty ? "未命名会话" : session.title
            sidebarContent.addArrangedSubview(sidebarButton(title: title, icon: session.running ? "circle.dotted" : "message") { [weak self] in
                self?.runtime.openSession(session.id)
                self?.toggleSidebar()
            })
        }

        sidebarContent.addArrangedSubview(sidebarButton(title: "插件与扩展", icon: "puzzlepiece.extension") { [weak self] in
            self?.openPluginCenter()
        })

        let sectionTitle = UILabel()
        sectionTitle.text = "扩展入口"
        sectionTitle.font = DHTheme.font(.caption1, weight: .semibold)
        sectionTitle.textColor = DHTheme.tertiaryText
        sectionTitle.text = sectionTitle.text?.uppercased()
        sectionTitle.translatesAutoresizingMaskIntoConstraints = false
        sidebarContent.addArrangedSubview(sectionTitle)
        sidebarContent.setCustomSpacing(14, after: sectionTitle)

        let surfaces = store.surfaces(at: "sidebar")
        if surfaces.isEmpty {
            let empty = sidebarHint(
                icon: "wand.and.stars",
                title: "正在发现插件",
                message: "原生入口会在服务端清单或自动适配完成后显示。"
            )
            sidebarContent.addArrangedSubview(empty)
        } else {
            surfaces.forEach { surface in
                sidebarContent.addArrangedSubview(
                    sidebarButton(title: surface.title, icon: surface.icon ?? "circle.grid.2x2") { [weak self] in
                        self?.open(surface: surface)
                    }
                )
            }
        }

        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        sidebarContent.addArrangedSubview(spacer)

        let connection = UIView()
        connection.dhApplyCard(backgroundColor: DHTheme.surfaceMuted, cornerRadius: DHTheme.cornerSmall)
        connection.translatesAutoresizingMaskIntoConstraints = false
        let dot = UIView()
        dot.backgroundColor = runtime?.connected == true ? DHTheme.success : DHTheme.warning
        dot.layer.cornerRadius = 4
        dot.translatesAutoresizingMaskIntoConstraints = false
        let status = UILabel()
        status.text = runtime?.statusText ?? "正在连接服务"
        status.font = DHTheme.font(.caption1, weight: .medium)
        status.textColor = DHTheme.secondaryText
        let endpoint = UILabel()
        endpoint.text = appState.endpointURL?.host ?? "未配置服务"
        endpoint.font = DHTheme.font(.caption2)
        endpoint.textColor = DHTheme.tertiaryText
        let connectionLabels = UIStackView(arrangedSubviews: [status, endpoint])
        connectionLabels.axis = .vertical
        connectionLabels.spacing = 2
        connectionLabels.translatesAutoresizingMaskIntoConstraints = false
        connection.addSubview(dot)
        connection.addSubview(connectionLabels)
        NSLayoutConstraint.activate([
            connection.heightAnchor.constraint(equalToConstant: 58),
            dot.leadingAnchor.constraint(equalTo: connection.leadingAnchor, constant: 14),
            dot.centerYAnchor.constraint(equalTo: connection.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            connectionLabels.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 10),
            connectionLabels.centerYAnchor.constraint(equalTo: connection.centerYAnchor),
            connectionLabels.trailingAnchor.constraint(equalTo: connection.trailingAnchor, constant: -10)
        ])
        sidebarContent.addArrangedSubview(connection)
        sidebarContent.addArrangedSubview(sidebarButton(title: "设置", icon: "gearshape") { [weak self] in self?.onSettings() })
    }

    private func sidebarHint(icon: String, title: String, message: String) -> UIView {
        let card = UIView()
        card.dhApplyCard(backgroundColor: DHTheme.surfaceMuted, cornerRadius: DHTheme.cornerSmall)
        let iconView = dhIconView(systemName: icon, tintColor: DHTheme.secondaryText, backgroundColor: DHTheme.surfaceStrong, size: 34, symbolSize: 15)
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = DHTheme.font(.subheadline, weight: .semibold)
        let messageLabel = UILabel()
        messageLabel.text = message
        messageLabel.font = DHTheme.font(.caption2)
        messageLabel.textColor = DHTheme.secondaryText
        messageLabel.numberOfLines = 0
        let labels = UIStackView(arrangedSubviews: [titleLabel, messageLabel])
        labels.axis = .vertical
        labels.spacing = 3
        labels.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(iconView)
        card.addSubview(labels)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            iconView.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            iconView.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -12),
            labels.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            labels.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            labels.topAnchor.constraint(equalTo: card.topAnchor, constant: 11),
            labels.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -11)
        ])
        return card
    }

    private func sidebarButton(title: String, icon: String, prominent: Bool = false, action: @escaping () -> Void) -> UIButton {
        var configuration = prominent ? UIButton.Configuration.filled() : UIButton.Configuration.plain()
        configuration.title = title
        configuration.image = UIImage(systemName: icon)
        configuration.imagePadding = 10
        configuration.cornerStyle = .medium
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        configuration.baseForegroundColor = prominent ? .white : DHTheme.text
        configuration.baseBackgroundColor = prominent ? DHTheme.accent : .clear
        let button = UIButton(configuration: configuration)
        button.contentHorizontalAlignment = .leading
        button.titleLabel?.font = DHTheme.font(.body, weight: prominent ? .semibold : .medium)
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    private func loadNativeManifest() {
        transport.loadManifest { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                if case let .success(manifest) = result { self.store.replace(manifest) }
                self.renderSidebar()
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
            DispatchQueue.main.async { self?.renderSidebar(); self?.navigationItem.prompt = status }
        }
        adapter.onSnapshot = { [weak self] result in
            DispatchQueue.main.async { self?.applyAutoSnapshot(result, endpoint: endpoint) }
        }
        adapter.start()
        renderSidebar()
    }

    private func applyAutoSnapshot(_ result: Result<NativeUINode, Error>, endpoint: URL) {
        let pluginID = "auto.projected.harness"
        let surfaceID = "auto.projected.harness.main"
        let plugin = NativeUIPlugin(id: pluginID, name: "自动适配界面", version: "runtime", enabled: true, nativeMode: "dom-projection", legacyURL: endpoint.absoluteString)
        let root: NativeUINode
        switch result {
        case let .success(node): root = node
        case let .failure(error):
            root = NativeUINode(type: "legacy", id: "auto-fallback", title: "Harness 兼容页面", subtitle: error.localizedDescription, url: endpoint.absoluteString)
        }
        let surface = NativeUISurface(id: surfaceID, pluginID: pluginID, title: "自动转换界面", subtitle: "现有 dsh.client 页面", icon: "wand.and.stars", placement: "sidebar", root: root, legacyURL: endpoint.absoluteString, order: -1000)
        let current = store.manifest
        var plugins = current.plugins.filter { $0.id != pluginID }
        plugins.append(plugin)
        var surfaces = current.surfaces.filter { $0.id != surfaceID }
        surfaces.append(surface)
        store.replace(NativeUIManifest(protocolVersion: current.protocolVersion, generatedAt: current.generatedAt, plugins: plugins, surfaces: surfaces, diagnostics: current.diagnostics))
    }

    private func makeActionHandler() -> NativeUIActionHandler {
        { [weak self] surfaceID, nodeID, action, payload, completion in
            guard let self else { completion(.failure(NativeUITransportError.message("Native UI 页面已退出。"))); return }
            if action.hasPrefix("dom.") {
                let event = action == "dom.input" ? "dom.input" : (action == "dom.toggle" ? "dom.toggle" : "dom.click")
                self.autoAdapter?.dispatch(nodeID: nodeID, event: event, value: payload["value"])
                completion(.success(NativeUIActionResponse(ok: true, message: nil, manifest: nil)))
                return
            }
            self.transport.perform(surfaceID: surfaceID, nodeID: nodeID, action: action, payload: payload, completion: completion)
        }
    }

    private func openPluginCenter() {
        let controller = NativePluginCenterViewController(store: store, transport: transport, actionHandler: makeActionHandler(), fallbackHandler: { [weak self] url in self?.openLegacy(url: url) })
        navigationController?.pushViewController(controller, animated: true)
    }

    private func open(surface: NativeUISurface) {
        if surface.isLegacyOnly { openLegacy(url: surface.legacyURL ?? surface.root.url); return }
        let controller = NativeUISurfaceViewController(surface: surface, store: store, transport: transport, actionHandler: makeActionHandler(), fallbackHandler: { [weak self] url in self?.openLegacy(url: url) })
        navigationController?.pushViewController(controller, animated: true)
    }

    private func openLegacy(url rawURL: String?) {
        guard let rawURL, let url = URL(string: rawURL) else { showNotice("此区域需要兼容层，但没有可用的页面地址。"); return }
        navigationController?.pushViewController(HarnessViewController(url: url), animated: true)
    }

    @objc func toggleSidebar() {
        isSidebarVisible.toggle()
        sidebarScrim.isHidden = false
        UIView.animate(withDuration: 0.24, delay: 0, options: [.curveEaseOut]) {
            self.sidebar.transform = self.isSidebarVisible ? .identity : CGAffineTransform(translationX: -320, y: 0)
            self.sidebarScrim.alpha = self.isSidebarVisible ? 1 : 0
        } completion: { _ in
            self.sidebarScrim.isHidden = !self.isSidebarVisible
        }
        if !isSidebarVisible { view.endEditing(true) }
    }

    private func showNotice(_ message: String) {
        let alert = UIAlertController(title: "Harness", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "知道了", style: .default))
        present(alert, animated: true)
    }
}

final class NativeConversationViewController: UIViewController, UITableViewDataSource, UITextViewDelegate {
    private let onSend: (String) -> Void
    private var messages: [(text: String, isUser: Bool)] = [
        ("你好，我是 Harness。\n\n原生界面已经准备好，插件入口也会在这里出现。", false)
    ]
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let inputContainer = UIView()
    private let input = UITextView()
    private let sendButton = UIButton(type: .system)
    private let modelButton = UIButton(type: .system)
    private let attachButton = UIButton(type: .system)
    private let emptyState = UIView()
    private let welcomeHeader = UIView()
    private var inputHeightConstraint: NSLayoutConstraint!

    init(onSend: @escaping (String) -> Void) {
        self.onSend = onSend
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DHTheme.background
        buildHeader()
        buildMessages()
        buildComposer()
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardChanged(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func buildHeader() {
        welcomeHeader.translatesAutoresizingMaskIntoConstraints = false
        let icon = dhIconView(systemName: "sparkles", size: 36, symbolSize: 16)
        let title = UILabel()
        title.text = "今天想做什么？"
        title.font = DHTheme.font(.title2, weight: .bold)
        let subtitle = UILabel()
        subtitle.text = "连接到你的 Harness 工作区"
        subtitle.font = DHTheme.font(.subheadline)
        subtitle.textColor = DHTheme.secondaryText
        let labels = UIStackView(arrangedSubviews: [title, subtitle])
        labels.axis = .vertical
        labels.spacing = 3
        labels.translatesAutoresizingMaskIntoConstraints = false
        welcomeHeader.addSubview(icon)
        welcomeHeader.addSubview(labels)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: welcomeHeader.leadingAnchor),
            icon.topAnchor.constraint(equalTo: welcomeHeader.topAnchor),
            icon.bottomAnchor.constraint(equalTo: welcomeHeader.bottomAnchor),
            labels.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 11),
            labels.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
            labels.trailingAnchor.constraint(equalTo: welcomeHeader.trailingAnchor)
        ])
        view.addSubview(welcomeHeader)
    }

    private func buildMessages() {
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.register(DHMessageCell.self, forCellReuseIdentifier: DHMessageCell.reuseIdentifier)
        tableView.separatorStyle = .none
        tableView.keyboardDismissMode = .interactive
        tableView.contentInset = UIEdgeInsets(top: 14, left: 0, bottom: 12, right: 0)
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.verticalScrollIndicatorInsets = UIEdgeInsets(top: 0, left: 0, bottom: 8, right: 0)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
    }

    private func buildComposer() {
        inputContainer.dhApplyCard(backgroundColor: DHTheme.surface, cornerRadius: DHTheme.cornerLarge, shadow: true)
        inputContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(inputContainer)

        input.font = DHTheme.font(.body)
        input.textColor = DHTheme.text
        input.backgroundColor = .clear
        input.layer.cornerRadius = 14
        input.textContainerInset = UIEdgeInsets(top: 13, left: 13, bottom: 10, right: 13)
        input.textContainer.lineFragmentPadding = 0
        input.delegate = self
        input.returnKeyType = .default
        input.translatesAutoresizingMaskIntoConstraints = false
        inputContainer.addSubview(input)

        var attachConfig = UIButton.Configuration.plain()
        attachConfig.image = UIImage(systemName: "paperclip")
        attachConfig.baseForegroundColor = DHTheme.secondaryText
        attachConfig.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 7, bottom: 7, trailing: 7)
        attachButton.configuration = attachConfig
        attachButton.accessibilityLabel = "添加附件"
        attachButton.addAction(UIAction { [weak self] _ in self?.showAttachmentNotice() }, for: .touchUpInside)
        attachButton.translatesAutoresizingMaskIntoConstraints = false
        inputContainer.addSubview(attachButton)

        modelButton.setTitle("默认模型", for: .normal)
        modelButton.setImage(UIImage(systemName: "slider.horizontal.3"), for: .normal)
        modelButton.tintColor = DHTheme.secondaryText
        modelButton.setTitleColor(DHTheme.secondaryText, for: .normal)
        modelButton.titleLabel?.font = DHTheme.font(.caption1, weight: .medium)
        modelButton.configuration?.imagePadding = 5
        modelButton.addAction(UIAction { [weak self] _ in self?.showModelNotice() }, for: .touchUpInside)
        modelButton.translatesAutoresizingMaskIntoConstraints = false
        inputContainer.addSubview(modelButton)

        var config = UIButton.Configuration.filled()
        config.image = UIImage(systemName: "arrow.up")
        config.cornerStyle = .capsule
        config.baseBackgroundColor = DHTheme.accent
        config.baseForegroundColor = .white
        config.contentInsets = NSDirectionalEdgeInsets(top: 9, leading: 9, bottom: 9, trailing: 9)
        sendButton.configuration = config
        sendButton.accessibilityLabel = "发送"
        sendButton.addTarget(self, action: #selector(send), for: .touchUpInside)
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        inputContainer.addSubview(sendButton)

        inputHeightConstraint = input.heightAnchor.constraint(greaterThanOrEqualToConstant: 48)
        NSLayoutConstraint.activate([
            inputContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            inputContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            inputContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            inputHeightConstraint,
            input.heightAnchor.constraint(lessThanOrEqualToConstant: 128),
            input.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor, constant: 10),
            input.trailingAnchor.constraint(equalTo: inputContainer.trailingAnchor, constant: -10),
            input.topAnchor.constraint(equalTo: inputContainer.topAnchor, constant: 4),
            input.bottomAnchor.constraint(equalTo: modelButton.topAnchor, constant: -2),
            attachButton.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor, constant: 10),
            attachButton.bottomAnchor.constraint(equalTo: inputContainer.bottomAnchor, constant: -8),
            attachButton.widthAnchor.constraint(equalToConstant: 36),
            attachButton.heightAnchor.constraint(equalToConstant: 36),
            modelButton.leadingAnchor.constraint(equalTo: attachButton.trailingAnchor, constant: 2),
            modelButton.bottomAnchor.constraint(equalTo: inputContainer.bottomAnchor, constant: -9),
            modelButton.heightAnchor.constraint(equalToConstant: 28),
            sendButton.trailingAnchor.constraint(equalTo: inputContainer.trailingAnchor, constant: -10),
            sendButton.bottomAnchor.constraint(equalTo: inputContainer.bottomAnchor, constant: -8),
            sendButton.widthAnchor.constraint(equalToConstant: 38),
            sendButton.heightAnchor.constraint(equalToConstant: 38)
        ])
        inputContainer.setContentCompressionResistancePriority(.required, for: .vertical)
        NSLayoutConstraint.activate([
            welcomeHeader.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            welcomeHeader.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            welcomeHeader.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 18),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: welcomeHeader.bottomAnchor, constant: 8),
            tableView.bottomAnchor.constraint(equalTo: inputContainer.topAnchor, constant: -8)
        ])
    }

    @objc private func send() {
        let text = input.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messages.append((text, true))
        input.text = ""
        inputHeightConstraint.constant = 48
        tableView.reloadData()
        scrollToBottom(animated: true)
        onSend(text)
    }

    private func scrollToBottom(animated: Bool) {
        guard !messages.isEmpty else { return }
        tableView.scrollToRow(at: IndexPath(row: messages.count - 1, section: 0), at: .bottom, animated: animated)
    }

    private func showModelNotice() {
        let alert = UIAlertController(title: "模型", message: "模型选择将在接入 Harness Models Remote 后显示。", preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "知道了", style: .cancel))
        if let popover = alert.popoverPresentationController { popover.sourceView = modelButton; popover.sourceRect = modelButton.bounds }
        present(alert, animated: true)
    }

    private func showAttachmentNotice() {
        let alert = UIAlertController(title: "添加附件", message: "附件选择器会在接入 Harness 文件通道后启用。", preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "知道了", style: .cancel))
        if let popover = alert.popoverPresentationController { popover.sourceView = attachButton; popover.sourceRect = attachButton.bounds }
        present(alert, animated: true)
    }

    @objc private func keyboardChanged(_ notification: Notification) {
        guard let info = notification.userInfo,
              let frame = info[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = info[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval else { return }
        let converted = view.convert(frame, from: nil)
        let overlap = max(0, view.bounds.maxY - converted.minY - view.safeAreaInsets.bottom)
        inputContainer.transform = CGAffineTransform(translationX: 0, y: -overlap)
        UIView.animate(withDuration: duration) { self.view.layoutIfNeeded() }
    }

    func textViewDidChange(_ textView: UITextView) {
        let height = min(max(textView.contentSize.height + 8, 48), 128)
        inputHeightConstraint.constant = height
        UIView.performWithoutAnimation { self.view.layoutIfNeeded() }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { messages.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: DHMessageCell.reuseIdentifier, for: indexPath) as! DHMessageCell
        let message = messages[indexPath.row]
        cell.configure(text: message.text, isUser: message.isUser)
        return cell
    }
}

final class DHMessageCell: UITableViewCell {
    static let reuseIdentifier = "DHMessageCell"
    private let bubble = UIView()
    private let messageLabel = UILabel()
    private let avatar = UIView()
    private var bubbleLeading: NSLayoutConstraint!
    private var bubbleTrailing: NSLayoutConstraint!
    private var avatarLeading: NSLayoutConstraint!
    private var avatarTrailing: NSLayoutConstraint!

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        contentView.backgroundColor = .clear
        avatar.layer.cornerRadius = 14
        avatar.translatesAutoresizingMaskIntoConstraints = false
        let image = UIImageView(image: UIImage(systemName: "sparkles"))
        image.tintColor = DHTheme.accent
        image.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        image.translatesAutoresizingMaskIntoConstraints = false
        avatar.addSubview(image)
        NSLayoutConstraint.activate([
            avatar.widthAnchor.constraint(equalToConstant: 28),
            avatar.heightAnchor.constraint(equalToConstant: 28),
            image.centerXAnchor.constraint(equalTo: avatar.centerXAnchor),
            image.centerYAnchor.constraint(equalTo: avatar.centerYAnchor)
        ])
        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.layer.cornerRadius = DHTheme.cornerMedium
        bubble.layer.masksToBounds = true
        messageLabel.font = DHTheme.font(.body)
        messageLabel.numberOfLines = 0
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        bubble.addSubview(messageLabel)
        contentView.addSubview(avatar)
        contentView.addSubview(bubble)
        bubbleLeading = bubble.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 56)
        bubbleTrailing = bubble.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18)
        avatarLeading = avatar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18)
        avatarTrailing = avatar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18)
        NSLayoutConstraint.activate([
            bubble.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 7),
            bubble.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -7),
            bubble.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.82),
            messageLabel.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 14),
            messageLabel.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -14),
            messageLabel.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 11),
            messageLabel.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -11),
            avatar.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 7)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(text: String, isUser: Bool) {
        messageLabel.text = text
        messageLabel.textColor = isUser ? .white : DHTheme.text
        bubble.backgroundColor = isUser ? DHTheme.userBubble : DHTheme.assistantBubble
        avatar.isHidden = isUser
        bubbleLeading.isActive = !isUser
        bubbleTrailing.isActive = isUser
        avatarLeading.isActive = !isUser
        avatarTrailing.isActive = false
        if isUser {
            avatarLeading.isActive = false
        }
        bubble.layer.borderWidth = isUser ? 0 : 1
        bubble.layer.borderColor = DHTheme.separator.withAlphaComponent(0.45).cgColor
    }
}

final class DHNavigationAppearance {
    static func make() -> UINavigationBarAppearance {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = DHTheme.background
        appearance.shadowColor = .clear
        appearance.titleTextAttributes = [.foregroundColor: DHTheme.text, .font: DHTheme.font(.headline, weight: .semibold)]
        return appearance
    }
}
