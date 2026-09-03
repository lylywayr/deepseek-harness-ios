import UIKit

final class HarnessSettingsCenterViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UITableViewDataSource, UITableViewDelegate {
    enum Page: Int, CaseIterable {
        case general, models, plugins, experts, presets, marketplace, services
        var title: String { ["通用设置", "模型", "插件", "专家", "Agent 预设", "插件市场", "服务控制"][rawValue] }
        var icon: String { ["gearshape", "externaldrive.badge.icloud", "slider.horizontal.3", "person.crop.circle.badge.checkmark", "point.3.connected.trianglepath.dotted", "shippingbox", "switch.2"][rawValue] }
    }

    struct Row {
        let title: String
        let subtitle: String?
        let value: String?
        let badge: String?
        let action: (() -> Void)?
    }

    private let appState: AppState
    private let onConnectionSettings: () -> Void
    private var selected: Page = .general
    private var tabs: UICollectionView!
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

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
        view.backgroundColor = DHTheme.background
        buildTabs()
        buildHeader()
        buildTable()
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "xmark"), style: .plain, target: self, action: #selector(close))
        renderPage()
    }

    private func buildTabs() {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumInteritemSpacing = 6
        layout.sectionInset = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        tabs = UICollectionView(frame: .zero, collectionViewLayout: layout)
        tabs.backgroundColor = DHTheme.surface
        tabs.showsHorizontalScrollIndicator = false
        tabs.dataSource = self
        tabs.delegate = self
        tabs.register(SettingsTabCell.self, forCellWithReuseIdentifier: "tab")
        tabs.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tabs)
        NSLayoutConstraint.activate([
            tabs.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabs.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabs.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tabs.heightAnchor.constraint(equalToConstant: 64)
        ])
    }

    private func buildHeader() {
        titleLabel.font = DHTheme.font(.title2, weight: .bold)
        titleLabel.textColor = DHTheme.text
        subtitleLabel.font = DHTheme.font(.subheadline)
        subtitleLabel.textColor = DHTheme.secondaryText
        subtitleLabel.numberOfLines = 0
        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: tabs.bottomAnchor, constant: 18)
        ])
        stack.tag = 91
    }

    private func buildTable() {
        table.backgroundColor = .clear
        table.separatorColor = DHTheme.separator
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 74
        table.dataSource = self
        table.delegate = self
        table.register(SettingsRowCell.self, forCellReuseIdentifier: "row")
        table.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(table)
        let header = view.viewWithTag(91)!
        NSLayoutConstraint.activate([
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            table.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func renderPage() {
        titleLabel.text = selected.title
        subtitleLabel.text = pageSubtitle
        tabs.reloadData()
        tabs.scrollToItem(at: IndexPath(item: selected.rawValue, section: 0), at: .centeredHorizontally, animated: true)
        table.reloadData()
    }

    private var pageSubtitle: String {
        switch selected {
        case .general: return "调整权限、语言、外观和对话显示。"
        case .models: return "填入各提供方的 API 密钥即可使用其模型。"
        case .plugins: return "配置和查看本部署已安装的插件。"
        case .experts: return "选择对话里可以召唤的专家。停用后不会出现在 @ 菜单中。"
        case .presets: return "预设即一个会话的 Agent 所运行的插件组装——它的工具、提示词与能力。"
        case .marketplace: return "发现、安装和更新 Harness 插件。"
        case .services: return "查看服务连接和可选能力的运行状态。"
        }
    }

    private var sections: [[Row]] {
        switch selected {
        case .general:
            return [[
                Row(title: "权限", subtitle: "选择新会话的默认权限模式", value: "完全权限", badge: nil, action: nil),
                Row(title: "语言", subtitle: nil, value: "中文", badge: nil, action: nil)
            ], [
                Row(title: "外观", subtitle: nil, value: "跟随系统", badge: nil, action: nil),
                Row(title: "字号大小", subtitle: "仅影响会话内容的字号", value: "14 px", badge: nil, action: nil),
                Row(title: "对话显示", subtitle: "控制已完成轮次的过程内容", value: "Compact", badge: nil, action: nil),
                Row(title: "繁忙时 Enter 键行为", subtitle: "仅在智能体运行时生效", value: "插话发送", badge: nil, action: nil)
            ]]
        case .models:
            return [[
                Row(title: "DeepSeek", subtitle: "官方提供方", value: "编辑", badge: "未连接", action: nil),
                Row(title: "workbuddy", subtitle: "自定义提供方", value: "编辑", badge: "已启用", action: nil)
            ], [
                Row(title: "添加提供方", subtitle: nil, value: nil, badge: nil, action: nil),
                Row(title: "添加自定义提供方", subtitle: nil, value: nil, badge: nil, action: nil)
            ]]
        case .plugins:
            return [[
                Row(title: "插件市场", subtitle: "查看插件市场版本与设置。", value: "展开", badge: nil, action: nil),
                Row(title: "终端", subtitle: "限制 agent 运行的每一条命令。", value: "展开", badge: nil, action: nil),
                Row(title: "Agent 循环", subtitle: "Agent 如何派发工具调用。", value: "展开", badge: nil, action: nil),
                Row(title: "Subagent", subtitle: "控制 Agent 为 Subagent 选择模型的权限。", value: "展开", badge: nil, action: nil),
                Row(title: "网页搜索", subtitle: "DeepSeek 搜索提供方。", value: "展开", badge: nil, action: nil),
                Row(title: "服务控制（dsh-service）", subtitle: "控制可选功能和外部能力。开关立即生效，无需重启。", value: "展开", badge: nil, action: nil)
            ]]
        case .experts:
            return [[
                Row(title: "273 位专家", subtitle: "1 位已启用 · 分类：全部（273）", value: "刷新", badge: nil, action: nil),
                Row(title: "地理学家", subtitle: "研究地形、气候、资源与人口分布的相互关系…", value: "启用", badge: "已停用", action: nil),
                Row(title: "历史学家", subtitle: "查阅档案和一手文献，核查史实…", value: "启用", badge: "已停用", action: nil),
                Row(title: "人类学家", subtitle: "开展田野调查与参与式观察…", value: "启用", badge: "已停用", action: nil),
                Row(title: "统计学家", subtitle: "设计实验方案，处理调查和试验数据…", value: "启用", badge: "已停用", action: nil)
            ]]
        case .presets:
            return [[
                Row(title: "标准模式", subtitle: "功能完整的编码 Agent，支持文件编辑、Shell、文件与网页检索、Skills、计划、目标、子代理和工作流。", value: "standard", badge: "当前使用", action: nil),
                Row(title: "PTC 模式", subtitle: "通过 PTC 模式 SDK 组合多步操作。", value: "ptc", badge: "内置", action: nil),
                Row(title: "极简模式", subtitle: "仅提供持久 bash 与 str_replace_editor 的双工具编码 Agent。", value: "minimal", badge: "内置", action: nil),
                Row(title: "创造模式", subtitle: "让 Agent 帮你创建新的预设。", value: nil, badge: "内置", action: nil)
            ]]
        case .marketplace:
            return [[
                Row(title: "搜索插件", subtitle: "按名称、作者或能力查找", value: nil, badge: nil, action: nil),
                Row(title: "已安装", subtitle: "管理本部署已安装的市场插件", value: "查看", badge: nil, action: nil),
                Row(title: "可用更新", subtitle: "检查插件的新版本", value: "检查", badge: nil, action: nil)
            ]]
        case .services:
            return [[
                Row(title: "Harness 服务", subtitle: appState.endpointString, value: "连接设置", badge: appState.hasConfiguredEndpoint ? "已配置" : "未配置", action: onConnectionSettings),
                Row(title: "运行状态", subtitle: "连接后读取服务控制 Remote", value: nil, badge: "待接入", action: nil),
                Row(title: "打开配置文件", subtitle: "查看当前 Harness 配置", value: nil, badge: "待接入", action: nil)
            ]]
        }
    }

    @objc private func close() { dismiss(animated: true) }

    func numberOfSections(in tableView: UITableView) -> Int { sections.count }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { sections[section].count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath) as! SettingsRowCell
        cell.configure(sections[indexPath.section][indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let row = sections[indexPath.section][indexPath.row]
        if let action = row.action { action(); return }
        let alert = UIAlertController(title: row.title, message: "页面结构已按真实 Harness 手机 UI 搬入；对应服务协议正在逐项接入。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "知道了", style: .default))
        present(alert, animated: true)
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { Page.allCases.count }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "tab", for: indexPath) as! SettingsTabCell
        let page = Page(rawValue: indexPath.item)!
        cell.configure(title: page.title, icon: page.icon, selected: page == selected)
        return cell
    }
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        selected = Page(rawValue: indexPath.item)!
        renderPage()
    }
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let page = Page(rawValue: indexPath.item)!
        return CGSize(width: max(76, CGFloat(page.title.count * 18 + 46)), height: 44)
    }
}

private final class SettingsTabCell: UICollectionViewCell {
    private let icon = UIImageView()
    private let label = UILabel()
    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 14
        icon.contentMode = .scaleAspectFit
        label.font = DHTheme.font(.subheadline, weight: .semibold)
        let stack = UIStackView(arrangedSubviews: [icon, label])
        stack.axis = .horizontal
        stack.spacing = 7
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 18), icon.heightAnchor.constraint(equalToConstant: 18),
            stack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor), stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    func configure(title: String, icon name: String, selected: Bool) {
        label.text = title
        icon.image = UIImage(systemName: name)
        label.textColor = DHTheme.text
        icon.tintColor = DHTheme.text
        contentView.backgroundColor = selected ? DHTheme.surfaceStrong : .clear
    }
}

