#!/usr/bin/env python3
"""Static smoke checks for the DEBUG-only Pocket UI screenshot fixture."""
from __future__ import annotations
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "DeepSeekHarness/NativeFixtureViewController.swift").read_text()
WORKSPACE = (ROOT / "DeepSeekHarness/PocketWorkspaceViewController.swift").read_text()
CONVERSATION = (ROOT / "DeepSeekHarness/PocketConversationViewController.swift").read_text()
PROJECT = (ROOT / "DeepSeekHarness.xcodeproj/project.pbxproj").read_text()
SCRIPT = (ROOT / "scripts/capture_native_ui.sh").read_text()
WORKFLOW = (ROOT / ".github/workflows/build-ipa.yml").read_text()
LAUNCH = (ROOT / "DeepSeekHarness/NativeMainViewController.swift").read_text()

if "#if DEBUG" not in SOURCE or "#endif" not in SOURCE:
    raise SystemExit("FAIL: fixture implementation is not DEBUG-only")
for marker in (
    'case "workspace"', 'case "drawer"', 'case "conversation"',
    'case "process"', 'case "artifacts"', 'case "activity"',
    'case "settings"', 'case "keyboard"',
):
    if marker not in SOURCE:
        raise SystemExit(f"FAIL: missing fixture scene {marker}")
for marker in (
    "HarnessRuntime.fixture", "NativeHomeViewController", "fixtureOpenDrawer",
    "fixtureSelectMode", "fixtureShowActivity", "fixtureShowSettings",
):
    if marker not in SOURCE + WORKSPACE + CONVERSATION:
        raise SystemExit(f"FAIL: missing real Pocket fixture marker {marker}")
for marker in ("NativeFixtureViewController.swift in Sources", "-UITestFixture", "390", "844"):
    haystack = PROJECT if marker == "NativeFixtureViewController.swift in Sources" else LAUNCH + SCRIPT
    if marker not in haystack:
        raise SystemExit(f"FAIL: missing fixture integration marker {marker}")
if 'SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG"' not in PROJECT:
    raise SystemExit("FAIL: Debug fixture compilation condition is missing")
for marker in ("workspace drawer conversation process artifacts activity settings keyboard", "390x844", "430x932", "PocketDark", "pocket-v2-ui-matrix", "UITestFixture", "-NativeFixtureScreen", "iPhone 16"):
    if marker not in LAUNCH + SCRIPT + WORKFLOW:
        raise SystemExit(f"FAIL: missing screenshot marker {marker}")
print("ok: Pocket fixture scenes 8")
print("ok: real Pocket controllers and Runtime are fixture-backed")
print("ok: native fixture is DEBUG-only and workflow-covered")
