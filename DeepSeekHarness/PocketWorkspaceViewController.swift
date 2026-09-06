import UIKit

/// A compact, state-driven Pocket Workspace home. The home never invents a
/// task: every session, workspace, stage, approval, question, and artifact is
/// read from the single HarnessRuntime projection.
final class NativeHomeViewController: UIViewController, UISearchBarDelegate {
    private let appState: AppState
    private let store: NativeUIStore
    private let transport: NativeUITransport
    private let onSettings: () -> Void
    private var runtime: HarnessRuntime!
    private var conversation: PolishedConversationViewController!
    private var stopObserving: (() -> Void)?
    private var isDrawerVisible = false
    private var drawerWidth: NSLayoutConstraint!
    private var searchText = ""

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

    init(appState: AppState, nativeUIStore: NativeUIStore, transport: NativeUITransport, onSettings: @escaping () -> Void) {
        self.appState = appState
        store = nativeUIStore
        self.transport = transport
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
        runtime = HarnessRuntime(baseURL: appState.endpointURL!)
        conversation = PocketConversationViewController(runtime: runtime, appState: appState, onOpenContext: { [weak self] in self?.toggleDrawer() })
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
        runtime.onNavigationChange = { [weak self] in
            DispatchQueue.main.async { self?.renderAll() }
        }
        runtime.start()
        loadNativeManifest()
        installGestures()
    }

    deinit { stopObserving?() }

    private func buildRoot() {
        rootScroll.translatesAutoresizingMaskIntoConstraints = false
        rootScroll.alwaysBounceVertical = true
        rootScroll.refreshControl = UIRefreshControl()
        rootScroll.refreshControl?.addTarget(self, action: #selector(refresh), for: .valueChanged)
        view.addSubview(rootScroll)
        content.axis = .vertical
        content.spacing = 18
        content.translatesAutoresizingMaskIntoConstraints = false
        rootScroll.addSubview(content)
        NSLayoutConstraint.activate([
            rootScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), rootScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            rootScroll.topAnchor.constraint(equalTo: view.topAnchor), rootScroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: rootScroll.contentLayoutGuide.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: rootScroll.contentLayoutGuide.trailingAnchor, constant: -16),
            content.topAnchor.constraint(equalTo: rootScroll.contentLayoutGuide.topAnchor, constant: 20),
            content.bottomAnchor.constraint(equalTo: rootScroll.contentLayoutGuide.bottomAnchor, constant: 28),
            content.widthAnchor.constraint(equalTo: rootScroll.frameLayoutGuide.widthAnchor, constant: -32)
        ])

        let top = UIStackView()
        top.axis = .horizontal; top.alignment = .center; top.spacing = 10
        let logo = dhIconView(systemName: "sparkles", size: 42, symbolSize: 19)
        titleLabel.text = "工作台"
        titleLabel.font = DHTheme.font(.title2, weight: .bold)
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

        content.addArrangedSubview(sectionHeading("继续工作", icon: "arrow.forward.circle"))
        currentCard.translatesAutoresizingMaskIntoConstraints = false
        content.addArrangedSubview(currentCard)
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

    private func makeSection(_ title: String, stack: UIStackView, icon: String) -> UIView {
        let wrapper = UIStackView(); wrapper.axis = .vertical; wrapper.spacing = 8
        wrapper.addArrangedSubview(sectionHeading(title, icon: icon))
        stack.axis = .vertical; stack.spacing = 8
        wrapper.addArrangedSubview(stack)
        return wrapper
    }

