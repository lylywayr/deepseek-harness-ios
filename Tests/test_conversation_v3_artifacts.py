#!/usr/bin/env python3
"""Unit tests for the conversation-v3 artifact contract.

These tests create small valid PNGs with the contract dimensions in a temporary
folder.  They exercise the validator directly and never require Xcode,
CoreSimulator, or simctl.
"""
from __future__ import annotations

import hashlib
import json
import pathlib
import struct
import sys
import tempfile
import unittest
import zlib
from typing import Any, Dict, List

SCRIPTS = pathlib.Path(__file__).resolve().parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))

from verify_conversation_v3_artifacts import (  # noqa: E402
    EXPECTED_ARTIFACTS,
    ArtifactValidationError,
    validate_artifacts,
)


PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def _chunk(kind: bytes, payload: bytes) -> bytes:
    return (
        struct.pack(">I", len(payload))
        + kind
        + payload
        + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)
    )


def _png(width: int, height: int, rgb: tuple[int, int, int]) -> bytes:
    """Return a valid, non-interlaced 8-bit RGB PNG for validator fixtures."""
    row = bytes((0,)) + bytes(rgb) * width
    pixels = zlib.compress(row * height, level=1)
    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return PNG_SIGNATURE + _chunk(b"IHDR", header) + _chunk(b"IDAT", pixels) + _chunk(b"IEND", b"")


class ConversationV3ArtifactsTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.tempdir.name)
        self._write_valid_bundle()

    def tearDown(self) -> None:
        self.tempdir.cleanup()

    def _write_valid_bundle(self) -> None:
        items: List[Dict[str, Any]] = []
        for index, spec in enumerate(EXPECTED_ARTIFACTS):
            image = _png(
                spec.pixel_width,
                spec.pixel_height,
                ((index + 1) & 0xFF, (index + 17) & 0xFF, (index + 33) & 0xFF),
            )
            (self.root / spec.filename).write_bytes(image)
            items.append(
                {
                    "filename": spec.filename,
                    "scene": spec.scene,
                    "device": spec.device,
                    "logicalSize": spec.logical_size,
                    "appearance": spec.appearance,
                    "pixelWidth": spec.pixel_width,
                    "pixelHeight": spec.pixel_height,
                    "sha256": hashlib.sha256(image).hexdigest(),
                }
            )
        (self.root / "manifest.json").write_text(
            json.dumps({"schemaVersion": 1, "artifacts": items}, indent=2) + "\n",
            encoding="utf-8",
        )

    def _manifest(self) -> Dict[str, Any]:
        return json.loads((self.root / "manifest.json").read_text(encoding="utf-8"))

    def _write_manifest(self, value: Dict[str, Any]) -> None:
        (self.root / "manifest.json").write_text(
            json.dumps(value, indent=2) + "\n", encoding="utf-8"
        )

    def assert_rejected(self, expected: str) -> None:
        with self.assertRaisesRegex(ArtifactValidationError, expected):
            validate_artifacts(self.root)

    def test_correct_fixed_collection_passes(self) -> None:
        validate_artifacts(self.root)

    def test_missing_png_fails(self) -> None:
        (self.root / EXPECTED_ARTIFACTS[0].filename).unlink()
        self.assert_rejected("missing artifact file")

    def test_extra_file_fails(self) -> None:
        (self.root / "unexpected.txt").write_text("not evidence", encoding="utf-8")
        self.assert_rejected("unexpected file")

    def test_wrong_pixel_dimensions_fail(self) -> None:
        spec = EXPECTED_ARTIFACTS[0]
        image = _png(spec.pixel_width - 1, spec.pixel_height, (80, 81, 82))
        path = self.root / spec.filename
        path.write_bytes(image)
        manifest = self._manifest()
        manifest["artifacts"][0]["sha256"] = hashlib.sha256(image).hexdigest()
        self._write_manifest(manifest)
        self.assert_rejected("dimensions are")

    def test_duplicate_sha_fails(self) -> None:
        first = self.root / EXPECTED_ARTIFACTS[0].filename
        second = self.root / EXPECTED_ARTIFACTS[1].filename
        second.write_bytes(first.read_bytes())
        manifest = self._manifest()
        manifest["artifacts"][1]["sha256"] = manifest["artifacts"][0]["sha256"]
        self._write_manifest(manifest)
        self.assert_rejected("sha256 values must all be unique")

    def test_manifest_sha_mismatch_fails(self) -> None:
        manifest = self._manifest()
        manifest["artifacts"][0]["sha256"] = "0" * 64
        self._write_manifest(manifest)
        self.assert_rejected("sha256 mismatch")


if __name__ == "__main__":
    unittest.main(verbosity=2)
