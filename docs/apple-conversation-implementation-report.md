# Apple Conversation Proposal A Implementation

## Requirement → production diff → runtime evidence
- Title/workspace/status hierarchy: `PocketConversationViewController.swift` adds a three-line native header with workspace path and live run state.
- Four modes: existing segmented control remains wired to transcript/process/trajectory/artifact data and paging/filtering.
- Explicit task configuration: native configuration summary card renders model, reasoning, permission, attachment count, and Queue/Steer state; controls remain connected to existing runtime methods.
- Continuous content and runtime controls: existing table stream, follow-scroll, stop/send, approvals/questions and Markdown cells remain wired; composer is multiline and attached to `keyboardLayoutGuide`.
- Frozen boundaries: no protocol, network, mux, keychain, endpoint, model, auth, workspace/drawer, or iOS deployment changes.

## Validation
- `git diff --check`: PASS.
- Source-only structural review: PASS; no WebKit/SwiftUI/legacy additions.
- CI/artifact/visual evidence: pending external workflow dispatch and device artifact collection.
