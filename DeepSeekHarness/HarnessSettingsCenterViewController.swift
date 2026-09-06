import UIKit

/// Local settings are deliberately separate from server capability settings.
/// A row is only presented as server-backed when a future Runtime capability
/// explicitly provides it; this screen never invents service settings.
final class HarnessSettingsCenterViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let appState: AppState
    private let runtime: HarnessRuntime?
    private let onConnectionSettings: () -> Void
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private var rows: [(String, [SettingRow])] = []

    struct SettingRow {
        let title: String
        let subtitle: String
        let value: String?
        let action: (() -> Void)?
    }

    init(appState: AppState, runtime: HarnessRuntime? = nil, onConnectionSettings: @escaping () -> Void) {
        self.appState = appState
        self.runtime = runtime
        self.onConnectionSettings = onConnectionSettings
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "设置"
        view.backgroundColor = DHTheme.background
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "xmark"), style: .plain, target: self, action: #selector(close))
        table.backgroundColor = .clear
        table.dataSource = self
        table.delegate = self
        table.register(SettingsRowCell.self, forCellReuseIdentifier: "row")
        table.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(table)
        NSLayoutConstraint.activate([
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor), table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), table.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        rebuildRows()
    }

    private func rebuildRows() {
        let s = appState.settings
        let connection = SettingRow(title: "Harness 主机", subtitle: appState.endpointString.isEmpty ? "尚未配置服务地址" : appState.endpointString, value: appState.hasConfiguredEndpoint ? (appState.hasStoredCredential ? "令牌已保存" : "未保存令牌") : "未配置", action: onConnectionSettings)
        let appearance = [
            SettingRow(title: "外观", subtitle: "系统、浅色或深色；颜色会随系统动态调整。", value: themeName(s.theme), action: { [weak self] in self?.chooseTheme() }),
            SettingRow(title: "正文字号", subtitle: "支持 Dynamic Type；代码字号独立调整。", value: "\(s.fontSize) pt", action: { [weak self] in self?.chooseFontSize() }),
            SettingRow(title: "代码字号", subtitle: "等宽工具调用、命令与日志。", value: "\(s.codeFontSize) pt", action: { [weak self] in self?.chooseCodeFontSize() }),
            SettingRow(title: "对话显示", subtitle: "Compact 隐藏普通过程行，Normal 保留完整事件流。", value: s.transcriptView == .compact ? "Compact" : "Normal", action: { [weak self] in self?.chooseTranscriptView() }),
            SettingRow(title: "减少动态效果", subtitle: "同时遵循系统的减少动态效果设置。", value: s.reduceMotion ? "开" : "关", action: { [weak self] in self?.toggleReduceMotion() })
        ]
        let agent = [
            SettingRow(title: "新会话默认权限", subtitle: "仅影响随后创建的会话；当前会话在任务控制台切换。", value: permissionName(s.defaultPermission), action: { [weak self] in self?.choosePermission() }),
            SettingRow(title: "默认模型", subtitle: "新建任务时使用；当前会话仍可在 Pocket 控制台切换。", value: defaultModelName, action: { [weak self] in self?.chooseDefaultModel() }),
            SettingRow(title: "默认工作区", subtitle: runtime == nil ? "连接到 Harness 后可选择名称" : "新建任务时使用；来自当前 Harness 工作区", value: defaultWorkspaceName, action: { [weak self] in self?.chooseWorkspace() }),
            SettingRow(title: "繁忙时 Enter", subtitle: "运行中可排队或插话；Cmd/Ctrl+Enter 使用另一行为。", value: s.busyEnter == .queue ? "排队发送" : "插话发送", action: { [weak self] in self?.chooseBusyEnter() })
        ]
        let notifications = SettingRow(title: "通知", subtitle: "任务完成、审批、用户问题分别控制；系统通知能力未配置时不伪造。", value: notificationSummary(s), action: { [weak self] in self?.chooseNotifications() })
        let diagnostics = [
            SettingRow(title: "诊断", subtitle: "查看连接状态、服务版本与脱敏说明。", value: appState.hasConfiguredEndpoint ? "已配置" : "未配置", action: { [weak self] in self?.showDiagnostics() }),
            SettingRow(title: "凭据隐私", subtitle: "令牌仅存钥匙串，不回显；此处不会显示 Cookie 或原始请求。", value: "钥匙串", action: nil)
        ]
        rows = [("主机与连接", [connection]), ("外观与阅读", appearance), ("Agent 默认行为", agent), ("通知", [notifications]), ("诊断与隐私", diagnostics)]
        table.reloadData()
    }

    func numberOfSections(in tableView: UITableView) -> Int { rows.count }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows[section].1.count }
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { rows[section].0 }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell { let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath) as! SettingsRowCell; cell.configure(rows[indexPath.section].1[indexPath.row]); return cell }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) { tableView.deselectRow(at: indexPath, animated: true); rows[indexPath.section].1[indexPath.row].action?() }

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
        alert.addAction(UIAlertAction(title: "取消", style: .cancel)); presentSheet(alert)
    }
    private func chooseWorkspace() {
        guard let runtime else { return }
        let alert = UIAlertController(title: "默认工作区", message: "新任务将使用所选真实工作区。", preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: appState.settings.defaultWorkspaceID.isEmpty ? "未指定 ✓" : "清除默认工作区", style: .default) { [weak self] _ in self?.update { $0.defaultWorkspaceID = "" } })
        runtime.workspaces.forEach { workspace in
            alert.addAction(UIAlertAction(title: workspace.title + (workspace.id == appState.settings.defaultWorkspaceID ? " ✓" : ""), style: .default) { [weak self] _ in self?.update { $0.defaultWorkspaceID = workspace.id } })
        }
        if runtime.workspaces.isEmpty { alert.message = "当前没有服务端返回的工作区。" }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel)); presentSheet(alert)
    }

    private func themeName(_ value: HarnessThemePreference) -> String { value == .system ? "系统" : value == .light ? "浅色" : "深色" }
    private func permissionName(_ value: String) -> String { ["read-only": "只读", "workspace-write": "工作区可写", "danger-full-access": "完全权限"][value] ?? value }
    private func notificationSummary(_ s: HarnessClientSettings) -> String {
        let values = [s.notifyFinished ? "完成" : nil, s.notifyApproval ? "审批" : nil, s.notifyQuestion ? "问题" : nil].compactMap { $0 }
        return values.isEmpty ? "已关闭" : values.joined(separator: " · ")
    }
    private func update(_ change: (inout HarnessClientSettings) -> Void) { var next = appState.settings; change(&next); appState.updateSettings(next); rebuildRows() }

    private func choosePermission() { let values = ["read-only", "workspace-write", "danger-full-access"]; let alert = UIAlertController(title: "新会话默认权限", message: "只影响随后创建的会话；服务端仍以真实权限校验为准。", preferredStyle: .actionSheet); values.forEach { value in alert.addAction(UIAlertAction(title: permissionName(value) + (appState.settings.defaultPermission == value ? " ✓" : ""), style: .default) { [weak self] _ in self?.update { $0.defaultPermission = value } }) }; alert.addAction(UIAlertAction(title: "取消", style: .cancel)); presentSheet(alert) }
    private func chooseTheme() { let alert = UIAlertController(title: "外观", message: nil, preferredStyle: .actionSheet); HarnessThemePreference.allCases.forEach { value in alert.addAction(UIAlertAction(title: themeName(value) + (appState.settings.theme == value ? " ✓" : ""), style: .default) { [weak self] _ in self?.update { $0.theme = value } }) }; alert.addAction(UIAlertAction(title: "取消", style: .cancel)); presentSheet(alert) }
    private func chooseFontSize() { chooseNumber(title: "正文字号", values: Array(12...17), current: appState.settings.fontSize) { [weak self] value in self?.update { $0.fontSize = value } } }
    private func chooseCodeFontSize() { chooseNumber(title: "代码字号", values: Array(12...17), current: appState.settings.codeFontSize) { [weak self] value in self?.update { $0.codeFontSize = value } } }
    private func chooseNumber(title: String, values: [Int], current: Int, handler: @escaping (Int) -> Void) { let alert = UIAlertController(title: title, message: "支持 Dynamic Type 的原生排版。", preferredStyle: .actionSheet); values.forEach { value in alert.addAction(UIAlertAction(title: "\(value) pt" + (value == current ? " ✓" : ""), style: .default) { _ in handler(value) }) }; alert.addAction(UIAlertAction(title: "取消", style: .cancel)); presentSheet(alert) }
    private func chooseTranscriptView() { let alert = UIAlertController(title: "对话显示", message: "控制已完成轮次的过程内容。", preferredStyle: .actionSheet); HarnessTranscriptView.allCases.forEach { value in alert.addAction(UIAlertAction(title: (value == .compact ? "Compact" : "Normal") + (appState.settings.transcriptView == value ? " ✓" : ""), style: .default) { [weak self] _ in self?.update { $0.transcriptView = value } }) }; alert.addAction(UIAlertAction(title: "取消", style: .cancel)); presentSheet(alert) }
    private func chooseBusyEnter() { let alert = UIAlertController(title: "繁忙时 Enter", message: "运行中才生效。", preferredStyle: .actionSheet); HarnessBusyEnterBehavior.allCases.forEach { value in alert.addAction(UIAlertAction(title: (value == .queue ? "排队发送" : "插话发送") + (appState.settings.busyEnter == value ? " ✓" : ""), style: .default) { [weak self] _ in self?.update { $0.busyEnter = value } }) }; alert.addAction(UIAlertAction(title: "取消", style: .cancel)); presentSheet(alert) }
    private func toggleReduceMotion() { update { $0.reduceMotion.toggle() } }
    private func chooseNotifications() { let alert = UIAlertController(title: "通知", message: "这是本机通知偏好；只有真实系统通知入口启用后才会发送。", preferredStyle: .actionSheet); alert.addAction(UIAlertAction(title: "任务完成：\(appState.settings.notifyFinished ? "开" : "关")", style: .default) { [weak self] _ in self?.update { $0.notifyFinished.toggle() } }); alert.addAction(UIAlertAction(title: "审批：\(appState.settings.notifyApproval ? "开" : "关")", style: .default) { [weak self] _ in self?.update { $0.notifyApproval.toggle() } }); alert.addAction(UIAlertAction(title: "用户问题：\(appState.settings.notifyQuestion ? "开" : "关")", style: .default) { [weak self] _ in self?.update { $0.notifyQuestion.toggle() } }); alert.addAction(UIAlertAction(title: "取消", style: .cancel)); presentSheet(alert) }
    private func showDiagnostics() { let status = appState.hasConfiguredEndpoint ? "已配置 Harness 地址\n令牌状态：\(appState.hasStoredCredential ? "已保存（不回显）" : "未保存")" : "尚未配置 Harness 地址"; let alert = UIAlertController(title: "诊断与隐私", message: status + "\n\n连接测试和服务版本以真实 Runtime 返回为准；本页面不生成演示数据。", preferredStyle: .alert); alert.addAction(UIAlertAction(title: "知道了", style: .default)); present(alert, animated: true) }
    private func presentSheet(_ alert: UIAlertController) { alert.popoverPresentationController?.sourceView = view; alert.popoverPresentationController?.sourceRect = view.bounds; present(alert, animated: true) }
    @objc private func close() { dismiss(animated: true) }
}

