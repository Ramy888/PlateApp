#!/usr/bin/env bash
# Captures the store screenshot set from a release build on a running Android
# emulator or device.
#
#   flutter build apk --release
#   ./tool/capture_screens.sh [output-dir]
#
# Coordinates are percentages of the screen, tuned on a 1080x2424 Pixel 9 AVD.
# This is a scripted walk-through, not a UI test: if the layout moves, the taps
# land somewhere else and the output is wrong rather than failing. Always look
# at the images before uploading them.
set -euo pipefail

OUT="${1:-screenshots}"
ADB="${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb"
PKG="com.platepatch.app"
APK="build/app/outputs/flutter-apk/app-release.apk"

[ -x "$ADB" ] || { echo "adb not found at $ADB" >&2; exit 1; }
[ -f "$APK" ] || { echo "Missing $APK — run: flutter build apk --release" >&2; exit 1; }

# adb speaks CRLF; an unstripped \r poisons the arithmetic below.
size=$("$ADB" shell wm size | tr -d '\r' | sed 's/.*: //')
W=${size%x*}
H=${size#*x}
echo "Device screen: ${W}x${H}"

# Every adb call is redirected: left on the pipe, its output blocks this script.
tap() { # tap <x-percent> <y-percent> [settle-seconds]
  "$ADB" shell input tap $(( W * $1 / 100 )) $(( H * $2 / 100 )) >/dev/null 2>&1
  sleep "${3:-2}"
}

back() { # back [settle-seconds]
  "$ADB" shell input keyevent KEYCODE_BACK >/dev/null 2>&1
  sleep "${1:-2}"
}

shot() { # shot <name>
  "$ADB" exec-out screencap -p > "$OUT/$1.png"
  echo "  → $OUT/$1.png"
}

mkdir -p "$OUT"
rm -f "$OUT"/*.png

echo "Installing a clean copy..."
"$ADB" uninstall "$PKG" >/dev/null 2>&1 || true
"$ADB" install -r "$APK" >/dev/null 2>&1
# The camera screen is part of the walk-through, so grant it up front rather
# than screenshotting a permission dialog.
"$ADB" shell pm grant "$PKG" android.permission.CAMERA >/dev/null 2>&1
"$ADB" shell am start -n "$PKG/.MainActivity" >/dev/null 2>&1
sleep 7

shot 01_welcome
tap 50 92;    shot 02_goal            # Continue
tap 50 92;    shot 03_preferences     # Continue
tap 50 92 3;  shot 04_meal            # Start patching

# The scan flow. The camera needs a granted permission, which the install
# step above handles.
tap 50 28 6;  shot 05_scan_camera     # "Scan my meal" card
back 3

# The manual path still works with no network, and is what the rest of the
# walk-through uses.
tap 17 53 1                           # Rice
tap 45 65 1;  shot 06_meal_selected   # Chicken
tap 50 93 3;  shot 07_result          # Patch this meal
tap 50 69 3;  shot 08_check           # I'll add this, first card
tap 50 45 3                           # Comfortably satisfied
tap 94 9 3;   shot 09_saved           # bookmark icon
tap 87 9 3;   shot 10_paywall         # Get Pro

echo
echo "Done. Review every image — a mistimed tap produces a plausible wrong screen."
