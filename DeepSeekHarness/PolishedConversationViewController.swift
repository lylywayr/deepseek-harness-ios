import UIKit
import PhotosUI
import UniformTypeIdentifiers

final class PolishedConversationViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UITextViewDelegate, PHPickerViewControllerDelegate, UIDocumentPickerDelegate {
    private let runtime: HarnessRuntime
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let composer = UIView()
    private let input = UITextView()
    private let placeholder = UILabel()
    private let sendButton = UIButton(type: .system)
    private let attachButton = UIButton(type: .system)
    private let modelButton = UIButton(type: .system)
    private let permissionButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private let emptyState = UILabel()
    private let attachmentStrip = UIStackView()
    private var inputHeight: NSLayoutConstraint!
    private var composerBottom: NSLayoutConstraint!
    private var images: [[String: Any]] = []
    private var displayedIDs: [String] = []

    init(runtime: HarnessRuntime) {
        self.runtime = runtime
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DHTheme.background
        buildTable()
        buildComposer()
        buildEmptyState()
        runtime.onChange = { [weak self] in self?.render() }
        runtime.onApproval = { [weak self] value in self?.showApproval(value) }
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardChanged(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        render()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func buildTable() {
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.keyboardDismissMode = .interactive
        tableView.dataSource = self
        tableView.delegate = self
        tableView.estimatedRowHeight = 96
        tableView.rowHeight = UITableView.automaticDimension
        tableView.register(HarnessMessageCell.self, forCellReuseIdentifier: "message")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
    }

    private func buildComposer() {
        composer.translatesAutoresizingMaskIntoConstraints = false
        composer.dhApplyCard(backgroundColor: DHTheme.surface, cornerRadius: 22, borderColor: DHTheme.separator.withAlphaComponent(0.35), shadow: true)
        view.addSubview(composer)

        statusLabel.font = DHTheme.font(.caption2, weight: .medium)
        statusLabel.textColor = DHTheme.secondaryText
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        composer.addSubview(statusLabel)

        input.font = DHTheme.font(.body)
        input.textColor = DHTheme.text
        input.backgroundColor = .clear
        input.textContainerInset = UIEdgeInsets(top: 9, left: 10, bottom: 7, right: 10)
        input.textContainer.lineFragmentPadding = 0
        input.delegate = self
        input.translatesAutoresizingMaskIntoConstraints = false
        composer.addSubview(input)

        placeholder.text = "发消息或做任务…"
        placeholder.font = DHTheme.font(.body)
        placeholder.textColor = DHTheme.tertiaryText
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        composer.addSubview(placeholder)

        attachmentStrip.axis = .horizontal
        attachmentStrip.spacing = 6
        attachmentStrip.translatesAutoresizingMaskIntoConstraints = false
        attachmentStrip.isHidden = true
        composer.addSubview(attachmentStrip)

        configureIcon(attachButton, "paperclip", label: "添加图片")
        attachButton.addTarget(self, action: #selector(chooseAttachment), for: .touchUpInside)
        composer.addSubview(attachButton)
        configureText(modelButton, "默认模型")
        modelButton.addTarget(self, action: #selector(chooseModel), for: .touchUpInside)
        composer.addSubview(modelButton)
        configureIcon(permissionButton, "shield", label: "权限模式")
        permissionButton.addTarget(self, action: #selector(choosePermission), for: .touchUpInside)
        composer.addSubview(permissionButton)

        var sendConfig = UIButton.Configuration.filled()
        sendConfig.image = UIImage(systemName: "arrow.up")
        sendConfig.cornerStyle = .capsule
        sendConfig.baseBackgroundColor = DHTheme.accent
        sendConfig.baseForegroundColor = .white
        sendButton.configuration = sendConfig
        sendButton.accessibilityLabel = "发送消息"
        sendButton.addTarget(self, action: #selector(send), for: .touchUpInside)
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        composer.addSubview(sendButton)

        inputHeight = input.heightAnchor.constraint(equalToConstant: 46)
        composerBottom = composer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10)
        NSLayoutConstraint.activate([
            composer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12), composer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12), composerBottom,
            statusLabel.leadingAnchor.constraint(equalTo: composer.leadingAnchor, constant: 16), statusLabel.topAnchor.constraint(equalTo: composer.topAnchor, constant: 9),
            input.leadingAnchor.constraint(equalTo: composer.leadingAnchor, constant: 6), input.trailingAnchor.constraint(equalTo: composer.trailingAnchor, constant: -6), input.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 1), inputHeight,
            placeholder.leadingAnchor.constraint(equalTo: input.leadingAnchor, constant: 10), placeholder.topAnchor.constraint(equalTo: input.topAnchor, constant: 9),
            attachmentStrip.leadingAnchor.constraint(equalTo: composer.leadingAnchor, constant: 14), attachmentStrip.topAnchor.constraint(equalTo: input.bottomAnchor), attachmentStrip.heightAnchor.constraint(equalToConstant: 26),
            attachButton.leadingAnchor.constraint(equalTo: composer.leadingAnchor, constant: 10), attachButton.topAnchor.constraint(equalTo: attachmentStrip.bottomAnchor, constant: 3), attachButton.bottomAnchor.constraint(equalTo: composer.bottomAnchor, constant: -8), attachButton.widthAnchor.constraint(equalToConstant: 34), attachButton.heightAnchor.constraint(equalToConstant: 34),
            permissionButton.leadingAnchor.constraint(equalTo: attachButton.trailingAnchor, constant: 3), permissionButton.centerYAnchor.constraint(equalTo: attachButton.centerYAnchor), permissionButton.widthAnchor.constraint(equalToConstant: 34), permissionButton.heightAnchor.constraint(equalToConstant: 34),
            modelButton.leadingAnchor.constraint(equalTo: permissionButton.trailingAnchor, constant: 3), modelButton.centerYAnchor.constraint(equalTo: attachButton.centerYAnchor), modelButton.trailingAnchor.constraint(lessThanOrEqualTo: sendButton.leadingAnchor, constant: -6), modelButton.heightAnchor.constraint(equalToConstant: 32),
            sendButton.trailingAnchor.constraint(equalTo: composer.trailingAnchor, constant: -9), sendButton.centerYAnchor.constraint(equalTo: attachButton.centerYAnchor), sendButton.widthAnchor.constraint(equalToConstant: 38), sendButton.heightAnchor.constraint(equalToConstant: 38),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor), tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor), tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), tableView.bottomAnchor.constraint(equalTo: composer.topAnchor, constant: -6)
        ])
    }

    private func buildEmptyState() {
        emptyState.text = "选择或新建一个会话\n开始使用 Harness"
        emptyState.font = DHTheme.font(.title3, weight: .semibold)
        emptyState.textColor = DHTheme.secondaryText
        emptyState.textAlignment = .center
        emptyState.numberOfLines = 0
        emptyState.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyState)
        NSLayoutConstraint.activate([emptyState.centerXAnchor.constraint(equalTo: view.centerXAnchor), emptyState.centerYAnchor.constraint(equalTo: tableView.centerYAnchor), emptyState.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 30)])
    }

    private func configureIcon(_ button: UIButton, _ name: String, label: String) {
        var config = UIButton.Configuration.plain(); config.image = UIImage(systemName: name); config.baseForegroundColor = DHTheme.secondaryText
        button.configuration = config; button.accessibilityLabel = label; button.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureText(_ button: UIButton, _ title: String) {
        var config = UIButton.Configuration.tinted(); config.title = title; config.baseForegroundColor = DHTheme.secondaryText; config.background.cornerRadius = 9; config.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8)
        button.configuration = config; button.translatesAutoresizingMaskIntoConstraints = false
    }

    private func render() {
        let old = displayedIDs
        displayedIDs = runtime.items.map(\.id)
        tableView.reloadData()
        emptyState.isHidden = !runtime.items.isEmpty || runtime.selectedSessionID != nil
        statusLabel.text = runtime.lastError ?? runtime.statusText
        statusLabel.textColor = runtime.lastError == nil ? DHTheme.secondaryText : DHTheme.danger
        if let session = runtime.sessions.first(where: { $0.id == runtime.selectedSessionID }) {
            modelButton.configuration?.title = session.model.isEmpty ? "选择模型" : session.model
            permissionButton.configuration?.image = UIImage(systemName: session.permission == "danger-full-access" ? "shield.slash" : "shield")
            permissionButton.accessibilityLabel = "权限：\(session.permission)"
        }
        sendButton.configuration?.image = UIImage(systemName: runtime.isGenerating ? "stop.fill" : "arrow.up")
        sendButton.configuration?.baseBackgroundColor = runtime.isGenerating ? DHTheme.danger : DHTheme.accent
        updateSend()
        if old != displayedIDs, !displayedIDs.isEmpty { DispatchQueue.main.async { [weak self] in self?.scrollBottom() } }
    }

    private func updateSend() {
        let available = runtime.isGenerating || !input.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty
        sendButton.isEnabled = available
        sendButton.alpha = available ? 1 : 0.45
        placeholder.isHidden = !input.text.isEmpty
    }

    @objc private func send() {
        if runtime.isGenerating { runtime.cancel(); return }
        let text = input.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !images.isEmpty else { return }
        runtime.send(text, images: images)
        input.text = ""; images.removeAll(); renderAttachments(); textViewDidChange(input)
    }

    @objc private func chooseModel() {
        let alert = UIAlertController(title: "选择模型", message: nil, preferredStyle: .actionSheet)
        for group in Dictionary(grouping: runtime.models, by: \.provider) {
            for option in group.value { alert.addAction(UIAlertAction(title: "\(option.providerName) · \(option.modelName)", style: .default) { [weak self] _ in self?.runtime.selectModel(option) }) }
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel)); presentSheet(alert, source: modelButton)
    }

    @objc private func choosePermission() {
        let current = runtime.sessions.first(where: { $0.id == runtime.selectedSessionID })?.permission
        let alert = UIAlertController(title: "访问权限", message: "完全权限允许执行高风险命令，请确认当前服务环境可信。", preferredStyle: .actionSheet)
        [("只读", "read-only"), ("工作区可写", "workspace-write"), ("完全权限", "danger-full-access")].forEach { name, value in
            alert.addAction(UIAlertAction(title: name + (current == value ? " ✓" : ""), style: value == "danger-full-access" ? .destructive : .default) { [weak self] _ in self?.runtime.setPermission(value) })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel)); presentSheet(alert, source: permissionButton)
    }

    @objc private func chooseAttachment() {
        let alert = UIAlertController(title: "添加图片", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "照片图库", style: .default) { [weak self] _ in
            var config = PHPickerConfiguration(); config.selectionLimit = 20; config.filter = .images
            let picker = PHPickerViewController(configuration: config); picker.delegate = self; self?.present(picker, animated: true)
        })
        alert.addAction(UIAlertAction(title: "文件", style: .default) { [weak self] _ in
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.image], asCopy: true); picker.allowsMultipleSelection = true; picker.delegate = self; self?.present(picker, animated: true)
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel)); presentSheet(alert, source: attachButton)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        for result in results where result.itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            result.itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] data, _ in
                guard let data else { return }; Task { @MainActor in self?.appendImage(data, name: result.itemProvider.suggestedName) }
            }
        }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        for url in urls { if let data = try? Data(contentsOf: url) { appendImage(data, name: url.lastPathComponent) } }
    }

    private func appendImage(_ data: Data, name: String?) {
        guard data.count <= 20 * 1024 * 1024 else { showError("单张图片不能超过 20 MB"); return }
        let type = name?.lowercased().hasSuffix(".png") == true ? "image/png" : "image/jpeg"
        images.append(["type": "image", "mediaType": type, "data": data.base64EncodedString(), "name": name ?? "image"])
        renderAttachments(); updateSend()
    }

    private func renderAttachments() {
        attachmentStrip.arrangedSubviews.forEach { attachmentStrip.removeArrangedSubview($0); $0.removeFromSuperview() }
        attachmentStrip.isHidden = images.isEmpty
        for (index, image) in images.enumerated() {
            let button = UIButton(type: .system); button.setTitle("📎 \(image["name"] as? String ?? "图片") ×", for: .normal); button.titleLabel?.font = DHTheme.font(.caption2); button.tag = index; button.addTarget(self, action: #selector(removeAttachment(_:)), for: .touchUpInside); attachmentStrip.addArrangedSubview(button)
        }
    }

    @objc private func removeAttachment(_ sender: UIButton) { guard images.indices.contains(sender.tag) else { return }; images.remove(at: sender.tag); renderAttachments(); updateSend() }
    private func showApproval(_ value: [String: Any]) {
        guard let clientID = value["clientId"] as? String,
              let eventID = value["eventId"] as? String else { return }
        let request = value["request"] as? [String: Any]
        let tool = request?["toolName"] as? String ?? "未知工具"
        let reason = request?["reason"] as? String
        let message = ["工具：\(tool)", reason.map { "原因：\($0)" }].compactMap { $0 }.joined(separator: "\n\n")
        let alert = UIAlertController(title: "允许这次工具调用？", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "拒绝", style: .destructive) { [weak self] _ in
            self?.runtime.answerApproval(clientID: clientID, eventID: eventID, decision: "rejected")
        })
        alert.addAction(UIAlertAction(title: "仅允许一次", style: .default) { [weak self] _ in
            self?.runtime.answerApproval(clientID: clientID, eventID: eventID, decision: "allowed-once")
        })
        present(alert, animated: true)
    }
    private func showError(_ message: String) { let a=UIAlertController(title:"提示",message:message,preferredStyle:.alert);a.addAction(UIAlertAction(title:"好",style:.default));present(a,animated:true) }
    private func presentSheet(_ alert: UIAlertController, source: UIView) { alert.popoverPresentationController?.sourceView=source;alert.popoverPresentationController?.sourceRect=source.bounds;present(alert,animated:true) }
    private func scrollBottom() { guard !runtime.items.isEmpty else{return};tableView.scrollToRow(at:IndexPath(row:runtime.items.count-1,section:0),at:.bottom,animated:false) }

    @objc private func keyboardChanged(_ note: Notification) { guard let f=note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,let d=note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else{return};let c=view.convert(f,from:nil);composerBottom.constant = -10-max(0,view.bounds.maxY-c.minY-view.safeAreaInsets.bottom);UIView.animate(withDuration:d){self.view.layoutIfNeeded()} }
    func textViewDidChange(_ textView: UITextView) { inputHeight.constant=min(max(textView.contentSize.height,46),130);updateSend();view.layoutIfNeeded() }
    func tableView(_ tableView:UITableView,numberOfRowsInSection section:Int)->Int{runtime.items.count}
    func tableView(_ tableView:UITableView,cellForRowAt indexPath:IndexPath)->UITableViewCell{let c=tableView.dequeueReusableCell(withIdentifier:"message",for:indexPath) as! HarnessMessageCell;c.configure(runtime.items[indexPath.row]);return c}
    func tableView(_ tableView:UITableView,willDisplay cell:UITableViewCell,forRowAt indexPath:IndexPath){if indexPath.row==0&&runtime.hasMore{runtime.loadOlder()}}
}

final class HarnessMessageCell: UITableViewCell {
    private let card = UIView()
    private let title = UILabel()
    private let body = UILabel()
    private let meta = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        card.layer.cornerRadius = 14
        card.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(card)
        [title, body, meta].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview($0)
        }
        title.font = DHTheme.font(.caption1, weight: .semibold)
        body.font = DHTheme.font(.body)
        body.numberOfLines = 0
        meta.font = DHTheme.font(.caption2)
        meta.textColor = DHTheme.tertiaryText
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5),
            title.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 13),
            title.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -13),
            title.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            body.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            body.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 5),
            meta.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            meta.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            meta.topAnchor.constraint(equalTo: body.bottomAnchor, constant: 6),
            meta.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -9)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ item: HarnessConversationItem) {
        title.text = item.kind == .user ? "你" : item.kind == .assistant ? "Harness" : item.kind == .tool ? "工具" : "系统"
        body.text = item.text
        meta.text = item.subtitle
        card.backgroundColor = item.kind == .user ? DHTheme.accentSoft : item.kind == .tool ? DHTheme.surfaceMuted : DHTheme.surface
        title.textColor = item.kind == .user ? DHTheme.accent : DHTheme.secondaryText
    }
}
