import Foundation

/// Wire constants for the isolated dsh-market bootstrap surface.
/// The page compatibility version is intentionally separate from the package
/// version supplied by the integration configuration.
enum MarketBootstrapContract {
    static let packageID = "dshmarket"
    static let productID = "dsh-market"
    static let displayName = "dsh-market"
    static let verifiedPageVersion = "v1.41.0"
    static let statusPath = "mobile-bootstrap/market/status"
    static let installPath = "mobile-bootstrap/market/install"
    static let jobsPath = "mobile-bootstrap/jobs"
}

struct MarketPluginStatus: Codable, Equatable {
    let pluginID: String
    let installedVersion: String?
    let installed: Bool
    let compatible: Bool?

    init(
        pluginID: String = MarketBootstrapContract.packageID,
        installedVersion: String? = nil,
        installed: Bool = false,
        compatible: Bool? = nil
    ) {
        self.pluginID = pluginID
        self.installedVersion = installedVersion
        self.installed = installed
        self.compatible = compatible
    }

    private enum CodingKeys: String, CodingKey {
        case pluginID = "pluginId"
        case id
        case installedVersion
        case version
        case installed
        case compatible
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pluginID = try container.decodeIfPresent(String.self, forKey: .pluginID)
            ?? container.decodeIfPresent(String.self, forKey: .id)
            ?? MarketBootstrapContract.packageID
        installedVersion = try container.decodeIfPresent(String.self, forKey: .installedVersion)
            ?? container.decodeIfPresent(String.self, forKey: .version)
        installed = try container.decodeIfPresent(Bool.self, forKey: .installed)
            ?? installedVersion != nil
        compatible = try container.decodeIfPresent(Bool.self, forKey: .compatible)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pluginID, forKey: .pluginID)
        try container.encodeIfPresent(installedVersion, forKey: .installedVersion)
        try container.encode(installed, forKey: .installed)
        try container.encodeIfPresent(compatible, forKey: .compatible)
    }
}

/// Read-only status. Missing or unknown version fields are preserved as nil;
/// callers must not turn an incomplete status into an install or upgrade.
struct MarketStatusResponse: Codable, Equatable {
    let product: String?
    let version: String?
    let plugin: MarketPluginStatus?

    init(product: String?, version: String?, plugin: MarketPluginStatus?) {
        self.product = product
        self.version = version
        self.plugin = plugin
    }

    private enum CodingKeys: String, CodingKey {
        case product
        case market
        case version
        case marketVersion
        case plugin
        case pluginStatus
        case pluginID = "pluginId"
        case installed
        case installedVersion
        case compatible
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        product = try container.decodeIfPresent(String.self, forKey: .product)
            ?? container.decodeIfPresent(String.self, forKey: .market)
        version = try container.decodeIfPresent(String.self, forKey: .version)
            ?? container.decodeIfPresent(String.self, forKey: .marketVersion)
        if let value = try container.decodeIfPresent(MarketPluginStatus.self, forKey: .plugin) {
            plugin = value
        } else if let value = try container.decodeIfPresent(MarketPluginStatus.self, forKey: .pluginStatus) {
            plugin = value
        } else {
            let installed = try container.decodeIfPresent(Bool.self, forKey: .installed)
            let installedVersion = try container.decodeIfPresent(String.self, forKey: .installedVersion)
            let compatible = try container.decodeIfPresent(Bool.self, forKey: .compatible)
            let pluginID = try container.decodeIfPresent(String.self, forKey: .pluginID)
            plugin = (installed != nil || installedVersion != nil || compatible != nil || pluginID != nil)
                ? MarketPluginStatus(
                    pluginID: pluginID ?? MarketBootstrapContract.packageID,
                    installedVersion: installedVersion,
                    installed: installed ?? installedVersion != nil,
                    compatible: compatible
                )
                : nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(product, forKey: .product)
        try container.encodeIfPresent(version, forKey: .version)
        try container.encodeIfPresent(plugin, forKey: .plugin)
    }
}

typealias MarketBootstrapStatus = MarketStatusResponse

struct MarketInstallRequest: Codable, Equatable {
    let pluginID: String
    let version: String
    let automatic: Bool

    init(pluginID: String = MarketBootstrapContract.packageID, version: String, automatic: Bool = true) {
        self.pluginID = pluginID
        self.version = version
        self.automatic = automatic
    }

    private enum CodingKeys: String, CodingKey {
        case pluginID = "pluginId"
        case version
        case automatic
    }
}

struct MarketInstallResponse: Codable, Equatable {
    let jobID: String

    init(jobID: String) { self.jobID = jobID }

    private enum CodingKeys: String, CodingKey {
        case jobID = "jobId"
        case id
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let value = try container.decodeIfPresent(String.self, forKey: .jobID)
            ?? container.decodeIfPresent(String.self, forKey: .id), !value.isEmpty else {
            throw MarketBootstrapError.decodingFailed
        }
        jobID = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(jobID, forKey: .jobID)
    }
}

enum MarketJobState: Equatable, Codable {
    case queued
    case running
    case succeeded
    case failed
    case cancelled
    case unknown(String)

