import Foundation
import Network
import Security
import UIKit

struct HarnessModelOption {
    let provider: String
    let providerName: String
    let model: String
    let modelName: String
    let reasoning: [[String: String]]
    var key: String { "\(provider)/\(model)" }
}

struct HarnessDirectoryEntry {
    let name: String
    let path: String
    let hidden: Bool
}

struct HarnessDirectoryListing {
    let path: String
    let home: String
    let crumbs: [HarnessDirectoryEntry]
    let entries: [HarnessDirectoryEntry]
    let truncated: Bool
}

private enum HarnessClientError: LocalizedError {
    case invalidURL
    case unauthorized
    case http(Int)
    case invalidResponse
    case correlation
    case remote(code: String, message: String)
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Harness 服务地址无效。"
        case .unauthorized: return "Harness 鉴权失败，请检查服务地址或令牌。"
        case let .http(status): return "Harness 请求失败（HTTP \(status)）。"
        case .invalidResponse: return "Harness 返回了无效响应。"
        case .correlation: return "Harness 响应关联失败。"
        case let .remote(code, message): return message.isEmpty ? "Harness 服务错误（\(code)）。" : message
        case let .network(error): return error.localizedDescription
        }
    }
}

final class HarnessCredentialStore {
    private let service = "com.example.DeepSeekHarness"
    private let account: String

    init(baseURL: URL) {
        let canonical = HarnessEndpointCanonicalizer.canonicalize(baseURL)?.url ?? baseURL
        account = "launch-token-\(canonical.host ?? "unknown")-\(canonical.port ?? 80)"
    }

    func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func hasValue() -> Bool {
        read() != nil
    }

    func write(_ token: String) {
        guard let data = token.data(using: .utf8), !token.isEmpty else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let values: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        if SecItemUpdate(query as CFDictionary, values as CFDictionary) == errSecItemNotFound {
            _ = SecItemAdd(query.merging(values) { _, new in new } as CFDictionary, nil)
        }
    }

    func remove() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

final class HarnessClient {
    let baseURL: URL
    private let tokenFromURL: String?
    private let credentials: HarnessCredentialStore
    private let session: URLSession

    init(baseURL: URL) {
        let parsed = HarnessEndpointCanonicalizer.canonicalize(baseURL)
        self.baseURL = parsed?.url ?? baseURL
        tokenFromURL = parsed?.token
        credentials = HarnessCredentialStore(baseURL: self.baseURL)
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = HTTPCookieStorage.shared
        configuration.httpShouldSetCookies = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
        if let tokenFromURL, !tokenFromURL.isEmpty { credentials.write(tokenFromURL) }
    }

    func bootstrap(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let url = bootstrapURL() else {
            completion(.failure(HarnessClientError.invalidURL))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        session.dataTask(with: request) { _, response, error in
            if let error { completion(.failure(HarnessClientError.network(error))); return }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(HarnessClientError.invalidResponse)); return
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                completion(.failure(HarnessClientError.unauthorized)); return
            }
            guard (200..<400).contains(http.statusCode) else {
                completion(.failure(HarnessClientError.http(http.statusCode))); return
            }
            completion(.success(()))
        }.resume()
    }

    func bootstrapURL() -> URL? {
        guard let token = tokenFromURL ?? credentials.read(), !token.isEmpty else { return baseURL }
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return nil }
        var items = components.queryItems ?? []
        items.removeAll { $0.name == "token" }
        items.append(URLQueryItem(name: "token", value: token))
        components.queryItems = items
        return components.url
    }
    func call(endpoint: String, args: [String: Any], completion: @escaping (Result<Any, Error>) -> Void) {
        guard Self.validEndpoint(endpoint), let url = apiURL(endpoint) else {
            completion(.failure(HarnessClientError.invalidURL)); return
        }
        let rpcID = UUID().uuidString
        let envelope = HarnessWire.rpcRequest(endpoint: endpoint, args: args, rpcID: rpcID)
        guard JSONSerialization.isValidJSONObject(envelope),
              let body = try? JSONSerialization.data(withJSONObject: envelope) else {
            completion(.failure(HarnessClientError.invalidResponse)); return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        session.dataTask(with: request) { data, response, error in
            if let error { completion(.failure(HarnessClientError.network(error))); return }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(HarnessClientError.invalidResponse)); return
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                completion(.failure(HarnessClientError.unauthorized)); return
            }
            guard (200..<300).contains(http.statusCode), let data else {
                completion(.failure(HarnessClientError.invalidResponse)); return
            }
            do {
                let parsed = try HarnessWire.rpcResponse(data: data, expectedRPCID: rpcID)
                if parsed.ok {
                    completion(.success(parsed.value ?? NSNull()))
                } else {
                    completion(.failure(HarnessClientError.remote(
                        code: parsed.code ?? "gateway/internal",
                        message: parsed.message ?? "Harness 服务请求失败。"
                    )))
                }
            } catch let error as HarnessWire.WireError {
                completion(.failure(error))
            } catch {
                completion(.failure(HarnessClientError.invalidResponse))
            }
        }.resume()
    }

    func webSocketRequest() -> URLRequest? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return nil }
        components.path = appendingPath("api/remote.mux", to: components.path)
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        if let cookies = HTTPCookieStorage.shared.cookies(for: baseURL), !cookies.isEmpty {
            let fields = HTTPCookie.requestHeaderFields(with: cookies)
            if let value = fields["Cookie"] { request.setValue(value, forHTTPHeaderField: "Cookie") }
        }
        return request
    }

    func webSocketTask(with request: URLRequest) -> URLSessionWebSocketTask {
        session.webSocketTask(with: request)
    }

    func invalidate() { session.invalidateAndCancel() }

    private func appendingPath(_ suffix: String, to path: String) -> String {
        let prefix = path.hasSuffix("/") ? String(path.dropLast()) : path
        return prefix + "/" + suffix
    }

    func apiURL(_ endpoint: String) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return nil }
        components.path = appendingPath("api/\(endpoint)", to: components.path)
        return components.url
    }

    private static func validEndpoint(_ endpoint: String) -> Bool {
        guard !endpoint.isEmpty else { return false }
        return endpoint.split(separator: "/").allSatisfy { part in
            let value = String(part)
            return !value.isEmpty && value != "." && value != ".."
                && value.allSatisfy { $0.isLetter || $0.isNumber || "_$.-".contains($0) }
        }
    }
}

