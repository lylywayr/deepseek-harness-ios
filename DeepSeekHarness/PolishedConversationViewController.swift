import UIKit

/// Polished native conversation surface used by the Native-first home screen.
/// It deliberately keeps transport out of the view so visual iteration stays independent.
final class PolishedConversationViewController: UIViewController, UITableViewDataSource, UITextViewDelegate {
    private struct Message {
        let text: String
        let isUser: Bool
    }

    private let onSend: (String) -> Void
    private var messages: [Message] = []

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let composer = UIView()
    private let input = UITextView()
    private let placeholder = UILabel()
    private let sendButton = UIButton(type: .system)
    private let attachButton = UIButton(type: .system)
    private let modelButton = UIButton(type: .system)
    private let emptyState = UIView()
    private var inputHeightConstraint: NSLayoutConstraint!

    init(onSend: @escaping (String) -> Void) {
        self.onSend = onSend
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DHTheme.background
        buildMessages()
        buildEmptyState()
        buildComposer()
        updateEmptyState(animated: false)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardChanged(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func buildMessages() {
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.register(DHPolishedMessageCell.self, forCellReuseIdentifier: DHPolishedMessageCell.reuseIdentifier)
        tableView.separatorStyle = .none
        tableView.keyboardDismissMode = .interactive
        tableView.alwaysBounceVertical = true
        tableView.estimatedRowHeight = 76
        tableView.rowHeight = UITableView.automaticDimension
        tableView.contentInset = UIEdgeInsets(top: 18, left: 0, bottom: 16, right: 0)
        tableView.verticalScrollIndicatorInsets = UIEdgeInsets(top: 0, left: 0, bottom: 8, right: 0)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
    }

    private func buildEmptyState() {
        emptyState.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyState)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        emptyState.addSubview(stack)

        let icon = dhIconView(
            systemName: "sparkles",
            tintColor: DHTheme.accent,
            backgroundColor: DHTheme.accentSoft,
            size: 72,
            symbolSize: 28
        )
        let title = UILabel()
        title.text = "今天想做点什么？"
        title.font = DHTheme.font(.title2, weight: .bold)
        title.textColor = DHTheme.text
        title.textAlignment = .center

        let subtitle = UILabel()
        subtitle.text = "在你的 Harness 工作区里开始一段新的工作"
        subtitle.font = DHTheme.font(.subheadline)
        subtitle.textColor = DHTheme.secondaryText
        subtitle.textAlignment = .center
        subtitle.numberOfLines = 0

        let prompts = UIStackView()
        prompts.axis = .vertical
        prompts.spacing = 8
        prompts.alignment = .fill
        prompts.translatesAutoresizingMaskIntoConstraints = false
        prompts.addArrangedSubview(promptButton("帮我整理一份计划", icon: "list.bullet.clipboard"))
        prompts.addArrangedSubview(promptButton("分析一个文件", icon: "doc.text.magnifyingglass"))
        prompts.addArrangedSubview(promptButton("从一个想法开始", icon: "lightbulb"))
        prompts.widthAnchor.constraint(equalToConstant: 272).isActive = true

        stack.addArrangedSubview(icon)
        stack.addArrangedSubview(title)
        stack.addArrangedSubview(subtitle)
        stack.setCustomSpacing(20, after: subtitle)
        stack.addArrangedSubview(prompts)

        NSLayoutConstraint.activate([
            emptyState.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyState.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emptyState.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            emptyState.bottomAnchor.constraint(equalTo: composer.topAnchor, constant: -12),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: emptyState.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: emptyState.trailingAnchor, constant: -24),
            stack.centerXAnchor.constraint(equalTo: emptyState.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: emptyState.centerYAnchor, constant: -18),
            stack.topAnchor.constraint(greaterThanOrEqualTo: emptyState.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: emptyState.bottomAnchor, constant: -24)
        ])
    }

    private func promptButton(_ title: String, icon: String) -> UIButton {
        var configuration = UIButton.Configuration.tinted()
        configuration.title = title
        configuration.image = UIImage(systemName: icon)
        configuration.imagePadding = 10
        configuration.baseForegroundColor = DHTheme.text
        configuration.background.cornerRadius = DHTheme.cornerSmall
        configuration.background.backgroundColor = DHTheme.surface
        configuration.background.strokeColor = DHTheme.separator.withAlphaComponent(0.35)
        configuration.background.strokeWidth = 1
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
        let button = UIButton(configuration: configuration)
        button.contentHorizontalAlignment = .leading
        button.titleLabel?.font = DHTheme.font(.subheadline, weight: .medium)
        button.addAction(UIAction { [weak self] _ in
            self?.input.text = title
            self?.placeholder.isHidden = true
            self?.updateSendButton()
            self?.input.becomeFirstResponder()
        }, for: .touchUpInside)
        return button
    }

