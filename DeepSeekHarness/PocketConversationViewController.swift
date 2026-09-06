import UIKit

/// A single, scroll-stable session surface with three Harness semantics:
/// conversation, process, and confirmed artifacts.  Production data is always
/// supplied by HarnessRuntime; DEBUG fixture content is isolated elsewhere.
final class PocketConversationViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UITextViewDelegate {
    private let runtime: HarnessRuntime
    private let appState: AppState
    private let onOpenContext: () -> Void
    private let table = UITableView(frame: .zero, style: .plain)
    private let composer = UIView()
    private let input = UITextView()
    private let send = UIButton(type: .system)
    private let status = UILabel()
    private let segment = UISegmentedControl(items: ["对话", "过程", "产物"])
    private var mode = 0
    private var visibleItems: [HarnessConversationItem] = []

    init(runtime: HarnessRuntime, appState: AppState, onOpenContext: @escaping () -> Void) {
        self.runtime = runtime; self.appState = appState; self.onOpenContext = onOpenContext; super.init(nibName: nil, bundle: nil)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = DHTheme.background
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "sidebar.left"), style: .plain, target: self, action: #selector(openContext))
        navigationItem.title = "Harness Pocket"
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "状态", style: .plain, target: self, action: #selector(showStatus))
        segment.selectedSegmentIndex = 0; segment.addTarget(self, action: #selector(segmentChanged), for: .valueChanged); segment.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(segment)
        table.dataSource = self; table.delegate = self; table.backgroundColor = .clear; table.separatorStyle = .none; table.register(PocketMessageCell.self, forCellReuseIdentifier: "message"); table.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(table)
        composer.dhApplyCard(backgroundColor: DHTheme.surface, cornerRadius: DHTheme.cornerLarge, borderColor: DHTheme.separator.withAlphaComponent(0.25)); composer.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(composer)
        input.font = DHTheme.font(.body); input.textColor = DHTheme.text; input.backgroundColor = .clear; input.isScrollEnabled = false; input.layer.cornerRadius = 12; input.accessibilityLabel = "任务输入"; input.accessibilityHint = "输入任务或继续指令"
        let placeholder = UILabel(); placeholder.text = "输入任务或继续指令…"; placeholder.textColor = DHTheme.tertiaryText; placeholder.font = DHTheme.font(.body); placeholder.isUserInteractionEnabled = false; placeholder.translatesAutoresizingMaskIntoConstraints = false; input.addSubview(placeholder); input.delegate = self
        send.setImage(UIImage(systemName: "arrow.up.circle.fill"), for: .normal); send.tintColor = DHTheme.accent; send.accessibilityLabel = "发送或停止"; send.addTarget(self, action: #selector(sendTapped), for: .touchUpInside); send.translatesAutoresizingMaskIntoConstraints = false
        status.font = DHTheme.font(.caption1, weight: .semibold); status.textColor = DHTheme.secondaryText; status.numberOfLines = 2; status.translatesAutoresizingMaskIntoConstraints = false
        composer.addSubview(input); composer.addSubview(send); composer.addSubview(status)
        NSLayoutConstraint.activate([segment.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16), segment.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16), segment.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8), segment.heightAnchor.constraint(greaterThanOrEqualToConstant: 36), table.leadingAnchor.constraint(equalTo: view.leadingAnchor), table.trailingAnchor.constraint(equalTo: view.trailingAnchor), table.topAnchor.constraint(equalTo: segment.bottomAnchor, constant: 8), table.bottomAnchor.constraint(equalTo: composer.topAnchor, constant: -8), composer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12), composer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12), composer.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -8), input.leadingAnchor.constraint(equalTo: composer.leadingAnchor, constant: 12), input.topAnchor.constraint(equalTo: composer.topAnchor, constant: 10), input.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -4), input.trailingAnchor.constraint(equalTo: send.leadingAnchor, constant: -8), send.trailingAnchor.constraint(equalTo: composer.trailingAnchor, constant: -10), send.centerYAnchor.constraint(equalTo: input.centerYAnchor), send.widthAnchor.constraint(equalToConstant: 44), send.heightAnchor.constraint(equalToConstant: 44), status.leadingAnchor.constraint(equalTo: composer.leadingAnchor, constant: 14), status.trailingAnchor.constraint(equalTo: composer.trailingAnchor, constant: -14), status.bottomAnchor.constraint(equalTo: composer.bottomAnchor, constant: -9)])
        runtime.onChange = { [weak self] in DispatchQueue.main.async { self?.render() } }; render()
    }
    @objc private func openContext() { onOpenContext() }
    @objc private func segmentChanged() { mode = segment.selectedSegmentIndex; render() }
    @objc private func sendTapped() { if runtime.isGenerating { runtime.cancel(); return }; let text = input.text.trimmingCharacters(in: .whitespacesAndNewlines); guard !text.isEmpty else { return }; runtime.send(text, mode: "queue"); input.text = ""; render() }
    @objc private func showStatus() { let text = runtime.lastError ?? runtime.statusText; let a = UIAlertController(title: "任务状态", message: [text, runtime.currentStage.map { "阶段：\($0)" }, runtime.contextDirectory.map { "目录：\($0)" }].compactMap { $0 }.joined(separator: "\n"), preferredStyle: .actionSheet); a.addAction(UIAlertAction(title: "刷新", style: .default) { [weak self] _ in self?.runtime.refresh() }); a.addAction(UIAlertAction(title: "关闭", style: .cancel)); a.popoverPresentationController?.sourceView = view; a.popoverPresentationController?.sourceRect = view.bounds; present(a, animated: true) }
    private func render() { status.text = [runtime.statusText, runtime.currentStage.map { "阶段：\($0)" }, runtime.isGenerating ? "正在运行" : nil, runtime.pendingApprovals.isEmpty ? nil : "待审批", runtime.pendingQuestions.isEmpty ? nil : "待回答"].compactMap { $0 }.joined(separator: " · "); send.setImage(UIImage(systemName: runtime.isGenerating ? "stop.circle.fill" : "arrow.up.circle.fill"), for: .normal); if mode == 0 { visibleItems = HarnessPresentationPolicy.transcriptVisibleItems(runtime.items, view: appState.settings.transcriptView) } else if mode == 1 { visibleItems = runtime.items.filter { $0.kind == .system || $0.kind == .tool } } else { visibleItems = runtime.items.filter { $0.subtitle == "产物" }; if visibleItems.isEmpty { visibleItems = runtime.items.filter { $0.kind == .system && $0.detail != nil } }; }; table.reloadData() }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { visibleItems.isEmpty ? 1 : visibleItems.count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell { guard !visibleItems.isEmpty else { let cell = UITableViewCell(style: .default, reuseIdentifier: nil); cell.backgroundColor = .clear; cell.textLabel?.text = runtime.selectedSessionID == nil ? "从上下文抽屉选择一个真实会话" : (mode == 2 ? "当前会话尚无服务端确认的产物" : "等待 Harness 返回内容"); cell.textLabel?.textColor = DHTheme.secondaryText; cell.textLabel?.numberOfLines = 0; return cell }; let cell = tableView.dequeueReusableCell(withIdentifier: "message", for: indexPath) as! PocketMessageCell; cell.configure(visibleItems[indexPath.row], settings: appState.settings); return cell }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) { guard visibleItems.indices.contains(indexPath.row) else { return }; let item = visibleItems[indexPath.row]; if item.kind == .tool || item.subtitle == "产物" || item.subtitle == "错误" { let a = UIAlertController(title: item.subtitle ?? "事件详情", message: [item.text, item.detail].compactMap { $0 }.joined(separator: "\n\n"), preferredStyle: .actionSheet); a.addAction(UIAlertAction(title: "复制", style: .default) { _ in UIPasteboard.general.string = item.detail ?? item.text }); a.addAction(UIAlertAction(title: "取消", style: .cancel)); present(a, animated: true) } }
}