private final class SettingsRowCell: UITableViewCell {
    private let titleLabel = UILabel(); private let subtitleLabel = UILabel(); private let valueLabel = UILabel()
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) { super.init(style: style, reuseIdentifier: reuseIdentifier); backgroundColor = DHTheme.surface; titleLabel.font = DHTheme.font(.body, weight: .semibold); titleLabel.textColor = DHTheme.text; titleLabel.numberOfLines = 0; subtitleLabel.font = DHTheme.font(.subheadline); subtitleLabel.textColor = DHTheme.secondaryText; subtitleLabel.numberOfLines = 0; valueLabel.font = DHTheme.font(.caption1, weight: .semibold); valueLabel.textColor = DHTheme.accent; valueLabel.textAlignment = .right; valueLabel.numberOfLines = 0; valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal); let labels = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel]); labels.axis = .vertical; labels.spacing = 5; let row = UIStackView(arrangedSubviews: [labels, valueLabel]); row.axis = .horizontal; row.spacing = 12; row.alignment = .center; row.translatesAutoresizingMaskIntoConstraints = false; contentView.addSubview(row); NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18), row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18), row.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16), row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16)]) }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(_ row: HarnessSettingsCenterViewController.SettingRow) { titleLabel.text = row.title; subtitleLabel.text = row.subtitle; valueLabel.text = row.value; valueLabel.isHidden = row.value == nil; accessoryType = row.action == nil ? .none : .disclosureIndicator; accessibilityLabel = [row.title, row.subtitle, row.value].compactMap { $0 }.joined(separator: "，") }
}
