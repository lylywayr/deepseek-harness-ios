import UIKit

final class NativePluginCenterViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let store: NativeUIStore
    private let transport: NativeUITransport?
    private let actionHandler: NativeUIActionHandler?
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let refreshControl = UIRefreshControl()
    private var stopObserving: (() -> Void)?
    private var loading = false

    init(
        store: NativeUIStore,
        transport: NativeUITransport?,
        actionHandler: NativeUIActionHandler? = nil
    ) {
        self.store = store
        self.transport = transport
        self.actionHandler = actionHandler
        super.init(nibName: nil, bundle: nil)
        title = "插件"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DHTheme.background
        tableView.backgroundColor = DHTheme.background
        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .none
        tableView.register(DHPluginCell.self, forCellReuseIdentifier: DHPluginCell.reuseIdentifier)
        tableView.register(DHPluginEmptyCell.self, forCellReuseIdentifier: DHPluginEmptyCell.reuseIdentifier)
        tableView.refreshControl = refreshControl
        refreshControl.addTarget(self, action: #selector(refreshManifest), for: .valueChanged)
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "arrow.clockwise"),
            style: .plain,
            target: self,
            action: #selector(refreshManifest)
        )
        stopObserving = store.observe { [weak self] in
            DispatchQueue.main.async { self?.tableView.reloadData() }
        }
        refreshManifest()
    }

    deinit { stopObserving?() }

    @objc private func refreshManifest() {
        guard let transport, !loading else {
            refreshControl.endRefreshing()
            return
        }
        loading = true
        transport.loadManifest { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.loading = false
                self.refreshControl.endRefreshing()
                switch result {
                case let .success(manifest): self.store.replace(manifest)
                case let .failure(error): self.showNotice(error.localizedDescription)
                }
            }
        }
    }

    private var plugins: [NativeUIPlugin] { store.manifest.plugins }

    func numberOfSections(in tableView: UITableView) -> Int { 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        max(plugins.count, 1)
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        plugins.isEmpty ? 0.01 : 42
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard !plugins.isEmpty else { return nil }
        let header = UIView()
        let label = UILabel()
        label.text = "已安装插件"
        label.font = DHTheme.font(.caption1, weight: .semibold)
        label.textColor = DHTheme.tertiaryText
        label.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -20),
            label.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -8)
        ])
        return header
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard !plugins.isEmpty else {
            let cell = tableView.dequeueReusableCell(withIdentifier: DHPluginEmptyCell.reuseIdentifier, for: indexPath) as! DHPluginEmptyCell
            cell.configure()
            return cell
        }
        let plugin = plugins[indexPath.row]
        let surfaces = store.manifest.surfaces.filter { $0.pluginID == plugin.id }
        let cell = tableView.dequeueReusableCell(withIdentifier: DHPluginCell.reuseIdentifier, for: indexPath) as! DHPluginCell
        cell.configure(plugin: plugin, surfaceCount: surfaces.count)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard !plugins.isEmpty else { return }
        let plugin = plugins[indexPath.row]
        let surfaces = store.manifest.surfaces.filter { $0.pluginID == plugin.id }
        guard let surface = surfaces.sorted(by: { ($0.order ?? 0) < ($1.order ?? 0) }).first else {
            showNotice(plugin.enabled ? "这个插件暂时没有可显示的界面。" : "这个插件已被禁用。")
            return
        }
        if surface.isLegacyOnly {
            showNotice("该插件页面未声明 Native UI；当前 iOS 客户端不会打开网页兼容页面。")
        } else {
            navigationController?.pushViewController(
                NativeUISurfaceViewController(surface: surface, store: store, transport: transport, actionHandler: actionHandler),
                animated: true
            )
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }

    private func showNotice(_ message: String) {
        let alert = UIAlertController(title: "插件", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "知道了", style: .default))
        present(alert, animated: true)
    }
}