private final class PocketMessageCell: UITableViewCell {
    private let kind = UILabel(); private let body = UITextView(); private let meta = UILabel()
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) { super.init(style: style, reuseIdentifier: reuseIdentifier); selectionStyle = .none; backgroundColor = .clear; kind.font = DHTheme.font(.caption1, weight: .semibold); meta.font = DHTheme.font(.caption2); meta.textColor = DHTheme.tertiaryText; body.isEditable = false; body.isSelectable = true; body.backgroundColor = .clear; body.textContainerInset = .zero; body.textContainer.lineFragmentPadding = 0; let stack = UIStackView(arrangedSubviews: [kind, body, meta]); stack.axis = .vertical; stack.spacing = 5; stack.translatesAutoresizingMaskIntoConstraints = false; contentView.addSubview(stack); NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16), stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16), stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8), stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)]) }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    func configure(_ item: HarnessConversationItem, settings: HarnessClientSettings) { kind.text = item.kind == .user ? "你" : item.kind == .assistant ? "Harness" : item.kind == .tool ? "工具事件" : (item.subtitle ?? "过程"); kind.textColor = item.kind == .tool ? DHTheme.warning : item.kind == .user ? DHTheme.accent : DHTheme.secondaryText; body.attributedText = item.isMarkdown ? HarnessMarkdown.attributed(item.text, fontSize: CGFloat(settings.fontSize), color: DHTheme.text) : NSAttributedString(string: item.text, attributes: [.font: DHTheme.scaledFont(size: CGFloat(settings.fontSize)), .foregroundColor: DHTheme.text]); body.accessibilityLabel = "\(kind.text ?? "内容")：\(item.text)"; meta.text = item.detail }
}
