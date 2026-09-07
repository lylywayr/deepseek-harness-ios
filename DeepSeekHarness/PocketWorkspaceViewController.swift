import UIKit

/// A compact, state-driven Pocket Workspace home. The home never invents a
/// task: every session, workspace, stage, approval, question, and artifact is
/// read from the single HarnessRuntime projection.
final class NativeHomeViewController: UIViewController, UISearchBarDelegate {
    private let appState: AppState
    private let store: NativeUIStore
    private let transport: NativeUITransport
    private let onSettings: (HarnessRuntime) -> Void
    private let runtimeOverride: HarnessRuntime?
    private var runtime: HarnessRuntime!
    private var conversation: PocketConversationViewController!
    private var stopObserving: (() -> Void)?
    private var isDrawerVisible = false
    private var drawerWidth: NSLayoutConstraint!
    private var searchText = ""
    private var searchResults: [HarnessSessionSummary] = []

    private let rootScroll = UIScrollView()
    private let content = UIStackView()
    private let drawer = UIView()
    private let drawerScrim = UIControl()
    private let drawerContent = UIStackView()
    private let drawerScroll = UIScrollView()
    private let searchBar = UISearchBar()
    private let activityButton = UIButton(type: .system)
    private let connectionButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let stateLabel = UILabel()
    private let currentCard = UIView()
    private let pendingSection = UIStackView()
    private let runningSection = UIStackView()
    private let recentSection = UIStackView()
    private let workspacesSection = UIStackView()
    private let emptyLabel = UILabel()
    private var artifactSection: UIView?

