import UIKit
import PhotosUI
import UniformTypeIdentifiers

/// The UI-only input contract for the v3 conversation shell.  It deliberately
/// contains presentation values rather than Runtime or network types so a
/// screenshot fixture can exercise the same UIKit hierarchy as production.
struct ConversationScreenState: Equatable {
    enum Mode: Int, CaseIterable { case conversation, process, trajectory, artifacts }
    enum EventKind: Equatable { case user, assistant, thinking, tool }
    enum EventStatus: Equatable { case running, completed, failed, pending }
    struct Event: Equatable {
        let id: String
        let kind: EventKind
        let title: String
        let detail: String?
        let body: String?
        let status: EventStatus
        let summary: [String]
        let expanded: Bool
        let isMarkdown: Bool
    }

    var sessionTitle: String
    var workspaceStatus: String
    var model: String
    var reasoning: String
    var permission: String
    var attachmentSummary: String
    var statusText: String
    var statusHint: String
    var isRunning: Bool
    var errorText: String?
    var mode: Mode
    var events: [Event]
    var guidanceAvailable: Bool
    var guidanceDisabled: Bool = false

    static let unavailable = "不可用"
}

/// A native UIKit conversation page.  The host continues to own the drawer,
/// settings and bottom navigation; this controller owns only the conversation
/// shell, timeline and composer.
final class PocketConversationViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UITextViewDelegate, PHPickerViewControllerDelegate, UIDocumentPickerDelegate {
    private let runtime: HarnessRuntime
    private let appState: AppState
    private let onOpenContext: () -> Void
    private let onBack: () -> Void
    // Kept as a routing seam for the host. Settings is intentionally not shown
    // in this page's top bar in conversation-v3.
    private let onSettings: () -> Void
    private var stopObserving: (() -> Void)?
    private var stopEventObserving: (() -> Void)?

    private let topBar = UIView()
    private let backButton = UIButton(type: .system)
    private let newConversationButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let workspaceLabel = UILabel()
    private let modeTabs = AppleConversationModeTabs()
    private let configPanel = UIView()
    private let configCaption = UILabel()
    private let configStack = UIStackView()
    private let modelConfigButton = ConversationConfigButton()
    private let reasoningConfigButton = ConversationConfigButton()
    private let permissionConfigButton = ConversationConfigButton()
    private let attachmentConfigButton = ConversationConfigButton()

    private let table = UITableView(frame: .zero, style: .plain)
    private let statusControl = UIControl()
    private let statusIcon = UIImageView()
    private let statusLabel = UILabel()
    private let statusHint = UILabel()
    private let guidanceBanner = UIView()
    private let guidanceIcon = UIImageView()
    private let guidanceTitle = UILabel()
    private let guidanceDetail = UILabel()
    private var guidanceBannerHeight: NSLayoutConstraint!
    private var guidanceTableTopToConfigConstraint: NSLayoutConstraint!
    private var guidanceTableTopToBannerConstraint: NSLayoutConstraint!
    #if DEBUG
    private var fixtureThinkingStateInitialized = false
    #endif

    private let composer = UIView()
    private let composerStack = UIStackView()
    private let inputWrapper = UIView()
    private let input = PocketInputTextView()
    private let placeholder = UILabel()
    private let attachmentScroll = UIScrollView()
    private let attachmentStrip = UIStackView()
    private let plusButton = UIButton(type: .system)
    private let referenceButton = UIButton(type: .system)
    private let permissionButton = UIButton(type: .system)
    private let modelButton = UIButton(type: .system)
    private let reasoningButton = UIButton(type: .system)
    private let sendButton = UIButton(type: .system)
    private var inputHeight: NSLayoutConstraint!

    private let menuOverlay = UIControl()
    private var menuCard: UIView?
    private var menuDismissWorkItem: DispatchWorkItem?

    private var mode: ConversationScreenState.Mode = .conversation
    private var thinkingExpanded = false
    private var images: [[String: Any]] = []
    private var screenState: ConversationScreenState!
    private var visibleEvents: [ConversationScreenState.Event] = []
    private var visibleArtifacts: [HarnessArtifact] = []
    private var isNearBottom = true
    private var isLoadingOlder = false
    private var previousVisibleIDs: [String] = []

    init(runtime: HarnessRuntime, appState: AppState, onOpenContext: @escaping () -> Void = {}, onBack: @escaping () -> Void = {}, onSettings: @escaping () -> Void = {}) {
        self.runtime = runtime
        self.appState = appState
        self.onOpenContext = onOpenContext
        self.onBack = onBack
        self.onSettings = onSettings
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        buildTopBar()
        buildModesAndConfig()
        buildComposer()
        buildStatus()
        buildGuidanceBanner()
        buildTimeline()
        buildMenuOverlay()
        stopObserving = runtime.observeChanges { [weak self] in
            DispatchQueue.main.async { self?.render() }
        }
        stopEventObserving = runtime.observeEvents { [weak self] _ in
            DispatchQueue.main.async { self?.render() }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(settingsDidChange), name: .harnessClientSettingsDidChange, object: appState)
        #if DEBUG
        initializeFixtureThinkingStateIfNeeded()
        #endif
        render()
    }

    deinit {
        stopObserving?()
        stopEventObserving?()
        NotificationCenter.default.removeObserver(self)
    }

    #if DEBUG
    func fixtureSelectMode(_ index: Int) {
        guard let next = ConversationScreenState.Mode(rawValue: index) else { return }
        mode = next
        modeTabs.selectedIndex = index
        render()
    }

    func fixtureFocusComposer() { input.becomeFirstResponder() }
    func fixtureShowPlusMenu() { showPlusMenu() }
    func fixtureShowReferenceMenu() { showReferenceMenu() }
    #endif

