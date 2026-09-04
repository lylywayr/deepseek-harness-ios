import UIKit
import PhotosUI
import UniformTypeIdentifiers

final class PolishedConversationViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UITextViewDelegate, UISearchBarDelegate, PHPickerViewControllerDelegate, UIDocumentPickerDelegate {
    private let runtime: HarnessRuntime
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let sessionHeader = UIView()
    private let headerTitleButton = UIButton(type: .system)
    private let headerPresetButton = UIButton(type: .system)
    private let headerFilesButton = UIButton(type: .system)
    private let sessionLogButton = UIButton(type: .system)
    private let conversationTab = UIButton(type: .system)
    private let trajectoryTab = UIButton(type: .system)
    private let tabUnderline = UIView()
    private let trajectoryControls = UIView()
    private let durationButton = UIButton(type: .system)
    private let turnsButton = UIButton(type: .system)
    private let callsButton = UIButton(type: .system)
    private let trajectorySearch = UISearchBar()
    private let timeline = TrajectoryTimelineView()
    private var trajectoryControlsHeight: NSLayoutConstraint!
    private var trajectoryQuery = ""
    private var showTurns = true
    private var showCalls = true
    private var tabUnderlineCenter: NSLayoutConstraint!
    private var showingTrajectory = false
    private let composer = UIView()
    private let input = UITextView()
    private let placeholder = UILabel()
    private let sendButton = UIButton(type: .system)
    private let attachButton = UIButton(type: .system)
    private let modelButton = UIButton(type: .system)
    private let permissionButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private let emptyState = UIStackView()
    private let emptyTitleRow = UIStackView()
    private let workspaceButton = UIButton(type: .system)
    private let presetButton = UIButton(type: .system)
    private let attachmentStrip = UIStackView()
    private var inputHeight: NSLayoutConstraint!
    private var composerBottom: NSLayoutConstraint!
    private var images: [[String: Any]] = []
    private var displayedIDs: [String] = []

