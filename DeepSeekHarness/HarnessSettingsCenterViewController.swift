import UIKit

/// The host may provide these snapshots through the settings initializer.  The
/// native client deliberately does not invent plugin capabilities when the
/// Harness has not returned them yet.
enum HarnessPluginScope: String {
    case session
    case global
}

struct HarnessPluginDescriptor {
    let id: String
    let name: String
    let version: String?
    let enabled: Bool

    init(id: String, name: String, version: String? = nil, enabled: Bool) {
        self.id = id
        self.name = name
        self.version = version
        self.enabled = enabled
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? id : trimmed
    }
}

struct HarnessPluginSnapshot {
    let sessionPlugins: [HarnessPluginDescriptor]
    let globalPlugins: [HarnessPluginDescriptor]
    let currentAgentPreset: String?

    init(
        sessionPlugins: [HarnessPluginDescriptor] = [],
        globalPlugins: [HarnessPluginDescriptor] = [],
        currentAgentPreset: String? = nil
    ) {
        self.sessionPlugins = sessionPlugins
        self.globalPlugins = globalPlugins
        self.currentAgentPreset = currentAgentPreset
    }
}

enum HarnessPluginListState {
    case unavailable
    case loading
    case loaded(HarnessPluginSnapshot)
    case empty
    case failed(String)
}

struct HarnessPluginConfigurationSnapshot {
    let pluginMarket: String?
    let terminal: String?
    let agentLoop: String?
    let subagent: String?

    init(
        pluginMarket: String? = nil,
        terminal: String? = nil,
        agentLoop: String? = nil,
        subagent: String? = nil
    ) {
        self.pluginMarket = pluginMarket
        self.terminal = terminal
        self.agentLoop = agentLoop
        self.subagent = subagent
    }
}

enum HarnessPluginConfigurationState {
    case unavailable
    case loading
    case loaded(HarnessPluginConfigurationSnapshot)
    case failed(String)
}

typealias HarnessPluginListProvider = () -> HarnessPluginListState
typealias HarnessPluginConfigurationProvider = () -> HarnessPluginConfigurationState
typealias HarnessPluginMarketRoute = () -> Void

extension Notification.Name {
    /// Compatibility route for hosts that cannot inject a closure yet.  An
    /// observer should present the isolated market flow; this controller never
    /// creates a web surface itself.
    static let harnessPluginMarketRouteRequested = Notification.Name("HarnessPluginMarketRouteRequested")
}

/// Local settings are deliberately separate from server capability settings.
/// A row is only presented as server-backed when a Runtime or an injected
/// provider explicitly supplies it; this screen never invents service values.
final class HarnessSettingsCenterViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating {
    private enum Screen: Equatable {
        case root
        case general
        case model
        case deepPilot
        case pluginMenu
        case pluginConfiguration
        case pluginList
        case agentPreset
    }

    private let appState: AppState
    private let runtime: HarnessRuntime?
    private let onConnectionSettings: () -> Void
    private let pluginListProvider: HarnessPluginListProvider?
    private let pluginConfigurationProvider: HarnessPluginConfigurationProvider?
    private let onPluginMarket: HarnessPluginMarketRoute?
    private let onPluginListReload: (() -> Void)?
    private let screen: Screen
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private var rows: [(String, [SettingRow])] = []
    private var pluginListState: HarnessPluginListState = .unavailable
    private var pluginSearchController: UISearchController?

    struct SettingRow {
        let title: String
        let subtitle: String
        let value: String?
        let action: (() -> Void)?
    }

    init(
        appState: AppState,
        runtime: HarnessRuntime? = nil,
        onConnectionSettings: @escaping () -> Void,
        pluginListProvider: HarnessPluginListProvider? = nil,
        pluginConfigurationProvider: HarnessPluginConfigurationProvider? = nil,
        onPluginMarket: HarnessPluginMarketRoute? = nil,
        onPluginListReload: (() -> Void)? = nil
    ) {
        self.appState = appState
        self.runtime = runtime
        self.onConnectionSettings = onConnectionSettings
        self.pluginListProvider = pluginListProvider
        self.pluginConfigurationProvider = pluginConfigurationProvider
        self.onPluginMarket = onPluginMarket
        self.onPluginListReload = onPluginListReload
        self.screen = .root
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
    }