    private func configureIconButton(_ button: UIButton, icon: String, label: String) {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: icon)
        configuration.baseForegroundColor = .systemBlue
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 9, leading: 9, bottom: 9, trailing: 9)
        button.configuration = configuration
        button.accessibilityLabel = label
        button.accessibilityTraits = .button
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    }

    private func buildTopBar() {
        topBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topBar)
        configureIconButton(backButton, icon: "chevron.left", label: "返回工作台")
        backButton.addAction(UIAction { [weak self] _ in self?.onBack() }, for: .touchUpInside)
        configureIconButton(newConversationButton, icon: "plus.bubble", label: "新会话")
        newConversationButton.addAction(UIAction { [weak self] _ in self?.showUnavailable("新会话") }, for: .touchUpInside)

        titleLabel.font = DHTheme.font(.headline, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.numberOfLines = 1
        titleLabel.accessibilityTraits = .header
        workspaceLabel.font = DHTheme.font(.caption2)
        workspaceLabel.textColor = .secondaryLabel
        workspaceLabel.textAlignment = .center
        workspaceLabel.lineBreakMode = .byTruncatingMiddle
        workspaceLabel.numberOfLines = 1
        let center = UIStackView(arrangedSubviews: [titleLabel, workspaceLabel])
        center.axis = .vertical
        center.alignment = .fill
        center.spacing = 1
        center.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(center)
        topBar.addSubview(backButton)
        topBar.addSubview(newConversationButton)
        NSLayoutConstraint.activate([
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 50),
            backButton.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 10),
            backButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            newConversationButton.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -10),
            newConversationButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            center.leadingAnchor.constraint(greaterThanOrEqualTo: backButton.trailingAnchor, constant: 10),
            center.trailingAnchor.constraint(lessThanOrEqualTo: newConversationButton.leadingAnchor, constant: -10),
            center.centerXAnchor.constraint(equalTo: topBar.centerXAnchor),
            center.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            center.widthAnchor.constraint(lessThanOrEqualTo: topBar.widthAnchor, constant: -116)
        ])
    }

    private func buildModesAndConfig() {
        modeTabs.translatesAutoresizingMaskIntoConstraints = false
        modeTabs.onSelect = { [weak self] index in
            guard let self, let next = ConversationScreenState.Mode(rawValue: index) else { return }
            self.mode = next
            self.render()
        }
        view.addSubview(modeTabs)

        configPanel.translatesAutoresizingMaskIntoConstraints = false
        configPanel.dhApplyCard(backgroundColor: .secondarySystemGroupedBackground, cornerRadius: 14, borderColor: nil, shadow: false)
        view.addSubview(configPanel)
        configCaption.text = "配置"
        configCaption.font = DHTheme.font(.caption2)
        configCaption.textColor = .tertiaryLabel
        configCaption.translatesAutoresizingMaskIntoConstraints = false
        configPanel.addSubview(configCaption)
        configStack.axis = .horizontal
        configStack.distribution = .fillEqually
        configStack.spacing = 2
        configStack.translatesAutoresizingMaskIntoConstraints = false
        configPanel.addSubview(configStack)
        [modelConfigButton, reasoningConfigButton, permissionConfigButton, attachmentConfigButton].forEach { configStack.addArrangedSubview($0) }
        modelConfigButton.onTap = { [weak self] in self?.chooseModel() }
        reasoningConfigButton.onTap = { [weak self] in self?.chooseReasoning() }
        permissionConfigButton.onTap = { [weak self] in self?.choosePermission() }
        attachmentConfigButton.onTap = { [weak self] in self?.showPlusMenu() }
        NSLayoutConstraint.activate([
            modeTabs.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            modeTabs.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            modeTabs.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 7),
            modeTabs.heightAnchor.constraint(equalToConstant: 48),
            configPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            configPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            configPanel.topAnchor.constraint(equalTo: modeTabs.bottomAnchor, constant: 12),
            configPanel.heightAnchor.constraint(equalToConstant: 58),
            configCaption.leadingAnchor.constraint(equalTo: configPanel.leadingAnchor, constant: 15),
            configCaption.topAnchor.constraint(equalTo: configPanel.topAnchor, constant: 9),
            configStack.leadingAnchor.constraint(equalTo: configPanel.leadingAnchor, constant: 10),
            configStack.trailingAnchor.constraint(equalTo: configPanel.trailingAnchor, constant: -10),
            configStack.topAnchor.constraint(equalTo: configPanel.topAnchor, constant: 23),
            configStack.bottomAnchor.constraint(equalTo: configPanel.bottomAnchor, constant: -5)
        ])
    }

    private func buildGuidanceBanner() {
        guidanceBanner.translatesAutoresizingMaskIntoConstraints = false
        guidanceBanner.dhApplyCard(backgroundColor: .tertiarySystemGroupedBackground, cornerRadius: 12, borderColor: UIColor.systemOrange.withAlphaComponent(0.45), shadow: false)
        guidanceBanner.isHidden = true
        view.addSubview(guidanceBanner)

        guidanceIcon.translatesAutoresizingMaskIntoConstraints = false
        guidanceIcon.image = UIImage(systemName: "info.circle")
        guidanceIcon.tintColor = .systemOrange
        guidanceIcon.contentMode = .scaleAspectFit
        guidanceIcon.isAccessibilityElement = false
        guidanceTitle.font = DHTheme.font(.subheadline, weight: .semibold)
        guidanceTitle.textColor = .label
        guidanceTitle.text = "引导不可用"
        guidanceTitle.isAccessibilityElement = false
        guidanceDetail.font = DHTheme.font(.caption2)
        guidanceDetail.textColor = .secondaryLabel
        guidanceDetail.numberOfLines = 2
        guidanceDetail.text = "当前会话未提供 guidance 能力；不会显示示例引导。"
        guidanceDetail.isAccessibilityElement = false
        [guidanceIcon, guidanceTitle, guidanceDetail].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            guidanceBanner.addSubview($0)
        }
        guidanceBannerHeight = guidanceBanner.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            guidanceBanner.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            guidanceBanner.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            guidanceBanner.topAnchor.constraint(equalTo: configPanel.bottomAnchor, constant: 10),
            guidanceBannerHeight,
            guidanceIcon.leadingAnchor.constraint(equalTo: guidanceBanner.leadingAnchor, constant: 12),
            guidanceIcon.topAnchor.constraint(equalTo: guidanceBanner.topAnchor, constant: 13),
            guidanceIcon.widthAnchor.constraint(equalToConstant: 22),
            guidanceIcon.heightAnchor.constraint(equalToConstant: 22),
            guidanceTitle.leadingAnchor.constraint(equalTo: guidanceIcon.trailingAnchor, constant: 9),
            guidanceTitle.trailingAnchor.constraint(equalTo: guidanceBanner.trailingAnchor, constant: -12),
            guidanceTitle.topAnchor.constraint(equalTo: guidanceBanner.topAnchor, constant: 9),
            guidanceDetail.leadingAnchor.constraint(equalTo: guidanceTitle.leadingAnchor),
            guidanceDetail.trailingAnchor.constraint(equalTo: guidanceTitle.trailingAnchor),
            guidanceDetail.topAnchor.constraint(equalTo: guidanceTitle.bottomAnchor, constant: 2),
            guidanceDetail.bottomAnchor.constraint(lessThanOrEqualTo: guidanceBanner.bottomAnchor, constant: -8)
        ])
    }

    private func buildTimeline() {
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.keyboardDismissMode = .interactive
        table.dataSource = self
        table.delegate = self
        table.estimatedRowHeight = 70
        table.rowHeight = UITableView.automaticDimension
        table.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 4, right: 0)
        table.register(ConversationEventCell.self, forCellReuseIdentifier: "conversation.event")
        table.register(ConversationArtifactCell.self, forCellReuseIdentifier: "conversation.artifact")
        table.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(table)
        guidanceTableTopToConfigConstraint = table.topAnchor.constraint(equalTo: configPanel.bottomAnchor, constant: 16)
        guidanceTableTopToBannerConstraint = table.topAnchor.constraint(equalTo: guidanceBanner.bottomAnchor, constant: 16)
        guidanceTableTopToConfigConstraint.isActive = true
        NSLayoutConstraint.activate([
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.bottomAnchor.constraint(equalTo: statusControl.topAnchor, constant: -3)
        ])
    }

    private func buildStatus() {
        statusControl.translatesAutoresizingMaskIntoConstraints = false
        statusControl.accessibilityLabel = "运行状态"
        statusControl.addTarget(self, action: #selector(statusTapped), for: .touchUpInside)
        view.addSubview(statusControl)
        statusIcon.translatesAutoresizingMaskIntoConstraints = false
        statusIcon.contentMode = .scaleAspectFit
        statusLabel.font = DHTheme.font(.subheadline, weight: .semibold)
        statusHint.font = DHTheme.font(.caption2)
        statusHint.textColor = .secondaryLabel
        [statusIcon, statusLabel, statusHint].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; statusControl.addSubview($0) }
        NSLayoutConstraint.activate([
            statusControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            statusControl.bottomAnchor.constraint(equalTo: composer.topAnchor, constant: -8),
            statusControl.heightAnchor.constraint(equalToConstant: 40),
            statusIcon.leadingAnchor.constraint(equalTo: statusControl.leadingAnchor, constant: 8),
            statusIcon.centerYAnchor.constraint(equalTo: statusControl.centerYAnchor),
            statusIcon.widthAnchor.constraint(equalToConstant: 22),
            statusIcon.heightAnchor.constraint(equalToConstant: 22),
            statusLabel.leadingAnchor.constraint(equalTo: statusIcon.trailingAnchor, constant: 6),
            statusLabel.centerYAnchor.constraint(equalTo: statusControl.centerYAnchor),
            statusHint.leadingAnchor.constraint(equalTo: statusLabel.trailingAnchor, constant: 22),
            statusHint.trailingAnchor.constraint(lessThanOrEqualTo: statusControl.trailingAnchor, constant: -4),
            statusHint.centerYAnchor.constraint(equalTo: statusControl.centerYAnchor)
        ])
    }

    private func buildComposer() {
        composer.translatesAutoresizingMaskIntoConstraints = false
        composer.dhApplyCard(backgroundColor: .secondarySystemGroupedBackground, cornerRadius: 18, borderColor: UIColor.separator.withAlphaComponent(0.65), shadow: false)
        view.addSubview(composer)
        composerStack.axis = .vertical
        composerStack.spacing = 1
        composerStack.translatesAutoresizingMaskIntoConstraints = false
        composer.addSubview(composerStack)

        inputWrapper.translatesAutoresizingMaskIntoConstraints = false
        composerStack.addArrangedSubview(inputWrapper)
        input.font = DHTheme.scaledFont(size: CGFloat(appState.settings.fontSize), textStyle: .body)
        input.textColor = .label
        input.backgroundColor = .clear
        input.textContainerInset = UIEdgeInsets(top: 3, left: 3, bottom: 2, right: 3)
        input.textContainer.lineFragmentPadding = 0
        input.delegate = self
        input.onSubmit = { [weak self] commandModified in self?.sendCurrentInput(commandModified: commandModified) }
        input.translatesAutoresizingMaskIntoConstraints = false
        inputWrapper.addSubview(input)
        placeholder.text = "继续指令…"
        placeholder.font = input.font
        placeholder.textColor = .tertiaryLabel
        placeholder.isUserInteractionEnabled = false
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        inputWrapper.addSubview(placeholder)
        inputHeight = input.heightAnchor.constraint(equalToConstant: 29)
        NSLayoutConstraint.activate([
            input.leadingAnchor.constraint(equalTo: inputWrapper.leadingAnchor, constant: 9),
            input.trailingAnchor.constraint(equalTo: inputWrapper.trailingAnchor, constant: -9),
            input.topAnchor.constraint(equalTo: inputWrapper.topAnchor),
            input.bottomAnchor.constraint(equalTo: inputWrapper.bottomAnchor),
            inputHeight,
            placeholder.leadingAnchor.constraint(equalTo: input.leadingAnchor),
            placeholder.topAnchor.constraint(equalTo: input.topAnchor, constant: 4)
        ])

        attachmentScroll.showsHorizontalScrollIndicator = false
        attachmentScroll.translatesAutoresizingMaskIntoConstraints = false
        attachmentScroll.heightAnchor.constraint(equalToConstant: 34).isActive = true
        attachmentStrip.axis = .horizontal
        attachmentStrip.spacing = 6
        attachmentStrip.translatesAutoresizingMaskIntoConstraints = false
        attachmentScroll.addSubview(attachmentStrip)
        composerStack.addArrangedSubview(attachmentScroll)
        attachmentScroll.isHidden = true
        NSLayoutConstraint.activate([
            attachmentStrip.leadingAnchor.constraint(equalTo: attachmentScroll.contentLayoutGuide.leadingAnchor, constant: 9),
            attachmentStrip.trailingAnchor.constraint(equalTo: attachmentScroll.contentLayoutGuide.trailingAnchor, constant: -9),
            attachmentStrip.topAnchor.constraint(equalTo: attachmentScroll.contentLayoutGuide.topAnchor),
            attachmentStrip.bottomAnchor.constraint(equalTo: attachmentScroll.contentLayoutGuide.bottomAnchor),
            attachmentStrip.heightAnchor.constraint(equalTo: attachmentScroll.frameLayoutGuide.heightAnchor)
        ])

        let actionsScroll = UIScrollView()
        actionsScroll.showsHorizontalScrollIndicator = false
        actionsScroll.translatesAutoresizingMaskIntoConstraints = false
        let actions = UIStackView()
        actions.axis = .horizontal
        actions.alignment = .center
        actions.spacing = 0
        actions.translatesAutoresizingMaskIntoConstraints = false
        actionsScroll.addSubview(actions)
        NSLayoutConstraint.activate([
            actions.leadingAnchor.constraint(equalTo: actionsScroll.contentLayoutGuide.leadingAnchor),
            actions.trailingAnchor.constraint(equalTo: actionsScroll.contentLayoutGuide.trailingAnchor),
            actions.topAnchor.constraint(equalTo: actionsScroll.contentLayoutGuide.topAnchor),
            actions.bottomAnchor.constraint(equalTo: actionsScroll.contentLayoutGuide.bottomAnchor),
            actions.heightAnchor.constraint(equalTo: actionsScroll.frameLayoutGuide.heightAnchor)
        ])
        actionsScroll.heightAnchor.constraint(equalToConstant: 37).isActive = true

        configureComposerIcon(plusButton, icon: "plus", label: "添加附件")
        configureComposerIcon(referenceButton, icon: "quote.opening", label: "引用")
        configureComposerText(permissionButton, title: "权限")
        configureComposerText(modelButton, title: "模型")
        configureComposerText(reasoningButton, title: "思考")
        plusButton.addAction(UIAction { [weak self] _ in self?.showPlusMenu() }, for: .touchUpInside)
        referenceButton.addAction(UIAction { [weak self] _ in self?.showReferenceMenu() }, for: .touchUpInside)
        permissionButton.addAction(UIAction { [weak self] _ in self?.choosePermission() }, for: .touchUpInside)
        modelButton.addAction(UIAction { [weak self] _ in self?.chooseModel() }, for: .touchUpInside)
        reasoningButton.addAction(UIAction { [weak self] _ in self?.chooseReasoning() }, for: .touchUpInside)
        [plusButton, referenceButton, permissionButton, modelButton, reasoningButton].forEach { actions.addArrangedSubview($0) }

        var sendConfiguration = UIButton.Configuration.filled()
        sendConfiguration.image = UIImage(systemName: "arrow.up")
        sendConfiguration.cornerStyle = .capsule
        sendConfiguration.baseBackgroundColor = .systemBlue
        sendConfiguration.baseForegroundColor = .white
        sendConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 8, bottom: 7, trailing: 8)
        sendButton.configuration = sendConfiguration
        sendButton.accessibilityLabel = "发送或停止"
        sendButton.widthAnchor.constraint(equalToConstant: 40).isActive = true
        sendButton.heightAnchor.constraint(equalToConstant: 40).isActive = true
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        sendButton.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(sendLongPress(_:))))
        let actionRow = UIStackView(arrangedSubviews: [actionsScroll, sendButton])
        actionRow.axis = .horizontal
        actionRow.alignment = .center
        actionRow.spacing = 2
        actionRow.translatesAutoresizingMaskIntoConstraints = false
        actionsScroll.setContentHuggingPriority(.defaultLow, for: .horizontal)
        actionsScroll.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        composerStack.addArrangedSubview(actionRow)
        NSLayoutConstraint.activate([
            composer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            composer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            composer.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -8),
            composerStack.leadingAnchor.constraint(equalTo: composer.leadingAnchor, constant: 7),
            composerStack.trailingAnchor.constraint(equalTo: composer.trailingAnchor, constant: -7),
            composerStack.topAnchor.constraint(equalTo: composer.topAnchor, constant: 3),
            composerStack.bottomAnchor.constraint(equalTo: composer.bottomAnchor, constant: -3)
        ])
    }

    private func configureComposerIcon(_ button: UIButton, icon: String, label: String) {
        var c = UIButton.Configuration.plain()
        c.image = UIImage(systemName: icon)
        c.baseForegroundColor = .systemBlue
        c.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 19, weight: .medium)
        c.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 8, bottom: 7, trailing: 8)
        button.configuration = c
        button.accessibilityLabel = label
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
    }

    private func configureComposerText(_ button: UIButton, title: String) {
        var c = UIButton.Configuration.plain()
        c.title = title
        c.baseForegroundColor = .systemBlue
        c.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 5, bottom: 7, trailing: 5)
        button.configuration = c
        button.titleLabel?.font = DHTheme.font(.caption2, weight: .medium)
        button.accessibilityLabel = title
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
    }

    private func buildMenuOverlay() {
        menuOverlay.translatesAutoresizingMaskIntoConstraints = false
        menuOverlay.backgroundColor = .clear
        menuOverlay.isHidden = true
        menuOverlay.addTarget(self, action: #selector(dismissMenu), for: .touchUpInside)
        view.addSubview(menuOverlay)
        NSLayoutConstraint.activate([
            menuOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            menuOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            menuOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            menuOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    @objc private func settingsDidChange() {
        input.font = DHTheme.scaledFont(size: CGFloat(appState.settings.fontSize), textStyle: .body)
        placeholder.font = input.font
        table.reloadData()
        render()
    }

    @objc private func modeChanged() { render() }

    private func render() {
        let oldIDs = previousVisibleIDs
        let wasNearBottom = isNearBottom || isTableNearBottom()
        screenState = makeScreenState()
        visibleEvents = filteredEvents(screenState.events)
        visibleArtifacts = mode == .artifacts ? runtime.artifacts : []
        let nextIDs = mode == .artifacts ? visibleArtifacts.map(\.id) : visibleEvents.map(\.id)
        previousVisibleIDs = nextIDs
        updateHeader()
        updateGuidanceBanner()
        table.reloadData()
        renderAttachments()
        #if DEBUG
        if let fixtureScene = runtime.fixtureScene,
           ["conversation-v3-running-empty", "conversation-v3-thinking-collapsed", "conversation-v3-thinking-expanded"].contains(fixtureScene) {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.table.layoutIfNeeded()
                self.table.setContentOffset(
                    CGPoint(x: 0, y: -self.table.adjustedContentInset.top),
                    animated: false
                )
            }
            return
        }
        #endif
        if oldIDs != nextIDs && wasNearBottom {
            DispatchQueue.main.async { [weak self] in self?.scrollBottom() }
        }
    }

    private func filteredEvents(_ events: [ConversationScreenState.Event]) -> [ConversationScreenState.Event] {
        switch mode {
        case .conversation: return events
        case .process: return events.filter { $0.kind == .thinking || $0.kind == .tool }
        case .trajectory: return events
        case .artifacts: return []
        }
    }

    private func makeScreenState() -> ConversationScreenState {
        let session = runtime.sessions.first(where: { $0.id == runtime.selectedSessionID })
        let title = session?.title.isEmpty == false ? session!.title : "新会话"
        let workspace = session?.cwd.split(separator: "/").last.map(String.init) ?? "工作区"
        let connection = runtime.lastError == nil ? (runtime.connected ? runtime.statusText : "未连接") : "连接失败"
        let running = runtime.isGenerating
        var state = ConversationScreenState(
            sessionTitle: title,
            workspaceStatus: "\(workspace) · \(connection)",
            model: session?.model.isEmpty == false ? session!.model : ConversationScreenState.unavailable,
            reasoning: runtime.reasoningEffort?.isEmpty == false ? runtime.reasoningEffort! : ConversationScreenState.unavailable,
            permission: session.map { permissionName($0.permission) } ?? "未提供",
            attachmentSummary: images.isEmpty ? "0" : "\(images.count)",
            statusText: runtime.lastError == nil ? (running ? "运行中" : (runtime.connected ? "已完成" : "未连接")) : "失败",
            statusHint: runtime.lastError ?? (running ? "轻点停止本次运行" : (runtime.currentStage ?? "可继续输入")),
            isRunning: running,
            errorText: runtime.lastError,
            mode: mode,
            events: makeRuntimeEvents(),
            guidanceAvailable: false
        )
        #if DEBUG
        if let scene = runtime.fixtureScene, scene.hasPrefix("conversation-v3") {
            state = makeDebugFixtureState(scene, base: state)
        }
        #endif
        return state
    }

    private func makeRuntimeEvents() -> [ConversationScreenState.Event] {
        runtime.items.compactMap { item in
            switch item.kind {
            case .user:
                return ConversationScreenState.Event(id: item.id, kind: .user, title: "你的消息", detail: item.subtitle, body: item.text, status: .completed, summary: [], expanded: false, isMarkdown: item.isMarkdown)
            case .assistant:
                return ConversationScreenState.Event(id: item.id, kind: .assistant, title: item.subtitle ?? "Harness 回复", detail: nil, body: item.text, status: .completed, summary: [], expanded: false, isMarkdown: item.isMarkdown)
            case .tool:
                let failed = (item.subtitle ?? "").contains("失败") || (item.detail ?? "").contains("失败")
                return ConversationScreenState.Event(id: item.id, kind: .tool, title: item.text, detail: item.detail ?? "工具事件", body: nil, status: failed ? .failed : .completed, summary: [], expanded: false, isMarkdown: false)
            case .system:
                let isFailure = (item.subtitle ?? "").contains("失败") || (item.text).contains("失败")
                return ConversationScreenState.Event(id: item.id, kind: .thinking, title: item.subtitle ?? "思考摘要", detail: item.detail ?? "服务端过程摘要不可用", body: nil, status: isFailure ? .failed : (runtime.isGenerating ? .running : .completed), summary: [], expanded: thinkingExpanded, isMarkdown: false)
            }
        }
    }

    #if DEBUG
    private func initializeFixtureThinkingStateIfNeeded() {
        guard !fixtureThinkingStateInitialized,
              let scene = runtime.fixtureScene,
              scene.hasPrefix("conversation-v3") else { return }
        thinkingExpanded = scene == "conversation-v3-thinking-expanded"
        fixtureThinkingStateInitialized = true
    }

    private func makeDebugFixtureState(_ scene: String, base: ConversationScreenState) -> ConversationScreenState {
        let thinking = ConversationScreenState.Event(
            id: "fixture-thinking",
            kind: .thinking,
            title: thinkingExpanded ? "思考摘要 · balanced" : "正在思考 · balanced",
            detail: thinkingExpanded ? "服务端过程摘要" : "正在整理下一步操作 · 3.8 秒",
            body: nil,
            status: .running,
            summary: thinkingExpanded ? ["整理工作区结构", "比较方案文件", "准备下一步操作"] : [],
            expanded: thinkingExpanded,
            isMarkdown: false
        )
        let tool = ConversationScreenState.Event(id: "fixture-tool", kind: .tool, title: "读取工作区 · workspace.list", detail: "已完成 · 12 项", body: nil, status: .completed, summary: [], expanded: false, isMarkdown: false)
        let answer = ConversationScreenState.Event(id: "fixture-answer", kind: .assistant, title: "Harness 回复", detail: nil, body: "工作区已就绪，我会先整理 Pocket 项目结构，再准备下一步操作。", status: .completed, summary: [], expanded: false, isMarkdown: false)
        var result = base
        result.events = scene == "conversation-v3-running-empty" ? [] : [thinking, tool, answer]
        result.mode = mode
        result.statusText = "运行中"
        result.statusHint = "轻点停止本次运行"
        result.isRunning = true
        result.reasoning = "balanced"
        result.model = "DeepSeek V4"
        result.permission = "工作区可写"
        result.attachmentSummary = "2"
        result.guidanceDisabled = scene == "conversation-v3-guidance-disabled"
        return result
    }
    #endif

    private func updateGuidanceBanner() {
        guard let screenState else { return }
        let showBanner = screenState.guidanceDisabled
        guidanceBanner.isHidden = !showBanner
        guidanceBanner.accessibilityElementsHidden = !showBanner
        guidanceBanner.isAccessibilityElement = showBanner
        guidanceBanner.accessibilityLabel = showBanner ? "引导不可用。当前会话未提供 guidance 能力；不会显示示例引导。" : nil
        guidanceBanner.accessibilityValue = nil
        guidanceBanner.accessibilityTraits = showBanner ? [.staticText] : []
        guidanceBannerHeight.constant = showBanner ? 68 : 0
        if showBanner {
            guidanceTableTopToConfigConstraint.isActive = false
            guidanceTableTopToBannerConstraint.isActive = true
        } else {
            guidanceTableTopToBannerConstraint.isActive = false
            guidanceTableTopToConfigConstraint.isActive = true
        }
    }

    private func updateHeader() {
        guard let screenState else { return }
        titleLabel.text = screenState.sessionTitle
        titleLabel.accessibilityValue = screenState.sessionTitle
        workspaceLabel.text = screenState.workspaceStatus
        workspaceLabel.accessibilityValue = screenState.workspaceStatus
        [
            (modelConfigButton, "模型", screenState.model),
            (reasoningConfigButton, "思考", screenState.reasoning),
            (permissionConfigButton, "权限", screenState.permission),
            (attachmentConfigButton, "附件", screenState.attachmentSummary)
        ].forEach { $0.0.configure(label: $0.1, value: $0.2) }
        modelButton.configuration?.title = "模型"
        reasoningButton.configuration?.title = "思考"
        permissionButton.configuration?.title = "权限"
        let statusColor: UIColor = screenState.errorText == nil ? (screenState.isRunning ? .systemBlue : .secondaryLabel) : .systemRed
        statusLabel.text = screenState.statusText
        statusLabel.textColor = statusColor
        statusHint.text = screenState.statusHint
        statusIcon.image = UIImage(systemName: screenState.errorText == nil && screenState.isRunning ? "arrow.triangle.2.circlepath" : (screenState.errorText == nil ? "checkmark.circle" : "exclamationmark.triangle"))
        statusIcon.tintColor = statusColor
        statusControl.accessibilityLabel = "状态：\(screenState.statusText)。\(screenState.statusHint)"
        var sendConfiguration = sendButton.configuration ?? UIButton.Configuration.filled()
        sendConfiguration.image = UIImage(systemName: screenState.isRunning ? "stop.fill" : "arrow.up")
        sendConfiguration.baseBackgroundColor = screenState.isRunning ? .systemRed : .systemBlue
        sendButton.configuration = sendConfiguration
        sendButton.accessibilityLabel = screenState.isRunning ? "停止运行" : "发送"
        placeholder.isHidden = !input.text.isEmpty
    }

    @objc private func statusTapped() {
        if screenState?.isRunning == true && input.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && images.isEmpty {
            runtime.cancel()
        } else {
            showUnavailable("状态详情")
        }
    }

    @objc private func sendTapped() {
        if runtime.isGenerating && input.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && images.isEmpty {
            runtime.cancel()
            return
        }
        sendCurrentInput()
    }

    @objc private func sendLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        sendCurrentInput(explicitMode: "steer")
    }

    private func sendCurrentInput(commandModified: Bool = false, explicitMode: String? = nil) {
        let text = input.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !images.isEmpty else { return }
        let mode = explicitMode ?? HarnessBusyEnterBehavior.sendMode(for: appState.settings.busyEnter, isGenerating: runtime.isGenerating, commandModified: commandModified)
        runtime.send(text, mode: mode, images: images)
        input.text = ""
        images.removeAll()
        inputHeight.constant = 29
        renderAttachments()
        render()
    }

    func textViewDidChange(_ textView: UITextView) {
        let width = max(1, textView.bounds.width)
        let fitting = textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        inputHeight.constant = min(max(29, ceil(fitting)), 90)
        placeholder.isHidden = !textView.text.isEmpty
        view.layoutIfNeeded()
    }

    @objc private func dismissMenu() {
        menuDismissWorkItem?.cancel()
        menuCard?.removeFromSuperview()
        menuCard = nil
        menuOverlay.isHidden = true
    }

    private func showPlusMenu() {
        presentMenu(kind: .plus)
    }

    private func showReferenceMenu() {
        presentMenu(kind: .reference)
    }

    private enum MenuKind { case plus, reference }

    private func presentMenu(kind: MenuKind) {
        dismissMenu()
        menuOverlay.isHidden = false
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.dhApplyCard(backgroundColor: .secondarySystemGroupedBackground, cornerRadius: 16, borderColor: UIColor.separator.withAlphaComponent(0.7), shadow: true)
        menuOverlay.addSubview(card)
        menuCard = card
        var constraints: [NSLayoutConstraint]
        switch kind {
        case .plus:
            constraints = [card.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20), card.widthAnchor.constraint(equalToConstant: 270), card.bottomAnchor.constraint(equalTo: composer.topAnchor, constant: -24), card.heightAnchor.constraint(equalToConstant: 112)]
            addMenuRows(to: card, rows: [("photo", "上传图片", true), ("doc", "上传文件", true)], title: nil)
        case .reference:
            constraints = [card.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 48), card.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -52), card.bottomAnchor.constraint(equalTo: composer.topAnchor, constant: -8), card.heightAnchor.constraint(equalToConstant: 164)]
            addMenuRows(to: card, rows: [(nil, "引用工作区文件", false), (nil, "引用当前会话", false), (nil, "引用最近产物", false)], title: "引用")
        }
        NSLayoutConstraint.activate(constraints)
        UIAccessibility.post(notification: .layoutChanged, argument: card)
    }

    private func addMenuRows(to card: UIView, rows: [(String?, String, Bool)], title: String?) {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8), stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8), stack.topAnchor.constraint(equalTo: card.topAnchor, constant: title == nil ? 4 : 4), stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -4)])
        if let title {
            let label = UILabel()
            label.text = title
            label.font = DHTheme.font(.caption1)
            label.textColor = .tertiaryLabel
            label.textAlignment = .left
            label.translatesAutoresizingMaskIntoConstraints = false
            let wrapper = UIView()
            wrapper.addSubview(label)
            NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 16), label.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor), label.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor), wrapper.heightAnchor.constraint(equalToConstant: 30)])
            stack.addArrangedSubview(wrapper)
        }
        for (icon, title, enabled) in rows {
            let button = UIButton(type: .system)
            var configuration = UIButton.Configuration.plain()
            configuration.title = title
            configuration.image = icon.flatMap { UIImage(systemName: $0 == "doc" ? "doc" : $0) }
            configuration.imagePadding = 12
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
            configuration.baseForegroundColor = enabled ? .label : .secondaryLabel
            button.configuration = configuration
            button.contentHorizontalAlignment = .leading
            button.titleLabel?.font = DHTheme.font(.body)
            button.accessibilityLabel = enabled ? title : "\(title)，当前不可用"
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            button.isEnabled = enabled
            if enabled {
                if title == "上传图片" { button.addAction(UIAction { [weak self] _ in self?.chooseImages() }, for: .touchUpInside) }
                if title == "上传文件" { button.addAction(UIAction { [weak self] _ in self?.chooseFiles() }, for: .touchUpInside) }
            }
            stack.addArrangedSubview(button)
        }
    }

    private func chooseImages() {
        dismissMenu()
        guard images.count < 20 else { showUnavailable("附件上限") ; return }
        var configuration = PHPickerConfiguration()
        configuration.selectionLimit = min(20 - images.count, 20)
        configuration.filter = .images
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: !appState.settings.reduceMotion)
    }

    private func chooseFiles() {
        dismissMenu()
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = self
        present(picker, animated: !appState.settings.reduceMotion)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: !appState.settings.reduceMotion)
        for result in results where result.itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            result.itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] data, _ in
                guard let data else { return }
                Task { @MainActor in self?.appendImage(data, name: result.itemProvider.suggestedName) }
            }
        }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let remaining = max(0, 20 - images.count)
        for url in urls.prefix(remaining) {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            let isImage = UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true
            if isImage, let data = try? Data(contentsOf: url) {
                appendImage(data, name: url.lastPathComponent)
            } else {
                showUnavailable("文件引用")
            }
        }
    }

    private func appendImage(_ data: Data, name: String?) {
        guard images.count < 20 else { showUnavailable("附件上限"); return }
        guard data.count <= 20 * 1024 * 1024 else { showUnavailable("附件大小"); return }
        let type = name?.lowercased().hasSuffix(".png") == true ? "image/png" : "image/jpeg"
        images.append(["type": "image", "mediaType": type, "data": data.base64EncodedString(), "name": name ?? "图片"])
        renderAttachments()
        render()
    }

    private func renderAttachments() {
        attachmentStrip.arrangedSubviews.forEach { attachmentStrip.removeArrangedSubview($0); $0.removeFromSuperview() }
        attachmentScroll.isHidden = images.isEmpty
        for (index, image) in images.enumerated() {
            attachmentStrip.addArrangedSubview(PocketAttachmentChip(name: image["name"] as? String ?? "图片", data: image["data"] as? String, onRemove: { [weak self] in
                guard let self, self.images.indices.contains(index) else { return }
                self.images.remove(at: index)
                self.renderAttachments()
                self.render()
            }))
        }
    }

    private func showUnavailable(_ feature: String) {
        dismissMenu()
        statusLabel.text = "\(feature)：当前不可用"
        statusLabel.textColor = .secondaryLabel
        statusHint.text = "下一阶段实现"
        UIAccessibility.post(notification: .announcement, argument: "\(feature)当前不可用，下一阶段实现")
    }

    // Sheet routing seams are intentionally no-op for this UI-first delivery.
    @objc private func chooseModel() { showUnavailable("模型选择") }
    @objc private func chooseReasoning() { showUnavailable("思考设置") }
    @objc private func choosePermission() { showUnavailable("权限选择") }

    private func permissionName(_ value: String) -> String {
        ["read-only": "只读", "workspace-write": "工作区可写", "danger-full-access": "完全权限"][value] ?? (value.isEmpty ? "未提供" : value)
    }

    // MARK: UITableView

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        mode == .artifacts ? max(visibleArtifacts.count, 1) : max(visibleEvents.count, 1)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if mode == .artifacts {
            guard visibleArtifacts.indices.contains(indexPath.row) else { return emptyCell(text: "当前会话尚无服务端确认的产物") }
            let cell = tableView.dequeueReusableCell(withIdentifier: "conversation.artifact", for: indexPath) as! ConversationArtifactCell
            cell.configure(visibleArtifacts[indexPath.row], first: indexPath.row == 0, last: indexPath.row == visibleArtifacts.count - 1)
            return cell
        }
        guard visibleEvents.indices.contains(indexPath.row) else { return emptyCell(text: runtime.selectedSessionID == nil ? "请选择一个真实会话" : "等待服务端返回内容") }
        let cell = tableView.dequeueReusableCell(withIdentifier: "conversation.event", for: indexPath) as! ConversationEventCell
        cell.configure(visibleEvents[indexPath.row], first: indexPath.row == 0, last: indexPath.row == visibleEvents.count - 1, settings: appState.settings)
        return cell
    }

    private func emptyCell(text: String) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.backgroundColor = .clear
        cell.textLabel?.text = text
        cell.textLabel?.textColor = .secondaryLabel
        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.font = DHTheme.font(.body)
        cell.contentView.layoutMargins = UIEdgeInsets(top: 18, left: 20, bottom: 18, right: 20)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: !appState.settings.reduceMotion)
        guard mode != .artifacts, visibleEvents.indices.contains(indexPath.row) else { return }
        if visibleEvents[indexPath.row].kind == .thinking {
            thinkingExpanded.toggle()
            render()
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) { if scrollView === table { isNearBottom = isTableNearBottom() } }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard indexPath.row == 0, mode != .artifacts, runtime.hasMore, !isLoadingOlder else { return }
        isLoadingOlder = true
        let oldOffset = table.contentOffset.y
        let oldHeight = table.contentSize.height
        runtime.loadOlder { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.table.layoutIfNeeded()
                let delta = self.table.contentSize.height - oldHeight
                if delta > 0 { self.table.contentOffset.y = oldOffset + delta }
                self.isLoadingOlder = false
            }
        }
    }

    private func isTableNearBottom() -> Bool {
        let bottom = table.contentOffset.y + table.bounds.height - table.adjustedContentInset.bottom
        return table.contentSize.height <= 0 || bottom >= table.contentSize.height - 120
    }

    private func scrollBottom() {
        let count = mode == .artifacts ? visibleArtifacts.count : visibleEvents.count
        guard count > 0 else { return }
        table.scrollToRow(at: IndexPath(row: count - 1, section: 0), at: .bottom, animated: false)
        isNearBottom = true
    }
}

