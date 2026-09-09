# Deliverable Gap Report

## Integrated baseline

- Branch: `feature/apple-conversation`
- Integration HEAD before CI documentation update: `3a896ab2fd456f6a2a37776b973c306cbc046d50`
- Base: `003cd29b3f610a2565ea4c540019a93c0b281fe2`
- Scope: native settings, isolated plugin market, market bootstrap, static delivery gates.

## Requirement matrix

| Requirement | Integrated status | Evidence |
|---|---|---|
| Native UIKit settings and plugin hierarchy | PASS_LOCAL_STATIC | `test_settings_native_contract.py` |
| Unique isolated market WebView | PASS_LOCAL_STATIC | sole `HarnessPluginMarketViewController.swift` WebKit boundary |
| Market CSS byte integrity | PASS | SHA-256 checks for all versioned resources |
| Market root-SPA route | PASS_LOCAL_STATIC | controlled `.VOzbGW_trigger` then exact `插件市场` button script; no guessed URL |
| Authentication boundary | PASS_LOCAL_STATIC | same-origin secure Cookie copy to non-persistent store; no token URL/JS bridge |
| Bootstrap policy | PASS_LOCAL_STATIC | package `dshmarket` fixed at verified `1.41.0`; page contract remains `v1.41.0` |
| Install behavior | PASS_LOCAL_STATIC | compatible install skips; missing install posts once and polls; mismatch/unknown blocks |
| Official session-log export | BLOCKED_NOT_VERIFIED | no callable export route/RPC/CLI contract found in current official source or targeted history search |
| Protocol/native regression gates | PASS_LOCAL_STATIC | both native verifier scripts pass |
| Xcode build and unsigned IPA | PENDING_CI | iSH has no Xcode toolchain |

## Test results

- Standard discovery: 44 tests, OK, one expected export skip.
- `MARKET_WIRING_REQUIRED=1`: 44 tests, OK, one expected export skip.
- `DELIVERABLE_REQUIRED=1`: exactly one failure, official export.
- No SyntaxError or unittest ERROR.
- `git diff --check`: PASS.

## Export decision

The client does not synthesize or locally reconstruct an export. A native implementation requires a documented server response or generated remote contract defining the operation, payload, response bytes, filename/content type, authentication and failure semantics. Until that exists, the UI capability must remain unavailable rather than claim an official export.

## NOT VERIFIED

- macOS/Xcode compilation and linkage for this integration HEAD.
- Integrated Release archive and unsigned arm64 IPA.
- Real Harness endpoint bootstrap, root-SPA DOM contract and export behavior.
- Signed physical-device installation, Dynamic Type and VoiceOver interaction.
- iPhone 17 Pro Max and iOS 27.
