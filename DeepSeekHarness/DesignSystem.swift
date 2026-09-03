import UIKit

/// Shared visual language for the native-first client.
/// The palette is intentionally quiet so plugin surfaces do not compete
/// with the conversation itself, while still looking good in dark mode.
enum DHTheme {
    static let background = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.075, green: 0.078, blue: 0.090, alpha: 1)
            : UIColor(red: 0.965, green: 0.963, blue: 0.975, alpha: 1)
    }

    static let surface = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.115, green: 0.120, blue: 0.140, alpha: 1)
            : UIColor.white
    }

    static let surfaceMuted = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.145, green: 0.150, blue: 0.175, alpha: 1)
            : UIColor(red: 0.935, green: 0.932, blue: 0.950, alpha: 1)
    }

    static let surfaceStrong = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.170, green: 0.175, blue: 0.205, alpha: 1)
            : UIColor(red: 0.905, green: 0.900, blue: 0.925, alpha: 1)
    }

    static let accent = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.47, green: 0.58, blue: 1.0, alpha: 1)
            : UIColor(red: 0.255, green: 0.365, blue: 0.88, alpha: 1)
    }

    static let accentSoft = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.23, green: 0.28, blue: 0.48, alpha: 1)
            : UIColor(red: 0.89, green: 0.91, blue: 1.0, alpha: 1)
    }

    static let assistantBubble = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.135, green: 0.140, blue: 0.165, alpha: 1)
            : UIColor.white
    }

    static let userBubble = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.255, green: 0.315, blue: 0.66, alpha: 1)
            : UIColor(red: 0.255, green: 0.365, blue: 0.88, alpha: 1)
    }

    static let text = UIColor.label
    static let secondaryText = UIColor.secondaryLabel
    static let tertiaryText = UIColor.tertiaryLabel
    static let separator = UIColor.separator
    static let success = UIColor.systemGreen
    static let warning = UIColor.systemOrange
    static let danger = UIColor.systemRed

    static let cornerLarge: CGFloat = 22
    static let cornerMedium: CGFloat = 16
    static let cornerSmall: CGFloat = 12

    static func font(_ style: UIFont.TextStyle, weight: UIFont.Weight = .regular) -> UIFont {
        UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: style).pointSize, weight: weight)
    }
}

extension UIView {
    func dhApplyCard(
        backgroundColor: UIColor = DHTheme.surface,
        cornerRadius: CGFloat = DHTheme.cornerMedium,
        borderColor: UIColor? = nil,
        shadow: Bool = false
    ) {
        self.backgroundColor = backgroundColor
        layer.cornerRadius = cornerRadius
        layer.masksToBounds = !shadow
        if let borderColor {
            layer.borderColor = borderColor.cgColor
            layer.borderWidth = 1
        }
        if shadow {
            layer.masksToBounds = false
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = traitCollection.userInterfaceStyle == .dark ? 0.24 : 0.08
            layer.shadowRadius = 16
            layer.shadowOffset = CGSize(width: 0, height: 6)
        }
    }
}

final class DHBadgeLabel: UILabel {
    init(text: String, color: UIColor, filled: Bool = true) {
        super.init(frame: .zero)
        self.text = text
        self.textColor = filled ? color : DHTheme.secondaryText
        self.font = DHTheme.font(.caption1, weight: .semibold)
        self.textAlignment = .center
        self.layer.cornerRadius = 8
        self.layer.masksToBounds = true
        self.backgroundColor = filled ? color.withAlphaComponent(0.13) : DHTheme.surfaceMuted
        self.setContentHuggingPriority(.required, for: .horizontal)
        self.setContentCompressionResistancePriority(.required, for: .horizontal)
        self.translatesAutoresizingMaskIntoConstraints = false
        self.heightAnchor.constraint(greaterThanOrEqualToConstant: 26).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

func dhIconView(
    systemName: String,
    tintColor: UIColor = DHTheme.accent,
    backgroundColor: UIColor = DHTheme.accentSoft,
    size: CGFloat = 42,
    symbolSize: CGFloat = 18
) -> UIView {
    let container = UIView()
    container.backgroundColor = backgroundColor
    container.layer.cornerRadius = size / 2
    container.translatesAutoresizingMaskIntoConstraints = false
    container.widthAnchor.constraint(equalToConstant: size).isActive = true
    container.heightAnchor.constraint(equalToConstant: size).isActive = true

    let imageView = UIImageView(image: UIImage(systemName: systemName))
    imageView.tintColor = tintColor
    imageView.contentMode = .scaleAspectFit
    imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: symbolSize, weight: .semibold)
    imageView.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(imageView)
    NSLayoutConstraint.activate([
        imageView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
        imageView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        imageView.widthAnchor.constraint(equalToConstant: symbolSize + 4),
        imageView.heightAnchor.constraint(equalToConstant: symbolSize + 4)
    ])
    return container
}

func dhButton(
    title: String,
    systemName: String? = nil,
    filled: Bool = false,
    action: @escaping () -> Void
) -> UIButton {
    var configuration = filled ? UIButton.Configuration.filled() : UIButton.Configuration.plain()
    configuration.baseBackgroundColor = filled ? DHTheme.accent : nil
    configuration.baseForegroundColor = filled ? .white : DHTheme.text
    configuration.title = title
    configuration.image = systemName.flatMap { UIImage(systemName: $0) }
    configuration.imagePadding = 9
    configuration.cornerStyle = .medium
    configuration.contentInsets = NSDirectionalEdgeInsets(top: 11, leading: 14, bottom: 11, trailing: 14)
    let button = UIButton(configuration: configuration)
    button.titleLabel?.font = DHTheme.font(.body, weight: .semibold)
    button.addAction(UIAction { _ in action() }, for: .touchUpInside)
    return button
}

func dhSeparator() -> UIView {
    let separator = UIView()
    separator.backgroundColor = DHTheme.separator.withAlphaComponent(0.65)
    separator.translatesAutoresizingMaskIntoConstraints = false
    separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
    return separator
}
