import UIKit
import PhotosUI
import UniformTypeIdentifiers

/// The production Pocket task console. It keeps the previous native controls
/// (model, reasoning, permission, attachments, paging, queue/steer) while
/// presenting them inside the V2 conversation/process/artifact surface.
final class PocketConversationViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UITextViewDelegate, UISearchBarDelegate, PHPickerViewControllerDelegate, UIDocumentPickerDelegate {
    private let runtime: HarnessRuntime
    private let appState: AppState
    private let onOpenContext: () -> Void
    private let onBack: () -> Void
    private let onSettings: () -> Void
    private var stopObserving: (() -> Void)?

    private let topBar = UIView()
    private let backButton = UIButton(type: .system)
    private let drawerButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let stateButton = UIButton(type: .system)
    private let settingsButton = UIButton(type: .system)
    private let modeControl = UISegmentedControl(items: ["对话", "过程", "产物"])
    private let processControls = UIView()
    private let processSearch = UISearchBar()
    private let processTurns = UIButton(type: .system)
    private let processCalls = UIButton(type: .system)
    private let processDuration = UIButton(type: .system)
    private var processControlsHeight: NSLayoutConstraint!
    private let table = UITableView(frame: .zero, style: .plain)
    private let composer = UIView()
    private let composerStack = UIStackView()
    private let inputWrapper = UIView()
    private let input = UITextView()
    private let placeholder = UILabel()
    private let attachmentScroll = UIScrollView()
    private let attachmentStrip = UIStackView()
    private let attachButton = UIButton(type: .system)
    private let permissionButton = UIButton(type: .system)
    private let modelButton = UIButton(type: .system)
    private let sendModeButton = UIButton(type: .system)
    private let sendButton = UIButton(type: .system)
    private let status = UILabel()
    private var inputHeight: NSLayoutConstraint!