@MainActor
final class HarnessRuntime: NSObject {
    let baseURL: URL
    private let client: HarnessClient
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var streamGeneration = 0
    private var selectedCursor = -1
    private var oldestSeq = -1
    private var seenEventIDs = Set<String>()
    private var liveItems: [String: HarnessConversationItem] = [:]
    private var liveOrder: [String] = []
    private var sessionCursors: [String: (cursor: Int, oldest: Int)] = [:]
    private var workspacesByID: [String: HarnessWorkspace] = [:]
    private var workspaceOrder: [String] = []
    private var archivedSessionIDs = Set<String>()
    private var controlProjection: [String: [String: Any]] = [:]
    private var artifactsByID: [String: HarnessArtifact] = [:]
    private var isStarted = false
    private var isRefreshing = false
    private var followStreamID: String?
    private var workspaceStreamID: String?
    private var controlStreamID: String?
    private var eventsStreamID: String?
    private var eventClientID: String?

    private(set) var sessions: [HarnessSessionSummary] = []
    private(set) var workspaces: [HarnessWorkspace] = []
    private(set) var models: [HarnessModelOption] = []
    private(set) var items: [HarnessConversationItem] = []
    private(set) var selectedSessionID: String?
    private(set) var isLoading = true
    private(set) var isGenerating = false
    private(set) var hasMore = false
    private(set) var connected = false
    private(set) var lastError: String?
    private(set) var statusText = "正在连接"
    private(set) var currentStage: String?
    private(set) var pendingApprovals: [HarnessApprovalRequest] = []
    private(set) var pendingQuestions: [HarnessPendingQuestion] = []
    private(set) var artifacts: [HarnessArtifact] = []
    private(set) var contextDirectory: String?
    private(set) var reasoningEffort: String?
    private var changeObservers: [UUID: () -> Void] = [:]
    private var navigationObservers: [UUID: () -> Void] = [:]
    var onApproval: (([String: Any]) -> Void)?
    var onQuestion: ((HarnessPendingQuestion) -> Void)?

    init(baseURL: URL) {
        let parsed = HarnessEndpointCanonicalizer.canonicalize(baseURL)
        self.baseURL = parsed?.url ?? baseURL
        client = HarnessClient(baseURL: self.baseURL)
        super.init()
    }

    deinit {
        receiveTask?.cancel()
        reconnectTask?.cancel()
        socket?.cancel(with: .goingAway, reason: nil)
        client.invalidate()
    }

    func observeChanges(_ observer: @escaping () -> Void) -> () -> Void {
        let id = UUID()
        changeObservers[id] = observer
        return { [weak self] in self?.changeObservers.removeValue(forKey: id) }
    }

    func observeNavigation(_ observer: @escaping () -> Void) -> () -> Void {
        let id = UUID()
        navigationObservers[id] = observer
        return { [weak self] in self?.navigationObservers.removeValue(forKey: id) }
    }

    @discardableResult
    func addChangeObserver(_ observer: @escaping () -> Void) -> UUID {
        let id = UUID(); changeObservers[id] = observer; return id
    }

    @discardableResult
    func addNavigationObserver(_ observer: @escaping () -> Void) -> UUID {
        let id = UUID(); navigationObservers[id] = observer; return id
    }

    var archivedSessionIDsForPresentation: Set<String> {
        archivedSessionIDs
    }

    #if DEBUG
    static func fixture(scene: String = "workspace") -> HarnessRuntime {
        let runtime = HarnessRuntime(baseURL: URL(string: "http://fixture.invalid")!)
        let workspace = HarnessWorkspace(id: "workspace-project", title: "Pocket 项目", path: "/Users/demo/Pocket", sessionIDs: ["session-active", "session-research"])
        let active = HarnessSessionSummary(id: "session-active", title: "原生工作台 V2", cwd: "/Users/demo/Pocket", updatedAt: 200, running: scene == "workspace" || scene == "conversation" || scene == "process", blank: false, preset: "standard", permission: "workspace-write", provider: "deepseek", model: "DeepSeek V4", turns: 4, steps: 12, contextUsed: 0.42, status: "running", stage: "工具调用")
        let research = HarnessSessionSummary(id: "session-research", title: "验收与交付", cwd: "/Users/demo/Pocket/docs", updatedAt: 100, running: false, blank: false, preset: "standard", permission: "read-only", provider: "deepseek", model: "DeepSeek V4", turns: 2, steps: 6, contextUsed: 0.18)
        runtime.connected = true
        runtime.isLoading = false
        runtime.statusText = "已连接"
        runtime.currentStage = scene == "artifacts" ? "已完成" : "工具调用"
        runtime.contextDirectory = "/Users/demo/Pocket"
        runtime.sessions = [active, research]
        runtime.workspaces = [workspace]
        runtime.selectedSessionID = "session-active"
        runtime.isGenerating = scene == "workspace" || scene == "conversation" || scene == "process" || scene == "keyboard"
        runtime.reasoningEffort = "balanced"
        runtime.models = [HarnessModelOption(provider: "deepseek", providerName: "DeepSeek", model: "deepseek-v4", modelName: "DeepSeek V4", reasoning: [["id": "balanced", "name": "均衡"], ["id": "deep", "name": "深入"]])]
        runtime.items = [
            HarnessConversationItem(id: "u1", kind: .user, text: "请继续检查这个 Pocket 工作区。", subtitle: "刚刚", seq: 1, time: 1),
            HarnessConversationItem(id: "a1", kind: .assistant, text: "我会先读取工作区状态，再汇总可以验证的结果。", subtitle: "回答", seq: 2, time: 2, isMarkdown: true),
            HarnessConversationItem(id: "t1", kind: .tool, text: "workspace/list", subtitle: "工具", seq: 3, time: 3, detail: "返回 2 个工作区条目"),
            HarnessConversationItem(id: "r1", kind: .system, text: "分析上下文与执行阶段", subtitle: "轮次", seq: 4, time: 4, detail: "耗时 1.8 s"),
            HarnessConversationItem(id: "e1", kind: .system, text: "本轮完成，产物已由服务端确认。", subtitle: "完成", seq: 5, time: 5)
        ]
        runtime.artifacts = [HarnessArtifact(id: "artifact-1", name: "acceptance-report.md", path: "/Users/demo/Pocket/docs/acceptance-report.md", kind: "file", detail: "服务端确认的交付报告")]
        runtime.pendingApprovals = [HarnessApprovalRequest(clientID: "fixture-client", eventID: "fixture-approval", sessionID: active.id, toolName: "workspace/write", risk: "normal", reason: "更新交付报告", target: "acceptance-report.md", detail: "写入报告内容", arguments: nil)]
        runtime.pendingQuestions = [HarnessPendingQuestion(clientID: "fixture-client", eventID: "fixture-question", questions: [HarnessQuestion(id: "fixture-q", header: "需要确认", question: "是否继续执行下一步？", detail: "这是 Debug-only Pocket UI 夹具状态。", options: [HarnessQuestionOption(label: "继续", description: "继续当前任务"), HarnessQuestionOption(label: "暂停", description: "保留当前状态")], multiSelect: false)])]
        return runtime
    }

