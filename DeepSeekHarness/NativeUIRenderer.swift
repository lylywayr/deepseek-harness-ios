import UIKit

struct NativeUIRenderResult {
    let views: [UIView]
    let diagnostics: [String]
}

/// Converts the intermediate Native UI tree into UIKit controls.
/// Unsupported nodes are isolated as explicit fallback cards rather than
/// blanking the entire plugin surface.
final class NativeUIRenderer {
    private let surfaceID: String
    private let actionHandler: NativeUIActionHandler?
    private let fallbackHandler: (String?) -> Void
    private var diagnostics: [String] = []

    init(
        surfaceID: String,
        transport: NativeUITransport?,
        actionHandler: NativeUIActionHandler? = nil,
        fallbackHandler: @escaping (String?) -> Void = { _ in }
    ) {
        self.surfaceID = surfaceID
        self.actionHandler = actionHandler
        self.fallbackHandler = fallbackHandler
        _ = transport
    }

    func render(_ node: NativeUINode) -> NativeUIRenderResult {
        NativeUIRenderResult(views: [renderNode(node)], diagnostics: diagnostics)
    }

    private func renderNode(_ node: NativeUINode) -> UIView {
        switch node.type.lowercased() {
        case "text", "label", "markdown", "heading":
            return makeLabel(node.text ?? node.title ?? node.subtitle ?? "")
        case "badge", "pill":
            let view = makeLabel(node.text ?? node.title ?? "")
            view.textAlignment = .center
            view.textColor = .systemBlue
            view.backgroundColor = .secondarySystemBackground
            view.layer.cornerRadius = 8
            view.layer.masksToBounds = true
            view.setContentHuggingPriority(.required, for: .horizontal)
            return view
        case "button", "action", "link":
            return makeButton(node)
        case "textfield", "input", "textarea":
            return makeTextField(node)
        case "toggle", "switch":
            return makeToggle(node)
        case "stack", "section", "group", "form", "vstack", "hstack", "list", "scroll", "page":
            return makeContainer(node)
        case "divider", "separator":
            let line = UIView()
            line.backgroundColor = .separator
            line.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
            return line
        case "spacer":
            let spacer = UIView()
            spacer.heightAnchor.constraint(equalToConstant: 8).isActive = true
            return spacer
        case "legacy", "web":
            return makeFallback(node, reason: "此区域使用兼容模式。")
        default:
            return makeFallback(node, reason: "暂不支持组件类型：\(node.type)。")
        }
    }