    private var mode = 0
    private var showTurns = true
    private var showCalls = true
    private var processQuery = ""
    private var selectedSendMode = "queue"
    private var images: [[String: Any]] = []
    private var visibleItems: [HarnessConversationItem] = []
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
        view.backgroundColor = DHTheme.background
        buildTopBar()
        buildModes()
        buildProcessControls()
        buildTable()
        buildComposer()
        stopObserving = runtime.observeChanges { [weak self] in
            DispatchQueue.main.async { self?.render() }
        }
        runtime.onApproval = { [weak self] _ in
            DispatchQueue.main.async { self?.render() }
        }
        runtime.onQuestion = { [weak self] _ in
            DispatchQueue.main.async { self?.render() }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(settingsDidChange), name: .harnessClientSettingsDidChange, object: appState)
        render()
    }

    deinit {
        stopObserving?()
        NotificationCenter.default.removeObserver(self)
        runtime.onApproval = nil
        runtime.onQuestion = nil
    }

    #if DEBUG
    func fixtureSelectMode(_ index: Int) { modeControl.selectedSegmentIndex = index; modeChanged() }
    func fixtureFocusComposer() { input.becomeFirstResponder() }
    #endif

    private func makeIconButton(_ button: UIButton, icon: String, label: String) {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: icon)
        config.baseForegroundColor = DHTheme.text
        config.contentInsets = NSDirectionalEdgeInsets(top: 9, leading: 8, bottom: 9, trailing: 8)
        button.configuration = config
        button.accessibilityLabel = label
        button.accessibilityTraits = .button
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    }

    private func buildTopBar() {
        topBar.backgroundColor = DHTheme.surface
        topBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topBar)
        makeIconButton(backButton, icon: "chevron.left", label: "返回工作台")
        makeIconButton(drawerButton, icon: "sidebar.left", label: "打开上下文抽屉")
        backButton.addAction(UIAction { [weak self] _ in self?.onBack() }, for: .touchUpInside)
        drawerButton.addAction(UIAction { [weak self] _ in self?.onOpenContext() }, for: .touchUpInside)
        titleLabel.text = "Harness Pocket"
        titleLabel.font = DHTheme.font(.headline, weight: .semibold)
        titleLabel.textColor = DHTheme.text
        titleLabel.numberOfLines = 1
        titleLabel.accessibilityTraits = .header
        makeIconButton(settingsButton, icon: "gearshape", label: "打开设置")
        settingsButton.addAction(UIAction { [weak self] _ in self?.onSettings() }, for: .touchUpInside)
        var stateConfig = UIButton.Configuration.tinted()
        stateConfig.title = "状态"
        stateConfig.image = UIImage(systemName: "circle.fill")
        stateConfig.imagePadding = 5
        stateConfig.cornerStyle = .capsule
        stateConfig.baseForegroundColor = DHTheme.secondaryText
        stateButton.configuration = stateConfig
        stateButton.titleLabel?.font = DHTheme.font(.caption1, weight: .semibold)
        stateButton.accessibilityLabel = "任务状态"
        stateButton.addTarget(self, action: #selector(showStatus), for: .touchUpInside)
        let left = UIStackView(arrangedSubviews: [backButton, drawerButton])
        left.axis = .horizontal; left.spacing = 0
        let center = UIStackView(arrangedSubviews: [titleLabel, stateButton])
        center.axis = .vertical; center.spacing = 1; center.alignment = .leading
        let row = UIStackView(arrangedSubviews: [left, center, UIView(), settingsButton])
        row.axis = .horizontal; row.alignment = .center; row.spacing = 6; row.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(row)
        NSLayoutConstraint.activate([
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor), topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), topBar.heightAnchor.constraint(equalToConstant: 58),
            row.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 8), row.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -8),
            row.topAnchor.constraint(equalTo: topBar.topAnchor), row.bottomAnchor.constraint(equalTo: topBar.bottomAnchor)
        ])
    }

    private func buildModes() {
        modeControl.selectedSegmentIndex = 0
        modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        modeControl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(modeControl)
        NSLayoutConstraint.activate([
            modeControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16), modeControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            modeControl.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 8), modeControl.heightAnchor.constraint(greaterThanOrEqualToConstant: 36)
        ])
    }

    private func buildProcessControls() {
        processControls.backgroundColor = DHTheme.surface
        processControls.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(processControls)
        processControlsHeight = processControls.heightAnchor.constraint(equalToConstant: 0)
        let buttons = UIStackView(arrangedSubviews: [processDuration, processTurns, processCalls])
        buttons.axis = .horizontal; buttons.spacing = 2; buttons.translatesAutoresizingMaskIntoConstraints = false
        processControls.addSubview(buttons)
        configureProcessButton(processDuration, title: "时长", icon: "clock")
        configureProcessButton(processTurns, title: "轮次", icon: "rectangle.compress.vertical")
        configureProcessButton(processCalls, title: "调用", icon: "wrench.and.screwdriver")
        processDuration.addTarget(self, action: #selector(showDuration), for: .touchUpInside)
        processTurns.addTarget(self, action: #selector(toggleTurns), for: .touchUpInside)
        processCalls.addTarget(self, action: #selector(toggleCalls), for: .touchUpInside)
        processSearch.placeholder = "搜索过程、调用或错误"
        processSearch.searchBarStyle = .minimal
        processSearch.delegate = self
        processSearch.translatesAutoresizingMaskIntoConstraints = false
        processControls.addSubview(processSearch)
        NSLayoutConstraint.activate([
            processControls.leadingAnchor.constraint(equalTo: view.leadingAnchor), processControls.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            processControls.topAnchor.constraint(equalTo: modeControl.bottomAnchor, constant: 6), processControlsHeight,
            buttons.leadingAnchor.constraint(equalTo: processControls.leadingAnchor, constant: 10), buttons.trailingAnchor.constraint(equalTo: processControls.trailingAnchor, constant: -10),
            buttons.topAnchor.constraint(equalTo: processControls.topAnchor, constant: 3), buttons.heightAnchor.constraint(equalToConstant: 34),
            processSearch.leadingAnchor.constraint(equalTo: processControls.leadingAnchor, constant: 6), processSearch.trailingAnchor.constraint(equalTo: processControls.trailingAnchor, constant: -6),
            processSearch.topAnchor.constraint(equalTo: buttons.bottomAnchor, constant: 1), processSearch.bottomAnchor.constraint(equalTo: processControls.bottomAnchor)
        ])
    }

    private func configureProcessButton(_ button: UIButton, title: String, icon: String) {
        var config = UIButton.Configuration.plain()
        config.title = title; config.image = UIImage(systemName: icon); config.imagePadding = 4
        config.baseForegroundColor = DHTheme.secondaryText; config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 7, bottom: 4, trailing: 7)
        button.configuration = config; button.titleLabel?.font = DHTheme.font(.caption1, weight: .medium)
    }

    private func buildTable() {
        table.backgroundColor = .clear; table.separatorStyle = .none; table.keyboardDismissMode = .interactive
        table.dataSource = self; table.delegate = self; table.estimatedRowHeight = 96; table.rowHeight = UITableView.automaticDimension
        table.register(HarnessMessageCell.self, forCellReuseIdentifier: "pocket.message")
        table.register(PocketArtifactCell.self, forCellReuseIdentifier: "pocket.artifact")
        table.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(table)
        NSLayoutConstraint.activate([
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor), table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.topAnchor.constraint(equalTo: processControls.bottomAnchor, constant: 5), table.bottomAnchor.constraint(equalTo: composer.topAnchor, constant: -7)
        ])
    }

    private func buildComposer() {
        composer.dhApplyCard(backgroundColor: DHTheme.surface, cornerRadius: 22, borderColor: DHTheme.separator.withAlphaComponent(0.35), shadow: true)
        composer.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(composer)
        composerStack.axis = .vertical; composerStack.spacing = 4; composerStack.translatesAutoresizingMaskIntoConstraints = false
        composer.addSubview(composerStack)
        status.font = DHTheme.font(.caption2, weight: .medium); status.textColor = DHTheme.secondaryText; status.numberOfLines = 2
        composerStack.addArrangedSubview(status)
        inputWrapper.translatesAutoresizingMaskIntoConstraints = false
        composerStack.addArrangedSubview(inputWrapper)
        input.font = DHTheme.scaledFont(size: CGFloat(appState.settings.fontSize)); input.textColor = DHTheme.text; input.backgroundColor = .clear
        input.textContainerInset = UIEdgeInsets(top: 8, left: 10, bottom: 7, right: 10); input.textContainer.lineFragmentPadding = 0; input.delegate = self
        input.translatesAutoresizingMaskIntoConstraints = false; inputWrapper.addSubview(input)
        placeholder.text = "输入任务或继续指令…"; placeholder.font = DHTheme.scaledFont(size: CGFloat(appState.settings.fontSize)); placeholder.textColor = DHTheme.tertiaryText; placeholder.isUserInteractionEnabled = false
        placeholder.translatesAutoresizingMaskIntoConstraints = false; inputWrapper.addSubview(placeholder)
        inputHeight = input.heightAnchor.constraint(equalToConstant: 46)
        NSLayoutConstraint.activate([
            input.leadingAnchor.constraint(equalTo: inputWrapper.leadingAnchor), input.trailingAnchor.constraint(equalTo: inputWrapper.trailingAnchor),
            input.topAnchor.constraint(equalTo: inputWrapper.topAnchor), input.bottomAnchor.constraint(equalTo: inputWrapper.bottomAnchor), inputHeight,
            placeholder.leadingAnchor.constraint(equalTo: input.leadingAnchor, constant: 10), placeholder.topAnchor.constraint(equalTo: input.topAnchor, constant: 8)
        ])
        attachmentScroll.showsHorizontalScrollIndicator = false; attachmentScroll.translatesAutoresizingMaskIntoConstraints = false; attachmentScroll.heightAnchor.constraint(equalToConstant: 38).isActive = true
        attachmentStrip.axis = .horizontal; attachmentStrip.spacing = 6; attachmentStrip.translatesAutoresizingMaskIntoConstraints = false
        attachmentScroll.addSubview(attachmentStrip); composerStack.addArrangedSubview(attachmentScroll); attachmentScroll.isHidden = true
        NSLayoutConstraint.activate([
            attachmentStrip.leadingAnchor.constraint(equalTo: attachmentScroll.contentLayoutGuide.leadingAnchor, constant: 10), attachmentStrip.trailingAnchor.constraint(equalTo: attachmentScroll.contentLayoutGuide.trailingAnchor, constant: -10),
            attachmentStrip.topAnchor.constraint(equalTo: attachmentScroll.contentLayoutGuide.topAnchor), attachmentStrip.bottomAnchor.constraint(equalTo: attachmentScroll.contentLayoutGuide.bottomAnchor),
            attachmentStrip.heightAnchor.constraint(equalTo: attachmentScroll.frameLayoutGuide.heightAnchor)
        ])
        let actions = UIStackView(); actions.axis = .horizontal; actions.alignment = .center; actions.spacing = 3; actions.translatesAutoresizingMaskIntoConstraints = false
        configureSmallIcon(attachButton, icon: "plus", label: "添加图片或文件"); attachButton.addTarget(self, action: #selector(chooseAttachment), for: .touchUpInside)
        configureSmallIcon(permissionButton, icon: "shield", label: "切换权限"); permissionButton.addTarget(self, action: #selector(choosePermission), for: .touchUpInside)
        configureSmallText(modelButton, title: "模型"); modelButton.addTarget(self, action: #selector(chooseModel), for: .touchUpInside)
        configureSmallText(sendModeButton, title: "队列"); sendModeButton.addTarget(self, action: #selector(chooseSendMode), for: .touchUpInside)
        var sendConfig = UIButton.Configuration.filled(); sendConfig.image = UIImage(systemName: "arrow.up"); sendConfig.cornerStyle = .capsule; sendConfig.baseBackgroundColor = DHTheme.accent; sendConfig.baseForegroundColor = .white; sendConfig.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8); sendButton.configuration = sendConfig; sendButton.accessibilityLabel = "发送或停止"; sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        sendButton.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(sendLongPress(_:))))
        actions.addArrangedSubview(attachButton); actions.addArrangedSubview(permissionButton); actions.addArrangedSubview(modelButton); actions.addArrangedSubview(sendModeButton); actions.addArrangedSubview(UIView()); actions.addArrangedSubview(sendButton)
        sendButton.widthAnchor.constraint(equalToConstant: 40).isActive = true; sendButton.heightAnchor.constraint(equalToConstant: 40).isActive = true
        composerStack.addArrangedSubview(actions)
        NSLayoutConstraint.activate([
            composer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12), composer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            composer.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -8), composerStack.leadingAnchor.constraint(equalTo: composer.leadingAnchor, constant: 10),
            composerStack.trailingAnchor.constraint(equalTo: composer.trailingAnchor, constant: -10), composerStack.topAnchor.constraint(equalTo: composer.topAnchor, constant: 8), composerStack.bottomAnchor.constraint(equalTo: composer.bottomAnchor, constant: -7)
        ])
    }

    private func configureSmallIcon(_ button: UIButton, icon: String, label: String) {
        var c = UIButton.Configuration.plain(); c.image = UIImage(systemName: icon); c.baseForegroundColor = DHTheme.secondaryText; c.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 7, bottom: 7, trailing: 7); button.configuration = c; button.accessibilityLabel = label; button.widthAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true; button.heightAnchor.constraint(equalToConstant: 40).isActive = true
    }

    private func configureSmallText(_ button: UIButton, title: String) {
        var c = UIButton.Configuration.tinted(); c.title = title; c.baseForegroundColor = DHTheme.secondaryText; c.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 7, bottom: 6, trailing: 7); c.background.cornerRadius = 9; button.configuration = c; button.titleLabel?.font = DHTheme.font(.caption1, weight: .medium); button.heightAnchor.constraint(equalToConstant: 34).isActive = true
    }

    @objc private func settingsDidChange() { input.font = DHTheme.scaledFont(size: CGFloat(appState.settings.fontSize)); placeholder.font = input.font; table.reloadData(); render() }
    @objc private func modeChanged() { mode = modeControl.selectedSegmentIndex; processControlsHeight.constant = mode == 1 ? 78 : 0; processControls.isHidden = mode != 1; render() }
    @objc private func toggleTurns() { showTurns.toggle(); processTurns.configuration?.image = UIImage(systemName: showTurns ? "rectangle.compress.vertical" : "rectangle.expand.vertical"); render() }
    @objc private func toggleCalls() { showCalls.toggle(); processCalls.configuration?.image = UIImage(systemName: showCalls ? "wrench.and.screwdriver" : "rectangle.expand.vertical"); render() }
    @objc private func showDuration() { let a = UIAlertController(title: "过程时长", message: "时间字段来自 Harness 事件；当前按事件实际时间显示。", preferredStyle: .actionSheet); a.addAction(UIAlertAction(title: "实际时间 ✓", style: .default)); a.addAction(UIAlertAction(title: "相对耗时", style: .default)); a.addAction(UIAlertAction(title: "取消", style: .cancel)); presentSheet(a, source: processDuration) }
    @objc private func showStatus() {
        if let approval = runtime.pendingApprovals.first { present(UINavigationController(rootViewController: HarnessApprovalViewController(runtime: runtime, request: approval)), animated: true); return }
        if let question = runtime.pendingQuestions.first { present(UINavigationController(rootViewController: QuestionViewController(pending: question, onAnswer: { [weak self] answers in self?.runtime.answerQuestion(question, answers: answers); self?.dismiss(animated: true) }, onCancel: { [weak self] in self?.runtime.cancelQuestion(question); self?.dismiss(animated: true) })), animated: true); return }
        let details = [runtime.lastError ?? runtime.statusText, runtime.currentStage.map { "阶段：\($0)" }, runtime.contextDirectory.map { "目录：\($0)" }, runtime.isGenerating ? "正在运行" : "当前空闲"].compactMap { $0 }.joined(separator: "\n")
        let a = UIAlertController(title: "任务状态", message: details, preferredStyle: .actionSheet); a.addAction(UIAlertAction(title: "刷新", style: .default) { [weak self] _ in self?.runtime.refresh() }); a.addAction(UIAlertAction(title: "关闭", style: .cancel)); presentSheet(a, source: stateButton)
    }

    private func render() {
        let oldIDs = previousVisibleIDs
        let wasNearBottom = isNearBottom || isTableNearBottom()
        visibleItems = mode == 0 ? HarnessPresentationPolicy.transcriptVisibleItems(runtime.items, view: appState.settings.transcriptView) : processItems()
        visibleArtifacts = mode == 2 ? runtime.artifacts : []
        let nextIDs = mode == 2 ? visibleArtifacts.map(\.id) : visibleItems.map(\.id)
        previousVisibleIDs = nextIDs
        table.reloadData()
        updateHeader()
        renderAttachments()
        let changed = oldIDs != nextIDs
        if changed && wasNearBottom { DispatchQueue.main.async { [weak self] in self?.scrollBottom() } }
    }

    private func processItems() -> [HarnessConversationItem] {
        let source = runtime.items.filter { item in
            if item.kind == .tool { return showCalls }
            return showTurns
        }
        let q = processQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return source }
        return source.filter { ($0.text + " " + ($0.subtitle ?? "") + " " + ($0.detail ?? "")).localizedCaseInsensitiveContains(q) }
    }

    private func updateHeader() {
        if let session = runtime.sessions.first(where: { $0.id == runtime.selectedSessionID }) {
            titleLabel.text = session.title.isEmpty ? "新会话" : session.title
            let model = session.model.isEmpty ? "未选模型" : session.model
            modelButton.configuration?.title = model.count > 16 ? String(model.prefix(14)) + "…" : model
            permissionButton.configuration?.image = UIImage(systemName: session.permission == "danger-full-access" ? "shield.slash" : "shield")
            permissionButton.accessibilityLabel = "权限：\(permissionName(session.permission))"
        } else { titleLabel.text = "Harness Pocket" }
        status.text = [runtime.lastError ?? runtime.statusText, runtime.currentStage.map { "阶段：\($0)" }, runtime.isGenerating ? "运行中" : nil, runtime.reasoningEffort.map { "推理：\($0)" }].compactMap { $0 }.joined(separator: " · ")
        status.textColor = runtime.lastError == nil ? DHTheme.secondaryText : DHTheme.danger
        stateButton.configuration?.title = runtime.pendingApprovals.isEmpty && runtime.pendingQuestions.isEmpty ? (runtime.isGenerating ? "运行中" : "状态") : "待处理"
        stateButton.configuration?.baseForegroundColor = runtime.pendingApprovals.isEmpty && runtime.pendingQuestions.isEmpty ? DHTheme.secondaryText : DHTheme.warning
        sendButton.configuration?.image = UIImage(systemName: runtime.isGenerating ? "stop.fill" : "arrow.up")
        sendButton.configuration?.baseBackgroundColor = runtime.isGenerating ? DHTheme.danger : DHTheme.accent
        sendModeButton.configuration?.title = runtime.isGenerating ? (selectedSendMode == "steer" ? "插话" : "队列") : "队列"
        placeholder.isHidden = !input.text.isEmpty
    }

    @objc private func sendTapped() {
        if runtime.isGenerating && input.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && images.isEmpty { runtime.cancel(); return }
        sendCurrentInput()
    }

    @objc private func sendLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        selectedSendMode = "steer"
        sendCurrentInput()
    }

    private func sendCurrentInput() {
        let text = input.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !images.isEmpty else { return }
        let mode = runtime.isGenerating ? selectedSendMode : "queue"
        runtime.send(text, mode: mode, images: images)
        input.text = ""; images.removeAll(); inputHeight.constant = 46; renderAttachments(); updateHeader()
    }

    @objc private func chooseSendMode() {
        let a = UIAlertController(title: "运行中发送策略", message: "队列会等待当前轮次；插话会发送到当前运行。", preferredStyle: .actionSheet)
        [("队列", "queue"), ("插话", "steer")].forEach { name, value in a.addAction(UIAlertAction(title: name + (selectedSendMode == value ? " ✓" : ""), style: .default) { [weak self] _ in self?.selectedSendMode = value; self?.updateHeader() }) }
        a.addAction(UIAlertAction(title: "取消", style: .cancel)); presentSheet(a, source: sendModeButton)
    }

    @objc private func chooseModel() {
        let a = UIAlertController(title: "选择模型", message: "选择模型后可继续选择 reasoning effort。", preferredStyle: .actionSheet)
        for option in runtime.models { a.addAction(UIAlertAction(title: "\(option.providerName) · \(option.modelName)", style: .default) { [weak self] _ in self?.selectModel(option) }) }
        if runtime.models.isEmpty { a.message = "服务尚未返回模型目录" }
        a.addAction(UIAlertAction(title: "取消", style: .cancel)); presentSheet(a, source: modelButton)
    }

    private func selectModel(_ option: HarnessModelOption) {
        guard !option.reasoning.isEmpty else { runtime.selectModel(option); return }
        let a = UIAlertController(title: "Reasoning effort", message: "\(option.modelName)", preferredStyle: .actionSheet)
        a.addAction(UIAlertAction(title: "默认", style: .default) { [weak self] _ in self?.runtime.selectModel(option) })
        for effort in option.reasoning { if let id = effort["id"] { a.addAction(UIAlertAction(title: effort["name"] ?? id, style: .default) { [weak self] _ in self?.runtime.selectModel(option, reasoning: id) }) } }
        a.addAction(UIAlertAction(title: "取消", style: .cancel)); presentSheet(a, source: modelButton)
    }

    @objc private func choosePermission() {
        let current = runtime.sessions.first(where: { $0.id == runtime.selectedSessionID })?.permission
        let a = UIAlertController(title: "访问权限", message: "完全权限允许执行高风险命令。", preferredStyle: .actionSheet)
        [("只读", "read-only"), ("工作区可写", "workspace-write"), ("完全权限", "danger-full-access")].forEach { name, value in a.addAction(UIAlertAction(title: name + (current == value ? " ✓" : ""), style: value == "danger-full-access" ? .destructive : .default) { [weak self] _ in self?.runtime.setPermission(value) }) }
        a.addAction(UIAlertAction(title: "取消", style: .cancel)); presentSheet(a, source: permissionButton)
    }

    @objc private func chooseAttachment() {
        let a = UIAlertController(title: "添加附件", message: "发送协议支持图片内容。", preferredStyle: .actionSheet)
        a.addAction(UIAlertAction(title: "照片图库", style: .default) { [weak self] _ in var c = PHPickerConfiguration(); c.selectionLimit = 20; c.filter = .images; let p = PHPickerViewController(configuration: c); p.delegate = self; self?.present(p, animated: true) })
        a.addAction(UIAlertAction(title: "文件（图片）", style: .default) { [weak self] _ in let p = UIDocumentPickerViewController(forOpeningContentTypes: [.image], asCopy: true); p.allowsMultipleSelection = true; p.delegate = self; self?.present(p, animated: true) })
        a.addAction(UIAlertAction(title: "取消", style: .cancel)); presentSheet(a, source: attachButton)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        for result in results where result.itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            result.itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] data, _ in guard let data else { return }; Task { @MainActor in self?.appendImage(data, name: result.itemProvider.suggestedName) } }
        }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { urls.forEach { if let data = try? Data(contentsOf: $0) { appendImage(data, name: $0.lastPathComponent) } } }

    private func appendImage(_ data: Data, name: String?) {
        guard data.count <= 20 * 1024 * 1024 else { showError("单张图片不能超过 20 MB"); return }
        let type = name?.lowercased().hasSuffix(".png") == true ? "image/png" : "image/jpeg"
        images.append(["type": "image", "mediaType": type, "data": data.base64EncodedString(), "name": name ?? "图片"])
        renderAttachments(); updateHeader()
    }

    private func renderAttachments() {
        attachmentStrip.arrangedSubviews.forEach { attachmentStrip.removeArrangedSubview($0); $0.removeFromSuperview() }
        attachmentScroll.isHidden = images.isEmpty
        for (index, image) in images.enumerated() { attachmentStrip.addArrangedSubview(PocketAttachmentChip(name: image["name"] as? String ?? "图片", data: image["data"] as? String, onRemove: { [weak self] in guard let self, self.images.indices.contains(index) else { return }; self.images.remove(at: index); self.renderAttachments(); self.updateHeader() })) }
    }

    private func permissionName(_ value: String) -> String { ["read-only": "只读", "workspace-write": "工作区可写", "danger-full-access": "完全权限"][value] ?? (value.isEmpty ? "未设置" : value) }
    private func presentSheet(_ alert: UIAlertController, source: UIView) { alert.popoverPresentationController?.sourceView = source; alert.popoverPresentationController?.sourceRect = source.bounds; present(alert, animated: true) }
    private func showError(_ message: String) { let a = UIAlertController(title: "提示", message: message, preferredStyle: .alert); a.addAction(UIAlertAction(title: "知道了", style: .default)); present(a, animated: true) }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) { processQuery = searchText; render() }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { mode == 2 ? max(visibleArtifacts.count, 1) : max(visibleItems.count, 1) }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if mode == 2 {
            guard !visibleArtifacts.isEmpty else { let cell = UITableViewCell(style: .default, reuseIdentifier: nil); cell.backgroundColor = .clear; cell.textLabel?.text = "当前会话尚无服务端确认的产物"; cell.textLabel?.textColor = DHTheme.secondaryText; return cell }
            let cell = tableView.dequeueReusableCell(withIdentifier: "pocket.artifact", for: indexPath) as! PocketArtifactCell; cell.configure(visibleArtifacts[indexPath.row]); return cell
        }
        guard !visibleItems.isEmpty else { let cell = UITableViewCell(style: .default, reuseIdentifier: nil); cell.backgroundColor = .clear; cell.textLabel?.text = runtime.selectedSessionID == nil ? "从上下文抽屉选择一个真实会话" : "等待 Harness 返回内容"; cell.textLabel?.textColor = DHTheme.secondaryText; cell.textLabel?.numberOfLines = 0; return cell }
        let cell = tableView.dequeueReusableCell(withIdentifier: "pocket.message", for: indexPath) as! HarnessMessageCell; cell.configure(visibleItems[indexPath.row], settings: appState.settings); return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if mode == 2, visibleArtifacts.indices.contains(indexPath.row) { let a = UIAlertController(title: visibleArtifacts[indexPath.row].name, message: "\(visibleArtifacts[indexPath.row].path)\n\n\(visibleArtifacts[indexPath.row].detail ?? "服务端已确认此产物。")", preferredStyle: .actionSheet); a.addAction(UIAlertAction(title: "复制路径", style: .default) { _ in UIPasteboard.general.string = self.visibleArtifacts[indexPath.row].path }); a.addAction(UIAlertAction(title: "取消", style: .cancel)); presentSheet(a, source: table); return }
        guard visibleItems.indices.contains(indexPath.row) else { return }
        let item = visibleItems[indexPath.row]
        guard item.kind == .tool || item.detail != nil || item.subtitle == "错误" else { return }
        let a = UIAlertController(title: item.subtitle ?? "过程详情", message: [item.text, item.detail].compactMap { $0 }.joined(separator: "\n\n"), preferredStyle: .actionSheet); a.addAction(UIAlertAction(title: "复制详情", style: .default) { _ in UIPasteboard.general.string = item.detail ?? item.text }); a.addAction(UIAlertAction(title: "取消", style: .cancel)); presentSheet(a, source: table)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) { if scrollView === table { isNearBottom = isTableNearBottom() } }
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard indexPath.row == 0, mode != 2, runtime.hasMore, !isLoadingOlder else { return }
        isLoadingOlder = true
        let oldOffset = table.contentOffset.y; let oldHeight = table.contentSize.height
        runtime.loadOlder()
        DispatchQueue.main.async { [weak self] in guard let self else { return }; self.table.layoutIfNeeded(); let delta = self.table.contentSize.height - oldHeight; if delta > 0 { self.table.contentOffset.y = oldOffset + delta }; self.isLoadingOlder = false }
    }

    private func isTableNearBottom() -> Bool { let bottom = table.contentOffset.y + table.bounds.height - table.adjustedContentInset.bottom; return table.contentSize.height <= 0 || bottom >= table.contentSize.height - 120 }
    private func scrollBottom() { let count = mode == 2 ? visibleArtifacts.count : visibleItems.count; guard count > 0 else { return }; table.scrollToRow(at: IndexPath(row: count - 1, section: 0), at: .bottom, animated: false); isNearBottom = true }
}

