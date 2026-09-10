import Foundation
import UIKit

struct HarnessReasoningEffort: Equatable {
    let id: String
    let name: String
    let description: String?

    init(id: String, name: String, description: String? = nil) {
        self.id = id
        self.name = name
        self.description = description
    }

    /// Compatibility read-only view for the pre-typed UI call sites. The
    /// stored representation remains typed and never uses a string dictionary.
    subscript(_ key: String) -> String? {
        switch key {
        case "id": return id
        case "name": return name
        case "description": return description
        default: return nil
        }
    }
}

struct HarnessModelSelection: Equatable {
    let provider: String
    let model: String
    let reasoningEffort: String?

    init(provider: String, model: String, reasoningEffort: String? = nil) {
        self.provider = provider
        self.model = model
        self.reasoningEffort = reasoningEffort
    }
}

struct HarnessModelSelectionProjection: Equatable {
    let next: HarnessModelSelection?
    let lastUsed: HarnessModelSelection?

    init(next: HarnessModelSelection?, lastUsed: HarnessModelSelection?) {
        self.next = next
        self.lastUsed = lastUsed
    }
}

struct HarnessPermissionOption: Equatable {
    let value: String
    let name: String
    let description: String?

    init(value: String, name: String, description: String? = nil) {
        self.value = value
        self.name = name
        self.description = description
    }
}

struct HarnessPermissionSelect: Equatable {
    let options: [HarnessPermissionOption]
    let currentValue: String

    init(options: [HarnessPermissionOption], currentValue: String) {
        self.options = options
        self.currentValue = currentValue
    }
}

struct HarnessContextPressure: Equatable {
    let pressureTokens: Int?
    let projectedTokens: Int?
    let contextWindow: Int?

    init(pressureTokens: Int? = nil, projectedTokens: Int? = nil, contextWindow: Int? = nil) {
        self.pressureTokens = pressureTokens
        self.projectedTokens = projectedTokens
        self.contextWindow = contextWindow
    }

    var numerator: Int? {
        projectedTokens ?? pressureTokens
    }

    var contextUsed: Double? {
        guard let numerator, let contextWindow, contextWindow > 0 else { return nil }
        return Double(numerator) / Double(contextWindow)
    }
}

struct HarnessContextBreakdown: Equatable {
    let systemTokens: Int?
    let toolsTokens: Int?
    let messageTokens: Int?

    init(systemTokens: Int? = nil, toolsTokens: Int? = nil, messageTokens: Int? = nil) {
        self.systemTokens = systemTokens
        self.toolsTokens = toolsTokens
        self.messageTokens = messageTokens
    }
}

struct HarnessContextSnapshot: Equatable {
    let sessionID: String
    let pressure: HarnessContextPressure?
    let breakdown: HarnessContextBreakdown?

    init(sessionID: String, pressure: HarnessContextPressure? = nil, breakdown: HarnessContextBreakdown? = nil) {
        self.sessionID = sessionID
        self.pressure = pressure
        self.breakdown = breakdown
    }

    var contextUsed: Double? {
        pressure?.contextUsed
    }
}

struct HarnessModelOption: Equatable {
    let provider: String
    let providerName: String
    let model: String
    let modelName: String
    let description: String?
    let reasoning: [HarnessReasoningEffort]
    let defaultEffort: String?

    init(
        provider: String,
        providerName: String,
        model: String,
        modelName: String,
        description: String? = nil,
        reasoning: [HarnessReasoningEffort] = [],
        defaultEffort: String? = nil
    ) {
        self.provider = provider
        self.providerName = providerName
        self.model = model
        self.modelName = modelName
        self.description = description
        self.reasoning = reasoning
        self.defaultEffort = defaultEffort
    }

    var key: String { "\(provider)/\(model)" }
}

struct HarnessModelProviderGroup: Equatable {
    let id: String
    let name: String
    let models: [HarnessModelOption]

    init(id: String, name: String, models: [HarnessModelOption]) {
        self.id = id
        self.name = name
        self.models = models
    }
}

struct HarnessModelCatalogFailure: Equatable {
    let id: String
    let name: String
    let message: String

    init(id: String, name: String, message: String) {
        self.id = id
        self.name = name
        self.message = message
    }
}

