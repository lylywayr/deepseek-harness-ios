# Apple Workspace implementation report

## Scope
Production UIKit workspace was rebuilt around the Proposal A information architecture without changing conversation, drawer, protocol, Runtime, endpoint, Keychain, or iOS 15 constraints.

## Requirement → production diff → evidence
| Requirement | Production implementation | Evidence |
|---|---|---|
| Title and subtitle | Workspace header uses `工作台` and `你的 Harness 工作空间` | `PocketWorkspaceViewController.swift` buildRoot |
| Connection status | Compact live connection pill and state label, driven by Runtime | `renderAll()` |
| Today overview | Three live metrics: pending, running, completed | `makeOverviewStrip()` |
| Continue work | Dedicated live card, selected session title/metadata/status | `currentCard`, `installCard()` |
| Recent workspaces | Runtime workspace rows with title/path/session count and actions | `workspaceRow()` |
| New task CTA | Prominent native filled button invoking existing createSession | `开始新任务` |
| Recent sessions | Runtime ordered recent sessions | `recentSection` |
| Native navigation | Existing native activity/settings/drawer entry points retained | `buildRoot()` and existing navigation |
| Existing capabilities | pending approvals/questions, running sessions, artifacts, activity center and drawer remain | `renderAll()` |

## Validation
- Python integration checks: PASS (`verify_native_rework.py`, `verify_native_ui_fixture.py`).
- `git diff --check`: PASS.
- Runtime values are sourced from HarnessRuntime; no production fixture values are introduced.
- Visual target comparison: hierarchy now follows title/status → overview → continue → workspaces → CTA → recent sessions; production remains data-dependent and may hide empty sections.

## External evidence
Workflow dispatch and artifact/screenshot collection require repository GitHub credentials and are recorded in the orchestration report when available.
