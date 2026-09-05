import Foundation
import UIKit

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
    var transcriptView: HarnessTranscriptView = .compact
    var busyEnter: HarnessBusyEnterBehavior = .queue
    var defaultPermission: String = "read-only"
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
    static func attributed(_ markdown: String, fontSize: CGFloat = 14, color: UIColor = .label) -> NSAttributedString {
        let output = NSMutableAttributedString()
        let bodyFont = UIFont.systemFont(ofSize: fontSize)
        let codeFont = UIFont.monospacedSystemFont(ofSize: max(12, fontSize - 1), weight: .regular)
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