private final class ConversationConfigButton: UIControl {
    var onTap: (() -> Void)?
    private let labelLabel = UILabel()
    private let valueLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        labelLabel.font = DHTheme.font(.caption2)
        labelLabel.textColor = .secondaryLabel
        valueLabel.font = DHTheme.font(.caption2, weight: .semibold)
        valueLabel.textColor = .label
        valueLabel.lineBreakMode = .byTruncatingMiddle
        [labelLabel, valueLabel].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; addSubview($0) }
        NSLayoutConstraint.activate([
            labelLabel.leadingAnchor.constraint(equalTo: leadingAnchor), labelLabel.topAnchor.constraint(equalTo: topAnchor), labelLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            valueLabel.leadingAnchor.constraint(equalTo: leadingAnchor), valueLabel.topAnchor.constraint(equalTo: labelLabel.bottomAnchor, constant: 1), valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor), valueLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])
        accessibilityTraits = [.button]
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func configure(label: String, value: String) {
        labelLabel.text = label
        valueLabel.text = value
        accessibilityLabel = "\(label)：\(value)"
        accessibilityValue = value
    }

    @objc private func tapped() { onTap?() }
}

private final class ConversationEventCell: UITableViewCell {
    private let card = UIView()
    private let icon = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let statusLabel = UILabel()
    private let bodyLabel = UILabel()
    private let summaryCaption = UILabel()
    private let summaryStack = UIStackView()
    private let disclosure = UIImageView(image: UIImage(systemName: "chevron.right"))
    private var cardTop: NSLayoutConstraint!
    private var cardBottom: NSLayoutConstraint!

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .default
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerCurve = .continuous
        contentView.addSubview(card)
        cardTop = card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4)
        cardBottom = card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            cardTop,
            cardBottom,
            card.heightAnchor.constraint(greaterThanOrEqualToConstant: 72)
        ])
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.contentMode = .scaleAspectFit
        titleLabel.font = DHTheme.font(.body, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 2
        detailLabel.font = DHTheme.font(.caption1)
        detailLabel.textColor = .secondaryLabel
        detailLabel.numberOfLines = 2
        statusLabel.font = DHTheme.font(.caption1, weight: .semibold)
        statusLabel.textAlignment = .right
        bodyLabel.font = DHTheme.font(.subheadline)
        bodyLabel.textColor = .label
        bodyLabel.numberOfLines = 0
        summaryCaption.font = DHTheme.font(.caption2)
        summaryCaption.textColor = .systemBlue
        summaryStack.axis = .vertical
        summaryStack.spacing = 6
        summaryStack.translatesAutoresizingMaskIntoConstraints = false
        disclosure.translatesAutoresizingMaskIntoConstraints = false
        disclosure.tintColor = .secondaryLabel
        [icon, titleLabel, detailLabel, statusLabel, bodyLabel, summaryCaption, disclosure].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; card.addSubview($0) }
        card.addSubview(summaryStack)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16), icon.topAnchor.constraint(equalTo: card.topAnchor, constant: 18), icon.widthAnchor.constraint(equalToConstant: 20), icon.heightAnchor.constraint(equalToConstant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10), titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 14), titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: statusLabel.leadingAnchor, constant: -5),
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor), detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3), detailLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            statusLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14), statusLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor), statusLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 105),
            disclosure.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14), disclosure.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor), disclosure.widthAnchor.constraint(equalToConstant: 10), disclosure.heightAnchor.constraint(equalToConstant: 18),
            bodyLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12), bodyLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12), bodyLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 14),
            summaryCaption.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12), summaryCaption.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12), summaryCaption.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: 5),
            summaryStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8), summaryStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8), summaryStack.topAnchor.constraint(equalTo: summaryCaption.bottomAnchor, constant: 7), summaryStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -9)
        ])
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func configure(_ event: ConversationScreenState.Event, first: Bool, last: Bool, settings: HarnessClientSettings) {
        card.layer.maskedCorners = [first ? .layerMinXMinYCorner : [], first ? .layerMaxXMinYCorner : [], last ? .layerMinXMaxYCorner : [], last ? .layerMaxXMaxYCorner : []].reduce(CACornerMask()) { $0.union($1) }
        let color: UIColor
        switch event.kind {
        case .thinking: color = .systemBlue; icon.image = UIImage(systemName: "arrow.triangle.2.circlepath")
        case .tool: color = event.status == .failed ? .systemRed : .systemGreen; icon.image = UIImage(systemName: "wrench.and.screwdriver")
        case .assistant: color = .systemOrange; icon.image = UIImage(systemName: "sparkles")
        case .user: color = .systemBlue; icon.image = UIImage(systemName: "person")
        }
        icon.tintColor = color
        titleLabel.text = event.title
        detailLabel.text = event.detail
        bodyLabel.text = event.body
        bodyLabel.isHidden = event.body == nil
        summaryCaption.text = event.summary.isEmpty ? nil : "服务端过程摘要"
        summaryCaption.isHidden = event.summary.isEmpty
        summaryStack.arrangedSubviews.forEach { summaryStack.removeArrangedSubview($0); $0.removeFromSuperview() }
        for value in event.summary {
            let chip = UILabel()
            chip.text = value
            chip.font = DHTheme.scaledFont(size: 12, textStyle: .caption1)
            chip.textColor = .label
            chip.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.10)
            chip.layer.cornerRadius = 9
            chip.layer.masksToBounds = true
            chip.numberOfLines = 0
            chip.textAlignment = .left
            summaryStack.addArrangedSubview(chip)
        }
        let statusText: String
        switch event.status { case .running: statusText = "使用中"; case .completed: statusText = event.kind == .tool ? "完成 ✓" : ""; case .failed: statusText = "失败"; case .pending: statusText = "待处理" }
        statusLabel.text = statusText
        statusLabel.textColor = event.status == .failed ? .systemRed : (event.status == .running ? .systemBlue : .systemGreen)
        statusLabel.isHidden = statusText.isEmpty
        disclosure.isHidden = event.kind != .thinking && event.kind != .tool
        if event.kind == .thinking { disclosure.image = UIImage(systemName: event.expanded ? "chevron.up" : "chevron.down") }
        let normalBodyFont = DHTheme.scaledFont(size: CGFloat(settings.fontSize), textStyle: .subheadline)
        bodyLabel.font = normalBodyFont
        bodyLabel.textColor = event.kind == .user ? .systemBlue : .label
        accessibilityLabel = "\(event.title)\(event.detail.map { "，\($0)" } ?? "")\(event.body.map { "，\($0)" } ?? "")"
        accessibilityTraits = event.kind == .thinking ? [.button] : []
    }
}

