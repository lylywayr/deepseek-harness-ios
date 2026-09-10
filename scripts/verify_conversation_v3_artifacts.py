#!/usr/bin/env python3
"""Strict validator for the conversation-v3 simulator screenshot bundle.

The validator intentionally uses only the Python standard library.  It checks
both the bundle contract and the bytes of every PNG; it does not resize,
rewrite, or otherwise process image evidence.
"""
from __future__ import annotations

import hashlib
import json
import pathlib
import re
import struct
import sys
import zlib
from dataclasses import dataclass
from typing import Any, Dict, Iterable, List, Mapping, Sequence, Tuple


MANIFEST_NAME = "manifest.json"
SCHEMA_VERSION = 1
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
_SHA256_RE = re.compile(r"^[0-9a-f]{64}$")


@dataclass(frozen=True)
class ArtifactSpec:
    filename: str
    scene: str
    device: str
    logical_size: str
    appearance: str
    pixel_width: int
    pixel_height: int


EXPECTED_ARTIFACTS: Tuple[ArtifactSpec, ...] = (
    ArtifactSpec(
        "conversation-v3-running-empty-430x932-light.png",
        "conversation-v3-running-empty",
        "iPhone 15 Pro Max",
        "430x932",
        "light",
        1290,
        2796,
    ),
    ArtifactSpec(
        "conversation-v3-thinking-collapsed-430x932-light.png",
        "conversation-v3-thinking-collapsed",
        "iPhone 15 Pro Max",
        "430x932",
        "light",
        1290,
        2796,
    ),
    ArtifactSpec(
        "conversation-v3-thinking-expanded-430x932-light.png",
        "conversation-v3-thinking-expanded",
        "iPhone 15 Pro Max",
        "430x932",
        "light",
        1290,
        2796,
    ),
    ArtifactSpec(
        "conversation-v3-plus-menu-430x932-light.png",
        "conversation-v3-plus-menu",
        "iPhone 15 Pro Max",
        "430x932",
        "light",
        1290,
        2796,
    ),
    ArtifactSpec(
        "conversation-v3-reference-menu-430x932-light.png",
        "conversation-v3-reference-menu",
        "iPhone 15 Pro Max",
        "430x932",
        "light",
        1290,
        2796,
    ),
    ArtifactSpec(
        "conversation-v3-guidance-disabled-430x932-light.png",
        "conversation-v3-guidance-disabled",
        "iPhone 15 Pro Max",
        "430x932",
        "light",
        1290,
        2796,
    ),
    ArtifactSpec(
        "conversation-v3-running-empty-390x844-light.png",
        "conversation-v3-running-empty",
        "iPhone 14",
        "390x844",
        "light",
        1170,
        2532,
    ),
    ArtifactSpec(
        "conversation-v3-running-empty-430x932-dark.png",
        "conversation-v3-running-empty",
        "iPhone 15 Pro Max",
        "430x932",
        "dark",
        1290,
        2796,
    ),
)
EXPECTED_BY_FILENAME = {spec.filename: spec for spec in EXPECTED_ARTIFACTS}
EXPECTED_NAMES = frozenset(EXPECTED_BY_FILENAME)
_REQUIRED_ITEM_KEYS = frozenset(
    {
        "filename",
        "scene",
        "device",
        "logicalSize",
        "appearance",
        "pixelWidth",
        "pixelHeight",
        "sha256",
    }
)


class ArtifactValidationError(ValueError):
    """Raised when a conversation-v3 artifact bundle violates its contract."""


def _fail(message: str) -> None:
    raise ArtifactValidationError(message)


