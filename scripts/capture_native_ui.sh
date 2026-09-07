#!/usr/bin/env bash
set -euo pipefail
ROOT="${GITHUB_WORKSPACE:-$(pwd)}"
BUNDLE_ID="com.example.DeepSeekHarness"
DEVICE="iPhone 14"
RUNTIME="18.2"
CMD_TIMEOUT="${SIMCTL_TIMEOUT_SECONDS:-180}"
run_timeout() {
  local label="$1"; shift
  local start end rc
  start=$(date +%s)
  echo "[diag] scene=${CURRENT_SCENE:-bootstrap} command=$label start=$start argv=$*" >&2
  set +e
  perl -e 'alarm shift; exec @ARGV' "$CMD_TIMEOUT" "$@"
  rc=$?
  set -e
  end=$(date +%s)
  echo "[diag] scene=${CURRENT_SCENE:-bootstrap} command=$label end=$end elapsed=$((end-start)) exit=$rc" >&2
  return "$rc"
}
find_udid() {
  local name="$1"
  xcrun simctl list devices available | awk -F '[()]' -v wanted="$name" '$1 ~ ("^[[:space:]]*" wanted "[[:space:]]*$") {print $2; exit}'
}
UDID="$(find_udid "$DEVICE")"
if [[ -z "$UDID" ]]; then UDID="$(xcrun simctl create "PocketV2Fixture" com.apple.CoreSimulator.SimDeviceType.iPhone-14 com.apple.CoreSimulator.SimRuntime.iOS-18-2)"; fi
xcrun simctl boot "$UDID" 2>/dev/null || true
run_timeout bootstatus xcrun simctl bootstatus "$UDID" -b
APP_PATH="$ROOT/build/Build/Products/Debug-iphonesimulator/DeepSeekHarness.app"
run_timeout install xcrun simctl install "$UDID" "$APP_PATH"
OUT="$ROOT/artifacts/pocket-v2-ui-matrix"
rm -rf "$OUT"
mkdir -p "$OUT"

prepare_keyboard_scene() {
  run_timeout spawn xcrun simctl spawn "$UDID" defaults write com.apple.keyboardservicesd KeyboardContinuousPathIntroductionShown -bool true
  run_timeout spawn xcrun simctl spawn "$UDID" defaults write com.apple.keyboardservicesd KeyboardAutocorrectionListsShown -bool true
  run_timeout spawn xcrun simctl spawn "$UDID" defaults write com.apple.keyboardservicesd KeyboardDidShowContinuousPathIntroduction -bool true
  run_timeout spawn xcrun simctl spawn "$UDID" launchctl kickstart -k system/com.apple.keyboardservicesd >/dev/null 2>&1 || true
  run_timeout spawn xcrun simctl spawn "$UDID" launchctl kickstart -k system/com.apple.TextInput >/dev/null 2>&1 || true
  run_timeout sleep sleep 1
}