struct HarnessModelCatalog: Equatable {
    /// The server's declared deployment default. It is never inferred from a group.
    let defaultSelection: HarnessModelSelection?
    /// Nil means the server omitted/invalidated the field; an empty array is a
    /// real server-provided empty capability and is retained as such.
    let routableProviders: [String]?
    let groups: [HarnessModelProviderGroup]
    /// Nil means the server omitted/invalidated failures; [] means no failures.
    let failures: [HarnessModelCatalogFailure]?

    init(
        defaultSelection: HarnessModelSelection?,
        routableProviders: [String]?,
        groups: [HarnessModelProviderGroup],
        failures: [HarnessModelCatalogFailure]?
    ) {
        self.defaultSelection = defaultSelection
        self.routableProviders = routableProviders
        self.groups = groups
        self.failures = failures
    }

    /// Backing-name alias for callers matching the official wire vocabulary.
    var `default`: HarnessModelSelection? { defaultSelection }
}

enum HarnessProjectionParser {
    static func modelCatalog(_ value: Any?) -> HarnessModelCatalog? {
        guard let object = dictionary(value) else { return nil }
        let groups = (object["groups"] as? [[String: Any]] ?? []).compactMap(modelProviderGroup)
        let routableProviders = stringArray(object["routableProviders"])
        let failures: [HarnessModelCatalogFailure]?
        if object.keys.contains("failures") {
            failures = (object["failures"] as? [[String: Any]])?.compactMap(modelCatalogFailure)
        } else {
            failures = nil
        }
        return HarnessModelCatalog(
            defaultSelection: modelSelection(object["default"]),
            routableProviders: routableProviders,
            groups: groups,
            failures: failures
        )
    }

    static func modelSelection(_ value: Any?) -> HarnessModelSelection? {
        guard let object = dictionary(value),
              let provider = nonEmptyString(object["provider"]),
              let model = nonEmptyString(object["model"]) else { return nil }
        let reasoningEffort = nonEmptyString(object["reasoningEffort"])
        return HarnessModelSelection(provider: provider, model: model, reasoningEffort: reasoningEffort)
    }

    static func modelSelectionProjection(_ value: Any?) -> HarnessModelSelectionProjection? {
        guard let object = dictionary(value) else { return nil }
        let hasNestedShape = object.keys.contains("next") || object.keys.contains("lastUsed")
        if hasNestedShape {
            return HarnessModelSelectionProjection(
                next: modelSelection(object["next"]),
                lastUsed: modelSelection(object["lastUsed"])
            )
        }
        guard let flat = modelSelection(object) else { return nil }
        // Older Harness hosts exposed the selection itself rather than the
        // projection wrapper. Keep that compatibility shape explicit.
        return HarnessModelSelectionProjection(next: flat, lastUsed: flat)
    }

    static func permissionSelect(_ value: Any?) -> HarnessPermissionSelect? {
        guard let object = dictionary(value),
              object.keys.contains("options"),
              let rows = object["options"] as? [[String: Any]],
              let currentValue = nonEmptyString(object["currentValue"]) else { return nil }
        let options = rows.compactMap(permissionOption)
        return HarnessPermissionSelect(options: options, currentValue: currentValue)
    }

    static func contextPressure(_ value: Any?) -> HarnessContextPressure? {
        guard let object = dictionary(value) else { return nil }
        return HarnessContextPressure(
            pressureTokens: integer(object["pressureTokens"]),
            projectedTokens: integer(object["projectedTokens"]),
            contextWindow: integer(object["contextWindow"])
        )
    }

    static func contextBreakdown(_ value: Any?) -> HarnessContextBreakdown? {
        guard let object = dictionary(value) else { return nil }
        return HarnessContextBreakdown(
            systemTokens: integer(object["systemTokens"]),
            toolsTokens: integer(object["toolsTokens"]),
            messageTokens: integer(object["messageTokens"])
        )
    }

    private static func modelProviderGroup(_ value: [String: Any]) -> HarnessModelProviderGroup? {
        guard let id = nonEmptyString(value["id"]) else { return nil }
        let name = string(value["name"]) ?? id
        let models = (value["models"] as? [[String: Any]] ?? []).compactMap {
            modelOption($0, provider: id, providerName: name)
        }
        return HarnessModelProviderGroup(id: id, name: name, models: models)
    }