    private init(
        appState: AppState,
        runtime: HarnessRuntime?,
        screen: Screen,
        onConnectionSettings: @escaping () -> Void,
        pluginListProvider: HarnessPluginListProvider?,
        pluginConfigurationProvider: HarnessPluginConfigurationProvider?,
        onPluginMarket: HarnessPluginMarketRoute?,
        onPluginListReload: (() -> Void)?
    ) {
        self.appState = appState
        self.runtime = runtime
        self.screen = screen
        self.onConnectionSettings = onConnectionSettings
        self.pluginListProvider = pluginListProvider
        self.pluginConfigurationProvider = pluginConfigurationProvider
        self.onPluginMarket = onPluginMarket
        self.onPluginListReload = onPluginListReload
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = screenTitle
        view.backgroundColor = DHTheme.background
        table.backgroundColor = .clear
        table.dataSource = self
        table.delegate = self
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 72
        table.sectionHeaderHeight = UITableView.automaticDimension
        table.sectionFooterHeight = 8
        table.register(SettingsRowCell.self, forCellReuseIdentifier: "row")
        table.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(table)
        NSLayoutConstraint.activate([
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            table.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        if screen == .root {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                image: UIImage(systemName: "xmark"),
                style: .plain,
                target: self,
                action: #selector(close)
            )
            navigationItem.rightBarButtonItem?.accessibilityLabel = "关闭设置"
        }

        if screen == .pluginList {
            configurePluginSearch()
            let refresh = UIRefreshControl()
            refresh.addTarget(self, action: #selector(refreshPluginList), for: .valueChanged)
            refresh.accessibilityLabel = "刷新插件列表"
            table.refreshControl = refresh
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .refresh,
                target: self,
                action: #selector(refreshPluginList)
            )
            navigationItem.rightBarButtonItem?.accessibilityLabel = "刷新插件列表"
        }

        rebuildRows()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard isViewLoaded, screen == .pluginList else { return }
        rebuildRows()
    }

    private var screenTitle: String {
        switch screen {
        case .root: return "设置"
        case .general: return "通用设置"
        case .model: return "模型"
        case .deepPilot: return "DeepPilot"
        case .pluginMenu: return "插件"
        case .pluginConfiguration: return "插件配置"
        case .pluginList: return "插件列表"
        case .agentPreset: return "Agent 预设"
        }
    }

    private func configurePluginSearch() {
        let search = UISearchController(searchResultsController: nil)
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = "搜索插件"
        search.searchBar.accessibilityLabel = "搜索插件"
        search.searchBar.accessibilityHint = "按插件名称、标识或版本筛选"
        navigationItem.searchController = search
        navigationItem.hidesSearchBarWhenScrolling = false
        pluginSearchController = search
    }

    func updateSearchResults(for searchController: UISearchController) {
        guard screen == .pluginList else { return }
        rebuildRows()
    }

    private func rebuildRows() {
        switch screen {
        case .root:
            rows = rootRows()
        case .general:
            rows = generalRows()
        case .model:
            rows = modelRows()
        case .deepPilot:
            rows = deepPilotRows()
        case .pluginMenu:
            rows = pluginMenuRows()
        case .pluginConfiguration:
            rows = pluginConfigurationRows()
        case .pluginList:
            pluginListState = pluginListProvider?() ?? .unavailable
            rows = pluginListRows(for: pluginListState)
        case .agentPreset:
            rows = agentPresetRows()
        }
        table.reloadData()
    }

    private func rootRows() -> [(String, [SettingRow])] {
        let official: [SettingRow] = [
            SettingRow(
                title: "通用设置",
                subtitle: "阅读、通知与诊断等通用客户端偏好。",
                value: nil,
                action: { [weak self] in self?.push(.general) }
            ),
            SettingRow(
                title: "模型",
                subtitle: runtime?.models.isEmpty == false ? "使用当前 Harness 返回的模型目录。" : "模型目录尚未加载；不显示虚构模型。",
                value: nil,
                action: { [weak self] in self?.push(.model) }
            ),
            SettingRow(
                title: "DeepPilot",
                subtitle: runtime == nil ? "等待连接后读取真实服务端能力。" : "当前 Runtime 未返回 DeepPilot 配置值。",
                value: runtime == nil ? "等待连接" : "不可用",
                action: { [weak self] in self?.push(.deepPilot) }
            ),
            SettingRow(
                title: "插件",
                subtitle: "插件配置与插件列表。",
                value: nil,
                action: { [weak self] in self?.push(.pluginMenu) }
            ),
            SettingRow(
                title: "Agent 预设",
                subtitle: currentAgentPreset.map { "当前会话：\($0)" } ?? "当前会话预设尚未加载。",
                value: nil,
                action: { [weak self] in self?.push(.agentPreset) }
            ),
            SettingRow(
                title: "插件市场",
                subtitle: "独立市场入口；由集成层负责路由。",
                value: nil,
                action: { [weak self] in self?.openPluginMarket() }
            )
        ]
        let clientOnly = SettingRow(
            title: "Harness 主机连接（客户端专属）",
            subtitle: appState.endpointString.isEmpty ? "必要的客户端连接入口；未冒充 Harness 官方设置。" : appState.endpointString,
            value: appState.hasConfiguredEndpoint
                ? (appState.hasStoredCredential ? "令牌已保存" : "未保存令牌")
                : "未配置",
            action: onConnectionSettings
        )
        return [("官方 Harness 设置", official), ("客户端专属入口（非官方设置）", [clientOnly])]
    }

    private func generalRows() -> [(String, [SettingRow])] {
        let s = appState.settings
        let appearance = [
            SettingRow(title: "外观", subtitle: "系统、浅色或深色；颜色会随系统动态调整。", value: themeName(s.theme), action: { [weak self] in self?.chooseTheme() }),
            SettingRow(title: "正文字号", subtitle: "支持 Dynamic Type；代码字号独立调整。", value: "\(s.fontSize) pt", action: { [weak self] in self?.chooseFontSize() }),
            SettingRow(title: "代码字号", subtitle: "等宽工具调用、命令与日志。", value: "\(s.codeFontSize) pt", action: { [weak self] in self?.chooseCodeFontSize() }),
            SettingRow(title: "对话显示", subtitle: "Compact 隐藏普通过程行，Normal 保留完整事件流。", value: s.transcriptView == .compact ? "Compact" : "Normal", action: { [weak self] in self?.chooseTranscriptView() }),
            SettingRow(title: "减少动态效果", subtitle: "同时遵循系统的减少动态效果设置。", value: s.reduceMotion ? "开" : "关", action: { [weak self] in self?.toggleReduceMotion() })
        ]
        let agent = [
            SettingRow(title: "新会话默认权限", subtitle: "仅影响随后创建的会话；当前会话在任务控制台切换。", value: permissionName(s.defaultPermission), action: { [weak self] in self?.choosePermission() }),
            SettingRow(title: "默认工作区", subtitle: runtime == nil ? "连接到 Harness 后可选择名称。" : "新建任务时使用；来自当前 Harness 工作区。", value: defaultWorkspaceName, action: { [weak self] in self?.chooseWorkspace() }),
            SettingRow(title: "繁忙时 Enter", subtitle: "运行中可排队或插话；Cmd/Ctrl+Enter 使用另一行为。", value: s.busyEnter == .queue ? "排队发送" : "插话发送", action: { [weak self] in self?.chooseBusyEnter() })
        ]
        let notifications = SettingRow(title: "通知", subtitle: "任务完成、审批、用户问题分别控制；系统通知能力未配置时不伪造。", value: notificationSummary(s), action: { [weak self] in self?.chooseNotifications() })
        let diagnostics = [
            SettingRow(title: "诊断", subtitle: "查看连接状态、服务版本与脱敏说明。", value: appState.hasConfiguredEndpoint ? "已配置" : "未配置", action: { [weak self] in self?.showDiagnostics() }),
            SettingRow(title: "凭据隐私", subtitle: "令牌仅存钥匙串，不回显；此处不会显示 Cookie 或原始请求。", value: "钥匙串", action: nil)
        ]
        return [("外观与阅读", appearance), ("Agent 默认行为", agent), ("通知", [notifications]), ("诊断与隐私", diagnostics)]
    }

    private func modelRows() -> [(String, [SettingRow])] {
        let defaultRow = SettingRow(
            title: "默认模型",
            subtitle: "新建任务时使用；当前会话仍可在 Pocket 控制台切换。",
            value: defaultModelName,
            action: { [weak self] in self?.chooseDefaultModel() }
        )
        guard let runtime else {
            return [("模型偏好", [defaultRow, SettingRow(title: "模型目录", subtitle: "连接到 Harness 后读取真实模型；当前不可用。", value: "未连接", action: nil)])]
        }
        guard !runtime.models.isEmpty else {
            return [("模型偏好", [defaultRow, SettingRow(title: "模型目录", subtitle: "当前没有服务端返回的模型目录。", value: "暂无数据", action: nil)])]
        }
        let options = runtime.models.map { option in
            SettingRow(
                title: option.modelName,
                subtitle: "\(option.providerName) · \(option.key)",
                value: option.key == appState.settings.defaultModel ? "默认" : nil,
                action: { [weak self] in self?.update { $0.defaultModel = option.key } }
            )
        }
        return [("模型偏好", [defaultRow]), ("Harness 返回的模型", options)]
    }

    private func deepPilotRows() -> [(String, [SettingRow])] {
        let state = runtime == nil ? "等待连接" : "不可用"
        return [(
            "DeepPilot",
            [
                SettingRow(title: "DeepPilot 设置", subtitle: "服务端能力由 Harness 返回；当前客户端没有可用配置接口。", value: state, action: nil),
                SettingRow(title: "配置状态", subtitle: "未生成开关、权限或版本值。", value: "不可用", action: nil)
            ]
        )]
    }

    private func pluginMenuRows() -> [(String, [SettingRow])] {
        let preset = currentAgentPreset ?? "未加载"
        return [(
            "插件",
            [
                SettingRow(title: "插件配置", subtitle: "插件市场、终端、Agent 循环、Subagent。", value: nil, action: { [weak self] in self?.push(.pluginConfiguration) }),
                SettingRow(title: "插件列表", subtitle: "会话插件与全局插件；当前 Agent preset：\(preset)。", value: nil, action: { [weak self] in self?.push(.pluginList) })
            ]
        )]
    }

    private func pluginConfigurationRows() -> [(String, [SettingRow])] {
        let state = pluginConfigurationProvider?() ?? .unavailable
        let rows: [SettingRow] = [
            pluginConfigurationRow(title: "插件市场", subtitle: "查看插件市场版本与设置。", key: .pluginMarket, state: state),
            pluginConfigurationRow(title: "终端", subtitle: "限制 Agent 运行的每一条命令。", key: .terminal, state: state),
            pluginConfigurationRow(title: "Agent 循环", subtitle: "Agent 如何派发工具调用。", key: .agentLoop, state: state),
            pluginConfigurationRow(title: "Subagent", subtitle: "控制 Agent 为 Subagent 选择模型的权限。", key: .subagent, state: state)
        ]
        return [("真实配置项", rows)]
    }

    private enum PluginConfigurationKey {
        case pluginMarket
        case terminal
        case agentLoop
        case subagent
    }

    private func pluginConfigurationRow(
        title: String,
        subtitle: String,
        key: PluginConfigurationKey,
        state: HarnessPluginConfigurationState
    ) -> SettingRow {
        let resolved: String
        let detail: String
        switch state {
        case .unavailable:
            resolved = "不可用"
            detail = "Harness 未返回真实配置值；不显示或生成开关状态。"
        case .loading:
            resolved = "加载中"
            detail = "正在等待 Harness 返回真实配置值。"
        case let .failed(message):
            resolved = "加载失败"
            detail = message.isEmpty ? "Harness 未返回此配置。" : message
        case let .loaded(snapshot):
            let value: String?
            switch key {
            case .pluginMarket: value = snapshot.pluginMarket
            case .terminal: value = snapshot.terminal
            case .agentLoop: value = snapshot.agentLoop
            case .subagent: value = snapshot.subagent
            }
            resolved = value?.isEmpty == false ? value! : "不可用"
            detail = value?.isEmpty == false ? "来自当前 Harness 的真实配置值。" : "Harness 未返回此项配置值。"
        }
        return SettingRow(title: title, subtitle: "\(subtitle) \(detail)", value: resolved, action: nil)
    }

    private func pluginListRows(for state: HarnessPluginListState) -> [(String, [SettingRow])] {
        switch state {
        case .unavailable:
            return [("插件列表", [SettingRow(title: "插件列表不可用", subtitle: "当前 Harness 未提供插件列表接口；未生成示例插件。", value: "不可用", action: nil)])]
        case .loading:
            return [("插件列表", [SettingRow(title: "正在加载插件", subtitle: "正在等待 Harness 返回会话插件与全局插件。", value: "加载中", action: nil)])]
        case let .failed(message):
            return [("插件列表", [SettingRow(title: "插件列表加载失败", subtitle: message.isEmpty ? "Harness 未返回插件数据。" : message, value: "加载失败", action: nil)])]
        case .empty:
            return emptyPluginGroupRows(message: "Harness 返回了空插件列表。")
        case let .loaded(snapshot):
            let query = pluginSearchController?.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let session = filteredPlugins(snapshot.sessionPlugins, query: query)
            let global = filteredPlugins(snapshot.globalPlugins, query: query)
            let context = currentAgentPreset(snapshot: snapshot) ?? "未加载"
            let contextSubtitle = query.isEmpty
                ? "插件启用状态按当前会话投影；仅展示 Harness 返回的真实值。"
                : "搜索结果按当前 Agent preset 上下文投影；仅展示 Harness 返回的真实值。"
            let contextRow = SettingRow(title: "当前 Agent preset", subtitle: contextSubtitle, value: context, action: nil)
            let sessionRows = pluginRows(session, emptyMessage: query.isEmpty ? "当前没有会话插件。" : "没有匹配的会话插件。")
            let globalRows = pluginRows(global, emptyMessage: query.isEmpty ? "当前没有全局插件。" : "没有匹配的全局插件。")
            return [("上下文", [contextRow]), ("会话插件", sessionRows), ("全局插件", globalRows)]
        }
    }

    private func emptyPluginGroupRows(message: String) -> [(String, [SettingRow])] {
        let row = SettingRow(title: "暂无插件", subtitle: message, value: "空", action: nil)
        return [("上下文", [SettingRow(title: "当前 Agent preset", subtitle: "插件列表为空；没有可投影的启用状态。", value: currentAgentPreset ?? "未加载", action: nil)]), ("会话插件", [row]), ("全局插件", [row])]
    }

    private func filteredPlugins(_ plugins: [HarnessPluginDescriptor], query: String) -> [HarnessPluginDescriptor] {
        guard !query.isEmpty else { return plugins }
        return plugins.filter { plugin in
            [plugin.displayName, plugin.id, plugin.version ?? ""].contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private func pluginRows(_ plugins: [HarnessPluginDescriptor], emptyMessage: String) -> [SettingRow] {
        guard !plugins.isEmpty else {
            return [SettingRow(title: emptyMessage, subtitle: "没有写入静态示例或推测数量。", value: "空", action: nil)]
        }
        return plugins.map { plugin in
            let version = plugin.version?.trimmingCharacters(in: .whitespacesAndNewlines)
            let subtitle = [plugin.id.isEmpty ? nil : plugin.id, version?.isEmpty == false ? version : nil]
                .compactMap { $0 }
                .joined(separator: " · ")
            return SettingRow(
                title: plugin.displayName,
                subtitle: subtitle.isEmpty ? "Harness 未返回版本或标识。" : subtitle,
                value: plugin.enabled ? "已启用" : "已停用",
                action: nil
            )
        }
    }

    private func agentPresetRows() -> [(String, [SettingRow])] {
        let current = currentAgentPreset
        return [(
            "Agent 预设",
            [
                SettingRow(title: "当前会话预设", subtitle: "上下文来自当前 Runtime 会话；客户端不伪造预设目录。", value: current ?? "未加载", action: nil),
                SettingRow(title: "预设目录", subtitle: "当前没有可用的 Agent preset Remote 接口。", value: "不可用", action: nil)
            ]
        )]
    }

    private var currentAgentPreset: String? {
        guard let runtime, let selectedID = runtime.selectedSessionID,
              let session = runtime.sessions.first(where: { $0.id == selectedID }),
              !session.preset.isEmpty else { return nil }
        return session.preset
    }

    private func currentAgentPreset(snapshot: HarnessPluginSnapshot) -> String? {
        if let preset = snapshot.currentAgentPreset?.trimmingCharacters(in: .whitespacesAndNewlines), !preset.isEmpty {
            return preset
        }
        return currentAgentPreset
    }

    func numberOfSections(in tableView: UITableView) -> Int { rows.count }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows[section].1.count }
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { rows[section].0 }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath) as! SettingsRowCell
        cell.configure(rows[indexPath.section].1[indexPath.row])
        return cell
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        rows[indexPath.section].1[indexPath.row].action?()
    }

