#!/usr/bin/env python3
"""Static acceptance contract for the native settings hierarchy.

The production Harness does not expose a plugin settings schema in this
checkout. These checks therefore focus on the native surface, its explicit
injection boundaries, and the absence of demo data or a market WebView.
"""
from __future__ import annotations

import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "DeepSeekHarness/HarnessSettingsCenterViewController.swift").read_text()
PROJECT = (ROOT / "DeepSeekHarness.xcodeproj/project.pbxproj").read_text()


class NativeSettingsContractTests(unittest.TestCase):
    def test_settings_controller_remains_in_app_target(self) -> None:
        self.assertIn("HarnessSettingsCenterViewController.swift in Sources", PROJECT)
        self.assertIn("HarnessSettingsCenterViewController.swift", PROJECT)
        self.assertFalse((ROOT / "Tests/settings_native_contract.py").exists())

    def test_official_top_level_order_and_client_boundary(self) -> None:
        anchors = [
            'title: "通用设置"',
            'title: "模型"',
            'title: "DeepPilot"',
            'title: "插件"',
            'title: "Agent 预设"',
            'title: "插件市场"',
        ]
        positions = [SOURCE.index(anchor) for anchor in anchors]
        self.assertEqual(positions, sorted(positions))
        self.assertIn("客户端专属入口（非官方设置）", SOURCE)
        self.assertIn("Harness 主机连接（客户端专属）", SOURCE)

        general_start = SOURCE.index("private func generalRows()")
        general_end = SOURCE.index("private func modelRows()", general_start)
        general = SOURCE[general_start:general_end]
        # The official second-level page must expose these six categories.  The
        # language row is intentionally fixed until a real language model and
        # persistence API exist; it must not imply a switch that cannot work.
        for marker in (
            'title: "语言"',
            'title: "新会话默认权限"',
            'title: "外观"',
            'title: "正文字号"',
            'title: "对话显示"',
            'title: "繁忙时 Enter"',
        ):
            self.assertIn(marker, general)
        self.assertIn(
            'SettingRow(title: "语言", subtitle: "跟随系统；当前客户端没有可变语言模型或持久化语言接口，不可在此配置。", value: "跟随系统", action: nil)',
            general,
        )

    def test_plugin_subscreens_and_real_configuration_items_exist(self) -> None:
        for marker in (
            'case pluginConfiguration',
            'case pluginList',
            'title: "插件配置"',
            'title: "插件列表"',
            'title: "插件市场"',
            'title: "终端"',
            'title: "Agent 循环"',
            'title: "Subagent"',
            '"会话插件"',
            '"全局插件"',
        ):
            self.assertIn(marker, SOURCE)

    def test_plugin_data_is_injected_and_missing_states_are_explicit(self) -> None:
        for marker in (
            "HarnessPluginListProvider",
            "HarnessPluginConfigurationProvider",
            "HarnessPluginMarketRoute",
            "case unavailable",
            "case loading",
            "case failed(String)",
            'value: "加载中"',
            'value: "不可用"',
            'value: "加载失败"',
            "currentAgentPreset",
            "UISearchController",
            "已启用",
            "已停用",
        ):
            self.assertIn(marker, SOURCE)

    def test_dynamic_counts_and_market_webview_are_absent(self) -> None:
        self.assertNotIn("WKWebView", SOURCE)
        self.assertNotIn("WebKit", SOURCE)
        self.assertNotRegex(SOURCE, r"(?<![0-9])(27|162|9)(?![0-9])")
        self.assertNotRegex(SOURCE, r"https?://")
        self.assertNotIn("example-plugin", SOURCE.lower())

        start = SOURCE.index("private func openPluginMarket()")
        end = SOURCE.index("@objc private func refreshPluginList", start)
        market = SOURCE[start:end]
        self.assertIn("if let onPluginMarket", market)
        self.assertIn("onPluginMarket()", market)
        self.assertIn("NotificationCenter.default.post", market)
        self.assertNotIn("UIAlertController", market)
        self.assertNotIn("present(alert", market)
        self.assertIn("side-effect free", market)
        self.assertIn("harnessPluginMarketRouteRequested", SOURCE)


    def test_native_accessibility_and_dynamic_type_hooks_exist(self) -> None:
        self.assertIn("adjustsFontForContentSizeCategory = true", SOURCE)
        self.assertIn("accessibilityLabel", SOURCE)
        self.assertIn("accessibilityTraits", SOURCE)
        self.assertIn("UIRefreshControl", SOURCE)


if __name__ == "__main__":
    unittest.main(verbosity=2)