final class DHPluginCell: UITableViewCell {
    static let reuseIdentifier = "DHPluginCell"
    private let icon = UIView()
    private let iconImage = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let statusLabel = DHBadgeLabel(text: "", color: DHTheme.success)
    private let arrow = UIImageView(image: UIImage(systemName: "chevron.right"))
    private let card = UIView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        contentView.backgroundColor = .clear
        card.dhApplyCard(backgroundColor: DHTheme.surface, cornerRadius: DHTheme.cornerMedium, borderColor: DHTheme.separator.withAlphaComponent(0.25))
        card.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(card)
        icon.backgroundColor = DHTheme.accentSoft
        icon.layer.cornerRadius = 23
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconImage.image = UIImage(systemName: "puzzlepiece.extension.fill")
        iconImage.tintColor = DHTheme.accent
        iconImage.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        iconImage.translatesAutoresizingMaskIntoConstraints = false
        icon.addSubview(iconImage)
        titleLabel.font = DHTheme.font(.body, weight: .semibold)
        titleLabel.textColor = DHTheme.text
        subtitleLabel.font = DHTheme.font(.caption1)
        subtitleLabel.textColor = DHTheme.secondaryText
        subtitleLabel.numberOfLines = 1
        let labels = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        labels.axis = .vertical
        labels.spacing = 4
        labels.translatesAutoresizingMaskIntoConstraints = false
        arrow.tintColor = DHTheme.tertiaryText
        arrow.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        arrow.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        [icon, labels, statusLabel, arrow].forEach(card.addSubview)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16), card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5), card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5), card.heightAnchor.constraint(equalToConstant: 76),
            icon.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14), icon.centerYAnchor.constraint(equalTo: card.centerYAnchor), icon.widthAnchor.constraint(equalToConstant: 46), icon.heightAnchor.constraint(equalToConstant: 46),
            iconImage.centerXAnchor.constraint(equalTo: icon.centerXAnchor), iconImage.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
            labels.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12), labels.centerYAnchor.constraint(equalTo: card.centerYAnchor), labels.trailingAnchor.constraint(lessThanOrEqualTo: statusLabel.leadingAnchor, constant: -8),
            statusLabel.trailingAnchor.constraint(equalTo: arrow.leadingAnchor, constant: -8), statusLabel.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            arrow.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14), arrow.centerYAnchor.constraint(equalTo: card.centerYAnchor), arrow.widthAnchor.constraint(equalToConstant: 14)
        ])
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(plugin: NativeUIPlugin, surfaceCount: Int) {
        titleLabel.text = plugin.name
        subtitleLabel.text = "\(plugin.version ?? "未知版本")  ·  \(surfaceCount) 个入口"
        statusLabel.text = plugin.enabled ? "可用" : "停用"
        statusLabel.textColor = plugin.enabled ? DHTheme.success : DHTheme.secondaryText
        statusLabel.backgroundColor = plugin.enabled ? DHTheme.success.withAlphaComponent(0.13) : DHTheme.surfaceMuted
        iconImage.image = UIImage(systemName: plugin.enabled ? "puzzlepiece.extension.fill" : "puzzlepiece.extension")
        card.alpha = plugin.enabled ? 1 : 0.65
    }
}

final class DHPluginEmptyCell: UITableViewCell {
    static let reuseIdentifier = "DHPluginEmptyCell"
    private let card = UIView()
    private let icon = UIView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        card.dhApplyCard(backgroundColor: DHTheme.surface, cornerRadius: DHTheme.cornerLarge, borderColor: DHTheme.separator.withAlphaComponent(0.25))
        card.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(card)
        icon.backgroundColor = DHTheme.accentSoft
        icon.layer.cornerRadius = 28
        icon.translatesAutoresizingMaskIntoConstraints = false
        let image = UIImageView(image: UIImage(systemName: "puzzlepiece.extension"))
        image.tintColor = DHTheme.accent
        image.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 24, weight: .medium)
        image.translatesAutoresizingMaskIntoConstraints = false
        icon.addSubview(image)
        titleLabel.textAlignment = .center
        titleLabel.font = DHTheme.font(.headline, weight: .semibold)
        detailLabel.textAlignment = .center
        detailLabel.textColor = DHTheme.secondaryText
        detailLabel.font = DHTheme.font(.subheadline)
        detailLabel.numberOfLines = 0
        let stack = UIStackView(arrangedSubviews: [icon, titleLabel, detailLabel])
        stack.axis = .vertical; stack.alignment = .center; stack.spacing = 12; stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16), card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18), card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24), stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24), stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 28), stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -28),
            icon.widthAnchor.constraint(equalToConstant: 56), icon.heightAnchor.constraint(equalToConstant: 56), image.centerXAnchor.constraint(equalTo: icon.centerXAnchor), image.centerYAnchor.constraint(equalTo: icon.centerYAnchor)
        ])
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure() {
        titleLabel.text = "没有可用的原生插件入口"
        detailLabel.text = "当前服务没有返回 Native UI 清单，或插件均已停用。此版本不会安装、投影或打开插件网页。"
    }
}