    private var wireValue: String {
        switch self {
        case .queued: return "queued"
        case .running: return "running"
        case .succeeded: return "succeeded"
        case .failed: return "failed"
        case .cancelled: return "cancelled"
        case let .unknown(value): return value
        }
    }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self).lowercased()
        switch value {
        case "queued", "pending": self = .queued
        case "running", "in-progress", "in_progress": self = .running
        case "succeeded", "complete", "completed": self = .succeeded
        case "failed", "error": self = .failed
        case "cancelled", "canceled": self = .cancelled
        default: self = .unknown(value)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wireValue)
    }

    var isTerminal: Bool {
        switch self {
        case .succeeded, .failed, .cancelled: return true
        case .queued, .running, .unknown: return false
        }
    }
}

struct MarketJobError: Codable, Equatable {
    let code: String?
    let message: String
}

struct MarketJobResponse: Codable, Equatable {
    let jobID: String
    let state: MarketJobState
    let progress: Int?
    let message: String?
    let error: MarketJobError?

    private enum CodingKeys: String, CodingKey {
        case jobID = "jobId"
        case id
        case state
        case status
        case progress
        case message
        case error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = try container.decodeIfPresent(String.self, forKey: .jobID)
            ?? container.decodeIfPresent(String.self, forKey: .id), !id.isEmpty else {
            throw MarketBootstrapError.decodingFailed
        }
        jobID = id
        state = try container.decodeIfPresent(MarketJobState.self, forKey: .state)
            ?? container.decodeIfPresent(MarketJobState.self, forKey: .status)
            ?? .unknown("missing")
        progress = try container.decodeIfPresent(Int.self, forKey: .progress)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        error = try container.decodeIfPresent(MarketJobError.self, forKey: .error)
    }

    init(jobID: String, state: MarketJobState, progress: Int? = nil, message: String? = nil, error: MarketJobError? = nil) {
        self.jobID = jobID
        self.state = state
        self.progress = progress
        self.message = message
        self.error = error
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(jobID, forKey: .jobID)
        try container.encode(state, forKey: .state)
        try container.encodeIfPresent(progress, forKey: .progress)
        try container.encodeIfPresent(message, forKey: .message)
        try container.encodeIfPresent(error, forKey: .error)
    }
}

enum MarketInstallationDecision: Equatable {
    case skipInstalledCompatible
    case installMissing
    case needsDecision(installedVersion: String?)
}

struct MarketInstallationPolicy {
    let verifiedPackageVersion: String
    let productID: String
    let packageID: String

    init(
        verifiedPackageVersion: String,
        productID: String = MarketBootstrapContract.productID,
        packageID: String = MarketBootstrapContract.packageID
    ) {
        self.verifiedPackageVersion = verifiedPackageVersion
        self.productID = productID
        self.packageID = packageID
    }

    func decision(for status: MarketStatusResponse) -> MarketInstallationDecision {
        guard status.product == productID,
              status.version == MarketBootstrapContract.verifiedPageVersion else {
            return .needsDecision(installedVersion: status.plugin?.installedVersion)
        }
        guard let plugin = status.plugin else { return .installMissing }
        guard plugin.pluginID == packageID else {
            return .needsDecision(installedVersion: plugin.installedVersion)
        }
        guard plugin.installed else { return .installMissing }
        guard plugin.installedVersion == verifiedPackageVersion,
              plugin.compatible == true else {
            return .needsDecision(installedVersion: plugin.installedVersion)
        }
        return .skipInstalledCompatible
    }
}

enum MarketBootstrapError: LocalizedError, Equatable {
    case invalidBaseURL
    case missingVerifiedPackageVersion
    case invalidVerifiedPackageVersion
    case invalidJobID
    case unsupportedPlugin
    case noInstallDecision
    case invalidResponse
    case httpStatus(Int)
    case decodingFailed
    case timedOut
    case cancelled
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL: return "插件市场服务地址无效。"
        case .missingVerifiedPackageVersion: return "未配置固定的插件包版本，已阻止安装请求。"
        case .invalidVerifiedPackageVersion: return "插件包版本必须是非空固定版本，不能使用 latest。"
        case .invalidJobID: return "插件市场任务标识无效。"
        case .unsupportedPlugin: return "自动安装仅支持固定的 dshmarket 插件。"
        case .noInstallDecision: return "当前状态不允许生成安装请求。"
        case .invalidResponse: return "插件市场返回了无效响应。"
        case let .httpStatus(status): return "插件市场请求失败（HTTP \(status)）。"
        case .decodingFailed: return "插件市场响应格式无法识别。"
        case .timedOut: return "插件市场任务等待超时。"
        case .cancelled: return "插件市场加载已取消。"
        case let .transport(message): return message
        }
    }
}

/// URLSession client for status, install and job endpoints. Authentication is
/// delegated to the supplied session's cookie storage; no credential is copied
/// into a request URL, body, log or JavaScript context.
final class MarketBootstrapClient {
    let baseURL: URL
    let timeout: TimeInterval
    let verifiedPackageVersion: String
    private let session: URLSession
    private let decoder: JSONDecoder
    private let canonicalBaseURL: URL?