    init(runtime: HarnessRuntime) {
        self.runtime = runtime
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DHTheme.background
        buildSessionHeader()
        buildTrajectoryControls()
        buildTable()
        buildComposer()
        buildEmptyState()
        runtime.onChange = { [weak self] in self?.render() }
        runtime.onApproval = { [weak self] value in self?.showApproval(value) }
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardChanged(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        render()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func buildSessionHeader() {
        sessionHeader.backgroundColor = DHTheme.surface
        sessionHeader.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sessionHeader)

        configureHeaderButton(headerTitleButton, title: "新会话", icon: "sidebar.left")
        headerTitleButton.addAction(UIAction { [weak self] _ in self?.renameSession() }, for: .touchUpInside)
        configureHeaderButton(headerPresetButton, title: "标准模式", icon: "point.3.connected.trianglepath.dotted")
        headerPresetButton.addAction(UIAction { [weak self] _ in self?.showPresetNotice() }, for: .touchUpInside)
        configureHeaderButton(headerFilesButton, title: nil, icon: "folder")
        headerFilesButton.accessibilityLabel = "文件"
        headerFilesButton.addAction(UIAction { [weak self] _ in self?.showNativeFilesNotice() }, for: .touchUpInside)

        var logConfig = UIButton.Configuration.bordered()
        logConfig.title = "Session 日志"
        logConfig.image = UIImage(systemName: "arrow.down.to.line")
        logConfig.imagePlacement = .trailing
        logConfig.imagePadding = 6
        logConfig.cornerStyle = .capsule
        logConfig.baseForegroundColor = DHTheme.text
        sessionLogButton.configuration = logConfig
        sessionLogButton.addAction(UIAction { [weak self] _ in self?.showSessionLog() }, for: .touchUpInside)

        let top = UIStackView(arrangedSubviews: [headerTitleButton, headerPresetButton, headerFilesButton, UIView(), sessionLogButton])
        top.axis = .horizontal
        top.spacing = 3
        top.alignment = .center
        top.translatesAutoresizingMaskIntoConstraints = false
        sessionHeader.addSubview(top)

        configureTab(conversationTab, title: "对话", selected: true)
        configureTab(trajectoryTab, title: "轨迹", selected: false)
        conversationTab.addTarget(self, action: #selector(showConversation), for: .touchUpInside)
        trajectoryTab.addTarget(self, action: #selector(showTrajectory), for: .touchUpInside)
        let tabs = UIStackView(arrangedSubviews: [conversationTab, trajectoryTab, UIView()])
        tabs.axis = .horizontal
        tabs.spacing = 12
        tabs.translatesAutoresizingMaskIntoConstraints = false
        sessionHeader.addSubview(tabs)

        tabUnderline.backgroundColor = DHTheme.accent
        tabUnderline.layer.cornerRadius = 2
        tabUnderline.translatesAutoresizingMaskIntoConstraints = false
        sessionHeader.addSubview(tabUnderline)
        tabUnderlineCenter = tabUnderline.centerXAnchor.constraint(equalTo: conversationTab.centerXAnchor)

        NSLayoutConstraint.activate([
            sessionHeader.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sessionHeader.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sessionHeader.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            sessionHeader.heightAnchor.constraint(equalToConstant: 94),
            top.leadingAnchor.constraint(equalTo: sessionHeader.leadingAnchor, constant: 8),
            top.trailingAnchor.constraint(equalTo: sessionHeader.trailingAnchor, constant: -8),
            top.topAnchor.constraint(equalTo: sessionHeader.topAnchor, constant: 6),
            top.heightAnchor.constraint(equalToConstant: 42),
            tabs.leadingAnchor.constraint(equalTo: sessionHeader.leadingAnchor, constant: 14),
            tabs.trailingAnchor.constraint(equalTo: sessionHeader.trailingAnchor),
            tabs.bottomAnchor.constraint(equalTo: sessionHeader.bottomAnchor),
            tabs.heightAnchor.constraint(equalToConstant: 42),
            conversationTab.widthAnchor.constraint(equalToConstant: 58),
            trajectoryTab.widthAnchor.constraint(equalToConstant: 58),
            tabUnderline.bottomAnchor.constraint(equalTo: sessionHeader.bottomAnchor),
            tabUnderline.widthAnchor.constraint(equalToConstant: 36),
            tabUnderline.heightAnchor.constraint(equalToConstant: 3),
            tabUnderlineCenter
        ])
    }

    private func configureHeaderButton(_ button: UIButton, title: String?, icon: String) {
        var config = UIButton.Configuration.plain()
        config.title = title
        config.image = UIImage(systemName: icon)
        config.imagePadding = 5
        config.baseForegroundColor = DHTheme.secondaryText
        config.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 7, bottom: 5, trailing: 7)
        button.configuration = config
        button.titleLabel?.font = DHTheme.font(.subheadline, weight: .medium)
    }

    private func configureTab(_ button: UIButton, title: String, selected: Bool) {
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = DHTheme.font(.body, weight: .semibold)
        button.setTitleColor(selected ? DHTheme.accent : DHTheme.secondaryText, for: .normal)
    }

    private func buildTrajectoryControls() {
        trajectoryControls.backgroundColor = DHTheme.surface
        trajectoryControls.isHidden = true
        trajectoryControls.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(trajectoryControls)

        configureTrajectoryControl(durationButton, title: "时长", icon: "clock")
        configureTrajectoryControl(turnsButton, title: "轮次", icon: "rectangle.compress.vertical")
        configureTrajectoryControl(callsButton, title: "调用", icon: "rectangle.compress.vertical")
        turnsButton.addAction(UIAction { [weak self] _ in self?.toggleTurns() }, for: .touchUpInside)
        callsButton.addAction(UIAction { [weak self] _ in self?.toggleCalls() }, for: .touchUpInside)
        durationButton.addAction(UIAction { [weak self] _ in self?.showDurationMenu() }, for: .touchUpInside)
        let buttons = UIStackView(arrangedSubviews: [durationButton, turnsButton, callsButton])
        buttons.axis = .horizontal
        buttons.spacing = 2
        buttons.translatesAutoresizingMaskIntoConstraints = false
        trajectoryControls.addSubview(buttons)

        trajectorySearch.placeholder = "搜索"
        trajectorySearch.searchBarStyle = .minimal
        trajectorySearch.delegate = self
        trajectorySearch.translatesAutoresizingMaskIntoConstraints = false
        trajectoryControls.addSubview(trajectorySearch)

        timeline.translatesAutoresizingMaskIntoConstraints = false
        trajectoryControls.addSubview(timeline)
        trajectoryControlsHeight = trajectoryControls.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            trajectoryControls.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            trajectoryControls.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            trajectoryControls.topAnchor.constraint(equalTo: sessionHeader.bottomAnchor),
            trajectoryControlsHeight,
            buttons.leadingAnchor.constraint(equalTo: trajectoryControls.leadingAnchor, constant: 10),
            buttons.topAnchor.constraint(equalTo: trajectoryControls.topAnchor, constant: 5),
            buttons.heightAnchor.constraint(equalToConstant: 38),
            trajectorySearch.leadingAnchor.constraint(equalTo: buttons.trailingAnchor, constant: 4),
            trajectorySearch.trailingAnchor.constraint(equalTo: trajectoryControls.trailingAnchor, constant: -6),
            trajectorySearch.centerYAnchor.constraint(equalTo: buttons.centerYAnchor),
            timeline.leadingAnchor.constraint(equalTo: trajectoryControls.leadingAnchor),
            timeline.trailingAnchor.constraint(equalTo: trajectoryControls.trailingAnchor),
            timeline.topAnchor.constraint(equalTo: buttons.bottomAnchor, constant: 2),
            timeline.bottomAnchor.constraint(equalTo: trajectoryControls.bottomAnchor)
        ])
    }

