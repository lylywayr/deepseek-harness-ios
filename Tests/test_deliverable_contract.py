#!/usr/bin/env python3
"""Integration and delivery gates for the native iOS audit.

The audit runs against the current checkout, not against a historical branch or
an IPA copied from another run.  Known integration gaps are deliberately
optional in the normal mode so the historical full suite stays useful.  Set
``DELIVERABLE_REQUIRED=1`` on the integration branch to turn each optional
feature into an exact, named failure.
"""
from __future__ import annotations

import hashlib
import os
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
APP_ROOT = ROOT / "DeepSeekHarness"
INFO_PLIST = APP_ROOT / "Info.plist"
PROJECT = ROOT / "DeepSeekHarness.xcodeproj/project.pbxproj"
REQUIRED = os.environ.get("DELIVERABLE_REQUIRED") == "1"

BASE_CSS_SHA256 = "6c7f0f4adb2cd369d96bbed792b36453e7b30cafc340feb18c5f9ac0b3dd62fc"
THEME_CSS_SHA256 = "1f0866dc2b26325b03781f2c167a9a4b6a66a3d2b3f6d4b3ec3958f5a3f59677"
MARKET_GLOB = "*Plugin*Market*.swift"
KNOWN_OPTIONAL_FEATURES = {"settings", "market", "export", "context-sheet"}


def read(path: pathlib.Path) -> str:
    return path.read_text(encoding="utf-8")


def swift_sources() -> list[pathlib.Path]:
    return sorted(APP_ROOT.glob("*.swift"))


def class_names(source: str) -> list[str]:
    """Return ordinary Swift class declarations, excluding extensions."""
    return re.findall(r"\b(?:final\s+|open\s+|public\s+|private\s+)?class\s+([A-Za-z_]\w*)\b", source)