def _read_png(path: pathlib.Path) -> Tuple[int, int]:
    """Validate PNG structure and return its pixel dimensions.

    This is deliberately a small structural decoder rather than an image
    transformation.  It verifies chunk boundaries/CRCs and validates the
    non-interlaced scanline stream, which prevents a signature-only fake PNG
    from satisfying the gate.
    """
    try:
        data = path.read_bytes()
    except OSError as exc:
        _fail(f"cannot read {path.name}: {exc}")
    if len(data) < len(PNG_SIGNATURE) + 12:
        _fail(f"{path.name}: truncated PNG")
    if data[:8] != PNG_SIGNATURE:
        _fail(f"{path.name}: invalid PNG signature")

    offset = 8
    first_chunk = True
    saw_ihdr = False
    saw_idat = False
    saw_iend = False
    width = height = 0
    bit_depth = color_type = interlace = 0
    idat_parts: List[bytes] = []

    while offset < len(data):
        if len(data) - offset < 12:
            _fail(f"{path.name}: truncated PNG chunk header")
        length = struct.unpack(">I", data[offset : offset + 4])[0]
        chunk_type = data[offset + 4 : offset + 8]
        chunk_end = offset + 12 + length
        if chunk_end > len(data):
            _fail(f"{path.name}: PNG chunk exceeds file length")
        chunk_data = data[offset + 8 : offset + 8 + length]
        stored_crc = struct.unpack(">I", data[offset + 8 + length : chunk_end])[0]
        calculated_crc = zlib.crc32(chunk_type + chunk_data) & 0xFFFFFFFF
        if stored_crc != calculated_crc:
            name = chunk_type.decode("ascii", "replace")
            _fail(f"{path.name}: CRC mismatch in {name} chunk")
        if any(value < 32 or value > 126 for value in chunk_type):
            _fail(f"{path.name}: invalid PNG chunk type")
        if saw_iend:
            _fail(f"{path.name}: data appears after IEND")

        if first_chunk:
            if chunk_type != b"IHDR":
                _fail(f"{path.name}: first PNG chunk is not IHDR")
            first_chunk = False

        if chunk_type == b"IHDR":
            if saw_ihdr or length != 13:
                _fail(f"{path.name}: invalid IHDR")
            saw_ihdr = True
            width, height, bit_depth, color_type, compression, filtering, interlace = struct.unpack(
                ">IIBBBBB", chunk_data
            )
            if width == 0 or height == 0:
                _fail(f"{path.name}: PNG dimensions must be non-zero")
            valid_depths = {
                0: {1, 2, 4, 8, 16},
                2: {8, 16},
                3: {1, 2, 4, 8},
                4: {8, 16},
                6: {8, 16},
            }
            if color_type not in valid_depths or bit_depth not in valid_depths[color_type]:
                _fail(f"{path.name}: invalid PNG color type/bit depth")
            if compression != 0 or filtering != 0 or interlace not in (0, 1):
                _fail(f"{path.name}: unsupported PNG compression/filter/interlace")
        elif chunk_type == b"IDAT":
            saw_idat = True
            idat_parts.append(chunk_data)
        elif chunk_type == b"IEND":
            if length != 0:
                _fail(f"{path.name}: IEND must be empty")
            saw_iend = True

        offset = chunk_end

    if not saw_ihdr or not saw_idat or not saw_iend:
        _fail(f"{path.name}: PNG is missing IHDR, IDAT, or IEND")
    if offset != len(data):
        _fail(f"{path.name}: trailing PNG bytes")

    compressed = b"".join(idat_parts)
    try:
        decoder = zlib.decompressobj()
        scanlines = decoder.decompress(compressed)
        scanlines += decoder.flush()
    except zlib.error as exc:
        _fail(f"{path.name}: invalid PNG image stream: {exc}")
    if not decoder.eof or decoder.unused_data:
        _fail(f"{path.name}: invalid PNG zlib stream")

    if interlace == 0:
        channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[color_type]
        row_bytes = (width * channels * bit_depth + 7) // 8
        expected_length = height * (row_bytes + 1)
        if len(scanlines) != expected_length:
            _fail(
                f"{path.name}: PNG scanline length {len(scanlines)} != {expected_length}"
            )
        for row in range(height):
            filter_byte = scanlines[row * (row_bytes + 1)]
            if filter_byte > 4:
                _fail(f"{path.name}: invalid PNG filter byte on row {row}")

    return width, height


def _reject_duplicate_json_keys(pairs: Iterable[Tuple[str, Any]]) -> Dict[str, Any]:
    result: Dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ArtifactValidationError(f"manifest contains duplicate key: {key}")
        result[key] = value
    return result


def _reject_json_constant(value: str) -> Any:
    raise ArtifactValidationError(f"manifest contains non-standard JSON value: {value}")


def _load_manifest(path: pathlib.Path) -> Mapping[str, Any]:
    try:
        text = path.read_text(encoding="utf-8")
        value = json.loads(
            text,
            object_pairs_hook=_reject_duplicate_json_keys,
            parse_constant=_reject_json_constant,
        )
    except ArtifactValidationError:
        raise
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        _fail(f"cannot parse {MANIFEST_NAME}: {exc}")
    if not isinstance(value, dict):
        _fail(f"{MANIFEST_NAME}: top-level JSON value must be an object")
    return value


def _check_string(value: Any, field: str, context: str) -> str:
    if not isinstance(value, str) or not value:
        _fail(f"{context}: {field} must be a non-empty string")
    return value