    private func configureTrajectoryControl(_ button: UIButton, title: String, icon: String) {
        var config = UIButton.Configuration.plain()
        config.title = title
        config.image = UIImage(systemName: icon)
        config.imagePadding = 5
        config.baseForegroundColor = DHTheme.secondaryText
        config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 7, bottom: 4, trailing: 7)
        button.configuration = config
        button.titleLabel?.font = DHTheme.font(.caption1, weight: .medium)
    }

    private func buildTable() {
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.keyboardDismissMode = .interactive
        tableView.dataSource = self
        tableView.delegate = self
        tableView.estimatedRowHeight = 96
        tableView.rowHeight = UITableView.automaticDimension
        tableView.register(HarnessMessageCell.self, forCellReuseIdentifier: "message")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
    }

    private func buildComposer() {
        composer.translatesAutoresizingMaskIntoConstraints = false
        composer.dhApplyCard(backgroundColor: DHTheme.surface, cornerRadius: 22, borderColor: DHTheme.separator.withAlphaComponent(0.35), shadow: true)
        view.addSubview(composer)

        statusLabel.font = DHTheme.font(.caption2, weight: .medium)
        statusLabel.textColor = DHTheme.secondaryText
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        composer.addSubview(statusLabel)

        input.font = DHTheme.font(.body)
        input.textColor = DHTheme.text
        input.backgroundColor = .clear
        input.textContainerInset = UIEdgeInsets(top: 9, left: 10, bottom: 7, right: 10)
        input.textContainer.lineFragmentPadding = 0
        input.delegate = self
        input.translatesAutoresizingMaskIntoConstraints = false
        composer.addSubview(input)

        placeholder.text = "描述你想要构建的内容… / 调用指令 @ 文件或对话"
        placeholder.font = DHTheme.font(.body)
        placeholder.textColor = DHTheme.tertiaryText
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        composer.addSubview(placeholder)

        attachmentStrip.axis = .horizontal
        attachmentStrip.spacing = 6
        attachmentStrip.translatesAutoresizingMaskIntoConstraints = false
        attachmentStrip.isHidden = true
        composer.addSubview(attachmentStrip)

        configureIcon(attachButton, "plus", label: "添加")
        attachButton.addTarget(self, action: #selector(chooseAttachment), for: .touchUpInside)
        composer.addSubview(attachButton)
        configureText(modelButton, "默认模型")
        modelButton.addTarget(self, action: #selector(chooseModel), for: .touchUpInside)
        composer.addSubview(modelButton)
        configureIcon(permissionButton, "shield", label: "权限模式")
        permissionButton.addTarget(self, action: #selector(choosePermission), for: .touchUpInside)
        composer.addSubview(permissionButton)

        var sendConfig = UIButton.Configuration.filled()
        sendConfig.image = UIImage(systemName: "arrow.up")
        sendConfig.cornerStyle = .capsule
        sendConfig.baseBackgroundColor = DHTheme.accent
        sendConfig.baseForegroundColor = .white
        sendButton.configuration = sendConfig
        sendButton.accessibilityLabel = "发送消息"
        sendButton.addTarget(self, action: #selector(send), for: .touchUpInside)
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        composer.addSubview(sendButton)

        inputHeight = input.heightAnchor.constraint(equalToConstant: 46)
        composerBottom = composer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10)
        NSLayoutConstraint.activate([
            composer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12), composer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12), composerBottom,
            statusLabel.leadingAnchor.constraint(equalTo: composer.leadingAnchor, constant: 16), statusLabel.topAnchor.constraint(equalTo: composer.topAnchor, constant: 9),
            input.leadingAnchor.constraint(equalTo: composer.leadingAnchor, constant: 6), input.trailingAnchor.constraint(equalTo: composer.trailingAnchor, constant: -6), input.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 1), inputHeight,
            placeholder.leadingAnchor.constraint(equalTo: input.leadingAnchor, constant: 10), placeholder.topAnchor.constraint(equalTo: input.topAnchor, constant: 9),
            attachmentStrip.leadingAnchor.constraint(equalTo: composer.leadingAnchor, constant: 14), attachmentStrip.topAnchor.constraint(equalTo: input.bottomAnchor), attachmentStrip.heightAnchor.constraint(equalToConstant: 26),
            attachButton.leadingAnchor.constraint(equalTo: composer.leadingAnchor, constant: 10), attachButton.topAnchor.constraint(equalTo: attachmentStrip.bottomAnchor, constant: 3), attachButton.bottomAnchor.constraint(equalTo: composer.bottomAnchor, constant: -8), attachButton.widthAnchor.constraint(equalToConstant: 34), attachButton.heightAnchor.constraint(equalToConstant: 34),
            permissionButton.leadingAnchor.constraint(equalTo: attachButton.trailingAnchor, constant: 3), permissionButton.centerYAnchor.constraint(equalTo: attachButton.centerYAnchor), permissionButton.widthAnchor.constraint(equalToConstant: 34), permissionButton.heightAnchor.constraint(equalToConstant: 34),
            modelButton.leadingAnchor.constraint(equalTo: permissionButton.trailingAnchor, constant: 3), modelButton.centerYAnchor.constraint(equalTo: attachButton.centerYAnchor), modelButton.trailingAnchor.constraint(lessThanOrEqualTo: sendButton.leadingAnchor, constant: -6), modelButton.heightAnchor.constraint(equalToConstant: 32),
            sendButton.trailingAnchor.constraint(equalTo: composer.trailingAnchor, constant: -9), sendButton.centerYAnchor.constraint(equalTo: attachButton.centerYAnchor), sendButton.widthAnchor.constraint(equalToConstant: 38), sendButton.heightAnchor.constraint(equalToConstant: 38),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor), tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor), tableView.topAnchor.constraint(equalTo: trajectoryControls.bottomAnchor), tableView.bottomAnchor.constraint(equalTo: composer.topAnchor, constant: -6)
        ])
    }

    private func buildEmptyState() {
        let fish = UIImageView(image: UIImage(named: "FishLogo"))
        fish.contentMode = .scaleAspectFit
        fish.translatesAutoresizingMaskIntoConstraints = false
        fish.widthAnchor.constraint(equalToConstant: 52).isActive = true
        fish.heightAnchor.constraint(equalToConstant: 40).isActive = true

        let title = UILabel()
        title.text = "探索未至之境"
        title.font = .systemFont(ofSize: 29, weight: .bold)
        title.textColor = DHTheme.text

        let preview = UILabel()
        preview.text = "预览版"
        preview.font = DHTheme.font(.caption1, weight: .semibold)
        preview.textColor = DHTheme.accent
        preview.backgroundColor = DHTheme.accentSoft
        preview.layer.cornerRadius = 13
        preview.clipsToBounds = true
        preview.textAlignment = .center
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.widthAnchor.constraint(equalToConstant: 60).isActive = true
        preview.heightAnchor.constraint(equalToConstant: 28).isActive = true

        emptyTitleRow.axis = .horizontal
        emptyTitleRow.spacing = 10
        emptyTitleRow.alignment = .center
        emptyTitleRow.addArrangedSubview(fish)
        emptyTitleRow.addArrangedSubview(title)
        emptyTitleRow.addArrangedSubview(preview)

        configureEmptyChoice(workspaceButton, icon: "folder", title: "工作区")
        workspaceButton.addAction(UIAction { [weak self] _ in self?.showWorkspacePicker() }, for: .touchUpInside)
        configureEmptyChoice(presetButton, icon: "point.3.connected.trianglepath.dotted", title: "标准模式")
        presetButton.addAction(UIAction { [weak self] _ in self?.showPresetNotice() }, for: .touchUpInside)
        let choices = UIStackView(arrangedSubviews: [workspaceButton, presetButton])
        choices.axis = .horizontal
        choices.spacing = 12
        choices.alignment = .center

        emptyState.axis = .vertical
        emptyState.spacing = 18
        emptyState.alignment = .center
        emptyState.addArrangedSubview(emptyTitleRow)
        emptyState.addArrangedSubview(choices)
        emptyState.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyState)
        NSLayoutConstraint.activate([
            emptyState.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            emptyState.bottomAnchor.constraint(equalTo: composer.topAnchor, constant: -24),
            emptyState.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 22),
            emptyState.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -22)
        ])
    }

    private func configureEmptyChoice(_ button: UIButton, icon: String, title: String) {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: icon)
        config.title = title
        config.imagePadding = 7
        config.baseForegroundColor = DHTheme.text
        config.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 7, bottom: 5, trailing: 7)
        button.configuration = config
        button.titleLabel?.font = DHTheme.font(.subheadline, weight: .medium)
    }

    private func showWorkspacePicker() {
        let alert = UIAlertController(title: "选择工作区", message: nil, preferredStyle: .actionSheet)
        for workspace in runtime.workspaces {
            alert.addAction(UIAlertAction(title: workspace.title, style: .default))
        }
        if runtime.workspaces.isEmpty { alert.message = "正在读取工作区" }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        presentSheet(alert, source: workspaceButton)
    }

    private func showPresetNotice() {
        let alert = UIAlertController(title: "Agent 预设", message: "当前使用标准模式。其他预设将在对应 Remote 接入后开放切换。", preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "标准模式 ✓", style: .default))
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        presentSheet(alert, source: presetButton)
    }

    private func configureIcon(_ button: UIButton, _ name: String, label: String) {
        var config = UIButton.Configuration.plain(); config.image = UIImage(systemName: name); config.baseForegroundColor = DHTheme.secondaryText
        button.configuration = config; button.accessibilityLabel = label; button.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureText(_ button: UIButton, _ title: String) {
        var config = UIButton.Configuration.tinted(); config.title = title; config.baseForegroundColor = DHTheme.secondaryText; config.background.cornerRadius = 9; config.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8)
        button.configuration = config; button.translatesAutoresizingMaskIntoConstraints = false
    }

    private func render() {
        let old = displayedIDs
        displayedIDs = runtime.items.map(\.id)
        tableView.reloadData()
        emptyState.isHidden = !runtime.items.isEmpty
        statusLabel.isHidden = runtime.items.isEmpty && runtime.lastError == nil
        if let workspace = runtime.workspaces.first {
            workspaceButton.configuration?.title = workspace.title
        }
        statusLabel.text = runtime.lastError ?? runtime.statusText
        statusLabel.textColor = runtime.lastError == nil ? DHTheme.secondaryText : DHTheme.danger
        if let session = runtime.sessions.first(where: { $0.id == runtime.selectedSessionID }) {
            headerTitleButton.configuration?.title = session.title.isEmpty ? "新会话" : session.title
            headerPresetButton.configuration?.title = session.preset == "standard" ? "标准模式" : session.preset
            modelButton.configuration?.title = session.model.isEmpty ? "选择模型" : session.model
            permissionButton.configuration?.image = UIImage(systemName: session.permission == "danger-full-access" ? "shield.slash" : "shield")
            permissionButton.accessibilityLabel = "权限：\(session.permission)"
        }
        sendButton.configuration?.image = UIImage(systemName: runtime.isGenerating ? "stop.fill" : "arrow.up")
        sendButton.configuration?.baseBackgroundColor = runtime.isGenerating ? DHTheme.danger : DHTheme.accent
        updateSend()
        if old != displayedIDs, !displayedIDs.isEmpty { DispatchQueue.main.async { [weak self] in self?.scrollBottom() } }
    }

    private func updateSend() {
        let available = runtime.isGenerating || !input.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty
        sendButton.isEnabled = available
        sendButton.alpha = available ? 1 : 0.45
        placeholder.isHidden = !input.text.isEmpty
    }

    @objc private func showConversation() { setMode(trajectory: false) }
    @objc private func showTrajectory() { setMode(trajectory: true) }

    private func setMode(trajectory: Bool) {
        showingTrajectory = trajectory
        trajectoryControls.isHidden = !trajectory
        trajectoryControlsHeight.constant = trajectory ? 118 : 0
        conversationTab.setTitleColor(trajectory ? DHTheme.secondaryText : DHTheme.accent, for: .normal)
        trajectoryTab.setTitleColor(trajectory ? DHTheme.accent : DHTheme.secondaryText, for: .normal)
        tabUnderlineCenter.isActive = false
        tabUnderlineCenter = tabUnderline.centerXAnchor.constraint(equalTo: trajectory ? trajectoryTab.centerXAnchor : conversationTab.centerXAnchor)
        tabUnderlineCenter.isActive = true
        UIView.animate(withDuration: 0.18) { self.sessionHeader.layoutIfNeeded() }
        tableView.reloadData()
        timeline.update(items: runtime.items)
        emptyState.isHidden = trajectory || !runtime.items.isEmpty
        placeholder.text = trajectory ? "轨迹为只读视图" : "描述你想要构建的内容… / 调用指令 @ 文件或对话"
        input.isEditable = !trajectory
        composer.alpha = trajectory ? 0.65 : 1
    }

    private func renameSession() {
        guard let session = runtime.sessions.first(where: { $0.id == runtime.selectedSessionID }) else { return }
        let alert = UIAlertController(title: "重命名会话", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.text = session.title }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak self, weak alert] _ in
            guard let title = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return }
            self?.runtime.rename(title)
        })
        present(alert, animated: true)
    }

    private func showNativeFilesNotice() {
        showError("文件浏览页面将在下一阶段接入原生目录与文件 Remote。")
    }

    private func showSessionLog() {
        let text = runtime.items.map { "[\($0.kind.rawValue)] \($0.text)" }.joined(separator: "\n\n")
        let controller = SessionLogViewController(text: text.isEmpty ? "当前会话暂无日志" : text)
        let navigation = UINavigationController(rootViewController: controller)
        navigation.modalPresentationStyle = .pageSheet
        present(navigation, animated: true)
    }

    private func trajectoryItems() -> [HarnessConversationItem] {
        let source = runtime.items.filter { item in
            if item.kind == .tool { return showCalls }
            return showTurns && (item.kind == .user || item.kind == .assistant || item.kind == .system)
        }
        guard !trajectoryQuery.isEmpty else { return source }
        return source.filter { ($0.text + " " + ($0.subtitle ?? "")).localizedCaseInsensitiveContains(trajectoryQuery) }
    }

    private func toggleTurns() {
        showTurns.toggle()
        turnsButton.configuration?.image = UIImage(systemName: showTurns ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
        tableView.reloadData()
    }

    private func toggleCalls() {
        showCalls.toggle()
        callsButton.configuration?.image = UIImage(systemName: showCalls ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
        tableView.reloadData()
    }

    private func showDurationMenu() {
        let alert = UIAlertController(title: "轨迹时长", message: "时间轴可按实际时间或相对耗时显示。", preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "实际时间 ✓", style: .default))
        alert.addAction(UIAlertAction(title: "相对耗时", style: .default))
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        presentSheet(alert, source: durationButton)
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        trajectoryQuery = searchText
        tableView.reloadData()
    }

    @objc private func send() {
        if runtime.isGenerating { runtime.cancel(); return }
        let text = input.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !images.isEmpty else { return }
        runtime.send(text, images: images)
        input.text = ""; images.removeAll(); renderAttachments(); textViewDidChange(input)
    }

    @objc private func chooseModel() {
        let alert = UIAlertController(title: "选择模型", message: nil, preferredStyle: .actionSheet)
        for group in Dictionary(grouping: runtime.models, by: \.provider) {
            for option in group.value { alert.addAction(UIAlertAction(title: "\(option.providerName) · \(option.modelName)", style: .default) { [weak self] _ in self?.runtime.selectModel(option) }) }
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel)); presentSheet(alert, source: modelButton)
    }

    @objc private func choosePermission() {
        let current = runtime.sessions.first(where: { $0.id == runtime.selectedSessionID })?.permission
        let alert = UIAlertController(title: "访问权限", message: "完全权限允许执行高风险命令，请确认当前服务环境可信。", preferredStyle: .actionSheet)
        [("只读", "read-only"), ("工作区可写", "workspace-write"), ("完全权限", "danger-full-access")].forEach { name, value in
            alert.addAction(UIAlertAction(title: name + (current == value ? " ✓" : ""), style: value == "danger-full-access" ? .destructive : .default) { [weak self] _ in self?.runtime.setPermission(value) })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel)); presentSheet(alert, source: permissionButton)
    }

    @objc private func chooseAttachment() {
        let alert = UIAlertController(title: "添加图片", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "照片图库", style: .default) { [weak self] _ in
            var config = PHPickerConfiguration(); config.selectionLimit = 20; config.filter = .images
            let picker = PHPickerViewController(configuration: config); picker.delegate = self; self?.present(picker, animated: true)
        })
        alert.addAction(UIAlertAction(title: "文件", style: .default) { [weak self] _ in
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.image], asCopy: true); picker.allowsMultipleSelection = true; picker.delegate = self; self?.present(picker, animated: true)
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel)); presentSheet(alert, source: attachButton)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        for result in results where result.itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            result.itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] data, _ in
                guard let data else { return }; Task { @MainActor in self?.appendImage(data, name: result.itemProvider.suggestedName) }
            }
        }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        for url in urls { if let data = try? Data(contentsOf: url) { appendImage(data, name: url.lastPathComponent) } }
    }

    private func appendImage(_ data: Data, name: String?) {
        guard data.count <= 20 * 1024 * 1024 else { showError("单张图片不能超过 20 MB"); return }
        let type = name?.lowercased().hasSuffix(".png") == true ? "image/png" : "image/jpeg"
        images.append(["type": "image", "mediaType": type, "data": data.base64EncodedString(), "name": name ?? "image"])
        renderAttachments(); updateSend()
    }

    private func renderAttachments() {
        attachmentStrip.arrangedSubviews.forEach { attachmentStrip.removeArrangedSubview($0); $0.removeFromSuperview() }
        attachmentStrip.isHidden = images.isEmpty
        for (index, image) in images.enumerated() {
            let button = UIButton(type: .system); button.setTitle("📎 \(image["name"] as? String ?? "图片") ×", for: .normal); button.titleLabel?.font = DHTheme.font(.caption2); button.tag = index; button.addTarget(self, action: #selector(removeAttachment(_:)), for: .touchUpInside); attachmentStrip.addArrangedSubview(button)
        }
    }

    @objc private func removeAttachment(_ sender: UIButton) { guard images.indices.contains(sender.tag) else { return }; images.remove(at: sender.tag); renderAttachments(); updateSend() }
    private func showApproval(_ value: [String: Any]) {
        guard let clientID = value["clientId"] as? String,
              let eventID = value["eventId"] as? String else { return }
        let request = value["request"] as? [String: Any]
        let tool = request?["toolName"] as? String ?? "未知工具"
        let reason = request?["reason"] as? String
        let message = ["工具：\(tool)", reason.map { "原因：\($0)" }].compactMap { $0 }.joined(separator: "\n\n")
        let alert = UIAlertController(title: "允许这次工具调用？", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "拒绝", style: .destructive) { [weak self] _ in
            self?.runtime.answerApproval(clientID: clientID, eventID: eventID, decision: "rejected")
        })
        alert.addAction(UIAlertAction(title: "仅允许一次", style: .default) { [weak self] _ in
            self?.runtime.answerApproval(clientID: clientID, eventID: eventID, decision: "allowed-once")
        })
        present(alert, animated: true)
    }
    private func showError(_ message: String) { let a=UIAlertController(title:"提示",message:message,preferredStyle:.alert);a.addAction(UIAlertAction(title:"好",style:.default));present(a,animated:true) }
    private func presentSheet(_ alert: UIAlertController, source: UIView) { alert.popoverPresentationController?.sourceView=source;alert.popoverPresentationController?.sourceRect=source.bounds;present(alert,animated:true) }
    private func scrollBottom() { guard !runtime.items.isEmpty else{return};tableView.scrollToRow(at:IndexPath(row:runtime.items.count-1,section:0),at:.bottom,animated:false) }

    @objc private func keyboardChanged(_ note: Notification) { guard let f=note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,let d=note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else{return};let c=view.convert(f,from:nil);composerBottom.constant = -10-max(0,view.bounds.maxY-c.minY-view.safeAreaInsets.bottom);UIView.animate(withDuration:d){self.view.layoutIfNeeded()} }
    func textViewDidChange(_ textView: UITextView) { inputHeight.constant=min(max(textView.contentSize.height,46),130);updateSend();view.layoutIfNeeded() }
    private var visibleItems: [HarnessConversationItem] { showingTrajectory ? trajectoryItems() : runtime.items }
    func tableView(_ tableView:UITableView,numberOfRowsInSection section:Int)->Int{visibleItems.count}
    func tableView(_ tableView:UITableView,cellForRowAt indexPath:IndexPath)->UITableViewCell{let c=tableView.dequeueReusableCell(withIdentifier:"message",for:indexPath) as! HarnessMessageCell;c.configure(visibleItems[indexPath.row]);return c}
    func tableView(_ tableView:UITableView,didSelectRowAt indexPath:IndexPath){
        tableView.deselectRow(at:indexPath,animated:true)
        guard showingTrajectory, visibleItems.indices.contains(indexPath.row) else{return}
        let item=visibleItems[indexPath.row]
        let detail=TrajectoryDetailViewController(item:item)
        let navigation=UINavigationController(rootViewController:detail)
        navigation.modalPresentationStyle = .pageSheet
        present(navigation,animated:true)
    }
    func tableView(_ tableView:UITableView,willDisplay cell:UITableViewCell,forRowAt indexPath:IndexPath){if indexPath.row==0&&runtime.hasMore{runtime.loadOlder()}}
}