private final class ConversationArtifactCell: UITableViewCell {
    private let card = UIView()
    private let icon = UIImageView()
    private let titleLabel = UILabel()
    private let pathLabel = UILabel()
    private let detailLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerCurve = .continuous
        contentView.addSubview(card)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = .systemBlue
        titleLabel.font = DHTheme.font(.body, weight: .semibold)
        titleLabel.textColor = .label
        pathLabel.font = DHTheme.font(.caption1)
        pathLabel.textColor = .secondaryLabel
        pathLabel.lineBreakMode = .byTruncatingMiddle
        detailLabel.font = DHTheme.font(.caption2)
        detailLabel.textColor = .tertiaryLabel
        [icon, titleLabel, pathLabel, detailLabel].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; card.addSubview($0) }
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20), card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20), card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4), card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            icon.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14), icon.topAnchor.constraint(equalTo: card.topAnchor, constant: 15), icon.widthAnchor.constraint(equalToConstant: 25), icon.heightAnchor.constraint(equalToConstant: 25),
            titleLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10), titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14), titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            pathLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor), pathLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor), pathLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor), detailLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor), detailLabel.topAnchor.constraint(equalTo: pathLabel.bottomAnchor, constant: 3), detailLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12)
        ])
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func configure(_ artifact: HarnessArtifact, first: Bool, last: Bool) {
        card.layer.cornerRadius = 14
        card.layer.maskedCorners = [first ? .layerMinXMinYCorner : [], first ? .layerMaxXMinYCorner : [], last ? .layerMinXMaxYCorner : [], last ? .layerMaxXMaxYCorner : []].reduce(CACornerMask()) { $0.union($1) }
        icon.image = UIImage(systemName: artifact.kind == "image" ? "photo" : "doc.richtext")
        titleLabel.text = artifact.name
        pathLabel.text = artifact.path
        detailLabel.text = artifact.detail ?? "服务端确认产物"
        accessibilityLabel = "产物：\(artifact.name)，\(artifact.path)"
    }
}

