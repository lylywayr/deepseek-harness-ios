import UIKit

/// Connection screen for the native client. The active application never loads a web surface.
final class ConnectionRootViewController: UIViewController {
    private let appState = AppState()
    private var currentChild: UIViewController?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DHTheme.background
        render()
    }

    private func render() {
        removeCurrentChild()
        let controller = SetupViewController(initialValue: appState.endpointString)
        controller.onSave = { [weak self] value in
            guard let self, self.appState.saveEndpoint(value) else { return }
            self.render()
        }
        addChildController(controller)
        navigationItem.title = "DeepSeek Harness"
    }

    private func addChildController(_ controller: UIViewController) {
        currentChild = controller
        addChild(controller)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controller.view)
        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: view.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        controller.didMove(toParent: self)
    }

    private func removeCurrentChild() {
        guard let child = currentChild else { return }
        child.willMove(toParent: nil)
        child.view.removeFromSuperview()
        child.removeFromParent()
        currentChild = nil
    }
}

final class SetupViewController: UIViewController {
    var onSave: ((String) -> Void)?
    var onClearSession: (() -> Void)?
    private let initialValue: String
    private let endpointField = UITextField()
    private let errorLabel = UILabel()
    private let clearButton = UIButton(type: .system)

    init(initialValue: String) {
        self.initialValue = initialValue
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DHTheme.background
        navigationItem.title = "连接服务"
        if presentingViewController != nil {
            navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(close))
        }
        buildView()
    }

    private func buildView() {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        let content = UIStackView()
        content.axis = .vertical
        content.spacing = 14
        content.alignment = .fill
        content.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(content)

        let hero = UIView()
        hero.translatesAutoresizingMaskIntoConstraints = false
        let icon = dhIconView(systemName: "link", size: 58, symbolSize: 23)
        let title = UILabel()
        title.text = "连接你的 Harness"
        title.font = DHTheme.font(.title1, weight: .bold)
        title.textAlignment = .center
        let subtitle = UILabel()
        subtitle.text = "把你的工作区带到 iPhone 上"
        subtitle.font = DHTheme.font(.subheadline)
        subtitle.textColor = DHTheme.secondaryText
        subtitle.textAlignment = .center
        let labels = UIStackView(arrangedSubviews: [title, subtitle])
        labels.axis = .vertical
        labels.spacing = 5
        labels.translatesAutoresizingMaskIntoConstraints = false
        hero.addSubview(icon)
        hero.addSubview(labels)
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: hero.centerXAnchor),
            icon.topAnchor.constraint(equalTo: hero.topAnchor),
            labels.leadingAnchor.constraint(equalTo: hero.leadingAnchor),
            labels.trailingAnchor.constraint(equalTo: hero.trailingAnchor),
            labels.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 14),
            labels.bottomAnchor.constraint(equalTo: hero.bottomAnchor)
        ])

        let card = UIView()
        card.dhApplyCard(backgroundColor: DHTheme.surface, cornerRadius: DHTheme.cornerMedium, shadow: true)
        let cardContent = UIStackView()
        cardContent.axis = .vertical
        cardContent.spacing = 10
        cardContent.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(cardContent)
        let addressTitle = UILabel()
        addressTitle.text = "服务地址"
        addressTitle.font = DHTheme.font(.subheadline, weight: .semibold)
        endpointField.placeholder = "https://harness.example.com"
        endpointField.text = initialValue
        endpointField.keyboardType = .URL
        endpointField.autocapitalizationType = .none
        endpointField.autocorrectionType = .no
        endpointField.clearButtonMode = .whileEditing
        endpointField.returnKeyType = .done
        endpointField.delegate = self
        endpointField.font = DHTheme.font(.body)
        endpointField.backgroundColor = DHTheme.surfaceMuted
        endpointField.layer.cornerRadius = DHTheme.cornerSmall
        endpointField.setLeftPadding(13)
        endpointField.heightAnchor.constraint(equalToConstant: 48).isActive = true
        var saveConfig = UIButton.Configuration.filled()
        saveConfig.title = "保存并连接"
        saveConfig.cornerStyle = .medium
        saveConfig.baseBackgroundColor = DHTheme.accent
        saveConfig.baseForegroundColor = .white
        saveConfig.contentInsets = NSDirectionalEdgeInsets(top: 13, leading: 16, bottom: 13, trailing: 16)
        let saveButton = UIButton(configuration: saveConfig)
        saveButton.titleLabel?.font = DHTheme.font(.body, weight: .semibold)
        saveButton.addTarget(self, action: #selector(save), for: .touchUpInside)
        errorLabel.font = DHTheme.font(.footnote)
        errorLabel.textColor = DHTheme.danger
        errorLabel.numberOfLines = 0
        errorLabel.isHidden = true
        [addressTitle, endpointField, saveButton, errorLabel].forEach(cardContent.addArrangedSubview)
        NSLayoutConstraint.activate([
            cardContent.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            cardContent.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            cardContent.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            cardContent.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18)
        ])

        let note = UILabel()
        note.text = "支持 HTTP 和 HTTPS。公网访问请使用 HTTPS 或 VPN。地址中不要填写密码或 Token。"
        note.font = DHTheme.font(.footnote)
        note.textColor = DHTheme.secondaryText
        note.numberOfLines = 0
        note.textAlignment = .center
        [hero, card, note].forEach(content.addArrangedSubview)
        if onClearSession != nil {
            clearButton.setTitle("清除本机连接凭据", for: .normal)
            clearButton.setTitleColor(DHTheme.danger, for: .normal)
            clearButton.addTarget(self, action: #selector(clearSession), for: .touchUpInside)
            content.addArrangedSubview(clearButton)
        }
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 24),
            content.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -24),
            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 42),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -32),
            content.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -48)
        ])
    }

    @objc private func save() {
        view.endEditing(true)
        let value = endpointField.text ?? ""
        guard AppState.makeURL(from: value) != nil else {
            errorLabel.text = "请输入完整的 HTTP 或 HTTPS 地址。"
            errorLabel.isHidden = false
            return
        }
        errorLabel.isHidden = true
        onSave?(value)
    }

    @objc private func clearSession() { onClearSession?() }
    @objc private func close() { dismiss(animated: true) }
}

extension SetupViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool { save(); return true }
}

extension UITextField {
    func setLeftPadding(_ value: CGFloat) {
        let padding = UIView(frame: CGRect(x: 0, y: 0, width: value, height: 1))
        leftView = padding
        leftViewMode = .always
    }
}
