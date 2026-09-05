import UIKit

/// The settings screen owns only client preferences. Server-backed settings are
/// exposed only when `settings/describe` advertises a writable namespace.
final class HarnessSettingsCenterViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let appState: AppState
    private let onConnectionSettings: () -> Void
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private var localRows: [SettingRow] = []

    struct SettingRow {
        let title: String
        let subtitle: String
        let value: String?
        let action: (() -> Void)?
    }

    init(appState: AppState, onConnectionSettings: @escaping () -> Void) {
        self.appState = appState
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
        localRows = [
            SettingRow(title: "外观", subtitle: "跟随系统、浅色或深色界面。", value: themeName(s.theme), action: { [weak self] in self?.chooseTheme() }),
            SettingRow(title: "会话字号", subtitle: "仅影响会话内容字号。", value: "\(s.fontSize) pt", action: { [weak self] in self?.chooseFontSize() }),
            SettingRow(title: "对话显示", subtitle: "控制已完成轮次的过程内容。", value: s.transcriptView == .compact ? "Compact" : "Normal", action: { [weak self] in self?.chooseTranscriptView() }),
            SettingRow(title: "繁忙时 Enter 行为", subtitle: "仅在智能体运行时生效；Cmd/Ctrl+Enter 使用另一行为。", value: s.busyEnter == .queue ? "排队发送" : "插话发送", action: { [weak self] in self?.chooseBusyEnter() }),
            SettingRow(title: "新会话默认权限", subtitle: "仅影响随后创建的会话；当前会话请在输入框旁切换。", value: permissionName(s.defaultPermission), action: { [weak self] in self?.choosePermission() })
        ]
        table.reloadData()
    }

    private var sections: [(String, [SettingRow])] {
        let connection = SettingRow(title: "Harness 服务", subtitle: appState.endpointString.isEmpty ? "尚未配置服务地址" : appState.endpointString, value: appState.hasConfiguredEndpoint ? (appState.hasStoredCredential ? "令牌已保存" : "未保存令牌") : "未配置", action: onConnectionSettings)
        return [("连接", [connection]), ("本机显示", localRows)]
    }

    func numberOfSections(in tableView: UITableView) -> Int { sections.count }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { sections[section].1.count }
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { sections[section].0 }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath) as! SettingsRowCell
        cell.configure(sections[indexPath.section].1[indexPath.row])
        return cell
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        sections[indexPath.section].1[indexPath.row].action?()
    }

    private func themeName(_ value: HarnessThemePreference) -> String { value == .system ? "系统" : value == .light ? "浅色" : "深色" }
    private func permissionName(_ value: String) -> String { ["read-only": "只读", "workspace-write": "工作区可写", "danger-full-access": "完全权限"][value] ?? value }

    private func chooseTheme() {
        let alert = UIAlertController(title: "外观", message: nil, preferredStyle: .actionSheet)
        for value in HarnessThemePreference.allCases {
            alert.addAction(UIAlertAction(title: themeName(value) + (appState.settings.theme == value ? " ✓" : ""), style: .default) { [weak self] _ in
                guard let self else { return }; var next = self.appState.settings; next.theme = value; self.appState.updateSettings(next); self.rebuildRows()
            })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel)); presentSheet(alert)
    }

    private func chooseFontSize() {
        let alert = UIAlertController(title: "会话字号", message: "12–17 pt，仅影响会话内容。", preferredStyle: .actionSheet)
        for value in 12...17 {
            alert.addAction(UIAlertAction(title: "\(value) pt" + (appState.settings.fontSize == value ? " ✓" : ""), style: .default) { [weak self] _ in
                guard let self else { return }; var next = self.appState.settings; next.fontSize = value; self.appState.updateSettings(next); self.rebuildRows()
            })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel)); presentSheet(alert)
    }

    private func chooseTranscriptView() {
        let alert = UIAlertController(title: "对话显示", message: "控制已完成轮次的过程内容。", preferredStyle: .actionSheet)
        for value in HarnessTranscriptView.allCases {
            alert.addAction(UIAlertAction(title: (value == .compact ? "Compact" : "Normal") + (appState.settings.transcriptView == value ? " ✓" : ""), style: .default) { [weak self] _ in
                guard let self else { return }; var next = self.appState.settings; next.transcriptView = value; self.appState.updateSettings(next); self.rebuildRows()
            })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel)); presentSheet(alert)
    }

    private func chooseBusyEnter() {
        let alert = UIAlertController(title: "繁忙时 Enter 行为", message: "仅在智能体运行时生效。", preferredStyle: .actionSheet)
        for value in HarnessBusyEnterBehavior.allCases {
            alert.addAction(UIAlertAction(title: (value == .queue ? "排队发送" : "插话发送") + (appState.settings.busyEnter == value ? " ✓" : ""), style: .default) { [weak self] _ in
                guard let self else { return }; var next = self.appState.settings; next.busyEnter = value; self.appState.updateSettings(next); self.rebuildRows()
            })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel)); presentSheet(alert)
    }

    private func choosePermission() {
        let alert = UIAlertController(title: "新会话默认权限", message: "完全权限允许执行高风险命令，请确认服务环境可信。", preferredStyle: .actionSheet)
        let options = [("只读", "read-only"), ("工作区可写", "workspace-write"), ("完全权限", "danger-full-access")]
        for (title, value) in options {
            alert.addAction(UIAlertAction(title: title + (appState.settings.defaultPermission == value ? " ✓" : ""), style: value == "danger-full-access" ? .destructive : .default) { [weak self] _ in
                guard let self else { return }; var next = self.appState.settings; next.defaultPermission = value; self.appState.updateSettings(next); self.rebuildRows()
            })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel)); presentSheet(alert)
    }

    private func presentSheet(_ alert: UIAlertController) {
        alert.popoverPresentationController?.sourceView = view
        alert.popoverPresentationController?.sourceRect = view.bounds
        present(alert, animated: true)
    }
    @objc private func close() { dismiss(animated: true) }
}

private final class SettingsRowCell: UITableViewCell {
    private let titleLabel = UILabel(); private let subtitleLabel = UILabel(); private let valueLabel = UILabel()
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = DHTheme.surface
        titleLabel.font = DHTheme.font(.body, weight: .semibold); titleLabel.textColor = DHTheme.text
        subtitleLabel.font = DHTheme.font(.subheadline); subtitleLabel.textColor = DHTheme.secondaryText; subtitleLabel.numberOfLines = 0
        valueLabel.font = DHTheme.font(.caption1, weight: .semibold); valueLabel.textColor = DHTheme.accent; valueLabel.textAlignment = .right
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        let labels = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel]); labels.axis = .vertical; labels.spacing = 5
        let row = UIStackView(arrangedSubviews: [labels, valueLabel]); row.axis = .horizontal; row.spacing = 12; row.alignment = .center; row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)
        NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18), row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18), row.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16), row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16)])
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(_ row: HarnessSettingsCenterViewController.SettingRow) { titleLabel.text = row.title; subtitleLabel.text = row.subtitle; valueLabel.text = row.value; valueLabel.isHidden = row.value == nil; accessoryType = row.action == nil ? .none : .disclosureIndicator }
}
