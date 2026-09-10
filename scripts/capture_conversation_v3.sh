#!/usr/bin/env bash
set -euo pipefail

# Capture only the fixed conversation-v3 evidence set.  This script is kept
# independent from the legacy Pocket screenshot matrix and never edits images.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUNDLE_ID="com.example.DeepSeekHarness"
CMD_TIMEOUT="${SIMCTL_TIMEOUT_SECONDS:-180}"
OUT=""
UDID=""
CURRENT_SCENE="bootstrap"

usage() {
  printf 'usage: %s APP_PATH OUTPUT_DIRECTORY\n' "$(basename "$0")" >&2
}

if [[ "$#" -ne 2 ]]; then
  usage
  exit 2
fi
APP_PATH="$1"
OUT="$2"
if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle does not exist: $APP_PATH" >&2
  exit 1
fi
if [[ "$OUT" == "" || "$OUT" == "/" ]]; then
  echo "Refusing unsafe output directory: $OUT" >&2
  exit 1
fi

# The output is a generated evidence bundle.  Recreating this exact directory
# prevents stale screenshots or manifests from entering the strict gate.
if [[ -e "$OUT" ]]; then
  if [[ ! -d "$OUT" ]]; then
    echo "Output path is not a directory: $OUT" >&2
    exit 1
  fi
  rm -rf -- "$OUT"
fi
mkdir -p -- "$OUT"

run_timeout() {
  local label="$1"
  shift
  local start end rc
  start="$(date +%s)"
  echo "[diag] scene=${CURRENT_SCENE} command=${label} start=${start} argv=$*" >&2
  set +e
  perl -e 'alarm shift; exec @ARGV' "$CMD_TIMEOUT" "$@"
  rc=$?
  set -e
  end="$(date +%s)"
  echo "[diag] scene=${CURRENT_SCENE} command=${label} end=${end} elapsed=$((end-start)) exit=${rc}" >&2
  return "$rc"
}

find_udid() {
  local wanted="$1"
  xcrun simctl list devices available | awk -F '[()]' -v wanted="$wanted" \
    '$1 ~ ("^[[:space:]]*" wanted "[[:space:]]*$") { print $2; exit }'
}

boot_simulator() {
  local target="$1"
  local attempt rc

  # Start from a known state without parsing human-formatted `simctl list`
  # output. Shutdown may legitimately report that the device is already off.
  run_timeout shutdown-before-boot xcrun simctl shutdown "$target" || true
  run_timeout boot xcrun simctl boot "$target"
  for attempt in 1 2 3 4 5 6 7 8; do
    set +e
    run_timeout "bootstatus-${attempt}" xcrun simctl bootstatus "$target" -b
    rc=$?
    set -e
    if [[ "$rc" -eq 0 ]]; then
      return 0
    fi
    echo "[diag] simulator=${target} bootstatus attempt=${attempt} rc=${rc}" >&2
    if [[ "$attempt" -lt 8 ]]; then
      run_timeout "shutdown-retry-${attempt}" xcrun simctl shutdown "$target" || true
      run_timeout "reboot-${attempt}" xcrun simctl boot "$target"
    fi
  done
  echo "Simulator failed to reach booted state: $target" >&2
  return 1
}

prepare_device() {
  local device_name="$1"
  local logical_size="$2"
  local target
  target="$(find_udid "$device_name")"
  if [[ -z "$target" ]]; then
    echo "Required available simulator not found: $device_name" >&2
    return 1
  fi
  echo "[diag] preparing device=${device_name} logical_size=${logical_size} udid=${target}" >&2
  boot_simulator "$target"
  run_timeout install xcrun simctl install "$target" "$APP_PATH"
  UDID="$target"
}

terminate_if_running() {
  local process_log="$1"
  run_timeout process-list xcrun simctl spawn "$UDID" launchctl list >"$process_log" 2>&1
  if grep -Fq "$BUNDLE_ID" "$process_log"; then
    run_timeout terminate xcrun simctl terminate "$UDID" "$BUNDLE_ID"
  fi
}