final class HarnessMessageCell: UITableViewCell {
    private let card = UIView()
    private let title = UILabel()
    private let body = UILabel()
    private let meta = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        card.layer.cornerRadius = 14
        card.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(card)
        [title, body, meta].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview($0)
        }
        title.font = DHTheme.font(.caption1, weight: .semibold)
        body.font = DHTheme.font(.body)
        body.numberOfLines = 0
        meta.font = DHTheme.font(.caption2)
        meta.textColor = DHTheme.tertiaryText
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5),
            title.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 13),
            title.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -13),
            title.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            body.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            body.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 5),
            meta.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            meta.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            meta.topAnchor.constraint(equalTo: body.bottomAnchor, constant: 6),
            meta.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -9)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ item: HarnessConversationItem) {
        title.text = item.kind == .user ? "你" : item.kind == .assistant ? "Harness" : item.kind == .tool ? "工具" : "系统"
        body.text = item.text
        meta.text = item.subtitle
        card.backgroundColor = item.kind == .user ? DHTheme.accentSoft : item.kind == .tool ? DHTheme.surfaceMuted : DHTheme.surface
        title.textColor = item.kind == .user ? DHTheme.accent : DHTheme.secondaryText
    }
}

final class SessionLogViewController: UIViewController {
    private let text: String
    init(text: String) { self.text = text; super.init(nibName: nil, bundle: nil) }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Session 日志"
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(close))
        view.backgroundColor = DHTheme.background
        let textView = UITextView()
        textView.text = text
        textView.isEditable = false
        textView.backgroundColor = .clear
        textView.textColor = DHTheme.text
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textContainerInset = UIEdgeInsets(top: 18, left: 14, bottom: 18, right: 14)
        textView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    @objc private func close() { dismiss(animated: true) }
}

