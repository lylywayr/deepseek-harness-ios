#!/usr/bin/env python3
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
WORKSPACE = (ROOT / "DeepSeekHarness/PocketWorkspaceViewController.swift").read_text()

class WorkspaceLayoutContractTests(unittest.TestCase):
    def test_proposal_a_order_is_explicit(self):
        order = [
            'configurePill(connectionButton', 'sectionHeading("今日概览"',
            'sectionHeading("继续工作"', 'makeSection("最近工作区"',
            'let start = dhButton(title: "开始新任务"', 'makeSection("最近会话"',
            'makeSection("活动中心"'
        ]
        positions = [WORKSPACE.index(marker) for marker in order]
        self.assertEqual(positions, sorted(positions))

    def test_safe_area_and_scroll_bottom_inset(self):
        self.assertIn('rootScroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)', WORKSPACE)
        self.assertIn('content.bottomAnchor.constraint(equalTo: rootScroll.contentLayoutGuide.bottomAnchor, constant: 12)', WORKSPACE)

    def test_continue_card_has_title_workspace_status_and_empty_state(self):
        self.assertIn('installCard(currentCard', WORKSPACE)
        self.assertIn('metadata(selected)', WORKSPACE)
        self.assertIn('"还没有选中的会话"', WORKSPACE)
        self.assertIn('暂无任务。开始新任务后', WORKSPACE)

    def test_legacy_activity_capabilities_are_compactly_retained(self):
        for marker in ('pendingSection', 'runningSection', 'artifactSection', 'showActivityCenter'):
            self.assertIn(marker, WORKSPACE)
        self.assertIn('activitySection.addArrangedSubview', WORKSPACE)

if __name__ == '__main__':
    unittest.main(verbosity=2)