    private func makeContainer(_ node: NativeUINode) -> UIView {
        let stack = UIStackView()
        let horizontal = node.axis?.lowercased() == "horizontal" || node.type.lowercased() == "hstack"
        stack.axis = horizontal ? .horizontal : .vertical
        stack.spacing = 12
        stack.alignment = horizontal ? .center : .fill
        stack.translatesAutoresizingMaskIntoConstraints = false

        if let title = node.title, !title.isEmpty {
            let heading = makeLabel(title)
            heading.font = .preferredFont(forTextStyle: .headline)
            stack.addArrangedSubview(heading)
        }
        if let subtitle = node.subtitle, !subtitle.isEmpty {
            let detail = makeLabel(subtitle)
            detail.font = .preferredFont(forTextStyle: .footnote)
            detail.textColor = .secondaryLabel
            stack.addArrangedSubview(detail)
        }
        node.resolvedChildren.forEach { stack.addArrangedSubview(renderNode($0)) }

        let type = node.type.lowercased()
        guard type == "section" || type == "page" else { return stack }
        let wrapper = UIView()
        wrapper.backgroundColor = .secondarySystemBackground
        wrapper.layer.cornerRadius = 12
        wrapper.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -14)
        ])
        return wrapper
    }

    private func makeLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .body)
        label.numberOfLines = 0
        return label
    }

    private func makeButton(_ node: NativeUINode) -> UIButton {
        var configuration = UIButton.Configuration.tinted()
        configuration.title = node.displayTitle
        configuration.cornerStyle = .medium
        if let icon = node.icon, let image = UIImage(systemName: icon) {
            configuration.image = image
            configuration.imagePadding = 8
        }
        let button = UIButton(configuration: configuration)
        button.isEnabled = node.isEnabled ?? true
        button.accessibilityLabel = node.accessibilityLabel ?? node.displayTitle
        if let action = node.action {
            let target = NativeUIActionTarget(
                surfaceID: surfaceID,
                node: node,
                action: action,
                handler: actionHandler
            )
            button.addTarget(target, action: #selector(NativeUIActionTarget.invoke), for: .touchUpInside)
            objc_setAssociatedObject(button, &NativeUIActionTarget.associationKey, target, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        return button
    }

    private func makeTextField(_ node: NativeUINode) -> UITextField {
        let field = UITextField()
        field.borderStyle = .roundedRect
        field.placeholder = node.placeholder ?? node.title
        field.text = node.value
        field.accessibilityLabel = node.accessibilityLabel ?? node.title
        if let action = node.action {
            let target = NativeUITextFieldTarget(
                surfaceID: surfaceID,
                node: node,
                action: action,
                handler: actionHandler
            )
            field.addTarget(target, action: #selector(NativeUITextFieldTarget.changed(_:)), for: .editingChanged)
            objc_setAssociatedObject(field, &NativeUITextFieldTarget.associationKey, target, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        return field
    }

    private func makeToggle(_ node: NativeUINode) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 12
        let title = makeLabel(node.title ?? node.text ?? node.displayTitle)
        let control = UISwitch()
        control.isOn = node.value?.lowercased() == "true"
        row.addArrangedSubview(title)
        row.addArrangedSubview(UIView())
        row.addArrangedSubview(control)
        if let action = node.action {
            let target = NativeUISwitchTarget(
                surfaceID: surfaceID,
                node: node,
                action: action,
                handler: actionHandler
            )
            control.addTarget(target, action: #selector(NativeUISwitchTarget.changed(_:)), for: .valueChanged)
            objc_setAssociatedObject(control, &NativeUISwitchTarget.associationKey, target, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        return row
    }

    private func makeFallback(_ node: NativeUINode, reason: String) -> UIView {
        diagnostics.append("\(node.displayTitle)：\(reason)")
        let wrapper = UIView()
        wrapper.backgroundColor = .tertiarySystemBackground
        wrapper.layer.cornerRadius = 10
        wrapper.layer.borderWidth = 1
        wrapper.layer.borderColor = UIColor.systemOrange.cgColor
        let label = makeLabel("兼容模式\n\(node.displayTitle)\n\(reason)\n点击打开原始插件页面")
        label.textColor = .secondaryLabel
        label.isUserInteractionEnabled = true
        wrapper.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -12)
        ])
        let tap = UITapGestureRecognizer(target: self, action: #selector(openFallback(_:)))
        wrapper.addGestureRecognizer(tap)
        objc_setAssociatedObject(wrapper, &NativeUIRenderer.fallbackURLKey, node.url, .OBJC_ASSOCIATION_COPY_NONATOMIC)
        return wrapper
    }

    @objc private func openFallback(_ gesture: UITapGestureRecognizer) {
        guard let view = gesture.view,
              let url = objc_getAssociatedObject(view, &NativeUIRenderer.fallbackURLKey) as? String else { return }
        fallbackHandler(url)
    }

    static var fallbackURLKey = "NativeUIFallbackURL"
}

private final class NativeUIActionTarget: NSObject {
    static var associationKey = "NativeUIActionTarget"
    private let surfaceID: String
    private let node: NativeUINode
    private let action: String
    private let handler: NativeUIActionHandler?

    init(surfaceID: String, node: NativeUINode, action: String, handler: NativeUIActionHandler?) {
        self.surfaceID = surfaceID
        self.node = node
        self.action = action
        self.handler = handler
    }

    @objc func invoke() {
        handler?(surfaceID, node.id ?? node.displayTitle, action, [:]) { _ in }
    }
}

private final class NativeUITextFieldTarget: NSObject {
    static var associationKey = "NativeUITextFieldTarget"
    private let surfaceID: String
    private let node: NativeUINode
    private let action: String
    private let handler: NativeUIActionHandler?

    init(surfaceID: String, node: NativeUINode, action: String, handler: NativeUIActionHandler?) {
        self.surfaceID = surfaceID
        self.node = node
        self.action = action
        self.handler = handler
    }

    @objc func changed(_ sender: UITextField) {
        handler?(surfaceID, node.id ?? node.displayTitle, action, ["value": sender.text ?? ""]) { _ in }
    }
}

private final class NativeUISwitchTarget: NSObject {
    static var associationKey = "NativeUISwitchTarget"
    private let surfaceID: String
    private let node: NativeUINode
    private let action: String
    private let handler: NativeUIActionHandler?

    init(surfaceID: String, node: NativeUINode, action: String, handler: NativeUIActionHandler?) {
        self.surfaceID = surfaceID
        self.node = node
        self.action = action
        self.handler = handler
    }

    @objc func changed(_ sender: UISwitch) {
        handler?(surfaceID, node.id ?? node.displayTitle, action, ["value": sender.isOn ? "true" : "false"]) { _ in }
    }
}