private final class PocketAttachmentChip: UIView {
    init(name: String, data: String?, onRemove: @escaping () -> Void) {
        super.init(frame: .zero)
        backgroundColor = UIColor.systemBlue.withAlphaComponent(0.10)
        layer.cornerRadius = 10
        let image = UIImageView()
        image.contentMode = .scaleAspectFill
        image.clipsToBounds = true
        image.layer.cornerRadius = 7
        image.image = data.flatMap { Data(base64Encoded: $0) }.flatMap { UIImage(data: $0) } ?? UIImage(systemName: "photo")
        image.tintColor = .systemBlue
        image.translatesAutoresizingMaskIntoConstraints = false
        let label = UILabel()
        label.text = name
        label.font = DHTheme.font(.caption2)
        label.textColor = .label
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false
        let remove = UIButton(type: .system)
        remove.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        remove.tintColor = .secondaryLabel
        remove.accessibilityLabel = "移除附件 \(name)"
        remove.addAction(UIAction { _ in onRemove() }, for: .touchUpInside)
        remove.translatesAutoresizingMaskIntoConstraints = false
        [image, label, remove].forEach(addSubview)
        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5), image.centerYAnchor.constraint(equalTo: centerYAnchor), image.widthAnchor.constraint(equalToConstant: 28), image.heightAnchor.constraint(equalToConstant: 28),
            label.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 5), label.centerYAnchor.constraint(equalTo: centerYAnchor), label.widthAnchor.constraint(lessThanOrEqualToConstant: 100),
            remove.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 3), remove.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5), remove.centerYAnchor.constraint(equalTo: centerYAnchor), remove.widthAnchor.constraint(equalToConstant: 30), remove.heightAnchor.constraint(equalToConstant: 38), heightAnchor.constraint(equalToConstant: 38)
        ])
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
}

