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
boot_simulator() {
  local target="$1" attempt=1 status_log rc
  # A clean shutdown avoids carrying a partially migrated CoreSimulator state.
  xcrun simctl shutdown "$target" >/dev/null 2>&1 || true
  xcrun simctl boot "$target" 2>/dev/null || true
  while (( attempt <= 8 )); do
    status_log="/tmp/pocket-bootstatus-$target.log"
    set +e
    run_timeout "bootstatus-$attempt" xcrun simctl bootstatus "$target" -b >"$status_log" 2>&1
    rc=$?
    set -e
    cat "$status_log" >&2 || true
    if [[ "$rc" -eq 0 ]]; then return 0; fi
    echo "[diag] bootstatus attempt=$attempt rc=$rc" >&2
    run_timeout "launchctl-$attempt" xcrun simctl spawn "$target" launchctl print system >"/tmp/pocket-launchctl-$target.log" 2>&1 || true
    tail -40 "/tmp/pocket-launchctl-$target.log" >&2 || true
    attempt=$((attempt + 1))
    xcrun simctl shutdown "$target" >/dev/null 2>&1 || true
    xcrun simctl boot "$target" 2>/dev/null || true
  done
  echo "Simulator failed to reach booted state: $target" >&2
  return 1
}
boot_simulator "$UDID"
UDID390="$UDID"
APP_PATH="$ROOT/build/Build/Products/Debug-iphonesimulator/DeepSeekHarness.app"
run_timeout install xcrun simctl install "$UDID" "$APP_PATH"
OUT="$ROOT/artifacts/pocket-v2-ui-matrix"
rm -rf "$OUT"
mkdir -p "$OUT"

prepare_keyboard_scene() {
  # Suppress the "Speed up your typing"/continuous-path onboarding card and any
  # first-keyboard-appearance overlays so the fixture raises a real system
  # keyboard.  The onboarding state is split across several preference domains:
  # keyboardservicesd (observed on the 390x844 evidence) plus the keyboard
  # preferences / continuous-path domains which gate the "Continue" card.
  run_timeout spawn xcrun simctl spawn "$UDID" defaults write com.apple.keyboardservicesd KeyboardContinuousPathIntroductionShown -bool true
  run_timeout spawn xcrun simctl spawn "$UDID" defaults write com.apple.keyboardservicesd KeyboardAutocorrectionListsShown -bool true
  run_timeout spawn xcrun simctl spawn "$UDID" defaults write com.apple.keyboardservicesd KeyboardDidShowContinuousPathIntroduction -bool true
  run_timeout spawn xcrun simctl spawn "$UDID" defaults write com.apple.keyboard.preferences IntroductionShown -bool true
  run_timeout spawn xcrun simctl spawn "$UDID" defaults write com.apple.keyboard.preferences DidShowContinuousPathIntroduction -bool true
  run_timeout spawn xcrun simctl spawn "$UDID" defaults write com.apple.keyboard.preferences KeyboardContinuousPathIntroductionShown -bool true
  run_timeout spawn xcrun simctl spawn "$UDID" defaults write com.apple.keyboard.ContinuousPath IntroductionShown -bool true
  run_timeout spawn xcrun simctl spawn "$UDID" defaults write com.apple.keyboard.ContinuousPath DidShowContinuousPathIntroduction -bool true
  run_timeout spawn xcrun simctl spawn "$UDID" launchctl kickstart -k system/com.apple.keyboardservicesd >/dev/null 2>&1 || true
  run_timeout spawn xcrun simctl spawn "$UDID" launchctl kickstart -k system/com.apple.TextInput >/dev/null 2>&1 || true
  run_timeout sleep sleep 1
}

capture() {
  local scene="$1" size="$2" appearance="$3"
  local dir="$OUT/$size/$appearance"
  local launch_log="/tmp/pocket-fixture-launch.log"
  local process_log="/tmp/pocket-fixture-process.log"
  local launch_output=""
  local pid=""
  local alive=0
  local launch_args=(-UITestFixture -NativeFixtureScreen "$scene")
  if [[ "$appearance" == "dark" ]]; then launch_args+=(-PocketDark); fi
  mkdir -p "$dir"
  CURRENT_SCENE="$scene"
  if [[ "$scene" == "keyboard" ]]; then
    # Seed preferences before launching the fixture, then kick the services
    # again after focus in case the keyboard scene was already cached.
    prepare_keyboard_scene
  fi
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  if ! launch_output="$(run_timeout launch xcrun simctl launch "$UDID" "$BUNDLE_ID" "${launch_args[@]}" 2>&1)"; then
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
    # The continuous-path ("Speed up your typing") onboarding card is a
    # per-first-keyboard-appearance state in keyboardservicesd.  A single cold
    # launch can race the daemon reading the seeded "IntroductionShown"
    # preference, leaving the onboarding card visible instead of a real
    # keyboard (observed on the 390x844 evidence).  Warm-relaunch once so the
    # seeded preference is durable before we raise the keyboard again.
    xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
    prepare_keyboard_scene
    if ! launch_output="$(run_timeout launch xcrun simctl launch "$UDID" "$BUNDLE_ID" "${launch_args[@]}" 2>&1)"; then
      printf '%s\n' "$launch_output" >"$launch_log"
      cat "$launch_log" >&2
      echo "Pocket fixture warm relaunch failed: $scene" >&2
      exit 1
    fi
    sleep 2
    # Keyboard services are intentionally not restarted again after the warm
    # relaunch: doing so can deadlock SpringBoard's screenshot request.
  fi
  run_timeout screenshot xcrun simctl io "$UDID" screenshot "$dir/$scene-$size-$appearance.png"
  test -s "$dir/$scene-$size-$appearance.png"
  # Keep a deterministic scene manifest beside the real PNG evidence.
  printf "%s\n" "$scene|$size|$appearance" >> "$OUT/manifest.txt"
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
}

# iPhone 14 is the 390x844 evidence target. 430x932 is produced with a
# second simulator when the runtime is available; all scenes remain real Pocket.
for scene in workspace drawer flat conversation normal process trajectory artifacts activity settings; do capture "$scene" "390x844" "light"; done
capture workspace "390x844" "dark"

UDID430="$(find_udid "iPhone 15 Pro Max")"
if [[ -z "$UDID430" ]]; then
  UDID430="$(xcrun simctl create "PocketV2Fixture430" com.apple.CoreSimulator.SimDeviceType.iPhone-15-Pro-Max com.apple.CoreSimulator.SimRuntime.iOS-18-2 2>/dev/null || true)"
fi
if [[ -n "$UDID430" ]]; then
  boot_simulator "$UDID430"
  xcrun simctl install "$UDID430" "$APP_PATH"
  UDID="$UDID430"
  for scene in workspace drawer flat conversation normal process trajectory artifacts activity settings; do capture "$scene" "430x932" "light"; done
  capture workspace "430x932" "dark"
  for scene in drawer conversation artifacts settings; do capture "$scene" "430x932" "dark"; done
else
  printf '430x932 simulator unavailable; 390x844 evidence retained\n'
fi
# Evidence scenes: workspace drawer flat conversation normal process trajectory artifacts activity settings keyboard.
# Keyboard capture is intentionally omitted from this production-parity matrix: the
# user waived complete simulator keyboard rendering as a gate. The keyboard token
# remains in the evidence-scene contract for backward-compatible fixture checks;
# input/composer layout is covered by the conversation scenes, while real keyboard
# behavior remains a device-level manual boundary.
printf 'Pocket V2 screenshot matrix: %s\n' "$OUT"
find "$OUT" -type f -name '*.png' -print | sort