    private func push(_ screen: Screen) {
        let controller = HarnessSettingsCenterViewController(
            appState: appState,
            runtime: runtime,
            screen: screen,
            onConnectionSettings: onConnectionSettings,
            pluginListProvider: pluginListProvider,
            pluginConfigurationProvider: pluginConfigurationProvider,
            onPluginMarket: onPluginMarket,
            onPluginListReload: onPluginListReload
        )
        navigationController?.pushViewController(controller, animated: true)
    }

    private func openPluginMarket() {
        if let onPluginMarket {
            onPluginMarket()
            return
        }
        NotificationCenter.default.post(name: .harnessPluginMarketRouteRequested, object: self)
        let alert = UIAlertController(
            title: "插件市场",
            message: "插件市场路由尚未接入当前客户端。此处不会打开网页或生成市场内容。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "知道了", style: .default))
        present(alert, animated: true)
    }

    @objc private func refreshPluginList() {
        onPluginListReload?()
        rebuildRows()
        table.refreshControl?.endRefreshing()
    }

    private var defaultModelName: String {
        guard !appState.settings.defaultModel.isEmpty else { return "未指定" }
        return runtime?.models.first(where: { $0.key == appState.settings.defaultModel })?.modelName ?? appState.settings.defaultModel
    }

    private var defaultWorkspaceName: String {
        guard let runtime else { return appState.settings.defaultWorkspaceID.isEmpty ? "未指定" : "已保存" }
        return runtime.workspaces.first(where: { $0.id == appState.settings.defaultWorkspaceID })?.title ?? "未指定"
    }

    private func chooseDefaultModel() {
        guard let runtime else { return }
        let alert = UIAlertController(title: "默认模型", message: "只影响随后创建的会话。", preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: appState.settings.defaultModel.isEmpty ? "未指定 ✓" : "清除默认模型", style: .default) { [weak self] _ in self?.update { $0.defaultModel = "" } })
        runtime.models.forEach { option in
            alert.addAction(UIAlertAction(title: "\(option.providerName) · \(option.modelName)" + (option.key == appState.settings.defaultModel ? " ✓" : ""), style: .default) { [weak self] _ in self?.update { $0.defaultModel = option.key } })
        }
        if runtime.models.isEmpty { alert.message = "当前没有服务端返回的模型目录。" }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        presentSheet(alert)
    }

