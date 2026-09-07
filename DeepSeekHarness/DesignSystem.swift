import UIKit

/// Harness Pocket Workspace visual language.  All colors remain dynamic so the
/// native client stays legible in light, dark, high-contrast, and reduced
/// transparency configurations.
enum DHTheme {
    static let background = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.055, green: 0.055, blue: 0.060, alpha: 1)
        }
        return UIColor(red: 0.969, green: 0.965, blue: 0.953, alpha: 1) // #F7F6F3
    }

    static let surface = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.115, green: 0.115, blue: 0.125, alpha: 1)
            : UIColor(red: 1.0, green: 1.0, blue: 0.992, alpha: 1) // #FFFFFD
    }

    static let surfaceMuted = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.16, green: 0.16, blue: 0.17, alpha: 1)
            : UIColor(red: 0.925, green: 0.922, blue: 0.914, alpha: 1)
    }

    static let surfaceStrong = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.22, green: 0.22, blue: 0.23, alpha: 1)
            : UIColor(red: 0.90, green: 0.89, blue: 0.875, alpha: 1)
    }

    static let processSurface = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.09, green: 0.14, blue: 0.12, alpha: 1)
            : UIColor(red: 0.91, green: 0.965, blue: 0.94, alpha: 1)
    }

    static let accent = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.42, green: 0.62, blue: 1.0, alpha: 1)
            : UIColor(red: 0.169, green: 0.404, blue: 0.867, alpha: 1) // #2B67DD
    }

    static let accentDeep = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.55, green: 0.70, blue: 1.0, alpha: 1)
            : UIColor(red: 0.12, green: 0.31, blue: 0.70, alpha: 1)
    }

    static let accentSoft = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.12, green: 0.20, blue: 0.38, alpha: 1)
            : UIColor(red: 0.90, green: 0.93, blue: 1.0, alpha: 1)
    }

    static let assistantBubble = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.095, green: 0.120, blue: 0.190, alpha: 1)
            : UIColor.white
    }

    static let userBubble = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.20, green: 0.32, blue: 0.70, alpha: 1)
            : UIColor(red: 0.275, green: 0.400, blue: 0.900, alpha: 1)
    }

    static let text = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 0.94, alpha: 1) : UIColor(red: 0.137, green: 0.145, blue: 0.16, alpha: 1) // #232529
    }
    static let secondaryText = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 0.68, alpha: 1) : UIColor(red: 0.455, green: 0.467, blue: 0.486, alpha: 1) // #74777C
    }
    static let tertiaryText = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 0.52, alpha: 1) : UIColor(red: 0.56, green: 0.56, blue: 0.55, alpha: 1)
    }
    static let separator = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 0.26, alpha: 1) : UIColor(red: 0.898, green: 0.894, blue: 0.878, alpha: 1) // #E5E4E0
    }
    static let success = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.30, green: 0.75, blue: 0.48, alpha: 1) : UIColor(red: 0.153, green: 0.604, blue: 0.365, alpha: 1) // #279A5D
    }
    static let warning = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.95, green: 0.68, blue: 0.25, alpha: 1) : UIColor(red: 0.773, green: 0.518, blue: 0.137, alpha: 1) // #C58423
    }
    static let danger = UIColor.systemRed
    static let purple = UIColor.systemPurple

    // Pocket uses a dense tool-like rhythm. Touch targets remain native-sized,
    // while visual padding and decoration stay compact at every screen size.
    static let pageHorizontal: CGFloat = 16
    static let sectionSpacing: CGFloat = 14
    static let cardPaddingVertical: CGFloat = 10
    static let rowMinHeight: CGFloat = 46
    static let cornerLarge: CGFloat = 16
    static let cornerMedium: CGFloat = 12
    static let cornerSmall: CGFloat = 8

    static func font(_ style: UIFont.TextStyle, weight: UIFont.Weight = .regular) -> UIFont {
        // Keep the native Dynamic Type curve, but use a denser Pocket baseline.
        // UIFontMetrics still expands these values when the user requests larger text.
        let size: CGFloat
        switch style.rawValue {
        case UIFont.TextStyle.largeTitle.rawValue: size = 30
        case UIFont.TextStyle.title1.rawValue: size = 25
        case UIFont.TextStyle.title2.rawValue: size = 22
        case UIFont.TextStyle.title3.rawValue: size = 18
        case UIFont.TextStyle.headline.rawValue: size = 16
        case UIFont.TextStyle.body.rawValue: size = 15
        case UIFont.TextStyle.callout.rawValue: size = 15
        case UIFont.TextStyle.subheadline.rawValue: size = 14
        case UIFont.TextStyle.footnote.rawValue: size = 12
        case UIFont.TextStyle.caption1.rawValue: size = 12
        case UIFont.TextStyle.caption2.rawValue: size = 11
        default: size = 15
        }
        let base = UIFont.systemFont(ofSize: size, weight: weight)
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
            layer.shadowRadius = 10
            layer.shadowOffset = CGSize(width: 0, height: 3)
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
        heightAnchor.constraint(greaterThanOrEqualToConstant: 24).isActive = true
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
    configuration.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 11, bottom: 7, trailing: 11)
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
