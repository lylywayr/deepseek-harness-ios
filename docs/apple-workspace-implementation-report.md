# Apple Workspace implementation report

- event_id: `apple-workspace-r2-c3-20260907`
- implementation_round: 2; continuation: 3
- code SHA: `c37c2b0558e645382ba909452126fa37fbf66898`
- CI Run: `34082661812`
- Jobs: Build iOS device IPA **success** (`101620783760`); Native Pocket UI screenshots matrix **success** (`101620783944`)

## Evidence

- IPA: `/var/minis/attachments/apple-workspace-r2-run-34082661812/DeepSeekHarness-unsigned-ipa/DeepSeekHarness-unsigned.ipa`
- IPA SHA-256: `4d9d4afaf0949550e767186f6b3b4716afead022e6c562ed315add2b394ea5fd`
- Independent `unzip -t`: PASS.
- PNG count: 28; all unique by filename/content artifact set. 390×844 logical screenshots are 1170×2532 pixels; 430×932 logical screenshots are 1290×2796 pixels.
- Workspace screenshots: `pocket-v2-ui-matrix/390x844/light/workspace-390x844-light.png`, `pocket-v2-ui-matrix/430x932/light/workspace-430x932-light.png`, `pocket-v2-ui-matrix/430x932/dark/workspace-430x932-dark.png`.

## Visual conclusions

- 390 light: PASS. Real “工作台” title, subtitle/state, compact connection pill, overview metrics, continue-work card, workspaces, CTA, activity and four-item bottom navigation are visible without overlap.
- 430 light: PASS. Same production controller content scales correctly; text and cards remain inside the viewport and bottom navigation is visible.
- 430 dark: PASS. Continuous dark content/header treatment, readable controls and bottom navigation; no placeholder rectangles or overlap.

The final production fix constrains the scroll content width to the scroll frame minus page insets, preventing the prior horizontal compression/clipping. No session/drawer/protocol/runtime semantic changes.

## Requirement mapping

| Contract requirement | Production diff/runtime evidence | Result |
|---|---|---|
| Title and subtitle | NativeHomeViewController header; screenshots | PASS |
| Compact connection status | state-driven connection button | PASS |
| Three overview metrics | runtime session counts in `makeOverviewStrip` | PASS |
| Continue work | `currentCard` section | PASS |
| Recent workspaces | runtime workspaces section | PASS |
| Start new task | native CTA wired to `createSession()` | PASS |
| Recent sessions/activity/running/artifacts | existing sections retained and rendered | PASS |
| Native bottom navigation | four UIKit buttons | PASS |
| No clipping/overlap | three production matrix screenshots | PASS |

## Counter-evidence / limits

- Fixture-derived runtime data is used by the CI screenshot harness; visual evidence is nevertheless from the production `NativeHomeViewController` controller and real state projection path. Counts/titles are not hardcoded in production.
- The design proposal’s exact pixel geometry and any off-screen content below the captured viewport are not independently pixel-diff verified; scroll-width and visible viewport checks are verified.
- IPA is unsigned; signing/install on a physical device is NOT VERIFIED.

## Git scope

Only `DeepSeekHarness/PocketWorkspaceViewController.swift` (one scroll-width constraint) and this report are staged. `.orchestration/`, `.design-proposals/`, and pre-existing untracked files are not submitted. No main branch or force push.

**READY_FOR_ACCEPTANCE**
