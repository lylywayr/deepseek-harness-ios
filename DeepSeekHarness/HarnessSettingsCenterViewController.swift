import UIKit

/// Native settings shell. Only locally-owned settings and explicitly declared
/// server surfaces are shown; unsupported server domains are not fabricated.
final class HarnessSettingsCenterViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    struct Row {
        let title: String
        let subtitle: String
        let value: String?
        let action: (() -> Void)?
    }

    private let appState: AppState
    private let onConnectionSettings: () -> Void
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private let sections = [
        (
            title: "连接",
            rows: ["Harness 服务"]
        ),
        (
            title: "本机显示",
            rows: ["外观", "语言", "会话字号", "对话显示", "繁忙时 Enter 行为"]
        ),
        (
            title: "服务端能力",
            rows: ["由服务端提供的设置"]
        )
    ]

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
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "xmark"),
            style: .plain,
            target: self,
            action: #selector(close)
        )
        table.backgroundColor = .clear
        table.dataSource = self
        table.delegate = self
        table.register(SettingsRowCell.self, forCellReuseIdentifier: "row")
        table.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(table)
        NSLayoutConstraint.activate([
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            table.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private var rows: [[Row]] {
        [
            [Row(
                title: "Harness 服务",
                subtitle: appState.endpointString.isEmpty ? "尚未配置服务地址" : appState.endpointString,
                value: appState.hasConfiguredEndpoint ? (appState.hasStoredCredential ? "令牌已保存" : "未保存令牌") : "未配置",
                action: onConnectionSettings
            )],
            [
                Row(title: "外观", subtitle: "由系统设置控制；此版本不伪造服务端主题状态。", value: nil, action: nil),
                Row(title: "语言", subtitle: "沿用 iOS 当前语言；服务端 locale 尚未在此页联调。", value: nil, action: nil),
                Row(title: "会话字号", subtitle: "使用 Dynamic Type；可在系统设置中调整文字大小。", value: nil, action: nil),
                Row(title: "对话显示", subtitle: "当前由原生对话与轨迹视图固定展示。", value: nil, action: nil),
                Row(title: "繁忙时 Enter 行为", subtitle: "原生输入框当前按发送按钮提交；服务端偏好未联调。", value: nil, action: nil)
            ],
            [Row(
                title: "由服务端提供的设置",
                subtitle: "当前服务没有声明可供此原生客户端编辑的 settings Remote。模型与权限请从会话内的真实入口选择。",
                value: "未声明",
                action: nil
            )]
        ]
    }

    func numberOfSections(in tableView: UITableView) -> Int { sections.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows[section].count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].title
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath) as! SettingsRowCell
        cell.configure(rows[indexPath.section][indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let row = rows[indexPath.section][indexPath.row]
        if let action = row.action {
            action()
        } else {
            showNotice(row.subtitle)
        }
    }

    private func showNotice(_ message: String) {
        let alert = UIAlertController(title: "设置", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "知道了", style: .default))
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
        titleLabel.font = DHTheme.font(.body, weight: .semibold)
        titleLabel.textColor = DHTheme.text
        subtitleLabel.font = DHTheme.font(.subheadline)
        subtitleLabel.textColor = DHTheme.secondaryText
        subtitleLabel.numberOfLines = 0
        valueLabel.font = DHTheme.font(.caption1, weight: .semibold)
        valueLabel.textColor = DHTheme.accent
        valueLabel.textAlignment = .right
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        let labels = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        labels.axis = .vertical
        labels.spacing = 5
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
            row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ row: HarnessSettingsCenterViewController.Row) {
        titleLabel.text = row.title
        subtitleLabel.text = row.subtitle
        valueLabel.text = row.value
        valueLabel.isHidden = row.value == nil
        accessoryType = row.action == nil ? .none : .disclosureIndicator
    }
}
