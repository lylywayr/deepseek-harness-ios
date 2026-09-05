import XCTest
import Foundation

final class HarnessClientModelsTests: XCTestCase {
    private func session(_ id: String, title: String, updatedAt: Double, blank: Bool = false) -> HarnessSessionSummary {
        HarnessSessionSummary(id: id, title: title, cwd: "/tmp/\(id)", updatedAt: updatedAt, running: false, blank: blank, preset: "standard", permission: "read-only", provider: "deepseek-official", model: "deepseek-v4-flash", turns: 0, steps: 0, contextUsed: nil)
    }

    private func item(_ id: String, kind: HarnessConversationItem.Kind, subtitle: String?) -> HarnessConversationItem {
        HarnessConversationItem(id: id, kind: kind, text: id, subtitle: subtitle, seq: 0, time: 0)
    }

    func testSearchTrimsAndFiltersArchivedWithoutDestroyingSourceList() {
        let source = [session("old", title: "Archive me", updatedAt: 1), session("new", title: "Native Search", updatedAt: 2)]
        XCTAssertTrue(HarnessPresentationPolicy.search(" native ", sessions: source, archived: ["new"], showArchived: false).isEmpty)
        XCTAssertEqual(source.count, 2)
        XCTAssertEqual(HarnessPresentationPolicy.search("native", sessions: source, archived: [], showArchived: false).map(\.id), ["new"])
        XCTAssertEqual(HarnessPresentationPolicy.mergeSearchResults([HarnessSearchResult(sessionID: "new", snippet: "match")], sessions: source, archived: [], showArchived: false).map(\.id), ["new"])
        XCTAssertEqual(HarnessPresentationPolicy.mergeSearchResults([HarnessSearchResult(sessionID: "old", snippet: "match")], sessions: source, archived: ["old"], showArchived: false).count, 0)
    }

    func testOrderingHonorsUpdatedAndManualModes() {
        let a = session("a", title: "A", updatedAt: 1)
        let b = session("b", title: "B", updatedAt: 2)
        XCTAssertEqual(HarnessPresentationPolicy.ordered([a, b], archived: [], preferences: HarnessViewPreferences()).map(\.id), ["b", "a"])
        var manual = HarnessViewPreferences(); manual.orderBy = .manual
        XCTAssertEqual(HarnessPresentationPolicy.ordered([a, b], archived: [], preferences: manual).map(\.id), ["a", "b"])
    }

    func testWorkspaceSectionsHonorGroupModeAndAllWorkspaceMembership() {
        let one = session("one", title: "One", updatedAt: 1)
        let two = session("two", title: "Two", updatedAt: 2)
        let workspaces = [
            HarnessWorkspace(id: "w1", title: "Projects", path: "/projects", sessionIDs: ["one"]),
            HarnessWorkspace(id: "w2", title: "Research", path: "/research", sessionIDs: ["two"])
        ]
        let grouped = HarnessPresentationPolicy.sections(sessions: [one, two], workspaces: workspaces, archived: [], preferences: HarnessViewPreferences())
        XCTAssertEqual(grouped.map(\.title), ["Projects", "Research"])
        XCTAssertEqual(grouped.flatMap(\.sessions).map(\.id), ["one", "two"])
        var flat = HarnessViewPreferences(); flat.groupBy = .flat
        let flatSections = HarnessPresentationPolicy.sections(sessions: [one, two], workspaces: workspaces, archived: [], preferences: flat)
        XCTAssertEqual(flatSections.count, 1)
        XCTAssertEqual(flatSections[0].sessions.map(\.id), ["two", "one"])
    }

    func testWorkspaceSectionsKeepArchivedStateWhenRequested() {
        let archived = session("archived", title: "Archived", updatedAt: 1)
        let workspace = HarnessWorkspace(id: "w", title: "Work", path: "/work", sessionIDs: ["archived"])
        XCTAssertTrue(HarnessPresentationPolicy.sections(sessions: [archived], workspaces: [workspace], archived: ["archived"], preferences: HarnessViewPreferences()).isEmpty)
        var preferences = HarnessViewPreferences(); preferences.showArchived = true
        XCTAssertEqual(HarnessPresentationPolicy.sections(sessions: [archived], workspaces: [workspace], archived: ["archived"], preferences: preferences).flatMap(\.sessions).map(\.id), ["archived"])
    }

    func testCompactTranscriptHidesProcessRowsButRetainsErrors() {
        let process = item("process", kind: .system, subtitle: "轮次")
        let error = item("error", kind: .system, subtitle: "错误")
        let assistant = item("assistant", kind: .assistant, subtitle: "完成")
        let compact = HarnessPresentationPolicy.transcriptVisibleItems([process, error, assistant], view: .compact)
        XCTAssertEqual(compact.map(\.id), ["error", "assistant"])
        XCTAssertEqual(HarnessPresentationPolicy.transcriptVisibleItems([process, error, assistant], view: .normal).map(\.id), ["process", "error", "assistant"])
    }

    func testBusyEnterModeUsesConfiguredNormalAndModifiedSemantics() {
        XCTAssertEqual(HarnessBusyEnterBehavior.sendMode(for: .queue, isGenerating: false, commandModified: false), "queue")
        XCTAssertEqual(HarnessBusyEnterBehavior.sendMode(for: .queue, isGenerating: true, commandModified: false), "queue")
        XCTAssertEqual(HarnessBusyEnterBehavior.sendMode(for: .queue, isGenerating: true, commandModified: true), "steer")
        XCTAssertEqual(HarnessBusyEnterBehavior.sendMode(for: .steer, isGenerating: true, commandModified: true), "queue")
    }

    func testSettingsDefaultsAndQuestionEqualityAreStable() {
        XCTAssertEqual(HarnessClientSettings.defaults.theme, .system)
        XCTAssertEqual(HarnessClientSettings.defaults.fontSize, 14)
        let question = HarnessQuestion(id: "q", header: "H", question: "Choose", detail: nil, options: [HarnessQuestionOption(label: "A", description: nil)], multiSelect: false)
        XCTAssertEqual(question, HarnessQuestion(id: "q", header: "H", question: "Choose", detail: nil, options: [HarnessQuestionOption(label: "A", description: nil)], multiSelect: false))
    }


    func testMarkdownKeepsHeadingsListsAndCodeBlocksVisible() {
        let value = HarnessMarkdown.attributed("# Title\n- item\nInline `code` and [Harness](https://harness.example.com/docs)\n```swift\nlet ok = true\n```")
        XCTAssertTrue(value.string.contains("Title"))
        XCTAssertTrue(value.string.contains("item"))
        XCTAssertTrue(value.string.contains("let ok = true"))
        let codeRange = (value.string as NSString).range(of: "code")
        XCTAssertNotEqual(codeRange.location, NSNotFound)
        XCTAssertTrue(value.attribute(.font, at: codeRange.location, effectiveRange: nil) as? UIFont != nil)
        let linkRange = (value.string as NSString).range(of: "Harness")
        XCTAssertEqual(value.attribute(.link, at: linkRange.location, effectiveRange: nil) as? URL, URL(string: "https://harness.example.com/docs"))
    }

    func testPendingQuestionCarriesEventCorrelation() {
        let pending = HarnessPendingQuestion(clientID: "client", eventID: "event", questions: [])
        XCTAssertEqual(pending.clientID, "client")
        XCTAssertEqual(pending.eventID, "event")
    }
}
