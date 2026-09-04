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
        if let parsed = Self.parse(saved) {
            endpointString = parsed.url.absoluteString
            hasConfiguredEndpoint = true
            if let token = parsed.token, !token.isEmpty {
                HarnessCredentialStore(baseURL: parsed.url).write(token)
                UserDefaults.standard.set(endpointString, forKey: Keys.endpoint)
            }
        } else {
            endpointString = ""
            hasConfiguredEndpoint = false
        }
    }

    var endpointURL: URL? {
        Self.makeURL(from: endpointString)
    }

    var hasStoredCredential: Bool {
        guard let url = endpointURL else { return false }
        return HarnessCredentialStore(baseURL: url).hasValue()
    }

    @discardableResult
    func saveEndpoint(_ value: String, token: String? = nil) -> Bool {
        guard let parsed = Self.parse(value) else {
            return false
        }

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
        if let url = endpointURL {
            HarnessCredentialStore(baseURL: url).remove()
        }
        UserDefaults.standard.removeObject(forKey: Keys.endpoint)
        endpointString = ""
        hasConfiguredEndpoint = false
    }

    static func makeURL(from value: String) -> URL? {
        parse(value)?.url
    }

    private static func parse(_ value: String) -> (url: URL, token: String?)? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, var components = URLComponents(string: text) else {
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

        let token = components.queryItems?.first(where: { $0.name == "token" })?.value
        components.queryItems = (components.queryItems ?? []).filter { $0.name != "token" }
        guard let url = components.url else { return nil }
        return (url, token)
    }
}
