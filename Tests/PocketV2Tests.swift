import XCTest
import Foundation

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

    func testPocketProcessAndArtifactPoliciesRemainSeparate() {
        let runtime = HarnessRuntime.fixture(scene: "artifacts")
        let process = runtime.items.filter { $0.kind == .system || $0.kind == .tool }
        XCTAssertTrue(process.contains { $0.subtitle == "轮次" })
        XCTAssertEqual(runtime.artifacts.map(\.id), ["artifact-1"])
        XCTAssertFalse(runtime.items.contains { $0.subtitle == "产物" })
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
    }
}