private final class PocketInputTextView: UITextView {
    var onSubmit: ((Bool) -> Void)?
    override var keyCommands: [UIKeyCommand]? { [UIKeyCommand(input: "\r", modifierFlags: [.command], action: #selector(commandEnter)), UIKeyCommand(input: "\r", modifierFlags: [.control], action: #selector(commandEnter))] }
    @objc private func commandEnter() { onSubmit?(true) }
}

private final class AppleConversationModeTabs: UIView {
    var onSelect: ((Int) -> Void)?
    var selectedIndex = 0 { didSet { updateSelection() } }
    private let titles = ["对话", "过程", "轨迹", "产物"]
    private var buttons: [UIButton] = []
    private let underline = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 14
        layer.cornerCurve = .continuous
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        underline.backgroundColor = .systemBlue
        underline.layer.cornerRadius = 1
        underline.translatesAutoresizingMaskIntoConstraints = false
        addSubview(underline)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor), stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor), underline.bottomAnchor.constraint(equalTo: bottomAnchor), underline.heightAnchor.constraint(equalToConstant: 2), underline.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.25), underline.leadingAnchor.constraint(equalTo: leadingAnchor)])
        for (index, title) in titles.enumerated() {
            let button = UIButton(type: .system)
            button.setTitle(title, for: .normal)
            button.titleLabel?.font = DHTheme.font(.subheadline, weight: .medium)
            button.tag = index
            button.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
            button.accessibilityLabel = title
            button.accessibilityTraits = [.button]
            stack.addArrangedSubview(button)
            buttons.append(button)
        }
        updateSelection()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    @objc private func tapped(_ sender: UIButton) { selectedIndex = sender.tag; onSelect?(sender.tag) }
    private func updateSelection() {
        guard !buttons.isEmpty else { return }
        for (index, button) in buttons.enumerated() {
            let selected = index == selectedIndex
            button.setTitleColor(selected ? .systemBlue : .secondaryLabel, for: .normal)
            button.accessibilityTraits = selected ? [.button, .selected] : [.button]
        }
        underline.transform = CGAffineTransform(translationX: bounds.width * 0.25 * CGFloat(selectedIndex), y: 0)
    }
    override func layoutSubviews() { super.layoutSubviews(); updateSelection() }
}

private extension UILabel {
    var textInsets: UIEdgeInsets {
        get { .zero }
        set {
            let insetView = UIView(frame: .zero)
            insetView.isUserInteractionEnabled = false
            addSubview(insetView)
            // UILabel has no native inset API; use a layout-compatible wrapper
            // by adjusting text alignment through subclass-free padding.
            layer.masksToBounds = true
            layer.cornerRadius = 9
            _ = newValue
        }
    }
}
