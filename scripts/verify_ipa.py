#!/usr/bin/env python3
"""Programmatic gate for an unsigned device IPA.

Usage: python3 scripts/verify_ipa.py path/to/DeepSeekHarness-unsigned.ipa
The gate is intentionally dependency-free so it can run locally and in CI.
"""
from __future__ import annotations

import hashlib
import json
import plistlib
import re
import struct
import sys
import tempfile
import zipfile
from pathlib import Path

FORBIDDEN = (
    b"WebKit", b"WKWebView", b"evaluateJavaScript", b"AutoNativeAdapter",
    b"HarnessWebView", b"window.__harnessNative", b"dom-projection",
)


def fail(message: str) -> None:
    raise SystemExit(f"IPA GATE FAILED: {message}")


def main() -> int:
    if len(sys.argv) != 2:
        fail("usage: verify_ipa.py <ipa>")
    ipa = Path(sys.argv[1])
    if not ipa.is_file():
        fail(f"not a file: {ipa}")
    digest = hashlib.sha256(ipa.read_bytes()).hexdigest()
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        try:
            with zipfile.ZipFile(ipa) as archive:
                names = archive.namelist()
                archive.extractall(root)
        except (zipfile.BadZipFile, OSError) as exc:
            fail(f"invalid zip: {exc}")
        app_dirs = [p for p in (root / "Payload").glob("*.app") if p.is_dir()]
        if len(app_dirs) != 1:
            fail(f"expected one Payload/*.app, got {len(app_dirs)}")
        app = app_dirs[0]
        info_path = app / "Info.plist"
        if not info_path.is_file():
            fail("Info.plist missing")
        try:
            info = plistlib.loads(info_path.read_bytes())
        except Exception as exc:
            fail(f"invalid Info.plist: {exc}")
        executable = app / str(info.get("CFBundleExecutable", ""))
        if not executable.is_file():
            fail("CFBundleExecutable missing")
        if not info.get("CFBundleSupportedPlatforms") == ["iPhoneOS"]:
            fail("not an iPhoneOS app")
        minimum = str(info.get("MinimumOSVersion", ""))
        if minimum:
            version_parts = [int(part) for part in re.findall(r"\d+", minimum)[:2]]
            if tuple(version_parts + [0] * (2 - len(version_parts))) < (15, 0):
                fail(f"MinimumOSVersion is not iOS 15+: {minimum!r}")
        else:
            fail("MinimumOSVersion is missing")
        blob = executable.read_bytes()
        for marker in FORBIDDEN:
            if marker in blob:
                fail(f"forbidden marker in executable: {marker.decode(errors='replace')}")
        # Mach-O fat binaries carry one or more architecture slices. On Linux
        # we can still verify the CPU type directly from the Mach-O header.
        if len(blob) < 8:
            fail("executable is too small")
        magic = struct.unpack("<I", blob[:4])[0]
        is_fat = magic in (0xCAFEBABE, 0xBEBAFECA, 0xCAFEBABF, 0xBFBAFECA)
        cpu_values = []
        if is_fat:
            endian = ">" if magic in (0xCAFEBABE, 0xCAFEBABF) else "<"
            is_64 = magic in (0xCAFEBABF, 0xBFBAFECA)
            count = struct.unpack(endian + "I", blob[4:8])[0]
            stride = 32 if is_64 else 20
            for index in range(min(count, 32)):
                start = 8 + index * stride
                cpu_values.append(struct.unpack(endian + "I", blob[start:start + 4])[0])
        else:
            cpu_values.append(struct.unpack("<I", blob[4:8])[0])
        # CPU_TYPE_ARM64 = 0x0100000c. Reject simulator-only or malformed apps.
        if 0x0100000C not in cpu_values:
            fail(f"arm64 slice missing (cpu types: {cpu_values})")
        if "Payload/" not in "\n".join(names):
            fail("Payload missing")
        if (app / "_CodeSignature").exists():
            fail("expected unsigned IPA, but _CodeSignature exists")
    print(json.dumps({
        "ipa": str(ipa),
        "sha256": digest,
        "app": app.name,
        "bundleIdentifier": info.get("CFBundleIdentifier"),
        "minimumOSVersion": info.get("MinimumOSVersion"),
        "unsigned": True,
        "forbiddenMarkers": 0,
    }, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
