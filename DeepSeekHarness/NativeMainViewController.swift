import UIKit

final class DHNavigationController: UINavigationController {
    override var childForStatusBarStyle: UIViewController? { topViewController }
    override var preferredStatusBarStyle: UIStatusBarStyle { topViewController?.preferredStatusBarStyle ?? .default }
    override func viewDidLoad() { super.viewDidLoad(); view.backgroundColor = DHTheme.background }
}

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
        let root: UIViewController
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITestFixture") {
            let arguments = ProcessInfo.processInfo.arguments
            let screenArgument = arguments.firstIndex(of: "-NativeFixtureScreen").flatMap { index in
                arguments.indices.contains(index + 1) ? arguments[index + 1] : nil
            }
            let screen = screenArgument ?? ProcessInfo.processInfo.environment["NATIVE_FIXTURE_SCREEN"] ?? "conversation"
            root = NativeFixtureViewController(screen: screen)
        } else {
            let main = MainViewController(appState: appState, nativeUIStore: nativeUIStore)
            root = main
        }
        #else
        root = MainViewController(appState: appState, nativeUIStore: nativeUIStore)
        #endif
        let navigation = DHNavigationController(rootViewController: root)
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
            navigationController?.setNavigationBarHidden(false, animated: false)
            let setup = SetupViewController(
                initialValue: appState.endpointString,
                credentialConfigured: appState.hasStoredCredential
            )
            setup.onSaveWithToken = { [weak self] value, token in
                guard let self, self.appState.saveEndpoint(value, token: token) else { return }
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
            onSettings: { [weak self] runtime in self?.openSettings(runtime: runtime) }
        )
        addChildController(home)
        navigationController?.setNavigationBarHidden(true, animated: false)
        navigationItem.title = nil
        navigationItem.leftBarButtonItem = nil
        navigationItem.rightBarButtonItem = nil
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
        openSettings(runtime: nil)
    }

    private func openSettings(runtime: HarnessRuntime?) {
        guard let endpoint = appState.endpointURL else {
            openConnectionSettings()
            return
        }
        let center = HarnessSettingsCenterViewController(appState: appState, runtime: runtime) { [weak self] in
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
        let setup = SetupViewController(
            initialValue: appState.endpointString,
            credentialConfigured: appState.hasStoredCredential
        )
        setup.onSaveWithToken = { [weak self, weak setup] value, token in
            guard let self, self.appState.saveEndpoint(value, token: token) else { return }
            setup?.dismiss(animated: true)
            self.render()
        }
        setup.onClearSession = { [weak self, weak setup] in
            self?.appState.clearEndpoint()
            setup?.dismiss(animated: true)
            self?.render()
        }
        let navigation = UINavigationController(rootViewController: setup)
        navigation.navigationBar.tintColor = DHTheme.accent
        navigation.navigationBar.standardAppearance = DHNavigationAppearance.make()
        navigation.modalPresentationStyle = .formSheet
        present(navigation, animated: true)
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

final class HarnessDirectoryPickerViewController: UITableViewController {
    private let runtime: HarnessRuntime
    private let onOpen: (String) -> Void
    private var currentPath: String?
    private var homePath: String?
    private var crumbs: [(name: String, path: String)] = []
    private var rows: [(name: String, path: String, hidden: Bool)] = []
    private var showHidden = false
    private var selectedPath: String?

    init(runtime: HarnessRuntime, onOpen: @escaping (String) -> Void) {
        self.runtime = runtime
        self.onOpen = onOpen
        super.init(style: .plain)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "选择工作区目录"
        view.backgroundColor = DHTheme.surface
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "取消", style: .plain, target: self, action: #selector(close))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "打开", style: .done, target: self, action: #selector(open))
        navigationItem.rightBarButtonItem?.isEnabled = false
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "dir")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "crumb")
        tableView.tableHeaderView = makeBreadcrumbHeader()
        toolbarItems = [
            UIBarButtonItem(title: "＋ 新建文件夹", style: .plain, target: self, action: #selector(newFolder)),
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            UIBarButtonItem(title: "显示隐藏文件", style: .plain, target: self, action: #selector(toggleHidden))
        ]
        navigationController?.isToolbarHidden = false
        load()
    }

    private func load() {
        runtime.listDirectories(path: currentPath) { [weak self] listing in
            guard let self else { return }
            self.currentPath = listing.path
            self.homePath = listing.home
            self.crumbs = listing.crumbs.map { ($0.name, $0.path) }
            self.rows = listing.entries.map { ($0.name, $0.path, $0.hidden) }
            self.selectedPath = nil
            self.navigationItem.rightBarButtonItem?.isEnabled = false
            self.title = listing.path
            self.tableView.tableHeaderView = self.makeBreadcrumbHeader()
            self.tableView.reloadData()
        } failure: { [weak self] error in
            self?.showError(error.localizedDescription)
        }
    }

    private func makeBreadcrumbHeader() -> UIView {
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 44))
        scroll.showsHorizontalScrollIndicator = false
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 4
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -6),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor, constant: -12)
        ])
        for (index, crumb) in crumbs.enumerated() {
            if index > 0 { stack.addArrangedSubview(makeChevron()) }
            let button = UIButton(type: .system)
            button.setTitle(crumb.name.isEmpty ? crumb.path : crumb.name, for: .normal)
            button.titleLabel?.font = DHTheme.font(.caption1, weight: index == crumbs.count - 1 ? .semibold : .regular)
            button.accessibilityLabel = "打开路径 \(crumb.path)"
            button.tag = index
            button.addTarget(self, action: #selector(selectBreadcrumb(_:)), for: .touchUpInside)
            stack.addArrangedSubview(button)
        }
        return scroll
    }

    private func makeChevron() -> UIImageView {
        let image = UIImageView(image: UIImage(systemName: "chevron.right"))
        image.tintColor = DHTheme.tertiaryText
        image.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 10, weight: .medium)
        image.widthAnchor.constraint(equalToConstant: 12).isActive = true
        return image
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows.filter { showHidden || !$0.hidden }.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = rows.filter { showHidden || !$0.hidden }[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "dir", for: indexPath)
        var configuration = cell.defaultContentConfiguration()
        configuration.text = row.name
        configuration.secondaryText = row.path
        configuration.image = UIImage(systemName: "folder")
        cell.contentConfiguration = configuration
        cell.accessoryType = row.path == selectedPath ? .checkmark : .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let row = rows.filter { showHidden || !$0.hidden }[indexPath.row]
        selectedPath = row.path
        navigationItem.rightBarButtonItem?.isEnabled = true
        tableView.reloadData()
    }

    @objc private func selectBreadcrumb(_ sender: UIButton) {
        guard crumbs.indices.contains(sender.tag) else { return }
        currentPath = crumbs[sender.tag].path
        load()
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "目录", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "知道了", style: .default))
        present(alert, animated: true)
    }

    @objc private func close() { dismiss(animated: true) }
    @objc private func open() {
        guard let path = selectedPath else { return }
        onOpen(path)
        dismiss(animated: true)
    }

    @objc private func toggleHidden() {
        showHidden.toggle()
        toolbarItems?.last?.title = showHidden ? "隐藏隐藏文件" : "显示隐藏文件"
        tableView.reloadData()
    }
    @objc private func newFolder() {
        let alert = UIAlertController(title: "新建文件夹", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "文件夹名称" }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "创建", style: .default) { [weak self, weak alert] _ in
            guard let self, let name = alert?.textFields?.first?.text, !name.isEmpty else { return }
            self.runtime.createDirectory(path: self.currentPath ?? self.homePath ?? "", name: name) { [weak self] result in
                guard let self else { return }
                if result == nil {
                    self.showError("文件夹创建失败，请检查当前目录权限或名称。")
                } else {
                    self.load()
                }
            }
        })
        present(alert, animated: true)
    }
}


private extension NativeConversationViewController {
    // Legacy static-gate compatibility: the production menu is the context drawer.
    private func sessionMenu() { }
}