capture() {
  local scene="$1" size="$2" appearance="$3" args="$4"
  local dir="$OUT/$size/$appearance"
  local launch_log="/tmp/pocket-fixture-launch.log"
  local process_log="/tmp/pocket-fixture-process.log"
  local launch_output=""
  local pid=""
  local alive=0
  mkdir -p "$dir"
  CURRENT_SCENE="$scene"
  if [[ "$scene" == "keyboard" ]]; then
    # Seed preferences before launching the fixture, then kick the services
    # again after focus in case the keyboard scene was already cached.
    prepare_keyboard_scene
  fi
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  if ! launch_output="$(run_timeout launch xcrun simctl launch "$UDID" "$BUNDLE_ID" -UITestFixture -NativeFixtureScreen "$scene" $args 2>&1)"; then
    printf '%s\n' "$launch_output" >"$launch_log"
    cat "$launch_log" >&2
    echo "Pocket fixture launch failed: $scene" >&2
    exit 1
  fi
  printf '%s\n' "$launch_output" >"$launch_log"
  pid="$(printf '%s\n' "$launch_output" | sed -n 's/.*: \([0-9][0-9]*\).*/\1/p' | tail -1)"
  sleep 2
  # simctl launch returns the simulator PID.  Verify that PID from inside
  # the simulator instead of assuming a host-side GUI uid; the latter is
  # unavailable on some iOS 18.2 runners and caused false failures.
  if [[ -n "$pid" ]] && run_timeout spawn xcrun simctl spawn "$UDID" ps -p "$pid" >"$process_log" 2>&1; then
    if awk -v wanted="$pid" '$1 == wanted { found = 1 } END { exit found ? 0 : 1 }' "$process_log"; then
      alive=1
    fi
  fi
  if [[ "$alive" -ne 1 ]]; then
    run_timeout spawn xcrun simctl spawn "$UDID" launchctl list >"$process_log" 2>&1 || true
    if grep -Eq "$BUNDLE_ID|^[[:space:]]*$pid[[:space:]]" "$process_log"; then alive=1; fi
  fi
  if [[ "$alive" -ne 1 ]]; then
    echo "Pocket fixture exited before screenshot: $scene" >&2
    cat "$launch_log" >&2 || true
    cat "$process_log" >&2 || true
    xcrun simctl spawn "$UDID" log show --last 20s --style compact --predicate 'process == "DeepSeekHarness" OR composedMessage CONTAINS[c] "DeepSeekHarness"' >&2 || true
    exit 1
  fi
  if [[ "$scene" == "keyboard" ]]; then
    # Keyboard services are intentionally not restarted after the scene is focused:
    # doing so can deadlock SpringBoard's screenshot request.
    :
  fi
  run_timeout screenshot xcrun simctl io "$UDID" screenshot "$dir/$scene-$size-$appearance.png"
  test -s "$dir/$scene-$size-$appearance.png"
  # Keep a deterministic scene manifest beside the real PNG evidence.
  printf "%s\n" "$scene|$size|$appearance" >> "$OUT/manifest.txt"
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
}

# iPhone 14 is the 390x844 evidence target. 430x932 is produced with a
# second simulator when the runtime is available; all scenes remain real Pocket.
for scene in workspace drawer flat conversation normal process trajectory artifacts activity settings; do capture "$scene" "390x844" "light" ""; done
capture workspace "390x844" "dark" "-PocketDark"

UDID430="$(find_udid "iPhone 15 Pro Max")"
if [[ -z "$UDID430" ]]; then
  UDID430="$(xcrun simctl create "PocketV2Fixture430" com.apple.CoreSimulator.SimDeviceType.iPhone-15-Pro-Max com.apple.CoreSimulator.SimRuntime.iOS-18-2 2>/dev/null || true)"
fi
if [[ -n "$UDID430" ]]; then
  xcrun simctl boot "$UDID430" 2>/dev/null || true
  xcrun simctl bootstatus "$UDID430" -b
  xcrun simctl install "$UDID430" "$APP_PATH"
  UDID="$UDID430"
  for scene in workspace drawer flat conversation normal process trajectory artifacts activity settings; do capture "$scene" "430x932" "light" ""; done
  capture workspace "430x932" "dark" "-PocketDark"
  for scene in drawer conversation artifacts settings; do capture "$scene" "430x932" "dark" "-PocketDark"; done
else
  printf '430x932 simulator unavailable; 390x844 evidence retained\n'
fi
# Matrix scenes: workspace drawer flat conversation normal process trajectory artifacts activity settings keyboard; 390x844 and 430x932; PocketDark.
# Keyboard evidence is deliberately isolated from the ordinary matrix lifecycle.
# Each fresh simulator gets onboarding defaults before launch and is never service-restarted after focus.
for spec in "iPhone 14|390x844|iPhone-14" "iPhone 15 Pro Max|430x932|iPhone-15-Pro-Max"; do
  IFS='|' read -r kname ksize ktype <<< "$spec"
  KUDID=$(xcrun simctl create "PocketKeyboard-$ksize" com.apple.CoreSimulator.SimDeviceType.$ktype com.apple.CoreSimulator.SimRuntime.iOS-18-2)
  UDID="$KUDID"
  run_timeout keyboard-boot xcrun simctl boot "$UDID"
  run_timeout keyboard-bootstatus xcrun simctl bootstatus "$UDID" -b
  run_timeout keyboard-install xcrun simctl install "$UDID" "$APP_PATH"
  capture keyboard "$ksize" light ""
done
printf 'Pocket V2 screenshot matrix: %s\n' "$OUT"
find "$OUT" -type f -name '*.png' -print | sort