    private static func modelOption(
        _ value: [String: Any],
        provider: String,
        providerName: String
    ) -> HarnessModelOption? {
        guard let model = nonEmptyString(value["id"]) else { return nil }
        let modelName = string(value["name"]) ?? model
        let reasoningObject = dictionary(value["reasoning"])
        let efforts = (reasoningObject?["efforts"] as? [[String: Any]] ?? []).compactMap { effort -> HarnessReasoningEffort? in
            guard let id = nonEmptyString(effort["id"]) else { return nil }
            return HarnessReasoningEffort(id: id, name: string(effort["name"]) ?? id, description: string(effort["description"]))
        }
        return HarnessModelOption(
            provider: provider,
            providerName: providerName,
            model: model,
            modelName: modelName,
            description: string(value["description"]),
            reasoning: efforts,
            defaultEffort: string(reasoningObject?["defaultEffort"])
        )
    }

    private static func permissionOption(_ value: [String: Any]) -> HarnessPermissionOption? {
        guard let optionValue = nonEmptyString(value["value"]),
              let name = nonEmptyString(value["name"]) else { return nil }
        return HarnessPermissionOption(value: optionValue, name: name, description: string(value["description"]))
    }

    private static func modelCatalogFailure(_ value: [String: Any]) -> HarnessModelCatalogFailure? {
        guard let id = nonEmptyString(value["id"]),
              let name = nonEmptyString(value["name"]),
              let message = nonEmptyString(value["message"]) else { return nil }
        return HarnessModelCatalogFailure(id: id, name: name, message: message)
    }

