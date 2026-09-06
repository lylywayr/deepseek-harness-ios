import Foundation

struct HarnessEndpointValue {
    let url: URL
    let token: String?
}

enum HarnessEndpointCanonicalizer {
    static func canonicalize(_ value: String) -> HarnessEndpointValue? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let components = URLComponents(string: text) else { return nil }
        return canonicalize(components)
    }

    static func canonicalize(_ url: URL) -> HarnessEndpointValue? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        return canonicalize(components)
    }

    static func canonicalURL(_ url: URL) -> URL? {
        canonicalize(url)?.url
    }

    private static func canonicalize(_ source: URLComponents) -> HarnessEndpointValue? {
        var components = source
        guard let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              !host.isEmpty,
              components.user == nil,
              components.password == nil else { return nil }

        components.scheme = scheme
        let queryItems = components.queryItems ?? []
        let token = queryItems.first(where: { $0.name == "token" && !($0.value ?? "").isEmpty })?.value
        let remaining = queryItems.filter { $0.name != "token" }
        components.queryItems = remaining.isEmpty ? nil : remaining
        if remaining.isEmpty { components.percentEncodedQuery = nil }
        components.fragment = nil
        guard let url = components.url else { return nil }
        return HarnessEndpointValue(url: url, token: token)
    }
}