private final class PocketAttachmentChip: UIView {
    init(name: String, data: String?, onRemove: @escaping () -> Void) {
        super.init(frame: .zero); backgroundColor = DHTheme.surfaceMuted; layer.cornerRadius = 10
        let image = UIImageView(); image.contentMode = .scaleAspectFill; image.clipsToBounds = true; image.layer.cornerRadius = 7; image.image = data.flatMap { Data(base64Encoded: $0) }.flatMap { UIImage(data: $0) }; image.image = image.image ?? UIImage(systemName: "photo"); image.tintColor = DHTheme.accent; image.translatesAutoresizingMaskIntoConstraints = false
        let label = UILabel(); label.text = name; label.font = DHTheme.font(.caption2); label.textColor = DHTheme.text; label.lineBreakMode = .byTruncatingMiddle; label.translatesAutoresizingMaskIntoConstraints = false
        let remove = UIButton(type: .system); remove.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal); remove.tintColor = DHTheme.secondaryText; remove.accessibilityLabel = "移除附件 \(name)"; remove.addAction(UIAction { _ in onRemove() }, for: .touchUpInside); remove.translatesAutoresizingMaskIntoConstraints = false
        [image, label, remove].forEach(addSubview)
        NSLayoutConstraint.activate([image.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5), image.centerYAnchor.constraint(equalTo: centerYAnchor), image.widthAnchor.constraint(equalToConstant: 28), image.heightAnchor.constraint(equalToConstant: 28), label.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 5), label.centerYAnchor.constraint(equalTo: centerYAnchor), label.widthAnchor.constraint(lessThanOrEqualToConstant: 100), remove.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 3), remove.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5), remove.centerYAnchor.constraint(equalTo: centerYAnchor), remove.widthAnchor.constraint(equalToConstant: 22), remove.heightAnchor.constraint(equalToConstant: 22), heightAnchor.constraint(equalToConstant: 38)])
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
}

