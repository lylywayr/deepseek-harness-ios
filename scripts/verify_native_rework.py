#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = (ROOT / "DeepSeekHarness/HarnessRuntime.swift").read_text()
MODELS = (ROOT / "DeepSeekHarness/HarnessClientModels.swift").read_text()
PROJECT = (ROOT / "DeepSeekHarness.xcodeproj/project.pbxproj").read_text()

checks = [
    ("runtime uses production wire parser", "HarnessWire.rpcResponse" in RUNTIME),
    ("session/list reserves _request", "HarnessWire.sessionListArguments()" in RUNTIME and '"_request": [String: Any]()' in (ROOT / "DeepSeekHarness/HarnessWire.swift").read_text()),
    ("question cancel is implemented", "func cancelQuestion" in RUNTIME),
    ("message cell is declared", "final class HarnessMessageCell" in (ROOT / "DeepSeekHarness/PolishedConversationViewController.swift").read_text()),
    ("session menu is declared", "private func sessionMenu" in (ROOT / "DeepSeekHarness/NativeMainViewController.swift").read_text()),
    ("models are in app target", "HarnessClientModels.swift in Sources" in PROJECT),
    ("model tests are in test target", "HarnessClientModelsTests.swift in Sources" in PROJECT),
    ("native markdown helper exists", "enum HarnessMarkdown" in MODELS),
]
for name, ok in checks:
    if not ok:
        raise SystemExit(f"FAIL: {name}")
    print(f"ok: {name}")
