#!/usr/bin/env bash
# Build the standalone Quest 2 APK (build/vrfight-quest.apk) and, if a headset is connected over
# USB with Developer Mode on, install and launch it.
# Usage: GODOT=/path/to/Godot_console.exe tests/export_quest.sh [--no-install]
# Needs JDK 17, the Android SDK and the 4.7.2 export templates (see README "Standalone Quest 2").
set -euo pipefail
cd "$(dirname "$0")/.."
G="${GODOT:-godot}"
ADB="${ADB:-$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe}"
mkdir -p build

# A Gradle daemon left running keeps Godot's export from exiting.
GRADLE_OPTS="-Dorg.gradle.daemon=false" "$G" --headless --xr-mode off \
  --install-android-build-template --export-debug Quest build/vrfight-quest.apk
ls -la build/vrfight-quest.apk

[ "${1:-}" = "--no-install" ] && exit 0
if ! "$ADB" get-state >/dev/null 2>&1; then
  echo "No headset found by adb. Plug it in, put it on and accept 'Allow USB debugging'."
  exit 1
fi
"$ADB" install -r build/vrfight-quest.apk
"$ADB" shell monkey -p com.vrfight.game -c android.intent.category.LAUNCHER 1 >/dev/null
echo "Launched. Logs: \"$ADB\" logcat -s godot"