private final class PocketArtifactCell: UITableViewCell {
    private let icon = UIImageView(); private let titleLabel = UILabel(); private let pathLabel = UILabel(); private let detailLabel = UILabel()
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) { super.init(style: style, reuseIdentifier: reuseIdentifier); backgroundColor = .clear; selectionStyle = .default; icon.translatesAutoresizingMaskIntoConstraints = false; let labels = UIStackView(arrangedSubviews: [titleLabel, pathLabel, detailLabel]); labels.axis = .vertical; labels.spacing = 4; labels.translatesAutoresizingMaskIntoConstraints = false; titleLabel.font = DHTheme.font(.body, weight: .semibold); titleLabel.textColor = DHTheme.text; pathLabel.font = DHTheme.font(.caption1); pathLabel.textColor = DHTheme.secondaryText; pathLabel.numberOfLines = 2; detailLabel.font = DHTheme.font(.caption2); detailLabel.textColor = DHTheme.tertiaryText; detailLabel.numberOfLines = 2; contentView.addSubview(icon); contentView.addSubview(labels); NSLayoutConstraint.activate([icon.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16), icon.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14), icon.widthAnchor.constraint(equalToConstant: 28), icon.heightAnchor.constraint(equalToConstant: 28), labels.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12), labels.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16), labels.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12), labels.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)]) }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    func configure(_ artifact: HarnessArtifact) { icon.image = UIImage(systemName: artifact.kind == "image" ? "photo" : "doc.richtext"); icon.tintColor = DHTheme.accent; titleLabel.text = artifact.name; pathLabel.text = artifact.path; detailLabel.text = artifact.detail ?? "服务端确认产物"; accessibilityLabel = "产物：\(artifact.name)，\(artifact.path)" }
}