private final class SettingsRowCell: UITableViewCell {
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let valueLabel = UILabel()
    private let badgeLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = DHTheme.surface
        titleLabel.font = DHTheme.font(.body, weight: .semibold)
        titleLabel.textColor = DHTheme.text
        subtitleLabel.font = DHTheme.font(.subheadline)
        subtitleLabel.textColor = DHTheme.secondaryText
        subtitleLabel.numberOfLines = 2
        valueLabel.font = DHTheme.font(.subheadline, weight: .medium)
        valueLabel.textColor = DHTheme.accent
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        badgeLabel.font = DHTheme.font(.caption2, weight: .semibold)
        badgeLabel.textColor = DHTheme.secondaryText
        badgeLabel.backgroundColor = DHTheme.surfaceStrong
        badgeLabel.layer.cornerRadius = 7
        badgeLabel.clipsToBounds = true
        badgeLabel.textAlignment = .center
        let labels = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        labels.axis = .vertical
        labels.spacing = 5
        let trailing = UIStackView(arrangedSubviews: [badgeLabel, valueLabel])
        trailing.axis = .vertical
        trailing.spacing = 7
        trailing.alignment = .trailing
        let row = UIStackView(arrangedSubviews: [labels, trailing])
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
            badgeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 54),
            badgeLabel.heightAnchor.constraint(equalToConstant: 24)
        ])
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    func configure(_ row: HarnessSettingsCenterViewController.Row) {
        titleLabel.text = row.title
        subtitleLabel.text = row.subtitle
        subtitleLabel.isHidden = row.subtitle?.isEmpty != false
        valueLabel.text = row.value
        valueLabel.isHidden = row.value == nil
        badgeLabel.text = row.badge.map { "  \($0)  " }
        badgeLabel.isHidden = row.badge == nil
        accessoryType = row.action == nil ? .none : .disclosureIndicator
    }
}