final class NativeUISurfaceViewController: UIViewController {
    private let surface: NativeUISurface
    private let store: NativeUIStore
    private let transport: NativeUITransport?
    private let actionHandler: NativeUIActionHandler?
    private let scrollView = UIScrollView()
    private let content = UIStackView()
    private var stopObserving: (() -> Void)?

    init(surface: NativeUISurface, store: NativeUIStore, transport: NativeUITransport?, actionHandler: NativeUIActionHandler? = nil) {
        self.surface = surface; self.store = store; self.transport = transport; self.actionHandler = actionHandler
        super.init(nibName: nil, bundle: nil)
        title = surface.title
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DHTheme.background
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        content.axis = .vertical; content.spacing = 14; content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView); scrollView.addSubview(content)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor), scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor), scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 20), content.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -20), content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 20), content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -20), content.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40)
        ])
        render()
        stopObserving = store.observe { [weak self] in DispatchQueue.main.async { self?.render() } }
    }
    deinit { stopObserving?() }

    private func render() {
        content.arrangedSubviews.forEach { content.removeArrangedSubview($0); $0.removeFromSuperview() }
        let intro = UIView(); intro.dhApplyCard(backgroundColor: DHTheme.surface, cornerRadius: DHTheme.cornerMedium, borderColor: DHTheme.separator.withAlphaComponent(0.25)); intro.translatesAutoresizingMaskIntoConstraints = false
        let icon = dhIconView(systemName: surface.icon ?? "square.grid.2x2", size: 46, symbolSize: 19)
        let titleLabel = UILabel(); titleLabel.text = surface.title; titleLabel.font = DHTheme.font(.title3, weight: .bold)
        let subtitle = UILabel(); subtitle.text = surface.subtitle ?? "原生插件界面"; subtitle.font = DHTheme.font(.caption1); subtitle.textColor = DHTheme.secondaryText; subtitle.numberOfLines = 0
        let labels = UIStackView(arrangedSubviews: [titleLabel, subtitle]); labels.axis = .vertical; labels.spacing = 4; labels.translatesAutoresizingMaskIntoConstraints = false
        intro.addSubview(icon); intro.addSubview(labels)
        NSLayoutConstraint.activate([icon.leadingAnchor.constraint(equalTo: intro.leadingAnchor, constant: 16), icon.topAnchor.constraint(equalTo: intro.topAnchor, constant: 16), icon.bottomAnchor.constraint(equalTo: intro.bottomAnchor, constant: -16), labels.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12), labels.trailingAnchor.constraint(equalTo: intro.trailingAnchor, constant: -16), labels.centerYAnchor.constraint(equalTo: icon.centerYAnchor)])
        content.addArrangedSubview(intro)
        let renderer = NativeUIRenderer(surfaceID: surface.id, transport: transport, actionHandler: actionHandler)
        let result = renderer.render(surface.root); result.views.forEach(content.addArrangedSubview)
        result.diagnostics.forEach { diagnostic in
            let label = UILabel(); label.text = "⚠︎  \(diagnostic)"; label.textColor = DHTheme.warning; label.font = DHTheme.font(.caption1); label.numberOfLines = 0; content.addArrangedSubview(label)
        }
    }
}