    private func buildComposer() {
        composer.translatesAutoresizingMaskIntoConstraints = false
        composer.dhApplyCard(
            backgroundColor: DHTheme.surface,
            cornerRadius: DHTheme.cornerLarge,
            borderColor: DHTheme.separator.withAlphaComponent(0.3),
            shadow: true
        )
        view.addSubview(composer)

        input.font = DHTheme.font(.body)
        input.textColor = DHTheme.text
        input.tintColor = DHTheme.accent
        input.backgroundColor = .clear
        input.textContainerInset = UIEdgeInsets(top: 13, left: 13, bottom: 10, right: 13)
        input.textContainer.lineFragmentPadding = 0
        input.delegate = self
        input.returnKeyType = .default
        input.translatesAutoresizingMaskIntoConstraints = false
        composer.addSubview(input)

        placeholder.text = "写下你想做的事…"
        placeholder.font = DHTheme.font(.body)
        placeholder.textColor = DHTheme.tertiaryText
        placeholder.isUserInteractionEnabled = false
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        composer.addSubview(placeholder)

        var attachConfiguration = UIButton.Configuration.plain()
        attachConfiguration.image = UIImage(systemName: "paperclip")
        attachConfiguration.baseForegroundColor = DHTheme.secondaryText
        attachConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 7, bottom: 7, trailing: 7)
        attachButton.configuration = attachConfiguration
        attachButton.accessibilityLabel = "添加附件"
        attachButton.addAction(UIAction { [weak self] _ in self?.showUnavailable("附件") }, for: .touchUpInside)
        attachButton.translatesAutoresizingMaskIntoConstraints = false
        composer.addSubview(attachButton)

