#!/usr/bin/env python3
"""Static contract for the Light/Dark AppIcon asset catalog.

The uploaded source files are intentionally not part of the repository.  The
mapping contract therefore uses the stable generated-output SHA-256 values and
asset-catalog structure rather than an absolute uploads path.  The source to
output pixel comparison is recorded separately in the child evidence.
"""
from __future__ import annotations

import hashlib
import json
import pathlib
import re
import struct
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
APPICON_DIR = ROOT / "DeepSeekHarness/Assets.xcassets/AppIcon.appiconset"
CONTENTS = APPICON_DIR / "Contents.json"
PROJECT = ROOT / "DeepSeekHarness.xcodeproj/project.pbxproj"

# These are the deterministic outputs produced from the two supplied source
# images with a square, aspect-preserving 1024px LANCZOS resize.  Keeping the
# source labels and output hashes here gives a source-mapping gate without
# coupling tests to a user's /var/minis/attachments/uploads directory.
SOURCE_OUTPUT_CONTRACT = {
    "Light": {
        "source_label": "photo_3384E27E",
        "filename": "AppIcon-Light-1024.png",
        "sha256": "6de8b5d4ee647d0283655b559d8a83f544e07ea0dcd63e249803f83cc5af17a4",
        "appearance": None,
    },
    "Dark": {
        "source_label": "photo_E218A9F4",
        "filename": "AppIcon-Dark-1024.png",
        "sha256": "6c27f05ecc134cd3baee95fb341aabe3943e6431a8f760bea965fdb48eb95b3b",
        "appearance": {"appearance": "luminosity", "value": "dark"},
    },
}


class AppIconContractTests(unittest.TestCase):
    def test_catalog_contains_only_expected_light_dark_assets(self) -> None:
        self.assertTrue(APPICON_DIR.is_dir(), "AppIcon.appiconset is missing")
        self.assertTrue(CONTENTS.is_file(), "AppIcon Contents.json is missing")
        self.assertEqual(
            {path.name for path in APPICON_DIR.iterdir()},
            {"Contents.json", "AppIcon-Light-1024.png", "AppIcon-Dark-1024.png"},
        )

        contents = json.loads(CONTENTS.read_text(encoding="utf-8"))
        self.assertEqual(contents.get("info"), {"author": "xcode", "version": 1})
        images = contents.get("images")
        self.assertIsInstance(images, list)
        self.assertEqual(len(images), 2)

        by_filename = {entry.get("filename"): entry for entry in images}
        self.assertEqual(set(by_filename), {item["filename"] for item in SOURCE_OUTPUT_CONTRACT.values()})
        for mode, contract in SOURCE_OUTPUT_CONTRACT.items():
            entry = by_filename[contract["filename"]]
            self.assertEqual(entry.get("idiom"), "universal", mode)
            self.assertEqual(entry.get("platform"), "ios", mode)
            self.assertEqual(entry.get("scale"), "1x", mode)
            self.assertEqual(entry.get("size"), "1024x1024", mode)
            if contract["appearance"] is None:
                self.assertNotIn("appearances", entry, "Light must be the default appearance")
            else:
                self.assertEqual(entry.get("appearances"), [contract["appearance"]])

    def test_output_pngs_are_1024_rgb_and_match_source_mapping_hashes(self) -> None:
        for mode, contract in SOURCE_OUTPUT_CONTRACT.items():
            path = APPICON_DIR / contract["filename"]
            self.assertTrue(path.is_file(), mode)
            self.assertEqual(
                hashlib.sha256(path.read_bytes()).hexdigest(),
                contract["sha256"],
                f"{mode} output changed or source mapping is wrong",
            )
            width, height, bit_depth, color_type, interlace = self._read_png_ihdr(path)
            self.assertEqual((width, height), (1024, 1024), mode)
            self.assertEqual(bit_depth, 8, mode)
            self.assertEqual(color_type, 2, f"{mode} must be RGB, not indexed/alpha")
            self.assertEqual(interlace, 0, mode)

        self.assertNotEqual(
            SOURCE_OUTPUT_CONTRACT["Light"]["sha256"],
            SOURCE_OUTPUT_CONTRACT["Dark"]["sha256"],
            "Light and Dark outputs must not be interchangeable",
        )

    def test_app_target_uses_appicon_in_debug_and_release(self) -> None:
        project = PROJECT.read_text(encoding="utf-8")
        self.assertTrue(PROJECT.is_file())

        # Resolve the application target's configuration list rather than
        # accepting a setting that only belongs to the unit-test target.
        app_target = re.search(
            r"(?ms)^\s*[A-F0-9]+ /\* DeepSeekHarness \*/ = \{.*?"
            r"\n\s*buildConfigurationList = ([A-F0-9]+) /\*[^*]+\*/;.*?"
            r"\n\s*productType = \"com\.apple\.product-type\.application\";",
            project,
        )
        self.assertIsNotNone(app_target, "application target is missing")
        config_list_id = app_target.group(1)
        config_list = re.search(
            rf"(?ms)^\s*{re.escape(config_list_id)} /\*[^*]+\*/ = \{{.*?"
            r"\n\s*buildConfigurations = \(\s*(.*?)\n\s*\);",
            project,
        )
        self.assertIsNotNone(config_list, "application build configuration list is missing")
        config_ids = re.findall(r"([A-F0-9]+) /\* (Debug|Release) \*/", config_list.group(1))
        self.assertEqual({name for _, name in config_ids}, {"Debug", "Release"})

        for config_id, name in config_ids:
            block = re.search(
                rf"(?ms)^\s*{re.escape(config_id)} /\* {name} \*/ = \{{.*?"
                r"\n\s*name = (?:Debug|Release);\s*\n\s*\};",
                project,
            )
            self.assertIsNotNone(block, f"{name} configuration block is missing")
            self.assertIn("ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;", block.group(0))

    def test_assets_catalog_is_registered_once_as_existing_resource(self) -> None:
        project = PROJECT.read_text(encoding="utf-8")
        build_file = re.findall(r"/\* Assets\.xcassets in Resources \*/", project)
        self.assertEqual(len(build_file), 2, "one definition and one Resources-phase reference expected")
        self.assertEqual(project.count("Assets.xcassets in Resources"), 2)

        resources_phase = re.search(
            r"(?ms)/\* Begin PBXResourcesBuildPhase section \*/(.*?)/\* End PBXResourcesBuildPhase section \*/",
            project,
        )
        self.assertIsNotNone(resources_phase)
        self.assertEqual(resources_phase.group(1).count("Assets.xcassets in Resources"), 1)
        self.assertNotIn("AppIcon.appiconset in Resources", resources_phase.group(1))

    @staticmethod
    def _read_png_ihdr(path: pathlib.Path) -> tuple[int, int, int, int, int]:
        data = path.read_bytes()
        signature = b"\x89PNG\r\n\x1a\n"
        if data[:8] != signature:
            raise AssertionError(f"not a PNG: {path}")
        if data[12:16] != b"IHDR" or len(data) < 29:
            raise AssertionError(f"PNG IHDR missing: {path}")
        width, height, bit_depth, color_type, _compression, _filter, interlace = struct.unpack(
            ">IIBBBBB", data[16:29]
        )
        return width, height, bit_depth, color_type, interlace


if __name__ == "__main__":
    unittest.main()
