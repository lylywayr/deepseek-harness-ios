import UIKit

final class NativePluginCenterViewController: UITableViewController {
    private let store: NativeUIStore
    private let transport: NativeUITransport?
    private let actionHandler: NativeUIActionHandler?
    private let fallbackHandler: (String?) -> Void
    private var stopObserving: (() -> Void)?
    private var loading = false

    init(
        store: NativeUIStore,
        transport: NativeUITransport?,
        actionHandler: NativeUIActionHandler? = nil,
        fallbackHandler: @escaping (String?) -> Void = { _ in }
    ) {
        self.store = store
        self.transport = transport
        self.actionHandler = actionHandler
        self.fallbackHandler = fallbackHandler
        super.init(style: .insetGrouped)
        title = "插件"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .refresh,
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
        guard let transport, !loading else { return }
        loading = true
        navigationItem.rightBarButtonItem?.isEnabled = false
        transport.loadManifest { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.loading = false
                self.navigationItem.rightBarButtonItem?.isEnabled = true
                switch result {
                case let .success(manifest): self.store.replace(manifest)
                case let .failure(error): self.showNotice(error.localizedDescription)
                }
            }
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        max(store.manifest.plugins.count, 1)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if store.manifest.plugins.isEmpty { return 1 }
        let plugin = store.manifest.plugins[section]
        return max(store.manifest.surfaces.filter { $0.pluginID == plugin.id }.count, 1)
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        store.manifest.plugins.isEmpty ? "Native UI" : store.manifest.plugins[section].name
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = cell.defaultContentConfiguration()
        cell.accessoryType = .none

        if store.manifest.plugins.isEmpty {
            content.text = "尚未接入 Native UI 服务"
            content.secondaryText = "自动适配器会尝试转换现有 dsh.client 页面。"
        } else {
            let plugin = store.manifest.plugins[indexPath.section]
            let surfaces = store.manifest.surfaces.filter { $0.pluginID == plugin.id }
            if let surface = surfaces[safe: indexPath.row] {
                content.text = surface.title
                content.secondaryText = surface.isLegacyOnly ? "兼容模式（Web UI）" : "原生界面"
                cell.accessoryType = .disclosureIndicator
            } else {
                content.text = plugin.enabled ? "暂无界面" : "插件已禁用"
                content.secondaryText = plugin.version
            }
        }
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard !store.manifest.plugins.isEmpty else { return }
        let plugin = store.manifest.plugins[indexPath.section]
        let surfaces = store.manifest.surfaces.filter { $0.pluginID == plugin.id }
        guard let surface = surfaces[safe: indexPath.row] else { return }
        if surface.isLegacyOnly {
            fallbackHandler(surface.legacyURL ?? surface.root.url)
        } else {
            navigationController?.pushViewController(
                NativeUISurfaceViewController(
                    surface: surface,
                    store: store,
                    transport: transport,
                    actionHandler: actionHandler,
                    fallbackHandler: fallbackHandler
                ),
                animated: true
            )
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }

    private func showNotice(_ message: String) {
        let alert = UIAlertController(title: "Native UI", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
}

final class NativeUISurfaceViewController: UIViewController {
    private let surface: NativeUISurface
    private let store: NativeUIStore
    private let transport: NativeUITransport?
    private let actionHandler: NativeUIActionHandler?
    private let fallbackHandler: (String?) -> Void
    private let scrollView = UIScrollView()
    private let content = UIStackView()
    private var stopObserving: (() -> Void)?

    init(
        surface: NativeUISurface,
        store: NativeUIStore,
        transport: NativeUITransport?,
        actionHandler: NativeUIActionHandler? = nil,
        fallbackHandler: @escaping (String?) -> Void = { _ in }
    ) {
        self.surface = surface
        self.store = store
        self.transport = transport
        self.actionHandler = actionHandler
        self.fallbackHandler = fallbackHandler
        super.init(nibName: nil, bundle: nil)
        title = surface.title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        content.axis = .vertical
        content.spacing = 14
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(content)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -20),
            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 20),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -20),
            content.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40)
        ])
        render()
        stopObserving = store.observe { [weak self] in
            DispatchQueue.main.async { self?.render() }
        }
    }

    deinit { stopObserving?() }

    private func render() {
        content.arrangedSubviews.forEach { content.removeArrangedSubview($0); $0.removeFromSuperview() }
        let renderer = NativeUIRenderer(
            surfaceID: surface.id,
            transport: transport,
            actionHandler: actionHandler,
            fallbackHandler: fallbackHandler
        )
        let result = renderer.render(surface.root)
        result.views.forEach(content.addArrangedSubview)
        result.diagnostics.forEach { diagnostic in
            let label = UILabel()
            label.text = "⚠︎ \(diagnostic)"
            label.textColor = .systemOrange
            label.font = .preferredFont(forTextStyle: .footnote)
            label.numberOfLines = 0
            content.addArrangedSubview(label)
        }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil }
}
