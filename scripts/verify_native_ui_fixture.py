#!/usr/bin/env python3
"""Static smoke checks for the native-only UI screenshot fixture."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "DeepSeekHarness/NativeFixtureViewController.swift"
PROJECT = ROOT / "DeepSeekHarness.xcodeproj/project.pbxproj"
WORKFLOW = ROOT / ".github/workflows/build-ipa.yml"

source = SOURCE.read_text()
project = PROJECT.read_text()
workflow = WORKFLOW.read_text()

if "#if DEBUG" not in source or "#endif" not in source:
    raise SystemExit("FAIL: fixture implementation is not DEBUG-only")

required_screens = (
    'case "connection"', 'case "conversation"', 'case "sidebar"',
    'case "settings"', 'case "directory"', 'case "approval"',
    'case "question"', 'case "trajectory"',
)
for marker in required_screens:
    if marker not in source:
        raise SystemExit(f"FAIL: missing fixture scene {marker}")

for marker in (
    "NativeFixtureViewController.swift in Sources",
    "-UITestFixture",
    "390",
    "844",
):
    haystack = project if marker == "NativeFixtureViewController.swift in Sources" else source
    if marker not in haystack:
        raise SystemExit(f"FAIL: missing fixture integration marker {marker}")
if 'SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG"' not in project:
    raise SystemExit("FAIL: Debug fixture compilation condition is missing")

for marker in ("scripts/capture_native_ui.sh", "390x844", "UITestFixture", "-NativeFixtureScreen", "iPhone 16"):
    if marker not in workflow:
        raise SystemExit(f"FAIL: missing screenshot workflow marker {marker}")

print("ok: native fixture scenes", len(required_screens))
print("ok: native fixture is compiled and workflow-covered")