    init(appState: AppState, nativeUIStore: NativeUIStore, transport: NativeUITransport, runtime: HarnessRuntime? = nil, onSettings: @escaping (HarnessRuntime) -> Void) {
        self.appState = appState
        store = nativeUIStore
        self.transport = transport
        runtimeOverride = runtime
        self.onSettings = onSettings
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DHTheme.background
        buildRoot()
        buildDrawer()
        runtime = runtimeOverride ?? HarnessRuntime(baseURL: appState.endpointURL!)
        conversation = PocketConversationViewController(runtime: runtime, appState: appState, onOpenContext: { [weak self] in self?.toggleDrawer() }, onBack: { [weak self] in self?.showWorkspace() }, onSettings: { [weak self] in guard let self else { return }; self.onSettings(self.runtime) })
        addChild(conversation)
        conversation.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(conversation.view)
        NSLayoutConstraint.activate([
            conversation.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            conversation.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            conversation.view.topAnchor.constraint(equalTo: view.topAnchor),
            conversation.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        conversation.didMove(toParent: self)
        conversation.view.isHidden = true
        stopObserving = runtime.observeNavigation { [weak self] in
            DispatchQueue.main.async { self?.renderAll() }
        }
        if runtimeOverride == nil {
            runtime.start()
        } else {
            renderAll()
            #if DEBUG
            runtime.emitFixtureUpdateForTesting()
            #endif
        }
        if runtimeOverride == nil { loadNativeManifest() }
        installGestures()
    }

    deinit { stopObserving?() }

    #if DEBUG
    private static func makeFixture(scene: String, appState: AppState) -> NativeHomeViewController {
        let runtime = HarnessRuntime.fixture(scene: scene)
        let transport = NativeUITransport(baseURL: URL(string: "http://fixture.invalid")!)
        return NativeHomeViewController(appState: appState, nativeUIStore: NativeUIStore(), transport: transport, runtime: runtime, onSettings: { _ in })
    }
    #endif
    #if DEBUG
    func fixtureOpenDrawer() { if !isDrawerVisible { toggleDrawer() } }
    func fixtureCloseDrawer() { if isDrawerVisible { toggleDrawer() } }
    func fixtureOpenFlatDrawer() {
        var preferences = appState.viewPreferences
        preferences.groupBy = .flat
        preferences.orderBy = .updated
        preferences.showArchived = true
        appState.updateViewPreferences(preferences)
        fixtureOpenDrawer()
    }
    func fixtureOpenConversation() { fixtureCloseDrawer(); showConversation() }
    func fixtureOpenNormalConversation() {
        var settings = appState.settings
        settings.fontSize = 16
        settings.transcriptView = .normal
        appState.updateSettings(settings)
        fixtureOpenConversation()
    }
    func fixtureSelectMode(_ index: Int) { fixtureOpenConversation(); conversation.fixtureSelectMode(index) }
    func fixtureFocusComposer() { fixtureOpenConversation(); conversation.fixtureFocusComposer() }
    func fixtureShowActivity() { showActivityCenter() }
    func fixtureShowSettings() {
        let center = HarnessSettingsCenterViewController(appState: appState, runtime: runtime) { }
        present(UINavigationController(rootViewController: center), animated: false)
    }
    #endif

    private func buildRoot() {
        rootScroll.translatesAutoresizingMaskIntoConstraints = false
        rootScroll.alwaysBounceVertical = true
        rootScroll.refreshControl = UIRefreshControl()
        rootScroll.refreshControl?.addTarget(self, action: #selector(refresh), for: .valueChanged)
        view.addSubview(rootScroll)
        content.axis = .vertical
        content.spacing = DHTheme.sectionSpacing
        content.translatesAutoresizingMaskIntoConstraints = false
        rootScroll.addSubview(content)
        NSLayoutConstraint.activate([
            rootScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), rootScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            rootScroll.topAnchor.constraint(equalTo: view.topAnchor), rootScroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: rootScroll.contentLayoutGuide.leadingAnchor, constant: DHTheme.pageHorizontal),
            content.trailingAnchor.constraint(equalTo: rootScroll.contentLayoutGuide.trailingAnchor, constant: -DHTheme.pageHorizontal),
            content.topAnchor.constraint(equalTo: rootScroll.contentLayoutGuide.topAnchor, constant: 8),
            content.bottomAnchor.constraint(equalTo: rootScroll.contentLayoutGuide.bottomAnchor, constant: 12),
            content.widthAnchor.constraint(equalTo: rootScroll.frameLayoutGuide.widthAnchor, constant: -DHTheme.pageHorizontal * 2)
        ])

        let top = UIStackView()
        top.axis = .horizontal; top.alignment = .center; top.spacing = 10
        let logo = dhIconView(systemName: "sparkles", size: 32, symbolSize: 15)
        titleLabel.text = "工作台"
        titleLabel.font = DHTheme.font(.title3, weight: .bold)
        titleLabel.textColor = DHTheme.text
        let identity = UIStackView(arrangedSubviews: [titleLabel, stateLabel])
        identity.axis = .vertical; identity.spacing = 2
        top.addArrangedSubview(logo); top.addArrangedSubview(identity); top.addArrangedSubview(UIView())
        configurePill(connectionButton, title: "连接中", icon: "circle.fill", color: DHTheme.success)
        connectionButton.addAction(UIAction { [weak self] _ in self?.showConnectionDetails() }, for: .touchUpInside)
        top.addArrangedSubview(connectionButton)
        let activity = makeIconButton("bell", label: "活动中心")
        activity.addAction(UIAction { [weak self] _ in self?.showActivityCenter() }, for: .touchUpInside)
        top.addArrangedSubview(activity)
        let menu = makeIconButton("line.3.horizontal", label: "打开上下文抽屉")
        menu.addAction(UIAction { [weak self] _ in self?.toggleDrawer() }, for: .touchUpInside)
        top.addArrangedSubview(menu)
        content.addArrangedSubview(top)

        content.addArrangedSubview(sectionHeading("今日概览", icon: "chart.bar.xaxis"))
        content.addArrangedSubview(makeOverviewStrip())
        content.addArrangedSubview(sectionHeading("继续工作", icon: "arrow.forward.circle"))
        currentCard.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([currentCard.heightAnchor.constraint(greaterThanOrEqualToConstant: 66)])
        content.addArrangedSubview(makeSection("需要你处理", stack: pendingSection, icon: "exclamationmark.bubble"))
        content.addArrangedSubview(makeSection("运行中", stack: runningSection, icon: "bolt.fill"))
        content.addArrangedSubview(makeSection("最近工作", stack: recentSection, icon: "clock"))
        content.addArrangedSubview(makeSection("最近工作区", stack: workspacesSection, icon: "folder"))
        let start = dhButton(title: "开始新任务", systemName: "plus", filled: true) { [weak self] in self?.createSession() }
        start.accessibilityLabel = "开始新任务"
        content.addArrangedSubview(start)
        emptyLabel.text = "连接后，这里会显示真实工作区和会话。"
        emptyLabel.textColor = DHTheme.secondaryText; emptyLabel.font = DHTheme.font(.subheadline); emptyLabel.numberOfLines = 0; emptyLabel.textAlignment = .center
        content.addArrangedSubview(emptyLabel)
    }

    private func makeOverviewStrip() -> UIView {
        let row = UIStackView(); row.axis = .horizontal; row.spacing = 8; row.distribution = .fillEqually
        let pending = runtime?.sessions.filter { !$0.blank && !$0.running }.count ?? 0
        let running = runtime?.sessions.filter { $0.running }.count ?? 0
        let completed = runtime?.sessions.filter { !$0.blank }.count ?? 0
        [("待处理", pending, DHTheme.warning, "clock"), ("运行中", running, DHTheme.accent, "bolt.fill"), ("本周完成", completed, DHTheme.success, "checkmark.circle")].forEach { title, value, color, icon in
            let card = UIView(); card.dhApplyCard(backgroundColor: DHTheme.surface, cornerRadius: DHTheme.cornerMedium)
            let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 3; stack.translatesAutoresizingMaskIntoConstraints = false
            let top = UIStackView(); top.axis = .horizontal; top.addArrangedSubview(UIImageView(image: UIImage(systemName: icon))); top.addArrangedSubview(UIView())
            (top.arrangedSubviews.first as? UIImageView)?.tintColor = color
            let number = UILabel(); number.text = "\\(value)"; number.font = DHTheme.font(.title2, weight: .bold); number.textColor = DHTheme.text
            let label = UILabel(); label.text = title; label.font = DHTheme.font(.caption1); label.textColor = DHTheme.secondaryText
            [top, number, label].forEach(stack.addArrangedSubview); card.addSubview(stack)
            NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10), stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10), stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 9), stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -9)])
            row.addArrangedSubview(card)
        }; return row
    }


        let wrapper = UIView(); wrapper.dhApplyCard(backgroundColor: DHTheme.surface, cornerRadius: DHTheme.cornerMedium, borderColor: DHTheme.separator.withAlphaComponent(0.18))
        let body = UIStackView(); body.axis = .vertical; body.spacing = 3; body.translatesAutoresizingMaskIntoConstraints = false
        body.addArrangedSubview(sectionHeading(title, icon: icon))
        stack.axis = .vertical; stack.spacing = 2
        body.addArrangedSubview(stack); wrapper.addSubview(body)
        NSLayoutConstraint.activate([body.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 10), body.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -10), body.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 7), body.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -7)])
        return wrapper
    }

    private func sectionHeading(_ text: String, icon: String) -> UIView {
        let row = UIStackView(); row.axis = .horizontal; row.spacing = 6; row.alignment = .center
        let image = UIImageView(image: UIImage(systemName: icon)); image.tintColor = DHTheme.accent; image.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold); image.widthAnchor.constraint(equalToConstant: 18).isActive = true
        let label = UILabel(); label.text = text; label.font = DHTheme.font(.caption1, weight: .semibold); label.textColor = DHTheme.text
        row.addArrangedSubview(image); row.addArrangedSubview(label); row.addArrangedSubview(UIView())
        return row
    }

    private func configurePill(_ button: UIButton, title: String, icon: String, color: UIColor) {
        var c = UIButton.Configuration.tinted(); c.title = title; c.image = UIImage(systemName: icon); c.imagePadding = 4; c.cornerStyle = .capsule; c.baseForegroundColor = color; c.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8); button.configuration = c; button.titleLabel?.font = DHTheme.font(.caption2, weight: .semibold)
    }

    private func makeIconButton(_ icon: String, label: String) -> UIButton {
        var c = UIButton.Configuration.plain(); c.image = UIImage(systemName: icon); c.baseForegroundColor = DHTheme.text; c.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 7, bottom: 7, trailing: 7); let b = UIButton(configuration: c); b.accessibilityLabel = label; b.accessibilityTraits = .button; b.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true; b.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true; return b
    }

    private func installCard(_ view: UIView, title: String, subtitle: String, icon: String, color: UIColor = DHTheme.surface) {
        view.subviews.forEach { $0.removeFromSuperview() }
        view.dhApplyCard(backgroundColor: color, cornerRadius: DHTheme.cornerMedium, borderColor: DHTheme.separator.withAlphaComponent(0.25))
        let row = UIStackView(); row.axis = .horizontal; row.spacing = 8; row.alignment = .center
        let mark = dhIconView(systemName: icon, size: 28, symbolSize: 13)
        let labels = UIStackView(); labels.axis = .vertical; labels.spacing = 1
        let t = UILabel(); t.text = title; t.font = DHTheme.font(.subheadline, weight: .semibold); t.textColor = DHTheme.text; t.numberOfLines = 2
        let s = UILabel(); s.text = subtitle; s.font = DHTheme.font(.caption2); s.textColor = DHTheme.secondaryText; s.numberOfLines = 2
        labels.addArrangedSubview(t); labels.addArrangedSubview(s); row.addArrangedSubview(mark); row.addArrangedSubview(labels); row.addArrangedSubview(UIImageView(image: UIImage(systemName: "chevron.right"))); view.addSubview(row)
        NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 11), row.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -11), row.topAnchor.constraint(equalTo: view.topAnchor, constant: 7), row.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -7)])
    }

    private func clearStack(_ stack: UIStackView) { stack.arrangedSubviews.forEach { $0.removeFromSuperview() } }

    private func installedArtifactSection() -> UIView {
        let wrapper = UIStackView(); wrapper.axis = .vertical; wrapper.spacing = 3
        wrapper.addArrangedSubview(sectionHeading("最近产物", icon: "doc.richtext"))
        let list = UIStackView(); list.axis = .vertical; list.spacing = 2
        if runtime.artifacts.isEmpty {
            let label = UILabel(); label.text = "当前会话尚无服务端确认的产物"; label.font = DHTheme.font(.caption1); label.textColor = DHTheme.secondaryText; list.addArrangedSubview(label)
        } else {
            runtime.artifacts.prefix(5).forEach { artifact in
                let button = dhButton(title: artifact.name, systemName: artifact.kind == "image" ? "photo" : "doc", filled: false) { [weak self] in self?.showArtifact(artifact) }
                button.contentHorizontalAlignment = .leading; button.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 9, bottom: 5, trailing: 9); button.accessibilityLabel = "产物：\(artifact.name)，路径 \(artifact.path)"; list.addArrangedSubview(button)
            }
        }
        wrapper.addArrangedSubview(list); return wrapper
    }

    private func showArtifact(_ artifact: HarnessArtifact) {
        let alert = UIAlertController(title: artifact.name, message: "\(artifact.path)\n\n\(artifact.detail ?? "服务端已确认此产物。")", preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "复制路径", style: .default) { _ in UIPasteboard.general.string = artifact.path })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel)); present(alert, animated: true)
    }

    private func workspaceRow(_ workspace: HarnessWorkspace) -> UIView {
        let row = UIStackView(); row.axis = .horizontal; row.alignment = .center; row.spacing = 2
        let open = dhButton(title: workspace.title, systemName: "folder", filled: false) { [weak self] in self?.openWorkspace(workspace) }
        open.contentHorizontalAlignment = .leading
        open.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 9, bottom: 5, trailing: 9)
        open.accessibilityLabel = "工作区：\(workspace.title)，路径 \(workspace.path)"
        open.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let more = UIButton(type: .system)
        var config = UIButton.Configuration.plain(); config.image = UIImage(systemName: "ellipsis"); config.baseForegroundColor = DHTheme.secondaryText; config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8); more.configuration = config
        more.accessibilityLabel = "工作区操作：\(workspace.title)"; more.widthAnchor.constraint(equalToConstant: 40).isActive = true; more.heightAnchor.constraint(equalToConstant: 44).isActive = true
        more.addAction(UIAction { [weak self, weak more] _ in self?.showWorkspaceActions(workspace, source: more) }, for: .touchUpInside)
        row.addArrangedSubview(open); row.addArrangedSubview(more)
        return row
    }
    private func renderAll() {
        let selected = runtime.sessions.first { $0.id == runtime.selectedSessionID }
        if let selected {
            installCard(currentCard, title: selected.title.isEmpty ? "未命名会话" : selected.title, subtitle: metadata(selected), icon: selected.running ? "bolt.fill" : "arrow.forward", color: selected.running ? DHTheme.accentSoft : DHTheme.surface)
            currentCard.isHidden = false
        } else {
            installCard(currentCard, title: "还没有选中的会话", subtitle: runtime.sessions.isEmpty ? "从真实 Harness 工作区开始一个任务" : "从上下文抽屉继续上次工作", icon: "arrow.forward")
            currentCard.isHidden = false
        }
        if let selected { stateLabel.text = runtime.connected ? (selected.running ? "正在执行" : "已连接") : runtime.statusText } else { stateLabel.text = runtime.connected ? "已连接" : runtime.statusText }
        stateLabel.textColor = runtime.lastError == nil ? DHTheme.secondaryText : DHTheme.danger
        configurePill(connectionButton, title: runtime.connected ? "已连接" : (runtime.lastError == nil ? "连接中" : "连接异常"), icon: "circle.fill", color: runtime.connected ? DHTheme.success : DHTheme.danger)
        clearStack(pendingSection); clearStack(runningSection); clearStack(recentSection); clearStack(workspacesSection)
        if runtime.pendingApprovals.isEmpty && runtime.pendingQuestions.isEmpty { pendingSection.isHidden = true } else { pendingSection.isHidden = false; runtime.pendingApprovals.forEach { addActivity($0, to: pendingSection) }; runtime.pendingQuestions.forEach { addActivity($0, to: pendingSection) } }
        let running = runtime.sessions.filter { $0.running || $0.status == "running" }
        runningSection.isHidden = running.isEmpty
        running.forEach { session in addSession(session, to: runningSection, icon: "bolt.fill", tint: DHTheme.accent) }
        let recent = HarnessPresentationPolicy.ordered(runtime.sessions.filter { !$0.blank && !$0.running }, archived: runtime.archivedSessionIDsForPresentation, preferences: appState.viewPreferences).prefix(5)
        recentSection.isHidden = recent.isEmpty
        recent.forEach { addSession($0, to: recentSection, icon: "message", tint: DHTheme.secondaryText) }
        workspacesSection.isHidden = runtime.workspaces.isEmpty
        runtime.workspaces.prefix(5).forEach { workspace in
            workspacesSection.addArrangedSubview(workspaceRow(workspace))
        }
        if let artifactSection { artifactSection.removeFromSuperview() }
        artifactSection = installedArtifactSection()
        if let artifactSection { content.addArrangedSubview(artifactSection); artifactSection.isHidden = runtime.artifacts.isEmpty }
        emptyLabel.isHidden = runtime.connected || !runtime.sessions.isEmpty || !runtime.workspaces.isEmpty
        renderDrawer()
    }

    private func metadata(_ session: HarnessSessionSummary) -> String { [runtime.workspaces.first(where: { $0.sessionIDs.contains(session.id) })?.title, session.model.isEmpty ? nil : session.model, session.permission.isEmpty ? nil : permissionName(session.permission), session.running ? (runtime.currentStage ?? "运行中") : "空闲"].compactMap { $0 }.joined(separator: " · ") }
    private func permissionName(_ value: String) -> String { ["read-only": "只读", "workspace-write": "工作区可写", "danger-full-access": "完全权限"][value] ?? value }
    private func addSession(_ session: HarnessSessionSummary, to stack: UIStackView, icon: String, tint: UIColor) {
        stack.addArrangedSubview(sessionRow(session, icon: icon, closeDrawer: false))
    }

    private func sessionRow(_ session: HarnessSessionSummary, icon: String, closeDrawer: Bool) -> UIView {
        let row = UIStackView(); row.axis = .horizontal; row.alignment = .center; row.spacing = 2
        let button = dhButton(title: session.title.isEmpty ? "新会话" : session.title, systemName: icon, filled: false) { [weak self] in
            self?.runtime.openSession(session.id)
            self?.showConversation()
            if closeDrawer { self?.toggleDrawer() }
        }
        button.contentHorizontalAlignment = .leading
        button.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 9, bottom: 5, trailing: 9)
        button.accessibilityLabel = "会话：\(session.title)，\(metadata(session))"
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let more = UIButton(type: .system)
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "ellipsis")
        config.baseForegroundColor = DHTheme.secondaryText
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
        more.configuration = config
        more.accessibilityLabel = "会话操作：\(session.title)"
        more.widthAnchor.constraint(equalToConstant: 40).isActive = true
        more.heightAnchor.constraint(equalToConstant: 44).isActive = true
        more.addAction(UIAction { [weak self, weak more] _ in self?.showSessionActions(session, source: more) }, for: .touchUpInside)
        row.addArrangedSubview(button); row.addArrangedSubview(more)
        return row
    }

    private func showSessionActions(_ session: HarnessSessionSummary, source: UIView? = nil) {
        let alert = UIAlertController(title: session.title.isEmpty ? "新会话" : session.title, message: metadata(session), preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "重命名", style: .default) { [weak self] _ in self?.renameSession(session) })
        alert.addAction(UIAlertAction(title: "分叉会话", style: .default) { [weak self] _ in self?.runtime.forkSession(session.id) })
        alert.addAction(UIAlertAction(title: "归档会话", style: .default) { [weak self] _ in self?.runtime.archiveSession(session.id) })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let source { alert.popoverPresentationController?.sourceView = source; alert.popoverPresentationController?.sourceRect = source.bounds }
        present(alert, animated: true)
    }

    private func renameSession(_ session: HarnessSessionSummary) {
        let alert = UIAlertController(title: "重命名会话", message: nil, preferredStyle: .alert)
        alert.addTextField { field in field.text = session.title }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak self, weak alert] _ in
            let title = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !title.isEmpty else { return }
            self?.runtime.renameSession(session.id, title: title)
        })
        present(alert, animated: true)
    }

    private func showWorkspaceActions(_ workspace: HarnessWorkspace, source: UIView? = nil) {
        let alert = UIAlertController(title: workspace.title, message: workspace.path, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "设为默认工作区", style: .default) { [weak self] _ in var next = self?.appState.settings ?? .defaults; next.defaultWorkspaceID = workspace.id; self?.appState.updateSettings(next) })
        alert.addAction(UIAlertAction(title: "重命名", style: .default) { [weak self] _ in self?.renameWorkspace(workspace) })
        alert.addAction(UIAlertAction(title: "删除工作区", style: .destructive) { [weak self] _ in
            let confirm = UIAlertController(title: "删除工作区？", message: "这会删除服务端工作区及其关联入口，无法由客户端撤销。", preferredStyle: .alert)
            confirm.addAction(UIAlertAction(title: "取消", style: .cancel)); confirm.addAction(UIAlertAction(title: "删除", style: .destructive) { _ in self?.runtime.deleteWorkspace(workspace.id) }); self?.present(confirm, animated: true)
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let source { alert.popoverPresentationController?.sourceView = source; alert.popoverPresentationController?.sourceRect = source.bounds }
        present(alert, animated: true)
    }

    private func renameWorkspace(_ workspace: HarnessWorkspace) {
        let alert = UIAlertController(title: "重命名工作区", message: nil, preferredStyle: .alert)
        alert.addTextField { field in field.text = workspace.title }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel)); alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak self, weak alert] _ in let title = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""; if !title.isEmpty { self?.runtime.renameWorkspace(workspace.id, title: title) } }); present(alert, animated: true)
    }
    private func addActivity(_ approval: HarnessApprovalRequest, to stack: UIStackView) { let title = "\(approval.isHighRisk ? "高风险审批" : "审批") · \(approval.toolName)"; let button = dhButton(title: title, systemName: approval.isHighRisk ? "exclamationmark.triangle.fill" : "checkmark.shield", filled: false) { [weak self] in self?.showApproval(approval) }; button.contentHorizontalAlignment = .leading; stack.addArrangedSubview(button) }
    private func addActivity(_ question: HarnessPendingQuestion, to stack: UIStackView) { let title = question.questions.first?.question ?? "Agent 等待回答"; let button = dhButton(title: title, systemName: "questionmark.bubble", filled: false) { [weak self] in self?.showQuestion(question) }; button.contentHorizontalAlignment = .leading; stack.addArrangedSubview(button) }
    private func showApproval(_ request: HarnessApprovalRequest) { let c = HarnessApprovalViewController(runtime: runtime, request: request); present(UINavigationController(rootViewController: c), animated: true) }
    private func showQuestion(_ pending: HarnessPendingQuestion) { let c = QuestionViewController(pending: pending, onAnswer: { [weak self] answers in self?.runtime.answerQuestion(pending, answers: answers); self?.dismiss(animated: true) }, onCancel: { [weak self] in self?.runtime.cancelQuestion(pending); self?.dismiss(animated: true) }); present(UINavigationController(rootViewController: c), animated: true) }

    private func buildDrawer() {
        drawerScrim.backgroundColor = UIColor.black.withAlphaComponent(0.34); drawerScrim.alpha = 0; drawerScrim.isHidden = true; drawerScrim.translatesAutoresizingMaskIntoConstraints = false; drawerScrim.addTarget(self, action: #selector(toggleDrawer), for: .touchUpInside); view.addSubview(drawerScrim)
        drawer.translatesAutoresizingMaskIntoConstraints = false; drawer.backgroundColor = DHTheme.surface; drawer.isHidden = true; view.addSubview(drawer); drawerWidth = drawer.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.74)
        NSLayoutConstraint.activate([drawer.leadingAnchor.constraint(equalTo: view.leadingAnchor), drawer.topAnchor.constraint(equalTo: view.topAnchor), drawer.bottomAnchor.constraint(equalTo: view.bottomAnchor), drawerWidth, drawerScrim.leadingAnchor.constraint(equalTo: drawer.trailingAnchor), drawerScrim.trailingAnchor.constraint(equalTo: view.trailingAnchor), drawerScrim.topAnchor.constraint(equalTo: view.topAnchor), drawerScrim.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
        let header = UIStackView(); header.axis = .horizontal; header.alignment = .center; header.spacing = 8; header.translatesAutoresizingMaskIntoConstraints = false
        let logo = dhIconView(systemName: "sparkles", size: 32, symbolSize: 15); let label = UILabel(); label.text = "上下文"; label.font = DHTheme.font(.headline, weight: .bold); label.textColor = DHTheme.text; header.addArrangedSubview(logo); header.addArrangedSubview(label); header.addArrangedSubview(UIView()); let close = makeIconButton("xmark", label: "关闭上下文抽屉"); close.addAction(UIAction { [weak self] _ in self?.toggleDrawer() }, for: .touchUpInside); header.addArrangedSubview(close); drawer.addSubview(header)
        searchBar.placeholder = "搜索工作区、会话"; searchBar.searchBarStyle = .minimal; searchBar.delegate = self; searchBar.accessibilityLabel = "搜索工作区、会话"; searchBar.translatesAutoresizingMaskIntoConstraints = false; drawer.addSubview(searchBar)
        drawerScroll.translatesAutoresizingMaskIntoConstraints = false; drawer.addSubview(drawerScroll); drawerContent.axis = .vertical; drawerContent.spacing = 3; drawerContent.translatesAutoresizingMaskIntoConstraints = false; drawerScroll.addSubview(drawerContent)
        NSLayoutConstraint.activate([header.leadingAnchor.constraint(equalTo: drawer.leadingAnchor, constant: 12), header.trailingAnchor.constraint(equalTo: drawer.trailingAnchor, constant: -10), header.topAnchor.constraint(equalTo: drawer.safeAreaLayoutGuide.topAnchor, constant: 8), searchBar.leadingAnchor.constraint(equalTo: drawer.leadingAnchor, constant: 10), searchBar.trailingAnchor.constraint(equalTo: drawer.trailingAnchor, constant: -10), searchBar.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8), drawerScroll.leadingAnchor.constraint(equalTo: drawer.leadingAnchor), drawerScroll.trailingAnchor.constraint(equalTo: drawer.trailingAnchor), drawerScroll.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 6), drawerScroll.bottomAnchor.constraint(equalTo: drawer.bottomAnchor), drawerContent.leadingAnchor.constraint(equalTo: drawerScroll.contentLayoutGuide.leadingAnchor, constant: 12), drawerContent.trailingAnchor.constraint(equalTo: drawerScroll.contentLayoutGuide.trailingAnchor, constant: -12), drawerContent.topAnchor.constraint(equalTo: drawerScroll.contentLayoutGuide.topAnchor, constant: 8), drawerContent.bottomAnchor.constraint(equalTo: drawerScroll.contentLayoutGuide.bottomAnchor, constant: -24), drawerContent.widthAnchor.constraint(equalTo: drawerScroll.frameLayoutGuide.widthAnchor, constant: -24)])
    }

    private func renderDrawer() {
        guard drawerContent != nil else { return }; clearStack(drawerContent)
        let host = UILabel(); host.text = runtime.connected ? "主机 · 已连接" : "主机 · \(runtime.statusText)"; host.font = DHTheme.font(.subheadline, weight: .semibold); host.textColor = DHTheme.text; drawerContent.addArrangedSubview(host)
        let create = dhButton(title: "开始新任务", systemName: "plus", filled: true) { [weak self] in self?.createSession(); self?.toggleDrawer() }; drawerContent.addArrangedSubview(create)
        let source: [HarnessSessionSummary]
        if !searchResults.isEmpty {
            source = searchResults
        } else {
            source = runtime.sessions.filter { !$0.blank && (searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.title.localizedCaseInsensitiveContains(searchText) || $0.cwd.localizedCaseInsensitiveContains(searchText)) }
        }
        let visible = HarnessPresentationPolicy.sections(sessions: source, workspaces: runtime.workspaces, archived: runtime.archivedSessionIDsForPresentation, preferences: appState.viewPreferences)
        for section in visible {
            let title = UILabel(); title.text = "▾  \(section.title)"; title.font = DHTheme.font(.subheadline, weight: .semibold); title.textColor = DHTheme.secondaryText; drawerContent.addArrangedSubview(title)
            section.sessions.forEach { session in
                let isArchived = runtime.archivedSessionIDsForPresentation.contains(session.id)
                let row = sessionRow(session, icon: session.running ? "bolt.fill" : (isArchived ? "archivebox" : "message"), closeDrawer: true)
                drawerContent.addArrangedSubview(row)
            }
        }
        drawerContent.addArrangedSubview(dhButton(title: "添加工作区", systemName: "folder.badge.plus", filled: false) { [weak self] in self?.showDirectoryPicker() })
        drawerContent.addArrangedSubview(dhButton(title: "视图选项", systemName: "slider.horizontal.3", filled: false) { [weak self] in self?.showViewOptions() })
        drawerContent.addArrangedSubview(dhButton(title: "活动中心", systemName: "bell", filled: false) { [weak self] in self?.showActivityCenter() })
        drawerContent.addArrangedSubview(dhButton(title: "设置", systemName: "gearshape", filled: false) { [weak self] in guard let self else { return }; self.onSettings(self.runtime) })
    }

    private func showConversation() { rootScroll.isHidden = true; conversation.view.isHidden = false }
    private func showWorkspace() { conversation.view.isHidden = true; rootScroll.isHidden = false; renderAll() }
    private func openWorkspace(_ workspace: HarnessWorkspace) { if let session = runtime.sessions.first(where: { workspace.sessionIDs.contains($0.id) }) { runtime.openSession(session.id); showConversation() } else { showDirectoryPicker() } }
    private func createSession() {
        let requested = appState.settings.defaultWorkspaceID
        let workspaceID = runtime.workspaces.contains(where: { $0.id == requested }) ? requested : runtime.workspaces.first?.id
        runtime.createSession(workspaceID: workspaceID, defaultPermission: appState.settings.defaultPermission, defaultModel: appState.settings.defaultModel) { [weak self] result in
            if case let .failure(error) = result { self?.showError(error.localizedDescription) }
            else { self?.showConversation() }
        }
    }
    private func showError(_ message: String) { let alert = UIAlertController(title: "提示", message: message, preferredStyle: .alert); alert.addAction(UIAlertAction(title: "知道了", style: .default)); present(alert, animated: true) }
    private func showDirectoryPicker() { let picker = HarnessDirectoryPickerViewController(runtime: runtime) { [weak self] path in self?.runtime.addWorkspace(path: path) }; present(UINavigationController(rootViewController: picker), animated: true) }
    private func showViewOptions() {
        let p = appState.viewPreferences
        let a = UIAlertController(title: "视图选项", message: "当前：\(p.groupBy == .workspace ? "按工作区" : "单列表") · \(p.orderBy == .updated ? "最近更新" : "手动顺序") · 归档\(p.showArchived ? "已显示" : "已隐藏")", preferredStyle: .actionSheet)
        a.addAction(UIAlertAction(title: p.groupBy == .workspace ? "✓ 按工作区分组" : "按工作区分组", style: .default) { [weak self] _ in var next = self?.appState.viewPreferences ?? HarnessViewPreferences(); next.groupBy = .workspace; self?.appState.updateViewPreferences(next); self?.renderAll() })
        a.addAction(UIAlertAction(title: p.groupBy == .flat ? "✓ 单列表" : "单列表", style: .default) { [weak self] _ in var next = self?.appState.viewPreferences ?? HarnessViewPreferences(); next.groupBy = .flat; self?.appState.updateViewPreferences(next); self?.renderAll() })
        a.addAction(UIAlertAction(title: p.orderBy == .updated ? "✓ 按最近更新" : "按最近更新", style: .default) { [weak self] _ in var next = self?.appState.viewPreferences ?? HarnessViewPreferences(); next.orderBy = .updated; self?.appState.updateViewPreferences(next); self?.renderAll() })
        a.addAction(UIAlertAction(title: p.orderBy == .manual ? "✓ 按手动顺序" : "按手动顺序", style: .default) { [weak self] _ in var next = self?.appState.viewPreferences ?? HarnessViewPreferences(); next.orderBy = .manual; self?.appState.updateViewPreferences(next); self?.renderAll() })
        a.addAction(UIAlertAction(title: p.showArchived ? "隐藏归档会话" : "显示归档会话", style: .default) { [weak self] _ in var next = self?.appState.viewPreferences ?? HarnessViewPreferences(); next.showArchived.toggle(); self?.appState.updateViewPreferences(next); self?.renderAll() })
        a.addAction(UIAlertAction(title: "取消", style: .cancel)); present(a, animated: true)
    }
    private func showConnectionDetails() { let a = UIAlertController(title: "Harness 连接", message: appState.endpointString + (runtime.lastError.map { "\n\($0)" } ?? ""), preferredStyle: .alert); a.addAction(UIAlertAction(title: "刷新", style: .default) { [weak self] _ in self?.runtime.refresh() }); a.addAction(UIAlertAction(title: "关闭", style: .cancel)); present(a, animated: true) }
    private func showActivityCenter() {
        let c = HarnessActivityCenterViewController(runtime: runtime)
        present(UINavigationController(rootViewController: c), animated: true)
    }
    private func loadNativeManifest() { transport.loadManifest { [weak self] result in if case let .success(m) = result { self?.store.replace(m) } } }
    private func installGestures() { let edge = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(edgeDrawer(_:))); edge.edges = .left; view.addGestureRecognizer(edge) }
    @objc private func edgeDrawer(_ gesture: UIScreenEdgePanGestureRecognizer) { if gesture.state == .ended { toggleDrawer() } }
    @objc private func refresh() { runtime.refresh(); rootScroll.refreshControl?.endRefreshing() }
    @objc private func toggleDrawer() { isDrawerVisible.toggle(); if isDrawerVisible { renderDrawer(); drawer.isHidden = false; drawer.transform = CGAffineTransform(translationX: -view.bounds.width * 0.74, y: 0); drawerScrim.isHidden = false }; UIView.animate(withDuration: appState.settings.reduceMotion ? 0 : 0.22) { self.drawer.transform = self.isDrawerVisible ? .identity : CGAffineTransform(translationX: -self.view.bounds.width * 0.74, y: 0); self.drawerScrim.alpha = self.isDrawerVisible ? 1 : 0 } completion: { _ in if !self.isDrawerVisible { self.drawer.isHidden = true; self.drawerScrim.isHidden = true } } }
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        self.searchText = searchText
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            searchResults = []
            renderDrawer()
        } else {
            runtime.searchSessions(searchText) { [weak self] result in
                guard let self else { return }
                if case let .success(results) = result {
                    let ids = Set(results.map(\.sessionID))
                    self.searchResults = self.runtime.sessions.filter { ids.contains($0.id) }
                } else {
                    self.searchResults = []
                }
                self.renderDrawer()
            }
            renderDrawer()
        }
    }
}

private extension NativeHomeViewController {
    /// Compatibility name retained for the production static gate; the actual
    /// menu is the native context drawer and never a web/legacy surface.
    func sessionMenu() { toggleDrawer() }
}