capture_scene() {
  local scene="$1"
  local device_name="$2"
  local logical_size="$3"
  local appearance="$4"
  local output_path="$OUT/${scene}-${logical_size}-${appearance}.png"
  local launch_log="/tmp/conversation-v3-launch.log"
  local process_log="/tmp/conversation-v3-process.log"
  local launch_output pid alive
  local -a launch_args

  CURRENT_SCENE="$scene/$logical_size/$appearance"
  launch_args=(-UITestFixture -NativeFixtureScreen "$scene")
  if [[ "$appearance" == "dark" ]]; then
    launch_args+=(-PocketDark)
  elif [[ "$appearance" != "light" ]]; then
    echo "Unsupported appearance: $appearance" >&2
    return 1
  fi

  terminate_if_running "$process_log"
  if ! launch_output="$(run_timeout launch xcrun simctl launch "$UDID" "$BUNDLE_ID" "${launch_args[@]}" 2>&1)"; then
    printf '%s\n' "$launch_output" >"$launch_log"
    cat "$launch_log" >&2
    echo "Conversation-v3 fixture launch failed: $CURRENT_SCENE" >&2
    return 1
  fi
  printf '%s\n' "$launch_output" >"$launch_log"
  pid="$(printf '%s\n' "$launch_output" | sed -n 's/.*: \([0-9][0-9]*\).*/\1/p' | tail -1)"

  # The fixed settle interval follows the validated legacy capture behavior;
  # the screenshot is requested only after the launched process has settled.
  run_timeout wait-for-ui-stability sleep 2
  alive=0
  if [[ -n "$pid" ]] && run_timeout process-check xcrun simctl spawn "$UDID" ps -p "$pid" >"$process_log" 2>&1; then
    if awk -v wanted="$pid" '$1 == wanted { found = 1 } END { exit found ? 0 : 1 }' "$process_log"; then
      alive=1
    fi
  fi
  if [[ "$alive" -ne 1 ]]; then
    run_timeout process-list-after-launch xcrun simctl spawn "$UDID" launchctl list >"$process_log" 2>&1
    if grep -Eq "$BUNDLE_ID|^[[:space:]]*$pid[[:space:]]" "$process_log"; then
      alive=1
    fi
  fi
  if [[ "$alive" -ne 1 ]]; then
    echo "Conversation-v3 fixture exited before screenshot: $CURRENT_SCENE" >&2
    cat "$launch_log" >&2
    cat "$process_log" >&2
    xcrun simctl spawn "$UDID" log show --last 20s --style compact \
      --predicate 'process == "DeepSeekHarness" OR composedMessage CONTAINS[c] "DeepSeekHarness"' >&2
    return 1
  fi

  run_timeout screenshot xcrun simctl io "$UDID" screenshot "$output_path"
  if [[ ! -s "$output_path" ]]; then
    echo "Screenshot was not created: $output_path" >&2
    return 1
  fi
}

prepare_device "iPhone 15 Pro Max" "430x932"
for scene in \
  conversation-v3-running-empty \
  conversation-v3-thinking-collapsed \
  conversation-v3-thinking-expanded \
  conversation-v3-plus-menu \
  conversation-v3-reference-menu \
  conversation-v3-guidance-disabled; do
  capture_scene "$scene" "iPhone 15 Pro Max" "430x932" "light"
done
capture_scene "conversation-v3-running-empty" "iPhone 15 Pro Max" "430x932" "dark"

prepare_device "iPhone 14" "390x844"
capture_scene "conversation-v3-running-empty" "iPhone 14" "390x844" "light"

# Build the manifest only after every screenshot exists.  SHA-256 and pixel
# dimensions are read from those actual files; no digest is supplied in advance.
python3 - "$OUT" <<'PY'
from __future__ import annotations

import hashlib
import json
import pathlib
import struct
import sys

out = pathlib.Path(sys.argv[1])
specs = [
    ("conversation-v3-running-empty-430x932-light.png", "conversation-v3-running-empty", "iPhone 15 Pro Max", "430x932", "light", 1290, 2796),
    ("conversation-v3-thinking-collapsed-430x932-light.png", "conversation-v3-thinking-collapsed", "iPhone 15 Pro Max", "430x932", "light", 1290, 2796),
    ("conversation-v3-thinking-expanded-430x932-light.png", "conversation-v3-thinking-expanded", "iPhone 15 Pro Max", "430x932", "light", 1290, 2796),
    ("conversation-v3-plus-menu-430x932-light.png", "conversation-v3-plus-menu", "iPhone 15 Pro Max", "430x932", "light", 1290, 2796),
    ("conversation-v3-reference-menu-430x932-light.png", "conversation-v3-reference-menu", "iPhone 15 Pro Max", "430x932", "light", 1290, 2796),
    ("conversation-v3-guidance-disabled-430x932-light.png", "conversation-v3-guidance-disabled", "iPhone 15 Pro Max", "430x932", "light", 1290, 2796),
    ("conversation-v3-running-empty-390x844-light.png", "conversation-v3-running-empty", "iPhone 14", "390x844", "light", 1170, 2532),
    ("conversation-v3-running-empty-430x932-dark.png", "conversation-v3-running-empty", "iPhone 15 Pro Max", "430x932", "dark", 1290, 2796),
]

items = []
for filename, scene, device, logical_size, appearance, expected_width, expected_height in specs:
    path = out / filename
    if not path.is_file():
        raise SystemExit(f"missing screenshot while generating manifest: {filename}")
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n" or len(data) < 24:
        raise SystemExit(f"screenshot is not a readable PNG: {filename}")
    width, height = struct.unpack(">II", data[16:24])
    if (width, height) != (expected_width, expected_height):
        raise SystemExit(f"unexpected screenshot dimensions for {filename}: {width}x{height}")
    items.append({
        "filename": filename,
        "scene": scene,
        "device": device,
        "logicalSize": logical_size,
        "appearance": appearance,
        "pixelWidth": width,
        "pixelHeight": height,
        "sha256": hashlib.sha256(data).hexdigest(),
    })

(out / "manifest.json").write_text(
    json.dumps({"schemaVersion": 1, "artifacts": items}, indent=2) + "\n",
    encoding="utf-8",
)
PY
python3 "$SCRIPT_DIR/verify_conversation_v3_artifacts.py" "$OUT"
printf 'Conversation-v3 screenshot bundle: %s\n' "$OUT"
