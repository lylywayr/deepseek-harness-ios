import UIKit

#if DEBUG
/// Deterministic native-only launch fixture used by CI screenshots.
/// It is reachable only through -UITestFixture and never through the normal app path.
final class NativeFixtureViewController: UIViewController {
    private let screen: String
    private let fixtureFrame = UIView()

    init(screen: String) {
        self.screen = screen
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.08)
        fixtureFrame.backgroundColor = DHTheme.background
        fixtureFrame.layer.cornerRadius = 2
        fixtureFrame.clipsToBounds = true
        fixtureFrame.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(fixtureFrame)
        NSLayoutConstraint.activate([
            fixtureFrame.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            fixtureFrame.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            fixtureFrame.widthAnchor.constraint(equalToConstant: 390),
            fixtureFrame.heightAnchor.constraint(equalToConstant: 844)
        ])
        render()
    }

    private func render() {
        switch screen {
        case "connection": renderConnection()
        case "conversation": renderConversation()
        case "sidebar": renderSidebar()
        case "settings": renderSettings()
        case "directory": renderDirectory()
        case "approval": renderApproval()
        case "question": renderQuestion()
        case "trajectory": renderTrajectory()
        default: renderConversation()
        }
    }

    private func install(_ stack: UIStackView) {
        fixtureFrame.subviews.forEach { $0.removeFromSuperview() }
        let scroll = UIScrollView()
        scroll.alwaysBounceVertical = true
        scroll.showsVerticalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        fixtureFrame.addSubview(scroll)
        stack.axis = .vertical
        stack.spacing = 14
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: fixtureFrame.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: fixtureFrame.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: fixtureFrame.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: fixtureFrame.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -28),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -36)
        ])
    }

    private func heading(_ title: String, subtitle: String) -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 4
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = DHTheme.font(.title2, weight: .bold)
        titleLabel.textColor = DHTheme.text
        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitle
        subtitleLabel.font = DHTheme.font(.subheadline)
        subtitleLabel.textColor = DHTheme.secondaryText
        subtitleLabel.numberOfLines = 0
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(subtitleLabel)
        return stack
    }

    private func card(_ title: String, body: String? = nil, color: UIColor = DHTheme.surface) -> UIView {
        let container = UIView()
        container.dhApplyCard(backgroundColor: color, cornerRadius: 16, borderColor: DHTheme.separator.withAlphaComponent(0.28))
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = DHTheme.font(.headline, weight: .semibold)
        titleLabel.textColor = DHTheme.text
        titleLabel.numberOfLines = 0
        stack.addArrangedSubview(titleLabel)
        if let body {
            let bodyLabel = UILabel()
            bodyLabel.text = body
            bodyLabel.font = DHTheme.font(.body)
            bodyLabel.textColor = DHTheme.secondaryText
            bodyLabel.numberOfLines = 0
            stack.addArrangedSubview(bodyLabel)
        }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 15),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -15)
        ])
        return container
    }

    private func row(_ title: String, value: String, icon: String = "chevron.right") -> UIView {
        let button = UIButton(type: .system)
        button.backgroundColor = DHTheme.surface
        button.layer.cornerRadius = 12
        button.contentHorizontalAlignment = .left
        button.contentEdgeInsets = UIEdgeInsets(top: 13, left: 14, bottom: 13, right: 14)
        button.setImage(UIImage(systemName: icon), for: .normal)
        button.tintColor = DHTheme.accent
        button.setTitle("  \(title)", for: .normal)
        button.setTitleColor(DHTheme.text, for: .normal)
        button.titleLabel?.font = DHTheme.font(.body, weight: .medium)
        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = DHTheme.font(.caption1, weight: .semibold)
        valueLabel.textColor = DHTheme.accent
        valueLabel.textAlignment = .right
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(valueLabel)
        NSLayoutConstraint.activate([
            valueLabel.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -14),
            valueLabel.centerYAnchor.constraint(equalTo: button.centerYAnchor)
        ])
        return button
    }

    private func actionButton(_ title: String, filled: Bool = false) -> UIButton {
        var configuration = filled ? UIButton.Configuration.filled() : UIButton.Configuration.bordered()
        configuration.title = title
        configuration.cornerStyle = .medium
        configuration.baseBackgroundColor = filled ? DHTheme.accent : DHTheme.surfaceMuted
        configuration.baseForegroundColor = filled ? .white : DHTheme.text
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 11, leading: 14, bottom: 11, trailing: 14)
        return UIButton(configuration: configuration)
    }

    private func renderConnection() {
        let stack = UIStackView()
        install(stack)
        stack.addArrangedSubview(heading("连接 Harness", subtitle: "原生连接状态 · 390×844 fixture"))

        let connection = UIView()
        connection.dhApplyCard(backgroundColor: DHTheme.surface, cornerRadius: 16, borderColor: DHTheme.separator.withAlphaComponent(0.28))
        let content = UIStackView()
        content.axis = .vertical
        content.spacing = 10
        content.translatesAutoresizingMaskIntoConstraints = false
        connection.addSubview(content)

        let title = UILabel()
        title.text = "Harness 服务"
        title.font = DHTheme.font(.headline, weight: .semibold)
        title.textColor = DHTheme.text
        let detail = UILabel()
        detail.text = "服务地址和访问令牌仅保存在本机。"
        detail.font = DHTheme.font(.subheadline)
        detail.textColor = DHTheme.secondaryText
        detail.numberOfLines = 0
        let address = UITextField()
        address.text = "https://harness.example.com"
        address.font = DHTheme.font(.body)
        address.textColor = DHTheme.text
        address.backgroundColor = DHTheme.surfaceMuted
        address.layer.cornerRadius = 10
        address.setLeftPadding(12)
        address.heightAnchor.constraint(equalToConstant: 44).isActive = true
        let token = UITextField()
        token.placeholder = "访问令牌（可选）"
        token.isSecureTextEntry = true
        token.backgroundColor = DHTheme.surfaceMuted
        token.layer.cornerRadius = 10
        token.setLeftPadding(12)
        token.heightAnchor.constraint(equalToConstant: 44).isActive = true
        let error = UILabel()
        error.text = "● 连接失败"
        error.textColor = DHTheme.danger
        error.font = DHTheme.font(.subheadline, weight: .medium)
        error.numberOfLines = 1
        let errorDetail = UILabel()
        errorDetail.text = "请检查服务地址或访问令牌。"
        errorDetail.textColor = DHTheme.secondaryText
        errorDetail.font = DHTheme.font(.subheadline)
        errorDetail.numberOfLines = 0
        content.addArrangedSubview(title)
        content.addArrangedSubview(detail)
        content.addArrangedSubview(address)
        content.addArrangedSubview(token)
        content.addArrangedSubview(error)
        content.addArrangedSubview(errorDetail)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: connection.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: connection.trailingAnchor, constant: -16),
            content.topAnchor.constraint(equalTo: connection.topAnchor, constant: 15),
            content.bottomAnchor.constraint(equalTo: connection.bottomAnchor, constant: -15)
        ])
        stack.addArrangedSubview(connection)
        stack.addArrangedSubview(actionButton("重试连接", filled: true))
        stack.addArrangedSubview(actionButton("编辑连接"))
    }

    private func renderConversation() {
        let stack = UIStackView(); install(stack)
        stack.addArrangedSubview(heading("新会话", subtitle: "在线 · 标准模式"))
        stack.addArrangedSubview(card("你", body: "请帮我检查这个项目的构建状态。", color: DHTheme.accentSoft))
        let assistant = card("Harness", body: "我会先检查工作区，然后汇总可验证的结果。\n\n标题、列表和引用都在原生消息单元中显示。\n行内 `code` 与 [文档链接](https://harness.example.com/docs) 可复制或点击。")
        stack.addArrangedSubview(assistant)
        let code = card("代码块", body: "let result = await harness.check()\nprint(result.status)")
        if let body = code.subviews.compactMap({ $0 as? UIStackView }).first?.arrangedSubviews.last as? UILabel { body.font = .monospacedSystemFont(ofSize: 13, weight: .regular); body.textColor = DHTheme.text }
        stack.addArrangedSubview(code)
        stack.addArrangedSubview(card("工具调用 · workspace/list", body: "结果：3 个文件\n点击消息可查看调用参数、结果和错误详情。", color: DHTheme.surfaceMuted))
        let controls = UIStackView(); controls.axis = .horizontal; controls.spacing = 8
        controls.addArrangedSubview(row("模型", value: "DeepSeek V4")); controls.addArrangedSubview(row("权限", value: "只读"))
        stack.addArrangedSubview(controls)
        stack.addArrangedSubview(card("图片附件", body: "＋ image-1.png     × image-2.jpg", color: DHTheme.surfaceMuted))
        let composer = card("描述你想要构建的内容…", body: "＋ 添加图片                         ↑ 发送")
        stack.addArrangedSubview(composer)
    }

    private func renderSidebar() {
        fixtureFrame.subviews.forEach { $0.removeFromSuperview() }
        let rail = UIView(); rail.backgroundColor = DHTheme.surface; rail.translatesAutoresizingMaskIntoConstraints = false; fixtureFrame.addSubview(rail)
        let panel = UIView(); panel.backgroundColor = DHTheme.background; panel.translatesAutoresizingMaskIntoConstraints = false; fixtureFrame.addSubview(panel)
        NSLayoutConstraint.activate([rail.leadingAnchor.constraint(equalTo: fixtureFrame.leadingAnchor), rail.topAnchor.constraint(equalTo: fixtureFrame.topAnchor), rail.bottomAnchor.constraint(equalTo: fixtureFrame.bottomAnchor), rail.widthAnchor.constraint(equalToConstant: 56), panel.leadingAnchor.constraint(equalTo: rail.trailingAnchor), panel.trailingAnchor.constraint(equalTo: fixtureFrame.trailingAnchor), panel.topAnchor.constraint(equalTo: fixtureFrame.topAnchor), panel.bottomAnchor.constraint(equalTo: fixtureFrame.bottomAnchor)])
        let railStack = UIStackView(); railStack.axis = .vertical; railStack.spacing = 18; railStack.alignment = .center; railStack.translatesAutoresizingMaskIntoConstraints = false; rail.addSubview(railStack)
        NSLayoutConstraint.activate([railStack.topAnchor.constraint(equalTo: rail.topAnchor, constant: 32), railStack.leadingAnchor.constraint(equalTo: rail.leadingAnchor), railStack.trailingAnchor.constraint(equalTo: rail.trailingAnchor)])
        ["fish", "plus", "magnifyingglass", "folder", "gearshape"].forEach { name in
            let button = UIButton(type: .system); button.setImage(UIImage(systemName: name == "fish" ? "sparkles" : name), for: .normal); button.tintColor = name == "magnifyingglass" ? DHTheme.accent : DHTheme.secondaryText; button.widthAnchor.constraint(equalToConstant: 40).isActive = true; button.heightAnchor.constraint(equalToConstant: 40).isActive = true; railStack.addArrangedSubview(button)
        }
        let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 12; stack.translatesAutoresizingMaskIntoConstraints = false; panel.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 16), stack.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16), stack.topAnchor.constraint(equalTo: panel.topAnchor, constant: 30), stack.bottomAnchor.constraint(lessThanOrEqualTo: panel.bottomAnchor, constant: -20)])
        stack.addArrangedSubview(heading("Harness", subtitle: "会话与工作区"))
        let search = UISearchBar(); search.placeholder = "搜索会话…"; search.searchBarStyle = .minimal; stack.addArrangedSubview(search)
        stack.addArrangedSubview(card("没有匹配的会话", body: "尝试其他关键词，或清空搜索。", color: DHTheme.surfaceMuted))
        if screen == "sidebar" {
            stack.addArrangedSubview(card("视图选项 · 单列表", body: "Build Status  ·  Protocol Review\n最近更新时间排序\n归档会话：已显示", color: DHTheme.surfaceMuted))
        }
        stack.addArrangedSubview(row("插件", value: "原生入口"))
    }

    private func renderSettings() {
        let stack = UIStackView(); install(stack)
        stack.addArrangedSubview(heading("设置", subtitle: "本机显示偏好 · 可编辑"))
        stack.addArrangedSubview(card("连接", body: "https://harness.example.com\n令牌已保存"))
        stack.addArrangedSubview(row("外观", value: "跟随系统", icon: "paintbrush"))
        stack.addArrangedSubview(row("会话字号", value: "16 pt", icon: "textformat.size"))
        stack.addArrangedSubview(row("对话显示", value: "Normal", icon: "text.alignleft"))
        stack.addArrangedSubview(row("繁忙时 Enter", value: "插话发送", icon: "return"))
        stack.addArrangedSubview(row("新会话默认权限", value: "工作区可写", icon: "shield"))
        stack.addArrangedSubview(card("语言", body: "当前版本跟随 App 语言；未提供未实现的切换项。", color: DHTheme.surfaceMuted))
    }

    private func renderDirectory() {
        let stack = UIStackView(); install(stack)
        stack.addArrangedSubview(heading("选择工作区目录", subtitle: "目录选择器 · 原生 listing"))
        stack.addArrangedSubview(card("⌂ Home  /  Projects", body: "返回上级        根目录        Home", color: DHTheme.surfaceMuted))
        stack.addArrangedSubview(row("deepseek-harness-ios", value: "›", icon: "folder"))
        stack.addArrangedSubview(row("native-renderer", value: "✓", icon: "folder"))
        stack.addArrangedSubview(row(".config", value: "隐藏", icon: "folder"))
        stack.addArrangedSubview(card("新建文件夹", body: "文件夹名称                         ＋ 创建"))
        stack.addArrangedSubview(actionButton("打开已选择目录", filled: true))
    }

    private func renderApproval() {
        let stack = UIStackView(); install(stack)
        stack.addArrangedSubview(heading("工具审批", subtitle: "动作发生前需要你的确认"))
        stack.addArrangedSubview(card("允许这次工具调用？", body: "工具：workspace/write\n调用：write_file\n原因：需要更新项目文档\n详情：docs/native-completion-report.md", color: DHTheme.surface))
        stack.addArrangedSubview(actionButton("拒绝", filled: false))
        stack.addArrangedSubview(actionButton("仅允许一次", filled: true))
        stack.addArrangedSubview(card("安全提示", body: "完全权限可能执行高风险命令。每次审批都会显示调用详情。", color: DHTheme.surfaceMuted))
    }

    private func renderQuestion() {
        let stack = UIStackView(); install(stack)
        stack.addArrangedSubview(heading("需要你的回答", subtitle: "用户问题 · 单选、多选和自由输入"))
        stack.addArrangedSubview(card("部署目标", body: "请选择本次构建要使用的目标环境。"))
        ["模拟器 / CI", "签名真机", "稍后决定"].forEach { option in
            let button = actionButton("○  \(option)"); button.contentHorizontalAlignment = .left; stack.addArrangedSubview(button)
        }
        let input = UITextField(); input.placeholder = "或输入自定义回答"; input.backgroundColor = DHTheme.surface; input.layer.cornerRadius = 10; input.setLeftPadding(12); input.heightAnchor.constraint(equalToConstant: 46).isActive = true; stack.addArrangedSubview(input)
        stack.addArrangedSubview(actionButton("提交回答", filled: true))
    }

    private func renderTrajectory() {
        let stack = UIStackView(); install(stack)
        stack.addArrangedSubview(heading("Native Renderer", subtitle: "对话   ·   轨迹"))
        stack.addArrangedSubview(card("轨迹时间线", body: "输入  ●━━━━  模型  ●━━━━  工具  ●━━━━  结果", color: DHTheme.surfaceMuted))
        stack.addArrangedSubview(row("输入", value: "已完成", icon: "arrow.down.left"))
        stack.addArrangedSubview(row("模型推理", value: "1.8 s", icon: "sparkles"))
        stack.addArrangedSubview(row("工具调用", value: "成功", icon: "wrench.and.screwdriver"))
        stack.addArrangedSubview(card("Session 日志", body: "[system] connected\n[tool] workspace/list → ok\n[assistant] 完成检查。"))
    }
}
#endif