    init(
        baseURL: URL,
        verifiedPackageVersion: String,
        session: URLSession = .shared,
        timeout: TimeInterval = 20,
        decoder: JSONDecoder = JSONDecoder()
    ) throws {
        guard Self.isFixedPackageVersion(verifiedPackageVersion) else {
            throw verifiedPackageVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? MarketBootstrapError.missingVerifiedPackageVersion
                : MarketBootstrapError.invalidVerifiedPackageVersion
        }
        self.baseURL = baseURL
        self.timeout = min(max(timeout, 5), 120)
        self.verifiedPackageVersion = verifiedPackageVersion
        self.session = session
        self.decoder = decoder
        canonicalBaseURL = Self.canonicalBaseURL(baseURL)
    }

    func makeStatusRequest() throws -> URLRequest {
        try makeRequest(path: MarketBootstrapContract.statusPath, method: "GET")
    }

    func makeInstallRequest(_ payload: MarketInstallRequest) throws -> URLRequest {
        guard payload.pluginID == MarketBootstrapContract.packageID,
              payload.version == verifiedPackageVersion,
              Self.isFixedPackageVersion(payload.version) else {
            throw MarketBootstrapError.unsupportedPlugin
        }
        let body: Data
        do {
            body = try JSONEncoder().encode(payload)
        } catch {
            throw MarketBootstrapError.invalidResponse
        }
        return try makeRequest(path: MarketBootstrapContract.installPath, method: "POST", body: body)
    }

    /// Only a missing, verified-compatible status can produce an install
    /// request. A mismatch or an unknown field is always a user decision.
    func makeInstallRequest(for status: MarketStatusResponse) throws -> URLRequest {
        guard MarketInstallationPolicy(verifiedPackageVersion: verifiedPackageVersion).decision(for: status) == .installMissing else {
            throw MarketBootstrapError.noInstallDecision
        }
        return try makeInstallRequest(MarketInstallRequest(version: verifiedPackageVersion))
    }

    func makeJobRequest(jobID: String) throws -> URLRequest {
        guard Self.isSafeJobID(jobID) else { throw MarketBootstrapError.invalidJobID }
        return try makeRequest(path: "\(MarketBootstrapContract.jobsPath)/\(jobID)", method: "GET")
    }

    func fetchStatus() async throws -> MarketStatusResponse {
        try await perform(MarketStatusResponse.self, request: makeStatusRequest())
    }

    func install(_ payload: MarketInstallRequest) async throws -> MarketInstallResponse {
        try await perform(MarketInstallResponse.self, request: makeInstallRequest(payload))
    }

    func fetchJob(jobID: String) async throws -> MarketJobResponse {
        try await perform(MarketJobResponse.self, request: makeJobRequest(jobID: jobID))
    }

    /// Polls only the job status endpoint. It never retries or repeats POST.
    func pollInstallJob(jobID: String, interval: TimeInterval = 1, timeout: TimeInterval = 120) async throws -> MarketJobResponse {
        let pollInterval = min(max(interval, 0.25), 10)
        let deadline = Date().addingTimeInterval(min(max(timeout, 1), 600))
        while Date() < deadline {
            try Task.checkCancellation()
            let job = try await fetchJob(jobID: jobID)
            if job.state.isTerminal { return job }
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
        throw MarketBootstrapError.timedOut
    }

    private func makeRequest(path: String, method: String, body: Data? = nil) throws -> URLRequest {
        guard let root = canonicalBaseURL else { throw MarketBootstrapError.invalidBaseURL }
        let segments = path.split(separator: "/").map(String.init)
        let url = segments.reduce(root) { $0.appendingPathComponent($1, isDirectory: false) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = true
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func perform<T: Decodable>(_ type: T.Type, request: URLRequest) async throws -> T {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw MarketBootstrapError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else { throw MarketBootstrapError.httpStatus(http.statusCode) }
            do { return try decoder.decode(type, from: data) }
            catch { throw MarketBootstrapError.decodingFailed }
        } catch is CancellationError {
            throw MarketBootstrapError.cancelled
        } catch let error as MarketBootstrapError {
            throw error
        } catch {
            throw MarketBootstrapError.transport(error.localizedDescription)
        }
    }

    static func isFixedPackageVersion(_ value: String) -> Bool {
        let version = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !version.isEmpty, version.lowercased() != "latest", version.contains(where: { $0.isNumber }) else { return false }
        return version.allSatisfy { $0.isLetter || $0.isNumber || ".-_".contains($0) }
    }

    private static func canonicalBaseURL(_ value: URL) -> URL? {
        guard let components = URLComponents(url: value, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.fragment == nil, (components.queryItems ?? []).isEmpty else { return nil }
        var sanitized = components
        sanitized.scheme = scheme
        sanitized.query = nil
        sanitized.fragment = nil
        return sanitized.url
    }

    private static func isSafeJobID(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 200 && value.allSatisfy { $0.isLetter || $0.isNumber || "-_ .".replacingOccurrences(of: " ", with: "").contains($0) }
    }
}
