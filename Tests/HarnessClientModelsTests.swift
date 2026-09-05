import XCTest
import Foundation

final class HarnessClientModelsTests: XCTestCase {
    private func session(_ id: String, title: String, updatedAt: Double, blank: Bool = false) -> HarnessSessionSummary {
        HarnessSessionSummary(id: id, title: title, cwd: "/tmp/\(id)", updatedAt: updatedAt, running: false, blank: blank, preset: "standard", permission: "read-only", provider: "deepseek-official", model: "deepseek-v4-flash", turns: 0, steps: 0, contextUsed: nil)
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

    func testSettingsDefaultsAndQuestionEqualityAreStable() {
        XCTAssertEqual(HarnessClientSettings.defaults.theme, .system)
        XCTAssertEqual(HarnessClientSettings.defaults.fontSize, 14)
        let question = HarnessQuestion(id: "q", header: "H", question: "Choose", detail: nil, options: [HarnessQuestionOption(label: "A", description: nil)], multiSelect: false)
        XCTAssertEqual(question, HarnessQuestion(id: "q", header: "H", question: "Choose", detail: nil, options: [HarnessQuestionOption(label: "A", description: nil)], multiSelect: false))
    }

    func testMarkdownKeepsHeadingsListsAndCodeBlocksVisible() {
        let value = HarnessMarkdown.attributed("# Title\n- item\n```swift\nlet ok = true\n```")
        XCTAssertTrue(value.string.contains("Title"))
        XCTAssertTrue(value.string.contains("item"))
        XCTAssertTrue(value.string.contains("let ok = true"))
        XCTAssertNotNil(value.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
    }

    func testPendingQuestionCarriesEventCorrelation() {
        let pending = HarnessPendingQuestion(clientID: "client", eventID: "event", questions: [])
        XCTAssertEqual(pending.clientID, "client")
        XCTAssertEqual(pending.eventID, "event")
    }
}
