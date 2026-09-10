#!/usr/bin/env python3
"""Static contract for the ordered screenshot evidence workflow.

The test intentionally avoids a YAML dependency and checks the emitted workflow
text so it can run in the repository's dependency-free Python gates.
"""
from __future__ import annotations

import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github/workflows/build-ipa.yml"


class BuildIpaWorkflowContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.workflow = WORKFLOW.read_text(encoding="utf-8")
        marker = "  native-ui-screenshots:\n"
        self.assertIn(marker, self.workflow)
        self.native_job = self.workflow.split(marker, 1)[1]

    def test_legacy_matrix_remains_before_v3_and_unchanged(self) -> None:
        old_capture = "      - name: Capture Pocket screenshots\n"
        old_validate = "      - name: Validate Pocket screenshot artifacts\n"
        old_upload = "      - name: Upload Pocket screenshots\n"
        v3_capture = "      - name: Capture conversation v3 screenshots\n"
        v3_validate = "      - name: Validate conversation v3 artifacts\n"
        v3_upload = "      - name: Upload conversation v3 artifacts\n"

        positions = [
            self.native_job.index(marker)
            for marker in (
                old_capture,
                old_validate,
                old_upload,
                v3_capture,
                v3_validate,
                v3_upload,
            )
        ]
        self.assertEqual(positions, sorted(positions))
        self.assertEqual(self.native_job.count(old_capture), 1)
        self.assertEqual(self.native_job.count(old_validate), 1)
        self.assertEqual(self.native_job.count(old_upload), 1)

        legacy_prefix = self.native_job[: self.native_job.index(v3_capture)]
        self.assertIn(
            "          chmod +x scripts/capture_native_ui.sh\n"
            "          SIMCTL_TIMEOUT_SECONDS=180 scripts/capture_native_ui.sh\n",
            legacy_prefix,
        )
        self.assertIn(
            "          test -d \"$GITHUB_WORKSPACE/artifacts/pocket-v2-ui-matrix\"\n"
            "          png_count=\"$(find \"$GITHUB_WORKSPACE/artifacts/pocket-v2-ui-matrix\" -type f -name '*.png' | wc -l | tr -d ' ')\"\n"
            "          test \"$png_count\" -gt 0\n"
            "          python3 scripts/verify_screenshot_artifacts.py artifacts/pocket-v2-ui-matrix\n",
            legacy_prefix,
        )
        self.assertIn(
            "          name: pocket-v2-ui-matrix\n"
            "          path: ${{ github.workspace }}/artifacts/pocket-v2-ui-matrix/**\n"
            "          if-no-files-found: error\n",
            legacy_prefix,
        )

    def test_v3_reuses_debug_app_and_same_clean_output_directory(self) -> None:
        start = self.native_job.index("      - name: Capture conversation v3 screenshots\n")
        v3 = self.native_job[start:]
        self.assertIn(
            'APP_PATH="$GITHUB_WORKSPACE/build/Build/Products/Debug-iphonesimulator/DeepSeekHarness.app"',
            v3,
        )
        self.assertIn(
            'OUT="$GITHUB_WORKSPACE/artifacts/p4-conversation-v3"',
            v3,
        )
        self.assertIn('test -d "$APP_PATH"', v3)
        self.assertIn(
            'bash scripts/capture_conversation_v3.sh "$APP_PATH" "$OUT"',
            v3,
        )
        self.assertIn(
            'python3 scripts/verify_conversation_v3_artifacts.py "$GITHUB_WORKSPACE/artifacts/p4-conversation-v3"',
            v3,
        )
        self.assertNotIn("pocket-v2-ui-matrix", v3)

    def test_v3_upload_contract_and_fail_closed_steps(self) -> None:
        start = self.native_job.index("      - name: Capture conversation v3 screenshots\n")
        v3 = self.native_job[start:]
        self.assertIn(
            "          name: p4-conversation-v3\n"
            "          path: ${{ github.workspace }}/artifacts/p4-conversation-v3/**\n"
            "          if-no-files-found: error\n",
            v3,
        )
        self.assertEqual(v3.count("if-no-files-found: error"), 2)
        self.assertEqual(v3.count("set -euo pipefail"), 2)
        self.assertNotRegex(v3, r"(?m)^\s*continue-on-error\s*:")
        self.assertNotRegex(v3, r"\|\|\s*true")
        self.assertNotRegex(v3, r"(?i)\b(?:exclude|excluded|post[- ]?process(?:ing)?|copy|noise|noisy)\b")
        self.assertEqual(v3.count("        if: ${{ failure() }}\n"), 1)
        self.assertIn(
            "      - name: Upload failed conversation v3 diagnostics\n"
            "        if: ${{ failure() }}\n"
            "        uses: actions/upload-artifact@v4\n",
            v3,
        )
        self.assertNotRegex(v3, r"(?m)^\s*(?:cp|mv|rsync|sips|convert)\b")

    def test_v3_steps_have_no_failure_swallowing_or_exclusion(self) -> None:
        start = self.native_job.index("      - name: Capture conversation v3 screenshots\n")
        v3 = self.native_job[start:]
        for forbidden in ("always()", "success()", "if-no-files-found: warn"):
            self.assertNotIn(forbidden, v3)
        self.assertEqual(v3.count("failure()"), 1)
        self.assertEqual(v3.count('bash scripts/capture_conversation_v3.sh "$APP_PATH" "$OUT"'), 1)
        self.assertEqual(
            v3.count(
                'python3 scripts/verify_conversation_v3_artifacts.py '
                '"$GITHUB_WORKSPACE/artifacts/p4-conversation-v3"'
            ),
            1,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
