# Deliverable Gap Report

## Audit baseline

- Branch: `feature/deliverable-audit`
- Base: `003cd29b3f610a2565ea4c540019a93c0b281fe2`
- Scope: static and contract gates only; no production Swift changes.
- Required mode: `DELIVERABLE_REQUIRED=1`.
- Screenshot gate: NA — no artifact generated from this audit HEAD.

## Requirement matrix

| Requirement | Baseline status | Default gate | Required gate |
|---|---|---|---|
| Native UIKit entry and constrained renderer | Implemented structurally | PASS | PASS |
| Legacy/web fallback | Must remain unsupported, never required | PASS | PASS |
| Native settings/plugin hierarchy | Separate settings branch, absent here | SKIP | FAIL until merged |
| Unique isolated market WebView | Separate market branch, absent here | SKIP | FAIL until merged |
| Market CSS byte integrity | Gate checks approved base/theme SHA when resources exist | SKIP with market | FAIL until merged |
| Official server export to temporary file and system share | Not implemented on baseline | SKIP | FAIL until implemented |
| Model/reasoning/permission/context controls | Existing native entry markers accepted | PASS | PASS |
| Dynamic plugin values | Hard-coded sampled counts prohibited | PASS | PASS |
| Release fixture and credential boundaries | Existing static controls retained | PASS | PASS |
| iOS 15, arm64, unsigned IPA | CI scripts exist; no artifact from this HEAD | static only | artifact required later |

## Gate semantics

Default mode preserves the historical suite while reporting known unmerged integration work as explicit skips. Required mode converts settings, market and export gaps into deterministic failures. Security violations—non-whitelisted WebViews or credential-like literals—fail in every mode.

## NOT VERIFIED

- Xcode compilation and linkage.
- Current integrated Release archive and unsigned IPA.
- Real Harness endpoint behavior.
- Signed physical-device installation.
- Dynamic Type, VoiceOver and market touch coordinates on device.
- iPhone 17 Pro Max and iOS 27.

This gate must be rerun on the integration branch after settings, market and export implementations are merged. Historical screenshots, historical IPA files and sibling worktrees are not evidence for this audit HEAD.
