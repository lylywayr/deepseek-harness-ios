#!/usr/bin/env bash
set -euo pipefail

# Native-only screenshot smoke test. The fixture is never the production path.
ROOT="${GITHUB_WORKSPACE:-$(pwd)}"
DEVICE="iPhone 16"
RUNTIME="18.2"
UDID="$(xcrun simctl list devices available | awk -F '[()]' -v d="$DEVICE" -v r="$RUNTIME" '$0 ~ d && $0 ~ r {print $2; exit}')"
if [[ -z "$UDID" ]]; then
  UDID="$(xcrun simctl create "NativeFixture" com.apple.CoreSimulator.SimDeviceType.iPhone-16 com.apple.CoreSimulator.SimRuntime.iOS-18-2)"
fi
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
APP_PATH="$ROOT/build/Build/Products/Debug-iphonesimulator/DeepSeekHarness.app"
xcrun simctl install "$UDID" "$APP_PATH"
OUT="$ROOT/artifacts/native-ui-390x844"
rm -rf "$OUT"
mkdir -p "$OUT"
for screen in connection conversation sidebar settings directory approval question trajectory; do
  xcrun simctl launch "$UDID" com.example.DeepSeekHarness -UITestFixture --env NATIVE_FIXTURE_SCREEN="$screen" >/tmp/native-fixture-launch.log
  sleep 2
  xcrun simctl io "$UDID" screenshot "$OUT/$screen-390x844.png"
  xcrun simctl terminate "$UDID" com.example.DeepSeekHarness || true
done
printf 'native fixture screenshots: %s\n' "$OUT"
find "$OUT" -type f -name '*.png' | sort
