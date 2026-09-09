#!/usr/bin/env python3
"""Static contract gates for the isolated plugin-market surface.

These tests intentionally read source/resources only.  They do not launch the
app, open a URL, create a URLSession task, or issue a POST.
"""
from __future__ import annotations

import hashlib
import os
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
APP = ROOT / "DeepSeekHarness"
MARKET = (APP / "HarnessPluginMarketViewController.swift").read_text()
BOOTSTRAP = (APP / "MarketBootstrapClient.swift").read_text()
PROJECT = (ROOT / "DeepSeekHarness.xcodeproj/project.pbxproj").read_text()
NATIVE_MAIN = (APP / "NativeMainViewController.swift").read_text()
CSS = {
    "base": APP / "Resources/market-mobile-v1.41.0.css",
    "theme": APP / "Resources/theme-mobile-v1.41.0.css",
    "rendering": APP / "Resources/market-rendering-v1.41.0.css",
}

EXPECTED_CSS_SHA256 = {
    "base": "6c7f0f4adb2cd369d96bbed792b36453e7b30cafc340feb18c5f9ac0b3dd62fc",
    "theme": "1f0866dc2b26325b03781f2c167a9a4b6a66a3d2b3f6d4b3ec3958f5a3f59677",
    "rendering": "cf20a28838edf915dd851bd520c0cfc620f1d4478fe986fad8fd0473a5f7d1ed",
}


def script_bodies() -> tuple[str, ...]:
    """Return only the two JavaScript source literals in the market file."""
    bodies: list[str] = []
    markers = (
        'private static let versionDetectionScript = """',
        '        return """',
    )
    for marker in markers:
        start = MARKET.index(marker) + len(marker)
        end = MARKET.index('"""', start)
        bodies.append(MARKET[start:end])
    return tuple(bodies)