    private static func dictionary(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    private static func string(_ value: Any?) -> String? {
        value as? String
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let value = string(value) else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func stringArray(_ value: Any?) -> [String]? {
        guard let values = value as? [Any] else { return nil }
        guard values.allSatisfy({ $0 is String }) else { return nil }
        return values.compactMap { nonEmptyString($0) }
    }

    private static func integer(_ value: Any?) -> Int? {
        guard !(value is Bool), let number = value as? NSNumber else { return nil }
        let double = number.doubleValue
        guard double.isFinite, double >= 0, double.rounded(.towardZero) == double,
              double <= Double(Int.max) else { return nil }
        return Int(double)
    }
}

struct HarnessSessionSummary {
    let id: String
    var title: String
    var cwd: String
    var updatedAt: Double
    var running: Bool
    var blank: Bool
    var preset: String
    var permission: String
    var provider: String
    var model: String
    var turns: Int
    var steps: Int
    var contextUsed: Double?
    var status: String = "idle"
    var stage: String? = nil
}

struct HarnessArtifact: Equatable {
    let id: String
    let name: String
    let path: String
    let kind: String
    let detail: String?
}

struct HarnessApprovalRequest: Equatable {
    let clientID: String
    let eventID: String
    let sessionID: String?
    let toolName: String
    let risk: String
    let reason: String?
    let target: String?
    let detail: String?
    let arguments: String?

    var isHighRisk: Bool {
        let combined = [risk, toolName, detail ?? "", target ?? ""].joined(separator: " ").lowercased()
        return combined.contains("high") || combined.contains("danger") || combined.contains("shell") || combined.contains("write") || combined.contains("external")
    }
}

struct HarnessConversationItem {
    enum Kind: String { case user, assistant, tool, system }
    let id: String
    let kind: Kind
    var text: String
    var subtitle: String?
    let seq: Int
    let time: Double
    var detail: String? = nil
    var isMarkdown: Bool = false
}

struct HarnessWorkspace {
    let id: String
    let title: String
    let path: String
    let sessionIDs: [String]
}

struct HarnessSessionSection {
    let workspaceID: String?
    let title: String
    let sessions: [HarnessSessionSummary]
}

struct HarnessSearchResult: Equatable {
    let sessionID: String
    let snippet: String
}

struct HarnessQuestionOption: Equatable {
    let label: String
    let description: String?
}

struct HarnessQuestion: Equatable {
    let id: String
    let header: String?
    let question: String
    let detail: String?
    let options: [HarnessQuestionOption]
    let multiSelect: Bool
}

struct HarnessPendingQuestion: Equatable {
    let clientID: String
    let eventID: String
    let questions: [HarnessQuestion]
}

enum HarnessThemePreference: String, CaseIterable {
    case system, light, dark
}

enum HarnessTranscriptView: String, CaseIterable {
    case compact, normal
}

enum HarnessBusyEnterBehavior: String, CaseIterable {
    case queue, steer

    static func sendMode(for behavior: HarnessBusyEnterBehavior, isGenerating: Bool, commandModified: Bool) -> String {
        guard isGenerating else { return HarnessBusyEnterBehavior.queue.rawValue }
        if commandModified { return behavior == .queue ? HarnessBusyEnterBehavior.steer.rawValue : HarnessBusyEnterBehavior.queue.rawValue }
        return behavior.rawValue
    }
}

struct HarnessClientSettings: Equatable {
    var theme: HarnessThemePreference = .system
    var fontSize: Int = 14
    var codeFontSize: Int = 14
    var transcriptView: HarnessTranscriptView = .compact
    var busyEnter: HarnessBusyEnterBehavior = .queue
    var defaultPermission: String = "read-only"
    var defaultModel: String = ""
    var defaultWorkspaceID: String = ""
    var reduceMotion = false
    var notifyFinished = true
    var notifyApproval = true
    var notifyQuestion = true
    static let defaults = HarnessClientSettings()
}

struct HarnessViewPreferences: Equatable {
    enum GroupBy: String, CaseIterable { case workspace, flat }
    enum OrderBy: String, CaseIterable { case manual, updated }
    var groupBy: GroupBy = .workspace
    var orderBy: OrderBy = .updated
    var showArchived = false
}

enum HarnessPresentationPolicy {
    static func updatedDescending(_ lhs: HarnessSessionSummary, _ rhs: HarnessSessionSummary) -> Bool {
        lhs.updatedAt == rhs.updatedAt ? lhs.id < rhs.id : lhs.updatedAt > rhs.updatedAt
    }
    static func search(_ query: String, sessions: [HarnessSessionSummary], archived: Set<String>, showArchived: Bool) -> [HarnessSessionSummary] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        return sessions.filter { (showArchived || !archived.contains($0.id)) && ($0.title.localizedCaseInsensitiveContains(needle) || $0.cwd.localizedCaseInsensitiveContains(needle)) }.sorted(by: updatedDescending)
    }

    static func mergeSearchResults(_ results: [HarnessSearchResult], sessions: [HarnessSessionSummary], archived: Set<String>, showArchived: Bool) -> [HarnessSessionSummary] {
        let byID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        return results.compactMap { result in
            guard let session = byID[result.sessionID], (showArchived || !archived.contains(session.id)) else { return nil }
            return session
        }
    }

    static func ordered(_ sessions: [HarnessSessionSummary], archived: Set<String>, preferences: HarnessViewPreferences) -> [HarnessSessionSummary] {
        let visible = sessions.filter { preferences.showArchived || !archived.contains($0.id) }
        return preferences.orderBy == .updated ? visible.sorted(by: updatedDescending) : visible
    }

    /// Produces the sidebar's actual sections. Workspace mode follows the
    /// server-provided workspace/session IDs; flat mode intentionally has one
    /// section. Sessions absent from a workspace remain visible in a stable
    /// "Other" section instead of silently disappearing.
    static func sections(
        sessions: [HarnessSessionSummary],
        workspaces: [HarnessWorkspace],
        archived: Set<String>,
        preferences: HarnessViewPreferences
    ) -> [HarnessSessionSection] {
        let source = sessions.filter { !$0.blank }
        let visible = ordered(source, archived: archived, preferences: preferences)
        guard preferences.groupBy == .workspace else {
            return visible.isEmpty ? [] : [HarnessSessionSection(workspaceID: nil, title: "全部会话", sessions: visible)]
        }
        var remaining = Dictionary(uniqueKeysWithValues: visible.map { ($0.id, $0) })
        var result: [HarnessSessionSection] = []
        for workspace in workspaces {
            let grouped = workspace.sessionIDs.compactMap { remaining.removeValue(forKey: $0) }
            let rows = preferences.orderBy == .updated ? grouped.sorted(by: updatedDescending) : grouped
            if !rows.isEmpty { result.append(HarnessSessionSection(workspaceID: workspace.id, title: workspace.title, sessions: rows)) }
        }
        let other = visible.filter { remaining[$0.id] != nil }
        if !other.isEmpty { result.append(HarnessSessionSection(workspaceID: nil, title: "其他会话", sessions: other)) }
        return result
    }

    static func sessionTitle(_ session: HarnessSessionSummary, archived: Bool) -> String {
        let title = session.title.isEmpty ? "新会话" : session.title
        return archived ? "已归档 · \(title)" : title
    }

    static func transcriptVisibleItems(_ items: [HarnessConversationItem], view: HarnessTranscriptView) -> [HarnessConversationItem] {
        guard view == .compact else { return items }
        return items.filter { item in
            guard item.kind == .system else { return true }
            return item.subtitle == "错误" || item.subtitle == "工具" || item.subtitle == "指令结果"
        }
    }
}

/// Small, deterministic presentation helpers used by the native renderer and XCTest.
enum HarnessMarkdown {
    static func attributed(_ markdown: String, fontSize: CGFloat = 14, codeFontSize: CGFloat? = nil, color: UIColor = .label) -> NSAttributedString {
        let output = NSMutableAttributedString()
        let base = UIFont.systemFont(ofSize: fontSize)
        let bodyFont = UIFontMetrics(forTextStyle: .body).scaledFont(for: base)
        let codeFont = UIFont.monospacedSystemFont(ofSize: max(12, codeFontSize ?? (fontSize - 1)), weight: .regular)
        let lines = markdown.components(separatedBy: "\n")
        var inCode = false
        for (index, line) in lines.enumerated() {
            let value = line.trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("```") {
                inCode.toggle()
            } else {
                let paragraph = NSMutableParagraphStyle()
                paragraph.paragraphSpacing = 5
                paragraph.headIndent = value.hasPrefix("-") ? 12 : 0
                paragraph.firstLineHeadIndent = value.hasPrefix("-") ? -8 : 0
                let lineFont: UIFont
                let lineColor: UIColor
                if inCode { lineFont = codeFont; lineColor = color.withAlphaComponent(0.92) }
                else if value.hasPrefix(">") { lineFont = bodyFont; lineColor = color.withAlphaComponent(0.78); paragraph.headIndent = 14; paragraph.firstLineHeadIndent = 0 }
                else if value.hasPrefix("#") { lineFont = UIFont.boldSystemFont(ofSize: fontSize + (value.hasPrefix("# ") ? 4 : 2)); lineColor = color }
                else { lineFont = bodyFont; lineColor = color }
                let rendered = inline(line, font: lineFont, codeFont: codeFont, color: lineColor)
                rendered.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: rendered.length))
                output.append(rendered)
                if index + 1 < lines.count { output.append(NSAttributedString(string: "\n")) }
            }
        }
        return output
    }

    private static func inline(_ text: String, font: UIFont, codeFont: UIFont, color: UIColor) -> NSMutableAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        let pattern = #"`([^`]+)`|\[([^\]]+)\]\((https?://[^)\s]+)\)"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return result }
        let matches = expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed()
        for match in matches {
            if match.range(at: 1).location != NSNotFound {
                result.replaceCharacters(in: match.range(at: 0), with: String(text[Range(match.range(at: 1), in: text)!]))
                let replacementRange = NSRange(location: match.range(at: 0).location, length: match.range(at: 1).length)
                result.addAttribute(.font, value: codeFont, range: replacementRange)
                result.addAttribute(.backgroundColor, value: UIColor.secondarySystemFill, range: replacementRange)
            } else if match.range(at: 2).location != NSNotFound, let urlRange = Range(match.range(at: 3), in: text), let url = URL(string: String(text[urlRange])), let labelRange = Range(match.range(at: 2), in: text) {
                let replacement = NSMutableAttributedString(string: String(text[labelRange]), attributes: [.font: font, .foregroundColor: UIColor.link, .link: url])
                result.replaceCharacters(in: match.range(at: 0), with: replacement)
            }
        }
        return result
    }
}