    func emitFixtureUpdateForTesting() {
        publish()
    }
    #endif

    func start() {
        isStarted = true
        refresh()
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        isLoading = true
        publish()
        client.bootstrap { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.isRefreshing = false
                switch result {
                case .success:
                    self.clearError()
                    self.loadInitialState()
                case let .failure(error):
                    self.acceptError(error.localizedDescription)
                }
            }
        }
    }

    func openSession(_ id: String) {
        guard sessions.contains(where: { $0.id == id }) else { return }
        cancelFollowStream()
        selectedSessionID = id
        resetConversation()
        publish()
        openSessionStream(id)
    }

    func searchSessions(_ query: String, completion: @escaping (Result<[HarnessSearchResult], Error>) -> Void) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { completion(.success([])); return }
        call("session/search", args: HarnessWire.requestArguments(["query": trimmed])) { value in
            let body = value as? [String: Any] ?? [:]
            let results = (body["items"] as? [[String: Any]] ?? []).compactMap { row -> HarnessSearchResult? in
                guard let id = row["sessionId"] as? String, let snippet = row["snippet"] as? String else { return nil }
                return HarnessSearchResult(sessionID: id, snippet: snippet)
            }
            completion(.success(results))
        } failure: { error in completion(.failure(error)) }
    }

    func updateSettings(namespace: String, operations: [[String: Any]], expectedRevision: Int? = nil, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        var args: [String: Any] = ["ns": namespace, "ops": operations]
        if let expectedRevision { args["expectedRevision"] = expectedRevision }
        call("settings/mutate", args: args) { value in
            let temp = value as? [String: Any] ?? [:]
            let result = temp["value"] as? [String: Any] ?? temp
            completion(.success(result))
        } failure: { error in completion(.failure(error)) }
    }

    func answerQuestion(_ pending: HarnessPendingQuestion, answers: [[String: Any]], completion: ((Result<Void, Error>) -> Void)? = nil) {
        let outcome: [String: Any] = ["kind": "result", "value": ["answers": answers]]
        call("$events/result", args: HarnessWire.eventResult(clientID: pending.clientID, eventID: pending.eventID, outcome: outcome)) { [weak self] _ in
            self?.pendingQuestions.removeAll { $0.eventID == pending.eventID }
            self?.publish()
            completion?(.success(()))
        } failure: { error in completion?(.failure(error)) }
    }

    func cancelQuestion(_ pending: HarnessPendingQuestion, completion: ((Result<Void, Error>) -> Void)? = nil) {
        let outcome: [String: Any] = ["kind": "cancel"]
        call("$events/result", args: HarnessWire.eventResult(clientID: pending.clientID, eventID: pending.eventID, outcome: outcome)) { [weak self] _ in
            self?.pendingQuestions.removeAll { $0.eventID == pending.eventID }
            self?.publish()
            completion?(.success(()))
        } failure: { error in completion?(.failure(error)) }
    }

    func createSession(workspaceID: String?, defaultPermission: String? = nil, completion: ((Result<String, Error>) -> Void)? = nil) {
        var request: [String: Any] = [:]
        if let workspaceID { request["workspaceId"] = workspaceID }
        let createArgs = HarnessWire.requestArguments(request)
        call("session/create", args: createArgs) { [weak self] value in
            guard let self, let dict = value as? [String: Any], let id = dict["sessionId"] as? String else {
                completion?(.failure(HarnessClientError.invalidResponse)); return
            }
            self.refresh()
            self.selectedSessionID = id
            self.resetConversation()
            self.openSessionStream(id)
            if let defaultPermission, !defaultPermission.isEmpty {
                self.setPermission(defaultPermission, sessionID: id) { result in
                    switch result {
                    case .success:
                        completion?(.success(id))
                    case let .failure(error):
                        completion?(.failure(error))
                    }
                }
            } else {
                completion?(.success(id))
            }
        } failure: { error in completion?(.failure(error)) }
    }

    func send(_ text: String, mode: String = "queue", images: [[String: Any]] = [], completion: ((Result<Void, Error>) -> Void)? = nil) {
        guard let sessionID = selectedSessionID else { completion?(.failure(HarnessClientError.invalidResponse)); return }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty else { return }
        var content: [[String: Any]] = []
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            content.append(["type": "text", "text": text])
        }
        content.append(contentsOf: images)
        let request: [String: Any] = [
            "sessionId": sessionID,
            "content": content,
            "mode": mode,
            "clientTimeZone": TimeZone.current.identifier,
            "requestId": UUID().uuidString
        ]
        isGenerating = true
        publish()
        call("session/prompt", args: HarnessWire.requestArguments(request)) { [weak self] _ in
            completion?(.success(())); self?.publish()
        } failure: { [weak self] error in
            completion?(.failure(error)); self?.isGenerating = false; self?.publish()
        }
    }

    func cancel() {
        guard let id = selectedSessionID else { return }
        call("session/cancel", args: HarnessWire.requestArguments(["sessionId": id])) { [weak self] _ in
            self?.isGenerating = false
            self?.publish()
        }
    }

    func loadOlder() {
        guard let id = selectedSessionID, let cursor = sessionCursors[id], cursor.oldest >= 0, hasMore else { return }
        call("session/page", args: HarnessWire.sessionPageArguments(sessionID: id, throughSeq: cursor.cursor, beforeSeq: cursor.oldest, maxMessages: 30)) { [weak self] value in
            guard let self, let page = value as? [String: Any] else { return }
            self.parseRecords(page["records"] as? [Any] ?? [], prepend: true)
            self.hasMore = page["hasMore"] as? Bool ?? false
            self.sessionCursors[id] = (cursor.cursor, self.oldestSeq)
            self.publish()
        }
    }

    func selectModel(_ option: HarnessModelOption, reasoning: String? = nil) {
        guard let id = selectedSessionID else { return }
        var request: [String: Any] = ["sessionId": id, "provider": option.provider, "model": option.model]
        if let reasoning { request["reasoningEffort"] = reasoning }
        call("session/selectModel", args: HarnessWire.requestArguments(request)) { [weak self] _ in self?.refresh() }
    }

    func setPermission(_ value: String, sessionID: String? = nil, completion: ((Result<Void, Error>) -> Void)? = nil) {
        guard let id = sessionID ?? selectedSessionID else { completion?(.failure(HarnessClientError.invalidResponse)); return }
        call("commands/execute", args: HarnessWire.permissionCommandArguments(sessionID: id, value: value)) { [weak self] _ in
            completion?(.success(())); self?.refresh()
        } failure: { error in completion?(.failure(error)) }
    }

    func rename(_ title: String) {
        guard let id = selectedSessionID else { return }
        call("session/rename", args: HarnessWire.requestArguments(["sessionId": id, "title": title])) { [weak self] _ in self?.refresh() }
    }

    func renameWorkspace(_ id: String, title: String) {
        call("workspace/rename", args: HarnessWire.requestArguments(["workspaceId": id, "title": title])) { [weak self] _ in self?.refresh() }
    }

    func deleteWorkspace(_ id: String) {
        call("workspace/delete", args: HarnessWire.requestArguments(["workspaceId": id])) { [weak self] _ in self?.refresh() }
    }

    func archiveSession(_ id: String) {
        call("workspace/archiveSession", args: HarnessWire.requestArguments(["sessionId": id])) { [weak self] _ in self?.refresh() }
    }

    func forkSession(_ id: String) {
        call("session/fork", args: HarnessWire.requestArguments(["sessionId": id])) { [weak self] value in
            guard let self, let result = value as? [String: Any], let newID = result["sessionId"] as? String else { return }
            self.refresh()
            self.selectedSessionID = newID
            self.resetConversation()
            self.openSessionStream(newID)
        }
    }

    func addWorkspace(path: String) {
        call("workspace/create", args: HarnessWire.requestArguments(["path": path])) { [weak self] _ in self?.refresh() }
    }

    func listDirectories(path: String?, completion: @escaping (HarnessDirectoryListing) -> Void, failure: ((Error) -> Void)? = nil) {
        call("directoryPicker/list", args: HarnessWire.directoryListArguments(path: path)) { value in
            guard let object = value as? [String: Any],
                  let listedPath = object["path"] as? String,
                  let home = object["home"] as? String else {
                failure?(HarnessClientError.invalidResponse)
                return
            }
            func entries(_ value: Any?) -> [HarnessDirectoryEntry] {
                (value as? [[String: Any]] ?? []).compactMap { row in
                    guard let name = row["name"] as? String, let path = row["path"] as? String else { return nil }
                    return HarnessDirectoryEntry(name: name, path: path, hidden: row["hidden"] as? Bool ?? name.hasPrefix("."))
                }
            }
            completion(HarnessDirectoryListing(path: listedPath, home: home, crumbs: entries(object["crumbs"]), entries: entries(object["entries"]), truncated: object["truncated"] as? Bool ?? false))
        } failure: { error in
            failure?(error)
        }
    }

    func createDirectory(path: String, name: String, completion: @escaping (String?) -> Void) {
        call("directoryPicker/createDirectory", args: HarnessWire.directoryCreateArguments(path: path, name: name)) { value in
            completion(value as? String ?? (value as? [String: Any])?["path"] as? String)
        } failure: { _ in completion(nil) }
    }

    func answerApproval(clientID: String, eventID: String, decision: String) {
        guard !clientID.isEmpty else { return }
        call("$events/result", args: HarnessWire.eventResult(clientID: clientID, eventID: eventID, outcome: ["kind": "result", "value": decision])) { [weak self] _ in
            self?.pendingApprovals.removeAll { $0.eventID == eventID }
            self?.publish()
        }
    }

    private func loadInitialState() {
        let group = DispatchGroup()
        var sessionsValue: Any?
        var modelsValue: Any?
        var failed: Error?
        group.enter()
        call("session/list", args: HarnessWire.sessionListArguments()) { value in sessionsValue = value; group.leave() } failure: { error in failed = error; group.leave() }
        group.enter()
        call("session/modelCatalog", args: [:]) { value in modelsValue = value; group.leave() } failure: { error in failed = error; group.leave() }
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            if let failed { self.acceptError(failed.localizedDescription); return }
            self.applySessions(sessionsValue)
            self.applyModels(modelsValue)
            self.connected = true
            self.isLoading = false
            self.statusText = "已连接"
            self.openMuxStreams()
            self.publish()
        }
    }

    private func applySessions(_ value: Any?) {
        guard let object = value as? [String: Any], let rows = object["items"] as? [[String: Any]] else { return }
        let previousSelection = selectedSessionID
        sessions = rows.compactMap(Self.session)
        if let previousSelection, sessions.contains(where: { $0.id == previousSelection }) {
            selectedSessionID = previousSelection
        } else {
            selectedSessionID = sessions.first(where: { !$0.blank })?.id ?? sessions.first?.id
        }
        if let id = selectedSessionID, id != previousSelection { resetConversation(); openSessionStream(id) }
    }

    private func applyModels(_ value: Any?) {
        guard let object = value as? [String: Any], let groups = object["groups"] as? [[String: Any]] else { return }
        models = groups.flatMap { (group: [String: Any]) -> [HarnessModelOption] in
            let provider = group["id"] as? String ?? ""
            let providerName = group["name"] as? String ?? provider
            return (group["models"] as? [[String: Any]] ?? []).compactMap { (model: [String: Any]) -> HarnessModelOption? in
                guard let id = model["id"] as? String else { return nil }
                let efforts: [[String: String]] = ((model["reasoning"] as? [String: Any])?["efforts"] as? [[String: Any]] ?? []).compactMap { effort -> [String: String]? in
                    guard let effortID = effort["id"] as? String else { return nil }
                    return ["id": effortID, "name": effort["name"] as? String ?? effortID]
                }
                return HarnessModelOption(provider: provider, providerName: providerName, model: id, modelName: model["name"] as? String ?? id, reasoning: efforts)
            }
        }
    }

    private func refreshWorkspace(_ value: Any?) {
        guard let frame = value as? [String: Any], frame["type"] as? String == "baseline",
              let body = frame["value"] as? [String: Any] else { return }
        let rows = (body["items"] as? [[String: Any]] ?? []).compactMap(Self.workspace)
        workspacesByID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        workspaceOrder = rows.map(\.id)
        archivedSessionIDs = Set(body["archivedSessionIds"] as? [String] ?? [])
        rebuildWorkspaces()
    }

    private func openMuxStreams() {
        streamGeneration += 1
        let generation = streamGeneration
        receiveTask?.cancel()
        socket?.cancel(with: .goingAway, reason: nil)
        followStreamID = nil
        workspaceStreamID = "workspace-\(UUID().uuidString)"
        controlStreamID = "control-\(UUID().uuidString)"
        eventsStreamID = "events-\(UUID().uuidString)"
        eventClientID = nil
        guard let request = client.webSocketRequest() else {
            acceptError("无法建立 Harness 实时连接。")
            return
        }
        let task = client.webSocketTask(with: request)
        socket = task
        task.resume()
        let workspaceID = workspaceStreamID!
        let controlID = controlStreamID!
        let eventsID = eventsStreamID!
        receiveTask = Task.detached { [weak self, weak task] in
            guard let self, let task else { return }
            do {
                try await self.subscribe(task, streamID: workspaceID, endpoint: "workspace/follow", payload: ["args": [:]])
                try await self.subscribe(task, streamID: controlID, endpoint: "session/control", payload: ["args": [:]])
                try await self.subscribe(task, streamID: eventsID, endpoint: "$events", payload: ["args": [:]])
                let selectedID = await MainActor.run { self.selectedSessionID }
                if let id = selectedID {
                    let followID = "follow-\(UUID().uuidString)"
                    await MainActor.run { self.followStreamID = followID }
                    let payload = HarnessWire.sessionFollowPayload(sessionID: id)
                    try await self.subscribe(task, streamID: followID, endpoint: "session/follow", payload: payload)
                }
                while !Task.isCancelled {
                    let message = try await task.receive()
                    guard case let .string(text) = message else { continue }
                    await MainActor.run { self.acceptSocketMessage(text, generation: generation) }
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run { self.socketLost(generation: generation, message: error.localizedDescription) }
                }
            }
        }
    }

    private func followRequest(_ id: String) -> [String: Any] {
        ["address": ["kind": "session", "sessionId": id], "maxMessages": 50]
    }

    private func subscribe(_ socket: URLSessionWebSocketTask, streamID: String, endpoint: String, payload: [String: Any]) async throws {
        let object = HarnessWire.muxOpen(streamID: streamID, endpoint: endpoint, payload: payload)
        let data = try JSONSerialization.data(withJSONObject: object)
        guard let text = String(data: data, encoding: .utf8) else { throw HarnessClientError.invalidResponse }
        try await socket.send(.string(text))
    }

    private func openSessionStream(_ id: String) {
        guard let socket, socket.state == .running else { return }
        if let oldID = followStreamID { sendMuxCancel(socket, streamID: oldID) }
        let streamID = "follow-\(UUID().uuidString)"
        followStreamID = streamID
        let request = HarnessWire.muxOpen(streamID: streamID, endpoint: "session/follow", payload: HarnessWire.sessionFollowPayload(sessionID: id))
        guard let data = try? JSONSerialization.data(withJSONObject: request), let text = String(data: data, encoding: .utf8) else { return }
        socket.send(.string(text), completionHandler: { _ in })
    }

    private func cancelFollowStream() {
        guard let socket, let streamID = followStreamID else { return }
        sendMuxCancel(socket, streamID: streamID)
        followStreamID = nil
    }

    private func sendMuxCancel(_ socket: URLSessionWebSocketTask, streamID: String) {
        let object = HarnessWire.muxCancel(streamID: streamID)
        guard let data = try? JSONSerialization.data(withJSONObject: object), let text = String(data: data, encoding: .utf8) else { return }
        socket.send(.string(text), completionHandler: { _ in })
    }

    private func acceptSocketMessage(_ text: String, generation: Int) {
        guard generation == streamGeneration,
              let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { return }
        if object["type"] as? String == "error" {
            let error = object["error"] as? [String: Any]
            acceptError(error?["message"] as? String ?? "Harness 实时连接失败")
            return
        }
        guard object["type"] as? String == "item", let streamID = object["streamId"] as? String else { return }
        switch streamID {
        case followStreamID: acceptFollow(object["value"])
        case workspaceStreamID: acceptWorkspace(object["value"])
        case controlStreamID: acceptControl(object["value"])
        case eventsStreamID: acceptRemoteEvent(object["value"])
        default: break
        }
    }

    private func acceptWorkspace(_ value: Any?) {
        guard let object = value as? [String: Any] else { return }
        if object["type"] as? String == "baseline" { refreshWorkspace(object); publish(); return }
        switch object["type"] as? String {
        case "upsert":
            if let workspace = Self.workspace(object["workspace"] as? [String: Any] ?? [:]) { workspacesByID[workspace.id] = workspace; rebuildWorkspaces() }
        case "remove":
            if let id = object["workspaceId"] as? String { workspacesByID.removeValue(forKey: id); workspaceOrder.removeAll { $0 == id }; rebuildWorkspaces() }
        case "order": workspaceOrder = object["workspaceIds"] as? [String] ?? workspaceOrder; rebuildWorkspaces()
        case "archived": archivedSessionIDs = Set(object["archivedSessionIds"] as? [String] ?? []); rebuildWorkspaces()
        default: break
        }
        publish()
    }

    private func acceptControl(_ value: Any?) {
        guard let object = value as? [String: Any] else { return }
        if object["type"] as? String == "baseline", let body = object["value"] as? [String: Any] {
            if let projections = body["projections"] as? [String: Any] {
                for (id, block) in projections { controlProjection[id] = (block as? [String: Any])?["values"] as? [String: Any] ?? [:] }
            }
            updateGeneration(body["jobs"] as? [String: Any], queues: body["queues"] as? [String: Any])
            if let id = selectedSessionID, let projection = controlProjection[id] { for (key, value) in projection { applyRuntimeProjection(id, key: key, value: value) } }
        } else if object["type"] as? String == "projection", let id = object["sessionId"] as? String, let key = object["key"] as? String {
            var values = controlProjection[id] ?? [:]
            values[key] = object["value"]
            controlProjection[id] = values
            applyProjection(id, key: key, value: object["value"])
            applyRuntimeProjection(id, key: key, value: object["value"])
        } else if object["type"] as? String == "jobs", let id = object["sessionId"] as? String {
            let jobs = object["jobs"] as? [[String: Any]] ?? []
            let active = jobs.first(where: { ($0["status"] as? String) == "running" || ($0["status"] as? String) == "waiting" })
            isGenerating = id == selectedSessionID && jobs.contains { $0["status"] as? String == "running" }
            if id == selectedSessionID {
                currentStage = active?["stage"] as? String ?? active?["phase"] as? String ?? active?["name"] as? String
                if let status = active?["status"] as? String { statusText = status == "waiting" ? "等待你的介入" : "运行中" }
            }
        }
        publish()
    }

    private func updateGeneration(_ jobs: [String: Any]?, queues: [String: Any]?) {
        guard let id = selectedSessionID else { return }
        let rows = jobs?[id] as? [[String: Any]] ?? []
        let queue = queues?[id] as? [[String: Any]] ?? []
        isGenerating = rows.contains { $0["status"] as? String == "running" } || !queue.isEmpty
    }

    private func acceptFollow(_ value: Any?) {
        guard let object = value as? [String: Any] else { return }
        if object["type"] as? String == "snapshot" {
            resetConversation()
            selectedCursor = (object["cursor"] as? NSNumber)?.intValue ?? -1
            hasMore = object["hasMore"] as? Bool ?? false
            if let id = selectedSessionID { sessionCursors[id] = (selectedCursor, -1) }
            if let projections = object["projections"] as? [String: Any], let id = selectedSessionID {
                controlProjection[id] = projections["values"] as? [String: Any] ?? [:]
                applyAllProjections(id)
            }
            parseRecords(object["records"] as? [Any] ?? [], prepend: false)
            if let id = selectedSessionID { sessionCursors[id] = (selectedCursor, oldestSeq) }
        } else {
            parseRecords([value as Any], prepend: false)
        }
        isGenerating = items.last?.kind == .assistant && items.last?.subtitle == "生成中"
        publish()
    }

    private func acceptRemoteEvent(_ value: Any?) {
        guard let object = value as? [String: Any], let type = object["type"] as? String else { return }
        if type == "ready" {
            eventClientID = object["clientId"] as? String
            return
        }
        guard type == "waterfall",
              let clientID = eventClientID,
              let eventID = object["eventId"] as? String,
              !eventID.isEmpty,
              let request = object["request"] as? [String: Any] else { return }
        if let rawQuestions = request["questions"] as? [[String: Any]] {
            let questions = rawQuestions.compactMap { raw -> HarnessQuestion? in
                guard let id = raw["id"] as? String, let question = raw["question"] as? String else { return nil }
                let options = (raw["options"] as? [[String: Any]] ?? []).compactMap { option -> (label: String, description: String?)? in
                    guard let label = option["label"] as? String else { return nil }
                    return (label: label, description: option["description"] as? String)
                }
                return HarnessQuestion(id: id, header: raw["header"] as? String, question: question, detail: raw["detail"] as? String, options: options.map { HarnessQuestionOption(label: $0.label, description: $0.description) }, multiSelect: raw["multiSelect"] as? Bool ?? false)
            }
            if !questions.isEmpty {
                let pending = HarnessPendingQuestion(clientID: clientID, eventID: eventID, questions: questions)
                if !pendingQuestions.contains(where: { $0.eventID == eventID }) { pendingQuestions.append(pending) }
                onQuestion?(pending)
            }
            return
        }
        var approval = object
        approval["clientId"] = clientID
        approval["request"] = request
        let pending = Self.approval(value: approval)
        if let pending, !pendingApprovals.contains(where: { $0.eventID == pending.eventID }) { pendingApprovals.append(pending) }
        onApproval?(approval)
    }

    private func parseRecords(_ records: [Any], prepend: Bool) {
        let sequence: [Any] = prepend ? records : records.reversed()
        for raw in sequence { parseRecord(raw) }
        items = liveOrder.compactMap { liveItems[$0] }.sorted { $0.seq < $1.seq }
        oldestSeq = items.map(\.seq).filter { $0 >= 0 }.min() ?? oldestSeq
    }

    private func parseRecord(_ raw: Any) {
        guard let row = raw as? [String: Any] else { return }
        if row["type"] as? String == "chunks", let event = row["event"] as? [String: Any] { parseEvent(event); return }
        if let event = row["event"] as? [String: Any] { parseEvent(event) }
    }

    private func parseEvent(_ event: [String: Any]) {
        guard let type = event["type"] as? String else { return }
        let seq = (event["seq"] as? NSNumber)?.intValue ?? -1
        let eventID = event["eventId"] as? String ?? "\(seq):\(type)"
        guard seenEventIDs.insert(eventID).inserted else { return }
        if seq >= 0 { oldestSeq = oldestSeq < 0 ? seq : min(oldestSeq, seq) }
        let data = event["data"] as? [String: Any] ?? [:]
        let time = (event["time"] as? NSNumber)?.doubleValue ?? 0
        switch type {
        case "user/message":
            if let text = contentText(data["content"] ?? data["message"]), !text.isEmpty { upsert(HarnessConversationItem(id: eventID, kind: .user, text: text, subtitle: nil, seq: seq, time: time, isMarkdown: false)) }
        case "assistant/message":
            let message = data["message"] as? [String: Any] ?? data
            if let text = contentText(message["content"]), !text.isEmpty { upsert(HarnessConversationItem(id: eventID, kind: .assistant, text: text, subtitle: nil, seq: seq, time: time, isMarkdown: true)) }
        case "tool/call":
            let name = data["name"] as? String ?? "工具调用"
            let detail = data["arguments"] as? String ?? stringify(data["arguments"])
            upsert(HarnessConversationItem(id: eventID, kind: .tool, text: name, subtitle: "调用", seq: seq, time: time, detail: detail))
        case "tool/result":
            let message = data["message"] as? [String: Any]
            let resultText = contentText(message?["content"]) ?? "工具结果"
            let resultKind = (message?["isError"] as? Bool == true) ? "错误" : "结果"
            upsert(HarnessConversationItem(id: eventID, kind: .tool, text: resultText, subtitle: resultKind, seq: seq, time: time, detail: data["callId"] as? String))
        case "artifact", "file/created", "file/updated", "file/output", "attachment/created":
            if let artifact = Self.artifact(data: data, eventID: eventID) {
                artifactsByID[artifact.id] = artifact
                upsert(HarnessConversationItem(id: eventID, kind: .system, text: artifact.name, subtitle: "产物", seq: seq, time: time, detail: artifact.path))
            }
        case "command/done":
            if let result = data["result"] as? [String: Any], let text = result["text"] as? String { upsert(HarnessConversationItem(id: eventID, kind: .system, text: text, subtitle: result["kind"] as? String ?? "指令结果", seq: seq, time: time)) }
        case "turn/start":
            upsert(HarnessConversationItem(id: eventID, kind: .system, text: "第\((data["turn"] as? NSNumber)?.intValue ?? 0) 轮开始", subtitle: "轮次", seq: seq, time: time))
        case "turn/end":
            if let reason = data["reason"] as? [String: Any] { upsert(HarnessConversationItem(id: eventID, kind: .system, text: "本轮结束", subtitle: reason["kind"] as? String ?? "完成", seq: seq, time: time)) }
        case "chunkrow/text-chunks", "chunkrow/reasoning-chunks", "assistant/chunk": parseChunk(data, seq: seq, time: time, key: eventID)
        default:
            if type.contains("error") { upsert(HarnessConversationItem(id: eventID, kind: .system, text: data["message"] as? String ?? type, subtitle: "错误", seq: seq, time: time)) }
        }
    }

    private func parseChunk(_ data: [String: Any], seq: Int, time: Double, key: String) {
        let chunk = data["chunk"] as? [String: Any] ?? data
        let text = chunk["text"] as? String ?? chunk["content"] as? String ?? ""
        guard !text.isEmpty else { return }
        let reasoning = (chunk["type"] as? String)?.contains("reasoning") == true || key.contains("reasoning")
        let id = "live:\(reasoning ? "reasoning" : "assistant")"
        let existing = liveItems[id]?.text ?? ""
        upsert(HarnessConversationItem(id: id, kind: reasoning ? .system : .assistant, text: existing + text, subtitle: reasoning ? "思考中" : "生成中", seq: seq, time: time))
    }

    private func contentText(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let blocks = value as? [[String: Any]] {
            return blocks.compactMap { block in
                switch block["type"] as? String {
                case "text": return block["text"] as? String
                case "image": return "[图片] \(block["name"] as? String ?? "")"
                case "tool-result": return contentText(block["content"])
                case "reasoning": return "思考：\(block["text"] as? String ?? "")"
                default: return nil
                }
            }.filter { !$0.isEmpty }.joined(separator: "\n")
        }
        return nil
    }

    private func upsert(_ item: HarnessConversationItem) {
        if liveItems[item.id] == nil { liveOrder.append(item.id) }
        liveItems[item.id] = item
    }

    private func resetConversation() {
        items = []
        liveItems.removeAll()
        liveOrder.removeAll()
        artifactsByID.removeAll()
        artifacts = []
        currentStage = nil
        contextDirectory = nil
        reasoningEffort = nil
        seenEventIDs.removeAll()
        selectedCursor = -1
        oldestSeq = -1
        hasMore = false
        isGenerating = false
    }

    private func applyAllProjections(_ id: String) {
        for (key, value) in controlProjection[id] ?? [:] { applyProjection(id, key: key, value: value) }
    }

    private func applyProjection(_ id: String, key: String, value: Any?) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        var session = sessions[index]
        switch key {
        case "title": session.title = value as? String ?? session.title
        case "agentPreset": session.preset = value as? String ?? session.preset
        case "permissions": session.permission = (value as? [String: Any])?["currentValue"] as? String ?? session.permission
        case "sessionStats":
            if let v = value as? [String: Any] { session.turns = (v["turns"] as? NSNumber)?.intValue ?? session.turns; session.steps = (v["steps"] as? NSNumber)?.intValue ?? session.steps }
        case "contextPressure":
            if let v = value as? [String: Any], let window = (v["contextWindow"] as? NSNumber)?.doubleValue, window > 0 { session.contextUsed = ((v["pressureTokens"] as? NSNumber)?.doubleValue ?? 0) / window }
        case "modelSelection":
            let selected = (value as? [String: Any])?["next"] as? [String: Any] ?? (value as? [String: Any])?["lastUsed"] as? [String: Any] ?? [:]
            session.provider = selected["provider"] as? String ?? session.provider
            session.model = selected["model"] as? String ?? session.model
        default: break
        }
        sessions[index] = session
    }

    private func rebuildWorkspaces() {
        let ordered = workspaceOrder.compactMap { workspacesByID[$0] }
        workspaces = ordered
    }

    private func applyRuntimeProjection(_ id: String, key: String, value: Any?) {
        guard id == selectedSessionID else { return }
        switch key {
        case "currentStage", "stage", "phase": currentStage = value as? String ?? currentStage
        case "reasoningEffort": reasoningEffort = value as? String ?? reasoningEffort
        case "contextDirectory", "cwd": contextDirectory = value as? String ?? contextDirectory
        case "artifacts", "outputs":
            let rows = (value as? [[String: Any]] ?? []).compactMap { Self.artifact(data: $0, eventID: UUID().uuidString) }
            artifactsByID.merge(rows.map { ($0.id, $0) }, uniquingKeysWith: { _, next in next })
        default: break
        }
    }

    private func stringify(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let text = value as? String { return text }
        guard JSONSerialization.isValidJSONObject(value), let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted]), let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }


    private func call(_ endpoint: String, args: [String: Any], completion: ((Any?) -> Void)? = nil, failure: ((Error) -> Void)? = nil) {
        client.call(endpoint: endpoint, args: args) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case let .success(value): completion?(value)
                case let .failure(error):
                    self.acceptError(error.localizedDescription)
                    failure?(error)
                }
            }
        }
    }

    private func clearError() {
        lastError = nil
        connected = false
        statusText = "正在读取"
    }

    private func acceptError(_ text: String) {
        lastError = text
        isLoading = false
        connected = false
        statusText = "连接异常"
        publish()
    }

    private func publish() {
        artifacts = Array(artifactsByID.values).sorted { $0.id < $1.id }
        let changes = Array(changeObservers.values)
        let navigation = Array(navigationObservers.values)
        changes.forEach { $0() }
        navigation.forEach { $0() }
    }

    private func socketLost(generation: Int, message: String) {
        guard generation == streamGeneration else { return }
        connected = false
        statusText = "实时连接已断开：\(message)"
        publish()
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            self?.reconnect()
        }
    }

    private func reconnect() {
        guard isStarted else { return }
        openMuxStreams()
    }
}