    private func chooseWorkspace() {
        guard let runtime else { return }
        let alert = UIAlertController(title: "默认工作区", message: "新任务将使用所选真实工作区。", preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: appState.settings.defaultWorkspaceID.isEmpty ? "未指定 ✓" : "清除默认工作区", style: .default) { [weak self] _ in self?.update { $0.defaultWorkspaceID = "" } })
        runtime.workspaces.forEach { workspace in
            alert.addAction(UIAlertAction(title: workspace.title + (workspace.id == appState.settings.defaultWorkspaceID ? " ✓" : ""), style: .default) { [weak self] _ in self?.update { $0.defaultWorkspaceID = workspace.id } })
        }
        if runtime.workspaces.isEmpty { alert.message = "当前没有服务端返回的工作区。" }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        presentSheet(alert)
    }

    private func themeName(_ value: HarnessThemePreference) -> String { value == .system ? "系统" : value == .light ? "浅色" : "深色" }
    private func permissionName(_ value: String) -> String { ["read-only": "只读", "workspace-write": "工作区可写", "danger-full-access": "完全权限"][value] ?? value }
    private func notificationSummary(_ s: HarnessClientSettings) -> String {
        let values = [s.notifyFinished ? "完成" : nil, s.notifyApproval ? "审批" : nil, s.notifyQuestion ? "问题" : nil].compactMap { $0 }
        return values.isEmpty ? "已关闭" : values.joined(separator: " · ")
    }
    private func update(_ change: (inout HarnessClientSettings) -> Void) {
        var next = appState.settings
        change(&next)
        appState.updateSettings(next)
        rebuildRows()
    }

    private func choosePermission() {
        let values = ["read-only", "workspace-write", "danger-full-access"]
        let alert = UIAlertController(title: "新会话默认权限", message: "只影响随后创建的会话；服务端仍以真实权限校验为准。", preferredStyle: .actionSheet)
        values.forEach { value in
            alert.addAction(UIAlertAction(title: permissionName(value) + (appState.settings.defaultPermission == value ? " ✓" : ""), style: .default) { [weak self] _ in self?.update { $0.defaultPermission = value } })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        presentSheet(alert)
    }

    private func chooseTheme() {
        let alert = UIAlertController(title: "外观", message: nil, preferredStyle: .actionSheet)
        HarnessThemePreference.allCases.forEach { value in
            alert.addAction(UIAlertAction(title: themeName(value) + (appState.settings.theme == value ? " ✓" : ""), style: .default) { [weak self] _ in self?.update { $0.theme = value } })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        presentSheet(alert)
    }

    private func chooseFontSize() {
        chooseNumber(title: "正文字号", values: Array(12...17), current: appState.settings.fontSize) { [weak self] value in self?.update { $0.fontSize = value } }
    }

    private func chooseCodeFontSize() {
        chooseNumber(title: "代码字号", values: Array(12...17), current: appState.settings.codeFontSize) { [weak self] value in self?.update { $0.codeFontSize = value } }
    }

    private func chooseNumber(title: String, values: [Int], current: Int, handler: @escaping (Int) -> Void) {
        let alert = UIAlertController(title: title, message: "支持 Dynamic Type 的原生排版。", preferredStyle: .actionSheet)
        values.forEach { value in
            alert.addAction(UIAlertAction(title: "\(value) pt" + (value == current ? " ✓" : ""), style: .default) { _ in handler(value) })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        presentSheet(alert)
    }

    private func chooseTranscriptView() {
        let alert = UIAlertController(title: "对话显示", message: "控制已完成轮次的过程内容。", preferredStyle: .actionSheet)
        HarnessTranscriptView.allCases.forEach { value in
            alert.addAction(UIAlertAction(title: (value == .compact ? "Compact" : "Normal") + (appState.settings.transcriptView == value ? " ✓" : ""), style: .default) { [weak self] _ in self?.update { $0.transcriptView = value } })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        presentSheet(alert)
    }

    private func chooseBusyEnter() {
        let alert = UIAlertController(title: "繁忙时 Enter", message: "运行中才生效。", preferredStyle: .actionSheet)
        HarnessBusyEnterBehavior.allCases.forEach { value in
            alert.addAction(UIAlertAction(title: (value == .queue ? "排队发送" : "插话发送") + (appState.settings.busyEnter == value ? " ✓" : ""), style: .default) { [weak self] _ in self?.update { $0.busyEnter = value } })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        presentSheet(alert)
    }

    private func toggleReduceMotion() { update { $0.reduceMotion.toggle() } }

    private func chooseNotifications() {
        let alert = UIAlertController(title: "通知", message: "这是本机通知偏好；只有真实系统通知入口启用后才会发送。", preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "任务完成：\(appState.settings.notifyFinished ? "开" : "关")", style: .default) { [weak self] _ in self?.update { $0.notifyFinished.toggle() } })
        alert.addAction(UIAlertAction(title: "审批：\(appState.settings.notifyApproval ? "开" : "关")", style: .default) { [weak self] _ in self?.update { $0.notifyApproval.toggle() } })
        alert.addAction(UIAlertAction(title: "用户问题：\(appState.settings.notifyQuestion ? "开" : "关")", style: .default) { [weak self] _ in self?.update { $0.notifyQuestion.toggle() } })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        presentSheet(alert)
    }

    private func showDiagnostics() {
        let status = appState.hasConfiguredEndpoint
            ? "已配置 Harness 地址\n令牌状态：\(appState.hasStoredCredential ? "已保存（不回显）" : "未保存")"
            : "尚未配置 Harness 地址"
        let alert = UIAlertController(title: "诊断与隐私", message: status + "\n\n连接测试和服务版本以真实 Runtime 返回为准；本页面不生成演示数据。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "知道了", style: .default))
        present(alert, animated: true)
    }

    private func presentSheet(_ alert: UIAlertController) {
        alert.popoverPresentationController?.sourceView = view
        alert.popoverPresentationController?.sourceRect = view.bounds
        present(alert, animated: true)
    }

    @objc private func close() { dismiss(animated: true) }
}

private final class SettingsRowCell: UITableViewCell {
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let valueLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = DHTheme.surface
        selectionStyle = .default

        titleLabel.font = DHTheme.font(.body, weight: .semibold)
        titleLabel.textColor = DHTheme.text
        titleLabel.numberOfLines = 0
        titleLabel.adjustsFontForContentSizeCategory = true

        subtitleLabel.font = DHTheme.font(.subheadline)
        subtitleLabel.textColor = DHTheme.secondaryText
        subtitleLabel.numberOfLines = 0
        subtitleLabel.adjustsFontForContentSizeCategory = true

        valueLabel.font = DHTheme.font(.caption1, weight: .semibold)
        valueLabel.textColor = DHTheme.accent
        valueLabel.textAlignment = .right
        valueLabel.numberOfLines = 0
        valueLabel.adjustsFontForContentSizeCategory = true
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)

        let labels = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        labels.axis = .vertical
        labels.spacing = 5
        labels.alignment = .fill
        labels.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [labels, valueLabel])
        row.axis = .horizontal
        row.spacing = 12
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            row.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            labels.widthAnchor.constraint(greaterThanOrEqualToConstant: 0)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ row: HarnessSettingsCenterViewController.SettingRow) {
        titleLabel.text = row.title
        subtitleLabel.text = row.subtitle
        valueLabel.text = row.value
        valueLabel.isHidden = row.value == nil
        accessoryType = row.action == nil ? .none : .disclosureIndicator
        isAccessibilityElement = true
        accessibilityLabel = [row.title, row.subtitle, row.value].compactMap { $0 }.joined(separator: "，")
        accessibilityTraits = row.action == nil ? [.staticText] : [.button]
        accessibilityHint = row.action == nil ? nil : "打开"
    }
}
