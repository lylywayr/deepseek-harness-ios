import Foundation
import UIKit

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

    static func updatedDescending(_ lhs: HarnessSessionSummary, _ rhs: HarnessSessionSummary) -> Bool {
        lhs.updatedAt == rhs.updatedAt ? lhs.id < rhs.id : lhs.updatedAt > rhs.updatedAt
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
                output.append(NSAttributedString(string: line + (index + 1 < lines.count ? "\n" : ""), attributes: [.font: lineFont, .foregroundColor: lineColor, .paragraphStyle: paragraph]))
            }
        }
        return output
    }
}