private extension HarnessRuntime {
    static func session(_ value: [String: Any]) -> HarnessSessionSummary? {
        guard let id = value["sessionId"] as? String else { return nil }
        let projections = value["projections"] as? [String: Any]
        let values = projections?["values"] as? [String: Any] ?? [:]
        let metadata = values["sessionListMetadata"] as? [String: Any]
        return HarnessSessionSummary(
            id: id,
            title: metadata?["title"] as? String ?? "新会话",
            cwd: value["cwd"] as? String ?? "",
            updatedAt: (value["updatedAt"] as? NSNumber)?.doubleValue ?? 0,
            running: value["running"] as? Bool ?? false,
            blank: metadata?["blank"] as? Bool ?? value["blank"] as? Bool ?? false,
            preset: value["agentPreset"] as? String ?? "standard",
            permission: "",
            provider: "",
            model: "",
            turns: 0,
            steps: 0,
            contextUsed: nil,
            status: value["status"] as? String ?? ((value["running"] as? Bool ?? false) ? "running" : "idle"),
            stage: value["stage"] as? String
        )
    }

    static func artifact(data: [String: Any], eventID: String) -> HarnessArtifact? {
        let source = (data["artifact"] as? [String: Any]) ?? data
        guard let name = source["name"] as? String ?? source["filename"] as? String,
              let path = source["path"] as? String ?? source["url"] as? String else { return nil }
        return HarnessArtifact(id: source["id"] as? String ?? eventID, name: name, path: path, kind: source["kind"] as? String ?? "file", detail: source["detail"] as? String)
    }

    static func approval(value: [String: Any]) -> HarnessApprovalRequest? {
        guard let clientID = value["clientId"] as? String, let eventID = value["eventId"] as? String else { return nil }
        let request = value["request"] as? [String: Any] ?? [:]
        return HarnessApprovalRequest(clientID: clientID, eventID: eventID, sessionID: request["sessionId"] as? String, toolName: request["toolName"] as? String ?? "未知工具", risk: request["risk"] as? String ?? "unknown", reason: request["reason"] as? String, target: request["target"] as? String ?? request["path"] as? String, detail: request["command"] as? String ?? request["input"] as? String, arguments: stringify(request["arguments"]))
    }

    static func stringify(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let text = value as? String { return text }
        guard JSONSerialization.isValidJSONObject(value), let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted]), let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }

    static func workspace(_ value: [String: Any]) -> HarnessWorkspace? {
        guard let id = value["workspaceId"] as? String else { return nil }
        return HarnessWorkspace(id: id, title: value["title"] as? String ?? "工作区", path: value["path"] as? String ?? "", sessionIDs: value["sessionIds"] as? [String] ?? [])
    }
}