class MarketIntegrationContractTests(unittest.TestCase):
    def test_market_webview_is_unique_and_whitelisted(self) -> None:
        markers = ("WebKit", "WKWebView", "evaluateJavaScript")
        files_with_webkit: list[str] = []
        for path in sorted((APP).glob("*.swift")):
            source = path.read_text()
            if any(marker in source for marker in markers):
                files_with_webkit.append(path.name)
        self.assertEqual(files_with_webkit, ["HarnessPluginMarketViewController.swift"])
        self.assertEqual(MARKET.count("WKWebView(frame:"), 1)
        self.assertIn("final class HarnessPluginMarketViewController", MARKET)
        self.assertIn("private let webView: WKWebView", MARKET)

    def test_ephemeral_store_process_pool_origin_and_secure_cookie_contract(self) -> None:
        self.assertIn("configuration.websiteDataStore = .nonPersistent()", MARKET)
        self.assertIn("configuration.processPool = WKProcessPool()", MARKET)
        self.assertIn("guard let origin = MarketOrigin(url: marketURL)", MARKET)
        self.assertIn('scheme == "http" || scheme == "https"', MARKET)
        self.assertIn("url.user == nil, url.password == nil", MARKET)
        self.assertIn("url.scheme?.lowercased() == scheme", MARKET)
        self.assertIn("url.host?.lowercased() == host.lowercased()", MARKET)
        self.assertIn("url.port == port", MARKET)
        self.assertIn("let domainMatches = cookieDomain == marketHost", MARKET)
        self.assertIn("let transportMatches = marketOrigin.scheme != \"https\" || cookie.isSecure", MARKET)
        sync_start = MARKET.index("    func syncSameOriginCookies(")
        sync_end = MARKET.index("\n    func cancelLoading", sync_start)
        sync_body = MARKET[sync_start:sync_end]
        self.assertNotIn("setCookies", sync_body)
        self.assertNotIn("httpCookieStore.setCookies", MARKET)
        self.assertIn("let cookieStore = configuration.websiteDataStore.httpCookieStore", sync_body)
        self.assertIn("func setCookie(at index: Int)", sync_body)
        self.assertIn("guard index < accepted.count else", sync_body)
        self.assertIn("cookieStore.setCookie(accepted[index])", sync_body)
        self.assertIn("setCookie(at: index + 1)", sync_body)
        self.assertIn("setCookie(at: 0)", sync_body)
        self.assertEqual(sync_body.count("cookieStore.setCookie("), 1)
        self.assertEqual(sync_body.count("DispatchQueue.main.async"), 1)
        self.assertEqual(sync_body.count("completion?()"), 1)
        self.assertEqual(BOOTSTRAP.count("?? (installedVersion != nil)"), 2)
        self.assertNotIn("document.cookie", MARKET.lower())

    def test_market_javascript_has_no_credential_or_message_bridge_surface(self) -> None:
        scripts = script_bodies()
        self.assertEqual(len(scripts), 2)
        forbidden = (
            "document.cookie",
            "localstorage",
            "sessionstorage",
            "authorization",
            "bearer",
            "credential",
            "password",
            "token",
            "messagehandler",
            "postmessage",
            "fetch(",
            "xmlhttprequest",
        )
        for script in scripts:
            lowered = script.lower()
            for marker in forbidden:
                self.assertNotIn(marker, lowered, marker)
        self.assertIn("func javascriptStringLiteral", MARKET)
        self.assertIn("JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])", MARKET)

    def test_market_identifiers_keep_package_product_and_page_versions_separate(self) -> None:
        constants = {
            name: re.search(rf"static let {name} = \"([^\"]+)\"", BOOTSTRAP).group(1)
            for name in ("packageID", "productID", "verifiedPageVersion")
        }
        self.assertEqual(constants, {
            "packageID": "dshmarket",
            "productID": "dsh-market",
            "verifiedPageVersion": "v1.41.0",
        })
        self.assertEqual(len(set(constants.values())), 3)
        self.assertIn("let verifiedPackageVersion: String", BOOTSTRAP)
        self.assertIn("status.version == MarketBootstrapContract.verifiedPageVersion", BOOTSTRAP)
        self.assertIn("plugin.installedVersion == verifiedPackageVersion", BOOTSTRAP)

    def test_install_package_version_is_fixed_nonempty_and_not_latest(self) -> None:
        self.assertIn("guard Self.isFixedPackageVersion(verifiedPackageVersion)", BOOTSTRAP)
        for marker in (
            "trimmingCharacters(in: .whitespacesAndNewlines)",
            'version.lowercased() != "latest"',
            "version.contains(where: { $0.isNumber })",
            "version.allSatisfy { $0.isLetter || $0.isNumber || \".-_\".contains($0) }",
        ):
            self.assertIn(marker, BOOTSTRAP)
        self.assertIn("MarketBootstrapError.missingVerifiedPackageVersion", BOOTSTRAP)
        self.assertIn("MarketBootstrapError.invalidVerifiedPackageVersion", BOOTSTRAP)
        self.assertIn("payload.version == verifiedPackageVersion", BOOTSTRAP)
        self.assertIn("MarketInstallRequest(version: verifiedPackageVersion)", BOOTSTRAP)
        self.assertNotRegex(BOOTSTRAP, r'verifiedPackageVersion\s*=\s*["\']latest["\']')

    def test_status_install_and_job_endpoints_and_install_decisions(self) -> None:
        for path in (
            'static let statusPath = "mobile-bootstrap/market/status"',
            'static let installPath = "mobile-bootstrap/market/install"',
            'static let jobsPath = "mobile-bootstrap/jobs"',
        ):
            self.assertIn(path, BOOTSTRAP)
        self.assertIn('makeRequest(path: MarketBootstrapContract.statusPath, method: "GET")', BOOTSTRAP)
        self.assertIn('makeRequest(path: MarketBootstrapContract.installPath, method: "POST", body: body)', BOOTSTRAP)
        self.assertIn(r'makeRequest(path: "\(MarketBootstrapContract.jobsPath)/\(jobID)", method: "GET")', BOOTSTRAP)
        for decision in ("skipInstalledCompatible", "installMissing", "needsDecision(installedVersion:"):
            self.assertIn(decision, BOOTSTRAP)
        for guard in (
            "status.product == productID",
            "status.version == MarketBootstrapContract.verifiedPageVersion",
            "plugin.pluginID == packageID",
            "plugin.installed",
            "plugin.compatible == true",
            "MarketInstallationPolicy(verifiedPackageVersion: verifiedPackageVersion).decision(for: status)",
        ):
            self.assertIn(guard, BOOTSTRAP)

    def test_css_files_match_pinned_sha256_and_expected_market_selectors(self) -> None:
        actual = {
            name: hashlib.sha256(path.read_bytes()).hexdigest()
            for name, path in CSS.items()
        }
        self.assertEqual(actual, EXPECTED_CSS_SHA256)
        for digest in EXPECTED_CSS_SHA256.values():
            self.assertIn(digest, MARKET)
        for resource in (
            '("market-mobile-v1.41.0", "css", "market-mobile-v1.41.0.css")',
            '("theme-mobile-v1.41.0", "css", "theme-mobile-v1.41.0.css")',
            '("market-rendering-v1.41.0", "css", "market-rendering-v1.41.0.css")',
        ):
            self.assertIn(resource, MARKET)
        selectors = (
            ".nUhMVa_root",
            ".nUhMVa_tabSearchRow",
            ".nUhMVa_tabSearch",
            ".nUhMVa_tabs",
            ".nUhMVa_tab",
            ".nUhMVa_cats",
            ".nUhMVa_catsRow",
            ".nUhMVa_card",
            ".nUhMVa_version",
            ".nUhMVa_themeToolbar",
            ".nUhMVa_themeSearch",
            ".nUhMVa_themeCard",
            ".nUhMVa_themeGallery",
            ".nUhMVa_themeCover",
        )
        all_css = "\n".join(path.read_text() for path in CSS.values())
        for selector in selectors:
            self.assertIn(selector, all_css, selector)

    def test_rendering_css_does_not_hide_market_dom(self) -> None:
        rendering = CSS["rendering"].read_text()
        self.assertIn(".nUhMVa_root .nUhMVa_themeCard", rendering)
        self.assertIn(".nUhMVa_root .nUhMVa_card", rendering)
        self.assertIn("content-visibility: auto", rendering)
        self.assertNotRegex(rendering, r"(?i)\bdisplay\s*:\s*none\b")
        self.assertNotRegex(rendering, r"(?i)\bvisibility\s*:\s*hidden\b")
        self.assertNotRegex(rendering, r"(?i)\bopacity\s*:\s*0(?:\D|$)")

    def test_market_uses_crypto_integrity_and_safe_json_string_literals(self) -> None:
        self.assertIn("import CryptoKit", MARKET)
        self.assertIn("SHA256.hash(data: Data(value.utf8))", MARKET)
        self.assertIn("JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])", MARKET)
        self.assertIn("String(data: data, encoding: .utf8)", MARKET)

    def test_version_detection_has_attribute_and_text_fallback(self) -> None:
        self.assertIn("data-dsh-market-version", MARKET)
        self.assertIn("document.documentElement.getAttribute('data-dsh-market-version')", MARKET)
        self.assertIn("root.querySelector('.nUhMVa_version')", MARKET)
        self.assertIn("typeof versionNode.textContent === 'string'", MARKET)
        self.assertIn("typeof node.textContent === 'string'", MARKET)
        self.assertIn("guard version == MarketBootstrapContract.verifiedPageVersion else", MARKET)
        self.assertIn("self.cssBundle.removeStyles(from: self.webView)", MARKET)
        self.assertIn("if (versionFromDOM() !== verifiedVersion)", MARKET)
        self.assertIn("root.ownerDocument.querySelectorAll('style[data-dsh-market-css]')", MARKET)

    def test_mutation_observer_reapplies_only_on_relevant_dom_changes(self) -> None:
        for marker in (
            "const observer = new MutationObserver",
            "root.ownerDocument.documentElement",
            "root.ownerDocument.head",
            "root.ownerDocument.body",
            "observed.forEach(node => observer.observe(node, { childList: true, subtree: true, characterData: true }));",
            "root.__dshMarketObserver = observer",
            "requestAnimationFrame(() =>",
            "const relevant = (record) =>",
            "closest('style[data-dsh-market-css]')",
        ):
            self.assertIn(marker, MARKET)

    def test_theme_css_is_gated_by_page_key_and_verified_version(self) -> None:
        for marker in (
            "const pageKey = () =>",
            ".nUhMVa_themeCard",
            "/theme|主题|主题库/",
            "if (pageKey().split(':')[1] === 'theme') add('theme', themeCSS);",
            "else remove('theme');",
            "if (versionFromDOM() !== verifiedVersion)",
            "add('base', baseCSS);",
            "add('rendering', renderingCSS);",
        ):
            self.assertIn(marker, MARKET)

    def test_ios_16_4_inspection_guard_is_explicit(self) -> None:
        self.assertIn("if #available(iOS 16.4, *)", MARKET)
        self.assertIn("self.webView.isInspectable = false", MARKET)

    def test_pending_pbx_and_native_entry_is_skip_by_default_but_required_on_demand(self) -> None:
        missing: list[str] = []
        for marker in (
            "HarnessPluginMarketViewController.swift in Sources",
            "MarketBootstrapClient.swift in Sources",
        ):
            if marker not in PROJECT:
                missing.append(f"pbx:{marker}")
        for marker in ("HarnessPluginMarketViewController", "MarketBootstrapClient"):
            if marker not in NATIVE_MAIN:
                missing.append(f"NativeMain:{marker}")
        if missing:
            message = "market wiring pending: " + ", ".join(missing)
            if os.environ.get("MARKET_WIRING_REQUIRED") == "1":
                self.fail("MARKET_WIRING_REQUIRED=1 but " + message)
            self.skipTest(message)
        self.assertIn("HarnessPluginMarketViewController", NATIVE_MAIN)
        self.assertIn("MarketBootstrapClient", NATIVE_MAIN)


if __name__ == "__main__":
    unittest.main(verbosity=2)
