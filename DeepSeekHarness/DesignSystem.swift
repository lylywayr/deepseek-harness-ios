import UIKit

/// Harness Pocket Workspace visual language.  All colors remain dynamic so the
/// native client stays legible in light, dark, high-contrast, and reduced
/// transparency configurations.
enum DHTheme {
    static let background = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.045, green: 0.055, blue: 0.095, alpha: 1)
        }
        return UIColor(red: 0.969, green: 0.974, blue: 0.988, alpha: 1)
    }

    static let surface = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.085, green: 0.105, blue: 0.170, alpha: 1)
            : UIColor.white
    }

    static let surfaceMuted = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.115, green: 0.140, blue: 0.220, alpha: 1)
            : UIColor(red: 0.935, green: 0.949, blue: 0.980, alpha: 1)
    }

    static let surfaceStrong = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.155, green: 0.185, blue: 0.285, alpha: 1)
            : UIColor(red: 0.885, green: 0.910, blue: 0.970, alpha: 1)
    }

    static let processSurface = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.075, green: 0.095, blue: 0.150, alpha: 1)
            : UIColor(red: 0.945, green: 0.955, blue: 0.980, alpha: 1)
    }

    static let accent = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.46, green: 0.62, blue: 1.0, alpha: 1)
            : UIColor(red: 0.275, green: 0.400, blue: 0.900, alpha: 1)
    }

    static let accentDeep = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.32, green: 0.46, blue: 0.90, alpha: 1)
            : UIColor(red: 0.157, green: 0.275, blue: 0.725, alpha: 1)
    }

    static let accentSoft = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.14, green: 0.22, blue: 0.43, alpha: 1)
            : UIColor(red: 0.885, green: 0.920, blue: 1.0, alpha: 1)
    }

    static let userBubble = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.20, green: 0.32, blue: 0.70, alpha: 1)
            : UIColor(red: 0.275, green: 0.400, blue: 0.900, alpha: 1)
    }

    static let text = UIColor.label
    static let secondaryText = UIColor.secondaryLabel
    static let tertiaryText = UIColor.tertiaryLabel
    static let separator = UIColor.separator
    static let success = UIColor.systemGreen
    static let warning = UIColor.systemOrange
    static let danger = UIColor.systemRed
    static let purple = UIColor.systemPurple

    static let cornerLarge: CGFloat = 24
    static let cornerMedium: CGFloat = 16
    static let cornerSmall: CGFloat = 12

    static func font(_ style: UIFont.TextStyle, weight: UIFont.Weight = .regular) -> UIFont {
        let base = UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: style).pointSize, weight: weight)
        return UIFontMetrics(forTextStyle: style).scaledFont(for: base)
    }

    static func scaledFont(size: CGFloat, weight: UIFont.Weight = .regular, textStyle: UIFont.TextStyle = .body) -> UIFont {
        UIFontMetrics(forTextStyle: textStyle).scaledFont(for: UIFont.systemFont(ofSize: size, weight: weight))
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
        } else {
            layer.borderWidth = 0
        }
        if shadow {
            layer.masksToBounds = false
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = traitCollection.userInterfaceStyle == .dark ? 0.28 : 0.09
            layer.shadowRadius = 16
            layer.shadowOffset = CGSize(width: 0, height: 6)
        } else {
            layer.shadowOpacity = 0
        }
        accessibilityIgnoresInvertColors = true
    }

    func dhSetAccessibility(_ label: String, hint: String? = nil, traits: UIAccessibilityTraits = []) {
        isAccessibilityElement = true
        accessibilityLabel = label
        accessibilityHint = hint
        accessibilityTraits = traits
    }
}

final class DHBadgeLabel: UILabel {
    init(text: String, color: UIColor, filled: Bool = true) {
        super.init(frame: .zero)
        self.text = text
        textColor = filled ? color : DHTheme.secondaryText
        font = DHTheme.font(.caption1, weight: .semibold)
        textAlignment = .center
        layer.cornerRadius = 9
        layer.masksToBounds = true
        backgroundColor = filled ? color.withAlphaComponent(0.14) : DHTheme.surfaceMuted
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(greaterThanOrEqualToConstant: 28).isActive = true
        accessibilityTraits = .staticText
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
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
        imageView.widthAnchor.constraint(equalToConstant: symbolSize + 6),
        imageView.heightAnchor.constraint(equalToConstant: symbolSize + 6)
    ])
    return container
}

func dhButton(
    title: String,
    systemName: String? = nil,
    filled: Bool = false,
    action: @escaping () -> Void
) -> UIButton {
    var configuration = filled ? UIButton.Configuration.filled() : UIButton.Configuration.tinted()
    configuration.baseBackgroundColor = filled ? DHTheme.accent : DHTheme.accentSoft
    configuration.baseForegroundColor = filled ? .white : DHTheme.accentDeep
    configuration.title = title
    configuration.image = systemName.flatMap { UIImage(systemName: $0) }
    configuration.imagePadding = 8
    configuration.cornerStyle = .medium
    configuration.contentInsets = NSDirectionalEdgeInsets(top: 11, leading: 14, bottom: 11, trailing: 14)
    let button = UIButton(configuration: configuration)
    button.titleLabel?.font = DHTheme.font(.body, weight: .semibold)
    button.addAction(UIAction { _ in action() }, for: .touchUpInside)
    button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    return button
}

func dhSeparator() -> UIView {
    let separator = UIView()
    separator.backgroundColor = DHTheme.separator.withAlphaComponent(0.65)
    separator.translatesAutoresizingMaskIntoConstraints = false
    separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
    return separator
}
