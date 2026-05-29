#!/usr/bin/env bash
#
# Install the debug APK against an already-running emulator + run the
# instrumented burst test. Caller is responsible for booting the
# emulator first (`emulator -avd <name>` or the CI matrix runner).

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANDROID_APP="$HERE/android-app"
ADB="${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb"

echo "=== waiting for emulator ==="
"$ADB" wait-for-device
DEVICE_COUNT=$("$ADB" devices | tail -n +2 | awk '/device$/ {n++} END {print n+0}')
if [ "$DEVICE_COUNT" -eq 0 ]; then
  echo "FATAL: no emulator / device attached." >&2
  exit 1
fi

echo "=== :app:connectedDebugAndroidTest ==="
( cd "$ANDROID_APP" && ./gradlew :app:connectedDebugAndroidTest )

echo
echo "SUCCESS. Test reports at:"
echo "  $ANDROID_APP/app/build/reports/androidTests/connected/"