        var modelConfiguration = UIButton.Configuration.tinted()
        modelConfiguration.title = "默认模型"
        modelConfiguration.image = UIImage(systemName: "slider.horizontal.3")
        modelConfiguration.imagePadding = 5
        modelConfiguration.baseForegroundColor = DHTheme.secondaryText
        modelConfiguration.background.cornerRadius = 9
        modelConfiguration.background.backgroundColor = DHTheme.surfaceMuted
        modelConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 9, bottom: 6, trailing: 9)
        modelButton.configuration = modelConfiguration
        modelButton.titleLabel?.font = DHTheme.font(.caption1, weight: .medium)
        modelButton.addAction(UIAction { [weak self] _ in self?.showUnavailable("模型选择") }, for: .touchUpInside)
        modelButton.translatesAutoresizingMaskIntoConstraints = false
        composer.addSubview(modelButton)

        var sendConfiguration = UIButton.Configuration.filled()
        sendConfiguration.image = UIImage(systemName: "arrow.up")
        sendConfiguration.cornerStyle = .capsule
        sendConfiguration.baseBackgroundColor = DHTheme.accent
        sendConfiguration.baseForegroundColor = .white
        sendConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 9, leading: 9, bottom: 9, trailing: 9)
        sendButton.configuration = sendConfiguration
        sendButton.accessibilityLabel = "发送"
        sendButton.addTarget(self, action: #selector(send), for: .touchUpInside)
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        composer.addSubview(sendButton)

        inputHeightConstraint = input.heightAnchor.constraint(greaterThanOrEqualToConstant: 48)
        NSLayoutConstraint.activate([
            composer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            composer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            composer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            input.leadingAnchor.constraint(equalTo: composer.leadingAnchor, constant: 6),
            input.trailingAnchor.constraint(equalTo: composer.trailingAnchor, constant: -6),
            input.topAnchor.constraint(equalTo: composer.topAnchor, constant: 4),
            inputHeightConstraint,
            input.heightAnchor.constraint(lessThanOrEqualToConstant: 128),
            input.bottomAnchor.constraint(equalTo: modelButton.topAnchor, constant: -2),
            placeholder.leadingAnchor.constraint(equalTo: input.leadingAnchor, constant: 17),
            placeholder.topAnchor.constraint(equalTo: input.topAnchor, constant: 13),
            placeholder.trailingAnchor.constraint(lessThanOrEqualTo: input.trailingAnchor, constant: -12),
            attachButton.leadingAnchor.constraint(equalTo: composer.leadingAnchor, constant: 10),
            attachButton.bottomAnchor.constraint(equalTo: composer.bottomAnchor, constant: -8),
            attachButton.widthAnchor.constraint(equalToConstant: 36),
            attachButton.heightAnchor.constraint(equalToConstant: 36),
            modelButton.leadingAnchor.constraint(equalTo: attachButton.trailingAnchor, constant: 2),
            modelButton.bottomAnchor.constraint(equalTo: composer.bottomAnchor, constant: -9),
            modelButton.heightAnchor.constraint(equalToConstant: 28),
            sendButton.trailingAnchor.constraint(equalTo: composer.trailingAnchor, constant: -10),
            sendButton.bottomAnchor.constraint(equalTo: composer.bottomAnchor, constant: -8),
            sendButton.widthAnchor.constraint(equalToConstant: 38),
            sendButton.heightAnchor.constraint(equalToConstant: 38),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: composer.topAnchor, constant: -8)
        ])
    }

    private func updateEmptyState(animated: Bool) {
        let hidden = !messages.isEmpty
        let changes = { self.emptyState.alpha = hidden ? 0 : 1; self.tableView.alpha = hidden ? 1 : 0 }
        if animated { UIView.animate(withDuration: 0.2, animations: changes) } else { changes() }
    }

    private func updateSendButton() {
        let hasText = !input.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        sendButton.isEnabled = hasText
        sendButton.alpha = hasText ? 1 : 0.45
        placeholder.isHidden = !input.text.isEmpty
    }

    @objc private func send() {
        let text = input.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messages.append(Message(text: text, isUser: true))
        input.text = ""
        inputHeightConstraint.constant = 48
        updateSendButton()
        updateEmptyState(animated: true)
        tableView.reloadData()
        DispatchQueue.main.async { [weak self] in self?.scrollToBottom(animated: true) }
        onSend(text)
    }

    private func scrollToBottom(animated: Bool) {
        guard !messages.isEmpty else { return }
        tableView.scrollToRow(at: IndexPath(row: messages.count - 1, section: 0), at: .bottom, animated: animated)
    }

    private func showUnavailable(_ name: String) {
        let alert = UIAlertController(title: name, message: "这个入口会在接入 Harness 通道后启用。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "知道了", style: .default))
        present(alert, animated: true)
    }

    @objc private func keyboardChanged(_ notification: Notification) {
        guard let info = notification.userInfo,
              let frame = info[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = info[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval else { return }
        let converted = view.convert(frame, from: nil)
        let overlap = max(0, view.bounds.maxY - converted.minY - view.safeAreaInsets.bottom)
        composer.transform = CGAffineTransform(translationX: 0, y: -overlap)
        UIView.animate(withDuration: duration) { self.view.layoutIfNeeded() }
    }

    func textViewDidChange(_ textView: UITextView) {
        inputHeightConstraint.constant = min(max(textView.contentSize.height + 8, 48), 128)
        updateSendButton()
        UIView.performWithoutAnimation { self.view.layoutIfNeeded() }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { messages.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: DHPolishedMessageCell.reuseIdentifier, for: indexPath) as! DHPolishedMessageCell
        let message = messages[indexPath.row]
        cell.configure(text: message.text, isUser: message.isUser)
        return cell
    }
}

final class DHPolishedMessageCell: UITableViewCell {
    static let reuseIdentifier = "DHPolishedMessageCell"
    private let bubble = UIView()
    private let messageLabel = UILabel()
    private let avatar = UIView()
    private let roleLabel = UILabel()
    private var bubbleLeading: NSLayoutConstraint!
    private var bubbleTrailing: NSLayoutConstraint!
    private var avatarLeading: NSLayoutConstraint!

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        contentView.backgroundColor = .clear
        avatar.translatesAutoresizingMaskIntoConstraints = false
        avatar.layer.cornerRadius = 15
        avatar.backgroundColor = DHTheme.accentSoft
        let avatarImage = UIImageView(image: UIImage(systemName: "sparkles"))
        avatarImage.tintColor = DHTheme.accent
        avatarImage.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)
        avatarImage.translatesAutoresizingMaskIntoConstraints = false
        avatar.addSubview(avatarImage)
        NSLayoutConstraint.activate([
            avatar.widthAnchor.constraint(equalToConstant: 30), avatar.heightAnchor.constraint(equalToConstant: 30),
            avatarImage.centerXAnchor.constraint(equalTo: avatar.centerXAnchor), avatarImage.centerYAnchor.constraint(equalTo: avatar.centerYAnchor)
        ])
        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.layer.cornerRadius = DHTheme.cornerMedium
        bubble.layer.masksToBounds = true
        messageLabel.font = DHTheme.font(.body)
        messageLabel.textColor = DHTheme.text
        messageLabel.numberOfLines = 0
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        bubble.addSubview(messageLabel)
        contentView.addSubview(avatar)
        contentView.addSubview(bubble)
        bubbleLeading = bubble.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 62)
        bubbleTrailing = bubble.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18)
        avatarLeading = avatar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20)
        NSLayoutConstraint.activate([
            bubble.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8), bubble.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            bubble.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.82),
            messageLabel.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 15), messageLabel.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -15),
            messageLabel.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 12), messageLabel.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -12),
            avatar.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 4)
        ])
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(text: String, isUser: Bool) {
        messageLabel.text = text
        bubble.backgroundColor = isUser ? DHTheme.userBubble : DHTheme.assistantBubble
        messageLabel.textColor = isUser ? .white : DHTheme.text
        avatar.isHidden = isUser
        bubbleLeading.isActive = !isUser
        bubbleTrailing.isActive = isUser
        avatarLeading.isActive = !isUser
        bubble.layer.borderWidth = isUser ? 0 : 1
        bubble.layer.borderColor = DHTheme.separator.withAlphaComponent(0.3).cgColor
    }
}
[CONTEXT OFFLOADED] Content (~2634 tokens, 11301 bytes) saved to: /var/minis/offloads/tools/file_write_52b7563cf6ea.txt
Use file_read tool to retrieve if needed.[CONTEXT OFFLOADED] Content (~2811 tokens, 12126 bytes) saved to: /var/minis/offloads/tools/file_write_09a0cc8ee787.txt
Use file_read tool to retrieve if needed.