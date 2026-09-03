import Foundation
import Combine

final class AppState: ObservableObject {
    private enum Keys {
        static let endpoint = "harness.endpoint"
    }

    @Published private(set) var endpointString: String
    @Published private(set) var hasConfiguredEndpoint: Bool

    init() {
        let saved = UserDefaults.standard.string(forKey: Keys.endpoint) ?? ""
        endpointString = saved
        hasConfiguredEndpoint = Self.makeURL(from: saved) != nil
    }

    var endpointURL: URL? {
        Self.makeURL(from: endpointString)
    }

    @discardableResult
    func saveEndpoint(_ value: String) -> Bool {
        guard let url = Self.makeURL(from: value) else {
            return false
        }

        let normalized = url.absoluteString
        UserDefaults.standard.set(normalized, forKey: Keys.endpoint)
        endpointString = normalized
        hasConfiguredEndpoint = true
        return true
    }

    func clearEndpoint() {
        UserDefaults.standard.removeObject(forKey: Keys.endpoint)
        endpointString = ""
        hasConfiguredEndpoint = false
    }

    static func makeURL(from value: String) -> URL? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let components = URLComponents(string: text) else {
            return nil
        }

        guard let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              !host.isEmpty,
              components.user == nil,
              components.password == nil else {
            return nil
        }

        return components.url
    }
}