final class TrajectoryTimelineView: UIView {
    private let input = UILabel(), model = UILabel(), tools = UILabel()
    override init(frame: CGRect) {
        super.init(frame: frame)
        input.text = "输入"; model.text = "模型"; tools.text = "工具"
        [input, model, tools].forEach { $0.font = .monospacedSystemFont(ofSize: 11, weight: .medium); $0.textColor = DHTheme.secondaryText }
        let labels = UIStackView(arrangedSubviews: [input, model, tools]); labels.axis = .vertical; labels.spacing = 4; labels.tag = 700; labels.translatesAutoresizingMaskIntoConstraints = false
        addSubview(labels)
        NSLayoutConstraint.activate([labels.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12), labels.topAnchor.constraint(equalTo: topAnchor, constant: 5), labels.widthAnchor.constraint(equalToConstant: 34)])
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    func update(items: [HarnessConversationItem]) {
        let count = max(items.count, 1)
        let make = { (color: UIColor) -> UIView in
            let stack = UIStackView(); stack.axis = .horizontal; stack.spacing = 5
            for _ in 0..<min(count, 44) { let v=UIView(); v.backgroundColor=color; v.layer.cornerRadius=2; stack.addArrangedSubview(v); v.widthAnchor.constraint(equalToConstant: 5).isActive=true; v.heightAnchor.constraint(equalToConstant: 14).isActive=true }
            return stack
        }
        subviews.filter { $0.tag != 700 }.forEach { $0.removeFromSuperview() }
        let rows=[make(DHTheme.accent.withAlphaComponent(0.65)),make(DHTheme.accent.withAlphaComponent(0.35)),make(DHTheme.warning.withAlphaComponent(0.75))]
        for (i,row) in rows.enumerated(){ row.translatesAutoresizingMaskIntoConstraints=false; addSubview(row); NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 52),row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),row.topAnchor.constraint(equalTo: topAnchor, constant: 6+CGFloat(i)*18)]) }
    }
}

final class TrajectoryDetailViewController: UIViewController {
    private let item: HarnessConversationItem
    init(item: HarnessConversationItem){self.item=item;super.init(nibName:nil,bundle:nil)}
    @available(*, unavailable) required init?(coder:NSCoder){fatalError()}
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "调用详情"
        view.backgroundColor = DHTheme.background
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(close))
        let text = UITextView()
        text.isEditable = false
        text.backgroundColor = .clear
        text.textColor = DHTheme.text
        text.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        text.textContainerInset = UIEdgeInsets(top: 20, left: 16, bottom: 20, right: 16)
        text.text = "类型：\(item.kind)\n\n\(item.text)\n\n\(item.subtitle ?? "")"
        text.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(text)
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            text.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            text.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            text.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    @objc private func close() { dismiss(animated: true) }
}
