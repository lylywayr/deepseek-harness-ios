#!/usr/bin/env python3
"""Regression tests for the unsigned IPA marker gate.

The production market is the sole intentional WebKit boundary.  WebKit symbols
may therefore occur in its Release executable; legacy bridges, fixture code,
and private endpoint markers remain forbidden.
"""
from __future__ import annotations

import importlib.util
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
VERIFY_PATH = ROOT / "scripts/verify_ipa.py"

_spec = importlib.util.spec_from_file_location("verify_ipa", VERIFY_PATH)
assert _spec is not None and _spec.loader is not None
_verify = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_verify)


class IPAVerifierMarkerContractTests(unittest.TestCase):
    def test_webkit_market_markers_are_allowed_by_binary_gate(self) -> None:
        blob = b"WebKit WKWebView evaluateJavaScript"
        self.assertIsNone(_verify.first_forbidden_marker(blob))
        self.assertNotIn(b"WebKit", _verify.FORBIDDEN)
        self.assertNotIn(b"WKWebView", _verify.FORBIDDEN)
        self.assertNotIn(b"evaluateJavaScript", _verify.FORBIDDEN)

    def test_legacy_web_fixture_and_private_markers_remain_forbidden(self) -> None:
        for marker in _verify.FORBIDDEN:
            with self.subTest(marker=marker):
                self.assertEqual(_verify.first_forbidden_marker(b"prefix" + marker + b"suffix"), marker)

        for marker in (
            b"AutoNativeAdapter",
            b"HarnessWebView",
            b"window.__harnessNative",
            b"dom-projection",
            b"NativeFixtureViewController",
            b"UITestFixture",
            b"NativeFixtureScreen",
            b"192.168.31.2",
        ):
            self.assertIn(marker, _verify.FORBIDDEN)

    def test_marker_gate_does_not_replace_architecture_or_unsigned_checks(self) -> None:
        source = VERIFY_PATH.read_text(encoding="utf-8")
        for marker in (
            "CFBundleSupportedPlatforms",
            "MinimumOSVersion",
            "CPU_TYPE_ARM64",
            "arm64 slice missing",
            "_CodeSignature",
            "expected unsigned IPA",
        ):
            self.assertIn(marker, source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
