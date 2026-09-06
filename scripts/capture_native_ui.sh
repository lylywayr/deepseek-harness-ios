#!/usr/bin/env bash
set -euo pipefail
ROOT="${GITHUB_WORKSPACE:-$(pwd)}"
DEVICE="iPhone 16"
RUNTIME="18.2"
UDID="$(xcrun simctl list devices available | awk -F '[()]' -v d="$DEVICE" '$0 ~ d {print $2; exit}')"
if [[ -z "$UDID" ]]; then UDID="$(xcrun simctl create "PocketV2Fixture" com.apple.CoreSimulator.SimDeviceType.iPhone-16 com.apple.CoreSimulator.SimRuntime.iOS-18-2)"; fi
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
APP_PATH="$ROOT/build/Build/Products/Debug-iphonesimulator/DeepSeekHarness.app"
xcrun simctl install "$UDID" "$APP_PATH"
OUT="$ROOT/artifacts/pocket-v2-ui-matrix"
rm -rf "$OUT"
mkdir -p "$OUT"

capture() {
  local scene="$1" size="$2" appearance="$3" args="$4"
  local dir="$OUT/$size/$appearance"
  mkdir -p "$dir"
  xcrun simctl terminate "$UDID" com.example.DeepSeekHarness >/dev/null 2>&1 || true
  if ! xcrun simctl launch "$UDID" com.example.DeepSeekHarness -UITestFixture -NativeFixtureScreen "$scene" $args >/tmp/pocket-fixture-launch.log 2>&1; then
    cat /tmp/pocket-fixture-launch.log >&2
    echo "Pocket fixture launch failed: $scene" >&2
    exit 1
  fi
  sleep 2
  SIM_UID="$(xcrun simctl spawn "$UDID" id -u | tr -d '\r')"
  if ! xcrun simctl spawn "$UDID" launchctl print "gui/$SIM_UID" 2>/tmp/pocket-fixture-launchctl.log | grep -q "com.example.DeepSeekHarness"; then
    echo "Pocket fixture exited before screenshot: $scene" >&2
    cat /tmp/pocket-fixture-launch.log >&2 || true
    cat /tmp/pocket-fixture-launchctl.log >&2 || true
    xcrun simctl spawn "$UDID" log show --last 20s --style compact --predicate 'process == "DeepSeekHarness" OR composedMessage CONTAINS[c] "DeepSeekHarness"' >&2 || true
    exit 1
  fi
  xcrun simctl io "$UDID" screenshot "$dir/$scene-$size-$appearance.png"
  xcrun simctl terminate "$UDID" com.example.DeepSeekHarness >/dev/null 2>&1 || true
}

# iPhone 16 is the 390x844 evidence target. 430x932 is produced with a
# second simulator when the runtime is available; all scenes remain real Pocket.
for scene in workspace drawer conversation process artifacts activity settings; do capture "$scene" "390x844" "light" ""; done
capture keyboard "390x844" "light" ""
capture workspace "390x844" "dark" "-PocketDark"

UDID430="$(xcrun simctl list devices available | awk -F '[()]' '$0 ~ /iPhone 15 Pro Max/ {print $2; exit}')"
if [[ -z "$UDID430" ]]; then
  UDID430="$(xcrun simctl create "PocketV2Fixture430" com.apple.CoreSimulator.SimDeviceType.iPhone-15-Pro-Max com.apple.CoreSimulator.SimRuntime.iOS-18-2 2>/dev/null || true)"
fi
if [[ -n "$UDID430" ]]; then
  xcrun simctl boot "$UDID430" 2>/dev/null || true
  xcrun simctl bootstatus "$UDID430" -b
  xcrun simctl install "$UDID430" "$APP_PATH"
  UDID="$UDID430"
    for scene in workspace drawer conversation process artifacts activity settings keyboard; do capture "$scene" "430x932" "light" ""; done
    capture workspace "430x932" "dark" "-PocketDark"
else
  printf '430x932 simulator unavailable; 390x844 evidence retained\n'
fi
printf 'Pocket V2 screenshot matrix: %s\n' "$OUT"
find "$OUT" -type f -name '*.png' | sort