class DeliverableContractTests(unittest.TestCase):
    """Static gates which can run on Alpine without Xcode or an endpoint."""

    def setUp(self) -> None:
        self.sources = {path: read(path) for path in swift_sources()}
        self.production = "\n".join(self.sources.values())

    def require_feature(self, name: str, present: bool, reason: str) -> bool:
        """Require an optional integration feature without weakening safety.

        Every currently known integration gap goes through this helper.  A
        normal audit records a visible skip; required integration turns that
        same skip into one deterministic assertion failure.  Callers use
        ordinary assertions for security invariants, so those never skip.
        """
        self.assertIn(name, KNOWN_OPTIONAL_FEATURES, f"unknown optional feature: {name}")
        if present:
            return True
        message = f"feature={name}: {reason}"
        if REQUIRED:
            self.fail("DELIVERABLE_REQUIRED: " + message)
        self.skipTest("DELIVERABLE_OPTIONAL_SKIP: " + message)
        return False

    def market_candidates(self) -> list[pathlib.Path]:
        # Deliberately discover the production name; do not bake in one
        # historical filename such as PluginMarketViewController.swift.
        return sorted(APP_ROOT.glob(MARKET_GLOB))

    def market_bootstrap_sources(self) -> list[tuple[pathlib.Path, str]]:
        return [
            (path, source)
            for path, source in self.sources.items()
            if all(marker in source for marker in ("makeStatusRequest", "makeInstallRequest", "makeJobRequest"))
        ]

    def test_native_ui_is_constrained_and_legacy_is_not_silently_opened(self) -> None:
        protocol = read(APP_ROOT / "NativeUIProtocol.swift")
        renderer = read(APP_ROOT / "NativeUIRenderer.swift")
        views = read(APP_ROOT / "NativeUIViews.swift")
        self.assertIn("struct NativeUIManifest", protocol)
        self.assertIn("struct NativeUINode", protocol)
        self.assertIn("NativeUIActionRequest", protocol)
        self.assertIn("NativeUITransport", protocol)
        self.assertIn("NativeUIRenderer", renderer)
        self.assertIn("case \"legacy\", \"web\"", renderer)
        self.assertIn("isLegacyOnly", views + protocol)
        self.assertRegex(renderer, r"not available|不可用|不支持")

    def test_hard_security_boundaries_always_fail(self) -> None:
        """Non-whitelisted web views and literal credentials are never skips."""
        candidates = set(self.market_candidates())
        webview_paths = {
            path
            for path, source in self.sources.items()
            if re.search(r"\b(?:WebKit|WKWebView)\b", source)
        }
        non_whitelisted = sorted(webview_paths - candidates)
        self.assertEqual(
            non_whitelisted,
            [],
            "WKWebView/WebKit is only allowed in a discovered *Plugin*Market*.swift candidate: "
            + ", ".join(str(path.relative_to(ROOT)) for path in non_whitelisted),
        )

        credential_patterns = (
            r"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----",
            r"\bBearer\s+[A-Za-z0-9._~+/=-]{24,}",
            r"\b(?:ghp|gho|github_pat|sk|AKIA)[A-Za-z0-9_-]{16,}",
            r"https?://[^\s\"']+:[^\s\"']+@",
            r"\b(?:api[_-]?key|client[_-]?secret|password)\s*[:=]\s*[\"'][^\"']{16,}[\"']",
        )
        for path, source in self.sources.items():
            for pattern in credential_patterns:
                self.assertIsNone(
                    re.search(pattern, source, flags=re.IGNORECASE),
                    f"possible literal credential in {path.relative_to(ROOT)}: {pattern}",
                )

    def test_market_single_boundary_css_and_bootstrap_contract(self) -> None:
        """Discover, then fully validate the sole optional market boundary."""
        resource_dir = APP_ROOT / "Resources"
        css_files = sorted(resource_dir.glob("*.css")) if resource_dir.exists() else []
        if css_files:
            css_by_stem = {path.stem: path for path in css_files}
            for resource_name, expected_sha256 in (
                ("market-mobile-v1.41.0", BASE_CSS_SHA256),
                ("theme-mobile-v1.41.0", THEME_CSS_SHA256),
            ):
                resource = css_by_stem.get(resource_name)
                self.assertIsNotNone(resource, f"missing bundled CSS resource {resource_name}.css")
                self.assertEqual(
                    hashlib.sha256(resource.read_bytes()).hexdigest(),
                    expected_sha256,
                    f"unexpected byte SHA-256 for {resource_name}.css",
                )

        candidates = self.market_candidates()
        if not self.require_feature(
            "market",
            len(candidates) == 1,
            "expected exactly one production candidate matching "
            f"DeepSeekHarness/{MARKET_GLOB}; found {len(candidates)}",
        ):
            return

        candidate = candidates[0]
        source = read(candidate)
        names = class_names(source)
        self.assertEqual(len(names), 1, "market candidate must contain exactly one class")
        self.assertEqual(
            len(re.findall(r"\bWKWebView\s*\(", source)),
            1,
            "market boundary must construct exactly one WKWebView",
        )
        self.assertIn("WKWebViewConfiguration", source)
        self.assertIn("websiteDataStore = .nonPersistent()", source)
        self.assertIn("processPool = WKProcessPool()", source)
        self.assertIn("navigationDelegate", source)
        self.assertIn("WKNavigationDelegate", source)
        self.assertIn("MarketOrigin", source)
        self.assertIn("marketOrigin.matches", source)
        self.assertIn("externalNavigationHandler", source)
        self.assertIn("httpCookieStore", source)
        self.assertIn("cookieDomain", source)
        self.assertIn("cookie.isSecure", source)
        self.assertNotRegex(source, r"evaluateJavaScript[^\n]*(?:token|credential|authorization)")
        self.assertNotRegex(source, r"(?i)(?:localStorage|postMessage)\s*[^\n]*(?:token|credential)")
        self.assertIn("MarketBootstrapContract.verifiedVersion", source)
        self.assertIn("removeStyles", source)
        self.assertIn("lastInjectedPageKey", source)
        self.assertIn("data-dsh-market-css", source)
        self.assertIn(BASE_CSS_SHA256, source)
        self.assertIn(THEME_CSS_SHA256, source)
        self.assertNotIn("cf20a28838edf915dd851bd520c0cfc620f1d4478fe986fad8fd0473a5f7d1ed", source)

        bootstrap = self.market_bootstrap_sources()
        self.assertEqual(len(bootstrap), 1, "market bootstrap contract must have one source")
        bootstrap_path, bootstrap_source = bootstrap[0]
        self.assertIn("statusPath", bootstrap_source)
        self.assertIn("installPath", bootstrap_source)
        self.assertIn("jobsPath", bootstrap_source)
        self.assertIn("makeStatusRequest", bootstrap_source)
        self.assertIn("makeInstallRequest", bootstrap_source)
        self.assertIn("makeJobRequest", bootstrap_source)
        self.assertIn("isSafeJobID", bootstrap_source)
        self.assertIn("httpShouldHandleCookies", bootstrap_source)
        self.assertNotRegex(bootstrap_source, r"setValue\([^\n]*(?:Authorization|Bearer)")
        self.assertNotIn("token=", bootstrap_source.lower())

        project = read(PROJECT)
        self.assertIn(candidate.name, project, f"{candidate.name} is not in the app target")
        self.assertIn(bootstrap_path.name, project, f"{bootstrap_path.name} is not in the app target")
        resource_dir = APP_ROOT / "Resources"
        css_files = sorted(resource_dir.glob("*.css")) if resource_dir.exists() else []
        self.assertGreaterEqual(len(css_files), 3, "versioned market CSS resources are incomplete")
        names_in_source = re.findall(r'\("([A-Za-z0-9_-]+)",\s*"css"\)', source)
        for resource_name in names_in_source:
            self.assertTrue(
                any(path.stem == resource_name for path in css_files),
                f"missing bundled CSS resource {resource_name}.css",
            )
        css_by_stem = {path.stem: path for path in css_files}
        for resource_name, expected_sha256 in (
            ("market-mobile-v1.41.0", BASE_CSS_SHA256),
            ("theme-mobile-v1.41.0", THEME_CSS_SHA256),
        ):
            resource = css_by_stem.get(resource_name)
            self.assertIsNotNone(resource, f"missing bundled CSS resource {resource_name}.css")
            self.assertEqual(
                hashlib.sha256(resource.read_bytes()).hexdigest(),
                expected_sha256,
                f"unexpected byte SHA-256 for {resource_name}.css",
            )
        self.assertRegex(source, r"(?i)(?:sha256|SHA256|CryptoKit|integrity)")

    def test_release_marker_and_unverified_declaration(self) -> None:
        plist = read(INFO_PLIST)
        self.assertRegex(plist, r"<key>CFBundleShortVersionString</key>\s*<string>[^<]+</string>")
        self.assertRegex(plist, r"<key>CFBundleVersion</key>\s*<string>[^<]+</string>")
        self.assertNotIn("$(MARKETING_VERSION)", plist)
        self.assertNotIn("$(CURRENT_PROJECT_VERSION)", plist)

        evidence_text = "\n".join(
            read(path)
            for path in sorted(ROOT.glob("README.md")) + sorted((ROOT / "docs").glob("*.md"))
        )
        self.assertRegex(evidence_text, r"未验证|未联调|not a substitute|not claim|remain acceptance")

    def test_dynamic_data_is_not_faked_in_settings_or_plugin_surfaces(self) -> None:
        settings_path = APP_ROOT / "HarnessSettingsCenterViewController.swift"
        settings = read(settings_path)
        # Counts must come from providers/Runtime.  This targets the known
        # 27/162/9-style regression without rejecting ordinary UIKit geometry.
        self.assertIsNone(
            re.search(r"(?is)(?:plugin|market|agent|subagent).{0,120}\b(?:27|162|9)\b", settings),
            "settings/plugin data contains a hard-coded dynamic count",
        )
        self.assertNotRegex(settings, r"(?i)\b(?:demo|sample|mock)\s+(?:plugin|market|agent)")
        self.assertRegex(settings, r"(?:loading|加载中|unavailable|不可用|failed|失败|empty|空)")

    def test_optional_settings_integration_uses_require_feature(self) -> None:
        settings = read(APP_ROOT / "HarnessSettingsCenterViewController.swift")
        present = all(
            marker in settings
            for marker in (
                "HarnessPluginSnapshot",
                "pluginConfigurationRows",
                "pluginListRows",
                "onPluginMarket",
            )
        )
        self.require_feature(
            "settings",
            present,
            "rich plugin configuration/list settings are not integrated on this audit HEAD",
        )

    def test_optional_official_export_boundary_uses_require_feature(self) -> None:
        present = bool(
            re.search(
                r"UIActivityViewController|exportArtifact|officialExport|artifacts/export|exportPath",
                self.production,
                flags=re.IGNORECASE,
            )
        )
        self.require_feature(
            "export",
            present,
            "official export endpoint or native share boundary is not integrated",
        )

    def test_optional_context_sheet_uses_require_feature(self) -> None:
        """Recognize the native four-sheet controls, not a web context menu."""
        conversation_path = APP_ROOT / "PocketConversationViewController.swift"
        conversation = read(conversation_path)
        related = "\n".join(
            read(path)
            for path in (
                APP_ROOT / "PocketWorkspaceViewController.swift",
                APP_ROOT / "HarnessRuntime.swift",
            )
            if path.exists()
        )
        context_sources = conversation + "\n" + related
        self.assertNotIn("UIContextMenuInteraction", context_sources)
        context_markers = (
            r"\bchooseContext\b",
            r"\bcontextButton\b",
            r"\bcontextDirectory\b",
            r"\b(?:show|present|open|toggle)[A-Z]\w*Context(?:Sheet)?\b",
            r"\bcontext(?:Sheet|Drawer)\b",
        )
        context_present = any(re.search(marker, context_sources) for marker in context_markers)

        # These are existing native action-sheet entry points and must remain
        # independently wired while the context surface is checked.
        for button, action in (
            ("modelButton", "chooseModel"),
            ("reasoningButton", "chooseReasoning"),
            ("permissionButton", "choosePermission"),
        ):
            self.assertIn(button, conversation, f"missing native {button} entry point")
            self.assertIn(action, conversation, f"missing native {action} entry point")

        self.require_feature(
            "context-sheet",
            context_present,
            "native context sheet/drawer entry point is not present on this audit HEAD",
        )



if __name__ == "__main__":
    unittest.main(verbosity=2)
