import XCTest
import Foundation

@MainActor
final class PocketV2Tests: XCTestCase {
    func testPocketRuntimeUsesIndependentObservers() {
        let runtime = HarnessRuntime(baseURL: URL(string: "http://fixture.invalid")!)
        var changes = 0
        var navigation = 0
        let stopChanges = runtime.observeChanges { changes += 1 }
        let stopNavigation = runtime.observeNavigation { navigation += 1 }
        runtime.emitFixtureUpdateForTesting()
        XCTAssertEqual(changes, 1)
        XCTAssertEqual(navigation, 1)
        stopChanges()
        stopNavigation()
        runtime.emitFixtureUpdateForTesting()
        XCTAssertEqual(changes, 1)
        XCTAssertEqual(navigation, 1)
    }

    func testPocketFixtureContainsWorkspaceConsoleState() {
        let runtime = HarnessRuntime.fixture(scene: "conversation")
        XCTAssertEqual(runtime.selectedSessionID, "session-active")
        XCTAssertFalse(runtime.sessions.isEmpty)
        XCTAssertFalse(runtime.workspaces.isEmpty)
        XCTAssertFalse(runtime.models.isEmpty)
        XCTAssertEqual(runtime.reasoningEffort, "balanced")
        XCTAssertFalse(runtime.artifacts.isEmpty)
        XCTAssertFalse(runtime.pendingApprovals.isEmpty)
        XCTAssertFalse(runtime.pendingQuestions.isEmpty)
    }

    func testPocketRuntimeObserverTokensCanBeIndependentlyRemoved() {
        let runtime = HarnessRuntime(baseURL: URL(string: "http://fixture.invalid")!)
        var first = 0
        var second = 0
        let stopFirst = runtime.observeChanges { first += 1 }
        let stopSecond = runtime.observeChanges { second += 1 }
        runtime.emitFixtureUpdateForTesting()
        stopFirst()
        runtime.emitFixtureUpdateForTesting()
        stopSecond()
        runtime.emitFixtureUpdateForTesting()
        XCTAssertEqual(first, 1)
        XCTAssertEqual(second, 2)
    }

    func testPocketRuntimeEventObserversCanBeIndependentlyRemoved() {
        let runtime = HarnessRuntime(baseURL: URL(string: "http://fixture.invalid")!)
        var approvals = 0
        var questions = 0
        let stopApproval = runtime.observeEvents { event in if case .approval = event { approvals += 1 } }
        let stopQuestion = runtime.observeEvents { event in if case .question = event { questions += 1 } }
        let request = HarnessApprovalRequest(clientID: "c", eventID: "a", sessionID: nil, toolName: "tool", risk: "normal", reason: nil, target: nil, detail: nil, arguments: nil)
        let pending = HarnessPendingQuestion(clientID: "c", eventID: "q", questions: [])
        runtime.emitFixtureEventForTesting(.approval(request))
        runtime.emitFixtureEventForTesting(.question(pending))
        stopApproval()
        runtime.emitFixtureEventForTesting(.approval(request))
        runtime.emitFixtureEventForTesting(.question(pending))
        stopQuestion()
        runtime.emitFixtureEventForTesting(.question(pending))
        XCTAssertEqual(approvals, 1)
        XCTAssertEqual(questions, 2)
    }

    func testPocketFixtureExposesTaskConsoleCapabilities() {
        let runtime = HarnessRuntime.fixture(scene: "trajectory")
        XCTAssertTrue(runtime.models.contains { !$0.reasoning.isEmpty })
        XCTAssertEqual(runtime.sessions.first?.permission, "workspace-write")
        XCTAssertEqual(runtime.reasoningEffort, "balanced")
        XCTAssertTrue(runtime.items.contains { $0.kind == .tool })
        XCTAssertTrue(runtime.items.contains { $0.isMarkdown })
        XCTAssertFalse(runtime.pendingApprovals.isEmpty)
        XCTAssertFalse(runtime.pendingQuestions.isEmpty)
    }

    func testPocketSettingsHaveCompactAndNormalPresentationOptions() {
        XCTAssertEqual(HarnessTranscriptView.allCases, [.compact, .normal])
        XCTAssertEqual(HarnessBusyEnterBehavior.sendMode(for: .queue, isGenerating: false, commandModified: true), "queue")
    }
    func testPocketProcessAndArtifactPoliciesRemainSeparate() {
        let runtime = HarnessRuntime.fixture(scene: "artifacts")
        let process = runtime.items.filter { $0.kind == .system || $0.kind == .tool }
        XCTAssertTrue(process.contains { $0.subtitle == "轮次" })
        XCTAssertEqual(runtime.artifacts.map(\.id), ["artifact-1"])
        XCTAssertFalse(runtime.items.contains { $0.subtitle == "产物" })
    }

    func testPocketFixtureExposesMarkdownInlineAttributes() {
        let value = HarnessMarkdown.attributed("Inline `code` and [Harness](https://harness.example.com/docs)")
        let codeRange = (value.string as NSString).range(of: "code")
        let linkRange = (value.string as NSString).range(of: "Harness")
        XCTAssertNotEqual(codeRange.location, NSNotFound)
        XCTAssertNotNil(value.attribute(.backgroundColor, at: codeRange.location, effectiveRange: nil))
        XCTAssertEqual((value.attribute(.link, at: linkRange.location, effectiveRange: nil) as? URL)?.absoluteString, "https://harness.example.com/docs")
    }

    func testPocketSendModesKeepQueueAndSteerSemantics() {
        XCTAssertEqual(HarnessBusyEnterBehavior.sendMode(for: .queue, isGenerating: true, commandModified: false), "queue")
        XCTAssertEqual(HarnessBusyEnterBehavior.sendMode(for: .queue, isGenerating: true, commandModified: true), "steer")
        XCTAssertEqual(HarnessBusyEnterBehavior.sendMode(for: .steer, isGenerating: true, commandModified: false), "steer")
    }

    func testPocketWorkspacePreferencesAreAppliedByPresentationPolicy() {
        let runtime = HarnessRuntime.fixture(scene: "workspace")
        var flat = HarnessViewPreferences()
        flat.groupBy = .flat
        flat.orderBy = .manual
        let sections = HarnessPresentationPolicy.sections(sessions: runtime.sessions, workspaces: runtime.workspaces, archived: [], preferences: flat)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].title, "全部会话")
        var grouped = HarnessViewPreferences()
        grouped.showArchived = true
        let groupedSections = HarnessPresentationPolicy.sections(sessions: runtime.sessions, workspaces: runtime.workspaces, archived: runtime.archivedSessionIDsForPresentation, preferences: grouped)
        XCTAssertEqual(groupedSections.map(\.title), ["Pocket 项目", "验收文档"])
    }
}
