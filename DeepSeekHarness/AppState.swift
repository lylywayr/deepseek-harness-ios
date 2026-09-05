import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    private enum Keys {
        static let endpoint = "harness.endpoint"
        static let theme = "harness.settings.theme"
        static let fontSize = "harness.settings.fontSize"
        static let transcriptView = "harness.settings.transcriptView"
        static let busyEnter = "harness.settings.busyEnter"
        static let defaultPermission = "harness.settings.defaultPermission"
        static let groupBy = "harness.view.groupBy"
        static let orderBy = "harness.view.orderBy"
        static let showArchived = "harness.view.showArchived"
    }

    @Published private(set) var endpointString: String
    @Published private(set) var hasConfiguredEndpoint: Bool
    @Published private(set) var settings: HarnessClientSettings
    @Published private(set) var viewPreferences: HarnessViewPreferences

    init(defaults: UserDefaults = .standard) {
        let saved = defaults.string(forKey: Keys.endpoint) ?? ""
        if let parsed = Self.parse(saved) {
            endpointString = parsed.url.absoluteString
            hasConfiguredEndpoint = true
            if let token = parsed.token, !token.isEmpty {
                HarnessCredentialStore(baseURL: parsed.url).write(token)
                defaults.set(endpointString, forKey: Keys.endpoint)
            }
        } else {
            endpointString = ""
            hasConfiguredEndpoint = false
        }

        var client = HarnessClientSettings.defaults
        if let raw = defaults.string(forKey: Keys.theme), let value = HarnessThemePreference(rawValue: raw) { client.theme = value }
        if defaults.object(forKey: Keys.fontSize) != nil { client.fontSize = min(max(defaults.integer(forKey: Keys.fontSize), 12), 17) }
        if let raw = defaults.string(forKey: Keys.transcriptView), let value = HarnessTranscriptView(rawValue: raw) { client.transcriptView = value }
        if let raw = defaults.string(forKey: Keys.busyEnter), let value = HarnessBusyEnterBehavior(rawValue: raw) { client.busyEnter = value }
        if let value = defaults.string(forKey: Keys.defaultPermission), !value.isEmpty { client.defaultPermission = value }
        settings = client

        var view = HarnessViewPreferences()
        if let raw = defaults.string(forKey: Keys.groupBy), let value = HarnessViewPreferences.GroupBy(rawValue: raw) { view.groupBy = value }
        if let raw = defaults.string(forKey: Keys.orderBy), let value = HarnessViewPreferences.OrderBy(rawValue: raw) { view.orderBy = value }
        if defaults.object(forKey: Keys.showArchived) != nil { view.showArchived = defaults.bool(forKey: Keys.showArchived) }
        viewPreferences = view
    }

    var endpointURL: URL? { Self.makeURL(from: endpointString) }

    var hasStoredCredential: Bool {
        guard let url = endpointURL else { return false }
        return HarnessCredentialStore(baseURL: url).hasValue()
    }

    @discardableResult
    func saveEndpoint(_ value: String, token: String? = nil) -> Bool {
        guard let parsed = Self.parse(value) else { return false }
        let normalized = parsed.url.absoluteString
        UserDefaults.standard.set(normalized, forKey: Keys.endpoint)
        if let suppliedToken = token?.trimmingCharacters(in: .whitespacesAndNewlines), !suppliedToken.isEmpty {
            HarnessCredentialStore(baseURL: parsed.url).write(suppliedToken)
        } else if let urlToken = parsed.token, !urlToken.isEmpty {
            HarnessCredentialStore(baseURL: parsed.url).write(urlToken)
        }
        endpointString = normalized
        hasConfiguredEndpoint = true
        return true
    }

    func clearEndpoint() {
        if let url = endpointURL { HarnessCredentialStore(baseURL: url).remove() }
        UserDefaults.standard.removeObject(forKey: Keys.endpoint)
        endpointString = ""
        hasConfiguredEndpoint = false
    }

    func updateSettings(_ value: HarnessClientSettings) {
        settings = value
        let defaults = UserDefaults.standard
        defaults.set(value.theme.rawValue, forKey: Keys.theme)
        defaults.set(value.fontSize, forKey: Keys.fontSize)
        defaults.set(value.transcriptView.rawValue, forKey: Keys.transcriptView)
        defaults.set(value.busyEnter.rawValue, forKey: Keys.busyEnter)
        defaults.set(value.defaultPermission, forKey: Keys.defaultPermission)
        applyAppearance(value.theme)
    }

    func updateViewPreferences(_ value: HarnessViewPreferences) {
        viewPreferences = value
        let defaults = UserDefaults.standard
        defaults.set(value.groupBy.rawValue, forKey: Keys.groupBy)
        defaults.set(value.orderBy.rawValue, forKey: Keys.orderBy)
        defaults.set(value.showArchived, forKey: Keys.showArchived)
    }

    func applyAppearance(_ preference: HarnessThemePreference? = nil) {
        let selected = preference ?? settings.theme
        let style: UIUserInterfaceStyle
        switch selected {
        case .system: style = .unspecified
        case .light: style = .light
        case .dark: style = .dark
        }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        scenes.flatMap(\.windows).forEach { $0.overrideUserInterfaceStyle = style }
    }

    static func makeURL(from value: String) -> URL? { parse(value)?.url }

    private static func parse(_ value: String) -> (url: URL, token: String?)? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, var components = URLComponents(string: text) else { return nil }
        guard let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https", let host = components.host, !host.isEmpty, components.user == nil, components.password == nil else { return nil }
        let token = components.queryItems?.first(where: { $0.name == "token" })?.value
        components.queryItems = (components.queryItems ?? []).filter { $0.name != "token" }
        guard let url = components.url else { return nil }
        return (url, token)
    }
}
