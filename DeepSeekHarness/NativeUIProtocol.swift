import Foundation

/// Actions are resolved by the Harness host. The iOS client never executes
/// plugin JavaScript or loads plugin native code.
typealias NativeUIActionHandler = (
    _ surfaceID: String,
    _ nodeID: String,
    _ action: String,
    _ payload: [String: String],
    _ completion: @escaping (Result<NativeUIActionResponse, Error>) -> Void
) -> Void

struct NativeUIManifest: Codable {
    let protocolVersion: String
    let generatedAt: String?
    let plugins: [NativeUIPlugin]
    let surfaces: [NativeUISurface]
    let diagnostics: [NativeUIDiagnostic]

    init(
        protocolVersion: String = "dsh-native-ui/1",
        generatedAt: String? = nil,
        plugins: [NativeUIPlugin] = [],
        surfaces: [NativeUISurface] = [],
        diagnostics: [NativeUIDiagnostic] = []
    ) {
        self.protocolVersion = protocolVersion
        self.generatedAt = generatedAt
        self.plugins = plugins
        self.surfaces = surfaces
        self.diagnostics = diagnostics
    }
}

struct NativeUIPlugin: Codable {
    let id: String
    let name: String
    let version: String?
    let enabled: Bool
    let nativeMode: String?
}

struct NativeUISurface: Codable {
    let id: String
    let pluginID: String?
    let title: String
    let subtitle: String?
    let icon: String?
    let placement: String
    let root: NativeUINode
    let order: Int?

    var isLegacyOnly: Bool {
        ["legacy", "web"].contains(root.type.lowercased())
    }
}

struct NativeUIDiagnostic: Codable {
    let pluginID: String?
    let surfaceID: String?
    let code: String
    let message: String
    let fallback: String?
}

struct NativeUIOption: Codable {
    let id: String
    let title: String
    let subtitle: String?
}

/// Versioned intermediate representation shared by the server adapter and
/// the iOS renderer. Unknown JSON fields are intentionally ignored.
struct NativeUINode: Codable {
    let type: String
    let id: String?
    let title: String?
    let text: String?
    let subtitle: String?
    let icon: String?
    let action: String?
    let state: String?
    let value: String?
    let placeholder: String?
    let url: String?
    let isEnabled: Bool?
    let axis: String?
    let children: [NativeUINode]?
    let items: [NativeUINode]?
    let options: [NativeUIOption]?
    let accessibilityLabel: String?

    init(
        type: String,
        id: String? = nil,
        title: String? = nil,
        text: String? = nil,
        subtitle: String? = nil,
        icon: String? = nil,
        action: String? = nil,
        state: String? = nil,
        value: String? = nil,
        placeholder: String? = nil,
        url: String? = nil,
        isEnabled: Bool? = nil,
        axis: String? = nil,
        children: [NativeUINode]? = nil,
        items: [NativeUINode]? = nil,
        options: [NativeUIOption]? = nil,
        accessibilityLabel: String? = nil
    ) {
        self.type = type
        self.id = id
        self.title = title
        self.text = text
        self.subtitle = subtitle
        self.icon = icon
        self.action = action
        self.state = state
        self.value = value
        self.placeholder = placeholder
        self.url = url
        self.isEnabled = isEnabled
        self.axis = axis
        self.children = children
        self.items = items
        self.options = options
        self.accessibilityLabel = accessibilityLabel
    }

    var resolvedChildren: [NativeUINode] { children ?? items ?? [] }

    var displayTitle: String {
        let candidate = title ?? text ?? subtitle ?? type
        return candidate.isEmpty ? type : candidate
    }
}

struct NativeUIActionRequest: Codable {
    let protocolVersion: String
    let surfaceID: String
    let nodeID: String
    let action: String
    let payload: [String: String]
}

struct NativeUIActionResponse: Codable {
    let ok: Bool
    let message: String?
    let manifest: NativeUIManifest?
}

enum NativeUITransportError: LocalizedError {
    case protocolUnavailable
    case invalidManifest
    case invalidResponse
    case http(Int)
    case message(String)

    var errorDescription: String? {
        switch self {
        case .protocolUnavailable: return "当前 Harness 尚未提供 Native UI 接口。"
        case .invalidManifest: return "Native UI 清单格式无效。"
        case .invalidResponse: return "Harness 返回了无效响应。"
        case let .http(status): return "Harness 请求失败（HTTP \(status)）。"
        case let .message(value): return value
        }
    }
}

/// Optional server-side protocol for declarative native surfaces.
/// Actions are dispatched through the native JSON-RPC transport.
final class NativeUITransport {
    let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func loadManifest(completion: @escaping (Result<NativeUIManifest, Error>) -> Void) {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/native-ui/manifest"))
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        session.dataTask(with: request) { data, response, error in
            if let error { completion(.failure(error)); return }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(NativeUITransportError.invalidResponse)); return
            }
            guard (200..<300).contains(http.statusCode) else {
                completion(.failure(http.statusCode == 404
                    ? NativeUITransportError.protocolUnavailable
                    : NativeUITransportError.http(http.statusCode)))
                return
            }
            guard let data else {
                completion(.failure(NativeUITransportError.invalidManifest)); return
            }
            do {
                completion(.success(try JSONDecoder().decode(NativeUIManifest.self, from: data)))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    func perform(
        surfaceID: String,
        nodeID: String,
        action: String,
        payload: [String: String],
        completion: @escaping (Result<NativeUIActionResponse, Error>) -> Void
    ) {
        let body = NativeUIActionRequest(
            protocolVersion: "dsh-native-ui/1",
            surfaceID: surfaceID,
            nodeID: nodeID,
            action: action,
            payload: payload
        )
        var request = URLRequest(url: baseURL.appendingPathComponent("api/native-ui/action"))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            completion(.failure(error)); return
        }
        session.dataTask(with: request) { data, response, error in
            if let error { completion(.failure(error)); return }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(NativeUITransportError.invalidResponse)); return
            }
            guard (200..<300).contains(http.statusCode), let data else {
                completion(.failure(NativeUITransportError.http(http.statusCode))); return
            }
            do {
                completion(.success(try JSONDecoder().decode(NativeUIActionResponse.self, from: data)))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}

final class NativeUIStore {
    var manifest: NativeUIManifest
    let didChange: () -> Void
    private var observers: [UUID: () -> Void] = [:]

    init(
        manifest: NativeUIManifest = NativeUIManifest(),
        didChange: @escaping () -> Void = {}
    ) {
        self.manifest = manifest
        self.didChange = didChange
    }

    func replace(_ manifest: NativeUIManifest) {
        self.manifest = manifest
        observers.values.forEach { $0() }
        didChange()
    }

    func observe(_ observer: @escaping () -> Void) -> () -> Void {
        let id = UUID()
        observers[id] = observer
        return { [weak self] in self?.observers.removeValue(forKey: id) }
    }

    func surfaces(at placement: String) -> [NativeUISurface] {
        manifest.surfaces
            .filter { $0.placement == placement }
            .sorted { ($0.order ?? 0) < ($1.order ?? 0) }
    }
}
