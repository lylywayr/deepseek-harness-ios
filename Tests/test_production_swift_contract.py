#!/usr/bin/env python3
"""Static regression checks for production Swift wire integration.

This does not replace XCTest; it ensures CI cannot silently drop the production
helper from the app target or reintroduce the known empty session/list args.
"""
from __future__ import annotations

import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
APPSTATE = (ROOT / "DeepSeekHarness/AppState.swift").read_text()
ENDPOINT = (ROOT / "DeepSeekHarness/HarnessEndpoint.swift").read_text()
RUNTIME = (ROOT / "DeepSeekHarness/HarnessRuntime.swift").read_text()
WIRE = (ROOT / "DeepSeekHarness/HarnessWire.swift").read_text()
PROJECT = (ROOT / "DeepSeekHarness.xcodeproj/project.pbxproj").read_text()


class ProductionSwiftContractTests(unittest.TestCase):
    def test_wire_is_in_app_sources_and_runtime_uses_it(self) -> None:
        self.assertIn("HarnessWire.swift in Sources", PROJECT)
        self.assertIn("HarnessWire.swift", PROJECT)
        self.assertIn("HarnessWire.rpcRequest", RUNTIME)
        self.assertIn("HarnessWire.rpcResponse", RUNTIME)

    def test_session_list_never_constructs_empty_args(self) -> None:
        self.assertIn("HarnessWire.sessionListArguments()", RUNTIME)
        self.assertNotRegex(RUNTIME, r'call\("session/list",\s*args:\s*\[:\]\)')
        self.assertIn('"_request": [String: Any]()', WIRE)

    def test_request_bearing_calls_use_request_helper(self) -> None:
        for endpoint in (
            "session/create", "session/prompt", "session/cancel",
            "session/page", "session/selectModel", "session/rename",
            "session/fork", "workspace/create", "workspace/rename",
            "workspace/delete", "workspace/archiveSession",
        ):
            self.assertIn(f'call("{endpoint}"', RUNTIME)
        self.assertGreaterEqual(RUNTIME.count("HarnessWire.requestArguments("), 9)

    def test_directory_calls_remain_top_level(self) -> None:
        self.assertIn("HarnessWire.directoryListArguments(path: path)", RUNTIME)
        self.assertIn("HarnessWire.directoryCreateArguments(path: path, name: name)", RUNTIME)

    def test_apple_production_layout_contract(self) -> None:
        workspace = (ROOT / "DeepSeekHarness/PocketWorkspaceViewController.swift").read_text()
        conversation = (ROOT / "DeepSeekHarness/PocketConversationViewController.swift").read_text()
        fixture = (ROOT / "DeepSeekHarness/NativeFixtureViewController.swift").read_text()
        self.assertIn('number.text = "\\(value)"', workspace)
        self.assertNotIn('number.text = "\\\\(value)"', workspace)
        for marker in ("AppleBottomNavigationView", "工作台", "会话", "活动", "设置"):
            self.assertIn(marker, workspace)
        for marker in ("AppleConversationModeTabs", "underline", "selectedIndex"):
            self.assertIn(marker, conversation)
        self.assertTrue(fixture.lstrip().startswith("import UIKit\n\n#if DEBUG"))

        self.assertIn("HarnessEndpointCanonicalizer", ENDPOINT)
        self.assertIn("HarnessEndpointCanonicalizer.canonicalize", APPSTATE)
        self.assertIn("HarnessEndpointCanonicalizer.canonicalize", RUNTIME)
        self.assertIn("HarnessEndpoint.swift in Sources", PROJECT)
        self.assertIn("HarnessEndpoint.swift in Tests", PROJECT)
        self.assertIn("queryItems = remaining.isEmpty ? nil : remaining", ENDPOINT)
        self.assertIn("components.fragment = nil", ENDPOINT)
        self.assertIn("func bootstrapURL()", RUNTIME)
        self.assertIn("func apiURL(_ endpoint: String)", RUNTIME)
        self.assertIn("func webSocketRequest()", RUNTIME)

        for path in (ROOT / "DeepSeekHarness").glob("*.swift"):
            source = path.read_text()
            for marker in ("WebKit", "WKWebView", "evaluateJavaScript", "AutoNativeAdapter", "HarnessWebView", "openLegacy", "legacyURL", "dom-projection"):
                self.assertNotIn(marker, source, f"{marker} in {path}")


if __name__ == "__main__":
    unittest.main(verbosity=2)