def _validate_manifest(root: pathlib.Path) -> List[Mapping[str, Any]]:
    manifest_path = root / MANIFEST_NAME
    if manifest_path.is_symlink() or not manifest_path.is_file():
        _fail(f"missing regular manifest file: {MANIFEST_NAME}")
    manifest = _load_manifest(manifest_path)
    if set(manifest) != {"schemaVersion", "artifacts"}:
        _fail(f"{MANIFEST_NAME}: schema keys must be schemaVersion and artifacts")
    version = manifest["schemaVersion"]
    if isinstance(version, bool) or not isinstance(version, int) or version != SCHEMA_VERSION:
        _fail(f"{MANIFEST_NAME}: schemaVersion must be {SCHEMA_VERSION}")
    artifacts = manifest["artifacts"]
    if not isinstance(artifacts, list) or len(artifacts) != len(EXPECTED_ARTIFACTS):
        _fail(f"{MANIFEST_NAME}: artifacts must contain exactly {len(EXPECTED_ARTIFACTS)} items")

    items_by_filename: Dict[str, Mapping[str, Any]] = {}
    for index, item in enumerate(artifacts):
        context = f"{MANIFEST_NAME}.artifacts[{index}]"
        if not isinstance(item, dict):
            _fail(f"{context}: item must be an object")
        if set(item) != _REQUIRED_ITEM_KEYS:
            _fail(f"{context}: keys do not match the manifest schema")
        filename = _check_string(item["filename"], "filename", context)
        if filename in items_by_filename:
            _fail(f"{MANIFEST_NAME}: duplicate manifest filename {filename}")
        expected = EXPECTED_BY_FILENAME.get(filename)
        if expected is None:
            _fail(f"{context}: unexpected filename {filename}")
        items_by_filename[filename] = item
        for field, expected_value in (
            ("scene", expected.scene),
            ("device", expected.device),
            ("logicalSize", expected.logical_size),
            ("appearance", expected.appearance),
        ):
            actual = _check_string(item[field], field, context)
            if actual != expected_value:
                _fail(f"{context}: {field} must be {expected_value!r}, got {actual!r}")
        for field, expected_value in (
            ("pixelWidth", expected.pixel_width),
            ("pixelHeight", expected.pixel_height),
        ):
            actual = item[field]
            if isinstance(actual, bool) or not isinstance(actual, int) or actual != expected_value:
                _fail(f"{context}: {field} must be {expected_value}")
        digest = item["sha256"]
        if not isinstance(digest, str) or not _SHA256_RE.fullmatch(digest):
            _fail(f"{context}: sha256 must be 64 lowercase hexadecimal characters")

    if set(items_by_filename) != EXPECTED_NAMES:
        _fail(f"{MANIFEST_NAME}: filenames do not cover the fixed eight PNGs")
    digests = [items_by_filename[spec.filename]["sha256"] for spec in EXPECTED_ARTIFACTS]
    if len(set(digests)) != len(digests):
        _fail(f"{MANIFEST_NAME}: the eight sha256 values must all be unique")
    return [items_by_filename[spec.filename] for spec in EXPECTED_ARTIFACTS]


def validate_artifacts(root: pathlib.Path) -> None:
    """Validate one complete conversation-v3 artifact directory.

    The function raises :class:`ArtifactValidationError` on every contract
    failure and returns ``None`` on success, making it suitable for direct
    unit-test use as well as the command-line gate.
    """
    root = pathlib.Path(root)
    if not root.exists() or not root.is_dir() or root.is_symlink():
        _fail(f"artifact path is not a regular directory: {root}")

    expected_entries = set(EXPECTED_NAMES) | {MANIFEST_NAME}
    entries = list(root.iterdir())
    actual_entries = {entry.name for entry in entries}
    missing = sorted(expected_entries - actual_entries)
    extra = sorted(actual_entries - expected_entries)
    if missing:
        _fail(f"missing artifact file(s): {', '.join(missing)}")
    if extra:
        _fail(f"unexpected file(s) in artifact directory: {', '.join(extra)}")
    if len(entries) != len(expected_entries):
        _fail("artifact directory must contain exactly eight PNGs and one manifest")

    artifacts = _validate_manifest(root)
    actual_hashes: List[str] = []
    for item, expected in zip(artifacts, EXPECTED_ARTIFACTS):
        image_path = root / expected.filename
        if image_path.is_symlink() or not image_path.is_file():
            _fail(f"missing regular PNG file: {expected.filename}")
        width, height = _read_png(image_path)
        if (width, height) != (expected.pixel_width, expected.pixel_height):
            _fail(
                f"{expected.filename}: dimensions are {width}x{height}, expected "
                f"{expected.pixel_width}x{expected.pixel_height}"
            )
        if item["pixelWidth"] != width or item["pixelHeight"] != height:
            _fail(f"{expected.filename}: manifest pixel dimensions do not match PNG")
        digest = hashlib.sha256(image_path.read_bytes()).hexdigest()
        actual_hashes.append(digest)
        if digest != item["sha256"]:
            _fail(
                f"{expected.filename}: sha256 mismatch (manifest {item['sha256']}, "
                f"actual {digest})"
            )

    if len(set(actual_hashes)) != len(actual_hashes):
        _fail("the eight PNG sha256 values must all be unique")


def main(argv: Sequence[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    if len(args) != 1:
        print(f"usage: {pathlib.Path(sys.argv[0]).name} ARTIFACT_DIRECTORY", file=sys.stderr)
        return 2
    try:
        validate_artifacts(pathlib.Path(args[0]))
    except (ArtifactValidationError, OSError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1
    print(
        "PASS: conversation-v3 artifact bundle contains 8 unique PNGs "
        "with validated manifest, dimensions, format, and SHA-256 values"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