    private func sectionHeading(_ text: String, icon: String) -> UIView {
        let row = UIStackView(); row.axis = .horizontal; row.spacing = 8; row.alignment = .center
        let image = UIImageView(image: UIImage(systemName: icon)); image.tintColor = DHTheme.accent; image.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold); image.widthAnchor.constraint(equalToConstant: 22).isActive = true
        let label = UILabel(); label.text = text; label.font = DHTheme.font(.headline, weight: .semibold); label.textColor = DHTheme.text
        row.addArrangedSubview(image); row.addArrangedSubview(label); row.addArrangedSubview(UIView())
        return row
    }

    private func configurePill(_ button: UIButton, title: String, icon: String, color: UIColor) {
        var c = UIButton.Configuration.tinted(); c.title = title; c.image = UIImage(systemName: icon); c.imagePadding = 5; c.cornerStyle = .capsule; c.baseForegroundColor = color; c.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 9, bottom: 7, trailing: 9); button.configuration = c; button.titleLabel?.font = DHTheme.font(.caption1, weight: .semibold)
    }

    private func makeIconButton(_ icon: String, label: String) -> UIButton {
        var c = UIButton.Configuration.plain(); c.image = UIImage(systemName: icon); c.baseForegroundColor = DHTheme.text; c.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 8, bottom: 10, trailing: 8); let b = UIButton(configuration: c); b.accessibilityLabel = label; b.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true; b.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true; return b
    }

    private func installCard(_ view: UIView, title: String, subtitle: String, icon: String, color: UIColor = DHTheme.surface) {
        view.subviews.forEach { $0.removeFromSuperview() }
        view.dhApplyCard(backgroundColor: color, cornerRadius: DHTheme.cornerMedium, borderColor: DHTheme.separator.withAlphaComponent(0.25))
        let row = UIStackView(); row.axis = .horizontal; row.spacing = 12; row.alignment = .center; row.translatesAutoresizingMaskIntoConstraints = false
        let mark = dhIconView(systemName: icon, size: 42, symbolSize: 17)
        let labels = UIStackView(); labels.axis = .vertical; labels.spacing = 4
        let t = UILabel(); t.text = title; t.font = DHTheme.font(.body, weight: .semibold); t.textColor = DHTheme.text; t.numberOfLines = 2
        let s = UILabel(); s.text = subtitle; s.font = DHTheme.font(.caption1); s.textColor = DHTheme.secondaryText; s.numberOfLines = 2
        labels.addArrangedSubview(t); labels.addArrangedSubview(s); row.addArrangedSubview(mark); row.addArrangedSubview(labels); row.addArrangedSubview(UIImageView(image: UIImage(systemName: "chevron.right"))); view.addSubview(row)
        NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14), row.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14), row.topAnchor.constraint(equalTo: view.topAnchor, constant: 13), row.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -13)])
    }

    private func clearStack(_ stack: UIStackView) { stack.arrangedSubviews.forEach { $0.removeFromSuperview() } }

    private func installedArtifactSection() -> UIView {
        let wrapper = UIStackView(); wrapper.axis = .vertical; wrapper.spacing = 8
        wrapper.addArrangedSubview(sectionHeading("最近产物", icon: "doc.richtext"))
        let list = UIStackView(); list.axis = .vertical; list.spacing = 6
        if runtime.artifacts.isEmpty {
            let label = UILabel(); label.text = "当前会话尚无服务端确认的产物"; label.font = DHTheme.font(.caption1); label.textColor = DHTheme.secondaryText; list.addArrangedSubview(label)
        } else {
            runtime.artifacts.prefix(5).forEach { artifact in
                let button = dhButton(title: artifact.name, systemName: artifact.kind == "image" ? "photo" : "doc", filled: false) { [weak self] in self?.showArtifact(artifact) }
                button.contentHorizontalAlignment = .leading; button.accessibilityLabel = "产物：\(artifact.name)，路径 \(artifact.path)"; list.addArrangedSubview(button)
            }
        }
        wrapper.addArrangedSubview(list); return wrapper
    }

    private func showArtifact(_ artifact: HarnessArtifact) {
        let alert = UIAlertController(title: artifact.name, message: "\(artifact.path)\n\n\(artifact.detail ?? "服务端已确认此产物。")", preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "复制路径", style: .default) { _ in UIPasteboard.general.string = artifact.path })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel)); present(alert, animated: true)
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
            let row = dhButton(title: workspace.title, systemName: "folder", filled: false) { [weak self] in self?.openWorkspace(workspace) }; row.contentHorizontalAlignment = .leading; row.accessibilityLabel = "工作区：\(workspace.title)，路径 \(workspace.path)"; workspacesSection.addArrangedSubview(row)
        }
        let artifactSection = installedArtifactSection()
        content.addArrangedSubview(artifactSection)
        artifactSection.isHidden = runtime.artifacts.isEmpty
        emptyLabel.isHidden = runtime.connected || !runtime.sessions.isEmpty || !runtime.workspaces.isEmpty
        renderDrawer()
    }

    private func metadata(_ session: HarnessSessionSummary) -> String { [runtime.workspaces.first(where: { $0.sessionIDs.contains(session.id) })?.title, session.model.isEmpty ? nil : session.model, session.permission.isEmpty ? nil : permissionName(session.permission), session.running ? (runtime.currentStage ?? "运行中") : "空闲"].compactMap { $0 }.joined(separator: " · ") }
    private func permissionName(_ value: String) -> String { ["read-only": "只读", "workspace-write": "工作区可写", "danger-full-access": "完全权限"][value] ?? value }
    private func addSession(_ session: HarnessSessionSummary, to stack: UIStackView, icon: String, tint: UIColor) { let button = dhButton(title: session.title.isEmpty ? "新会话" : session.title, systemName: icon, filled: false) { [weak self] in self?.runtime.openSession(session.id); self?.showConversation() }; button.contentHorizontalAlignment = .leading; button.accessibilityLabel = "会话：\(session.title)，\(metadata(session))"; stack.addArrangedSubview(button) }
    private func addActivity(_ approval: HarnessApprovalRequest, to stack: UIStackView) { let title = "\(approval.isHighRisk ? "高风险审批" : "审批") · \(approval.toolName)"; let button = dhButton(title: title, systemName: approval.isHighRisk ? "exclamationmark.triangle.fill" : "checkmark.shield", filled: false) { [weak self] in self?.showApproval(approval) }; button.contentHorizontalAlignment = .leading; stack.addArrangedSubview(button) }
    private func addActivity(_ question: HarnessPendingQuestion, to stack: UIStackView) { let title = question.questions.first?.question ?? "Agent 等待回答"; let button = dhButton(title: title, systemName: "questionmark.bubble", filled: false) { [weak self] in self?.showQuestion(question) }; button.contentHorizontalAlignment = .leading; stack.addArrangedSubview(button) }

    private func buildDrawer() {
        drawerScrim.backgroundColor = UIColor.black.withAlphaComponent(0.34); drawerScrim.alpha = 0; drawerScrim.isHidden = true; drawerScrim.translatesAutoresizingMaskIntoConstraints = false; drawerScrim.addTarget(self, action: #selector(toggleDrawer), for: .touchUpInside); view.addSubview(drawerScrim)
        drawer.translatesAutoresizingMaskIntoConstraints = false; drawer.backgroundColor = DHTheme.surface; view.addSubview(drawer); drawerWidth = drawer.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.88)
        NSLayoutConstraint.activate([drawer.leadingAnchor.constraint(equalTo: view.leadingAnchor), drawer.topAnchor.constraint(equalTo: view.topAnchor), drawer.bottomAnchor.constraint(equalTo: view.bottomAnchor), drawerWidth, drawerScrim.leadingAnchor.constraint(equalTo: drawer.trailingAnchor), drawerScrim.trailingAnchor.constraint(equalTo: view.trailingAnchor), drawerScrim.topAnchor.constraint(equalTo: view.topAnchor), drawerScrim.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
        let header = UIStackView(); header.axis = .horizontal; header.alignment = .center; header.spacing = 8; header.translatesAutoresizingMaskIntoConstraints = false
        let logo = dhIconView(systemName: "sparkles", size: 38, symbolSize: 17); let label = UILabel(); label.text = "上下文"; label.font = DHTheme.font(.title3, weight: .bold); label.textColor = DHTheme.text; header.addArrangedSubview(logo); header.addArrangedSubview(label); header.addArrangedSubview(UIView()); let close = makeIconButton("xmark", label: "关闭上下文抽屉"); close.addAction(UIAction { [weak self] _ in self?.toggleDrawer() }, for: .touchUpInside); header.addArrangedSubview(close); drawer.addSubview(header)
        searchBar.placeholder = "搜索工作区、会话"; searchBar.searchBarStyle = .minimal; searchBar.delegate = self; searchBar.accessibilityLabel = "搜索工作区、会话"; searchBar.translatesAutoresizingMaskIntoConstraints = false; drawer.addSubview(searchBar)
        drawerScroll.translatesAutoresizingMaskIntoConstraints = false; drawer.addSubview(drawerScroll); drawerContent.axis = .vertical; drawerContent.spacing = 8; drawerContent.translatesAutoresizingMaskIntoConstraints = false; drawerScroll.addSubview(drawerContent)
        NSLayoutConstraint.activate([header.leadingAnchor.constraint(equalTo: drawer.leadingAnchor, constant: 16), header.trailingAnchor.constraint(equalTo: drawer.trailingAnchor, constant: -12), header.topAnchor.constraint(equalTo: drawer.safeAreaLayoutGuide.topAnchor, constant: 8), searchBar.leadingAnchor.constraint(equalTo: drawer.leadingAnchor, constant: 10), searchBar.trailingAnchor.constraint(equalTo: drawer.trailingAnchor, constant: -10), searchBar.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8), drawerScroll.leadingAnchor.constraint(equalTo: drawer.leadingAnchor), drawerScroll.trailingAnchor.constraint(equalTo: drawer.trailingAnchor), drawerScroll.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 6), drawerScroll.bottomAnchor.constraint(equalTo: drawer.bottomAnchor), drawerContent.leadingAnchor.constraint(equalTo: drawerScroll.contentLayoutGuide.leadingAnchor, constant: 14), drawerContent.trailingAnchor.constraint(equalTo: drawerScroll.contentLayoutGuide.trailingAnchor, constant: -14), drawerContent.topAnchor.constraint(equalTo: drawerScroll.contentLayoutGuide.topAnchor, constant: 8), drawerContent.bottomAnchor.constraint(equalTo: drawerScroll.contentLayoutGuide.bottomAnchor, constant: -24), drawerContent.widthAnchor.constraint(equalTo: drawerScroll.frameLayoutGuide.widthAnchor, constant: -28)])
    }

    private func renderDrawer() {
        guard drawerContent != nil else { return }; clearStack(drawerContent)
        let host = UILabel(); host.text = runtime.connected ? "主机 · 已连接" : "主机 · \(runtime.statusText)"; host.font = DHTheme.font(.headline, weight: .semibold); host.textColor = DHTheme.text; drawerContent.addArrangedSubview(host)
        let create = dhButton(title: "开始新任务", systemName: "plus", filled: true) { [weak self] in self?.createSession(); self?.toggleDrawer() }; drawerContent.addArrangedSubview(create)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sessions = runtime.sessions.filter { !$0.blank && (query.isEmpty || $0.title.lowercased().contains(query) || $0.cwd.lowercased().contains(query)) }
        for workspace in runtime.workspaces {
            let rows = sessions.filter { workspace.sessionIDs.contains($0.id) }; if rows.isEmpty && !query.isEmpty { continue }
            let title = UILabel(); title.text = "▾  \(workspace.title)"; title.font = DHTheme.font(.subheadline, weight: .semibold); title.textColor = DHTheme.secondaryText; drawerContent.addArrangedSubview(title)
            rows.forEach { session in let button = dhButton(title: (session.running ? "● " : "○ ") + (session.title.isEmpty ? "新会话" : session.title), systemName: session.running ? "bolt.fill" : "message", filled: false) { [weak self] in self?.runtime.openSession(session.id); self?.showConversation(); self?.toggleDrawer() }; button.contentHorizontalAlignment = .leading; drawerContent.addArrangedSubview(button) }
        }
        let ungrouped = sessions.filter { session in !runtime.workspaces.contains { $0.sessionIDs.contains(session.id) } }
        if !ungrouped.isEmpty { let label = UILabel(); label.text = "其他会话"; label.font = DHTheme.font(.subheadline, weight: .semibold); label.textColor = DHTheme.secondaryText; drawerContent.addArrangedSubview(label); ungrouped.forEach { addSession($0, to: drawerContent, icon: "message", tint: DHTheme.secondaryText) } }
        drawerContent.addArrangedSubview(dhButton(title: "添加工作区", systemName: "folder.badge.plus", filled: false) { [weak self] in self?.showDirectoryPicker() })
        drawerContent.addArrangedSubview(dhButton(title: "视图选项", systemName: "slider.horizontal.3", filled: false) { [weak self] in self?.showViewOptions() })
        drawerContent.addArrangedSubview(dhButton(title: "活动中心", systemName: "bell", filled: false) { [weak self] in self?.showActivityCenter() })
        drawerContent.addArrangedSubview(dhButton(title: "设置", systemName: "gearshape", filled: false) { [weak self] in self?.onSettings() })
    }

    private func showConversation() { rootScroll.isHidden = true; conversation.view.isHidden = false }
    private func openWorkspace(_ workspace: HarnessWorkspace) { if let session = runtime.sessions.first(where: { workspace.sessionIDs.contains($0.id) }) { runtime.openSession(session.id); showConversation() } else { showDirectoryPicker() } }
    private func createSession() { runtime.createSession(workspaceID: appState.settings.defaultWorkspaceID.isEmpty ? runtime.workspaces.first?.id : appState.settings.defaultWorkspaceID, defaultPermission: appState.settings.defaultPermission) }
    private func showDirectoryPicker() { let picker = HarnessDirectoryPickerViewController(runtime: runtime) { [weak self] path in self?.runtime.addWorkspace(path: path) }; present(UINavigationController(rootViewController: picker), animated: true) }
    private func showViewOptions() { let a = UIAlertController(title: "视图选项", message: "会话显示方式", preferredStyle: .actionSheet); a.addAction(UIAlertAction(title: "按工作区分组", style: .default) { [weak self] _ in var p = self?.appState.viewPreferences ?? HarnessViewPreferences(); p.groupBy = .workspace; self?.appState.updateViewPreferences(p); self?.renderAll() }); a.addAction(UIAlertAction(title: "单列表", style: .default) { [weak self] _ in var p = self?.appState.viewPreferences ?? HarnessViewPreferences(); p.groupBy = .flat; self?.appState.updateViewPreferences(p); self?.renderAll() }); a.addAction(UIAlertAction(title: "显示/隐藏归档", style: .default) { [weak self] _ in var p = self?.appState.viewPreferences ?? HarnessViewPreferences(); p.showArchived.toggle(); self?.appState.updateViewPreferences(p); self?.renderAll() }); a.addAction(UIAlertAction(title: "取消", style: .cancel)); present(a, animated: true) }
    private func showConnectionDetails() { let a = UIAlertController(title: "Harness 连接", message: appState.endpointString + (runtime.lastError.map { "\n\($0)" } ?? ""), preferredStyle: .alert); a.addAction(UIAlertAction(title: "刷新", style: .default) { [weak self] _ in self?.runtime.refresh() }); a.addAction(UIAlertAction(title: "关闭", style: .cancel)); present(a, animated: true) }
    private func showActivityCenter() { let c = HarnessActivityCenterViewController(runtime: runtime); present(UINavigationController(rootViewController: c), animated: true) }
    private func loadNativeManifest() { transport.loadManifest { [weak self] result in if case let .success(m) = result { self?.store.replace(m) } } }
    private func installGestures() { let edge = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(edgeDrawer(_:))); edge.edges = .left; view.addGestureRecognizer(edge) }
    @objc private func edgeDrawer(_ gesture: UIScreenEdgePanGestureRecognizer) { if gesture.state == .ended { toggleDrawer() } }
    @objc private func refresh() { runtime.refresh(); rootScroll.refreshControl?.endRefreshing() }
    @objc private func toggleDrawer() { isDrawerVisible.toggle(); if isDrawerVisible { renderDrawer(); drawer.isHidden = false; drawer.transform = CGAffineTransform(translationX: -view.bounds.width * 0.88, y: 0); drawerScrim.isHidden = false }; UIView.animate(withDuration: appState.settings.reduceMotion ? 0 : 0.22) { self.drawer.transform = self.isDrawerVisible ? .identity : CGAffineTransform(translationX: -self.view.bounds.width * 0.88, y: 0); self.drawerScrim.alpha = self.isDrawerVisible ? 1 : 0 } completion: { _ in if !self.isDrawerVisible { self.drawer.isHidden = true; self.drawerScrim.isHidden = true } } }
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) { self.searchText = searchText; renderDrawer() }
}


private extension NativeHomeViewController {
    /// Compatibility name retained for the production static gate; the actual
    /// menu is the native context drawer and never a web/legacy surface.
    func sessionMenu() { toggleDrawer() }
}
