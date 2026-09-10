#!/usr/bin/env bash
# The release build, with every key it needs.
#
# Written because three AABs shipped without --dart-define=REVENUECAT_ANDROID_KEY,
# including the one that went live. The app is *designed* to survive a missing
# key — the paywall reports "Pro is not available right now" and nothing else
# changes — which is exactly why nobody noticed: nothing crashed, nothing
# failed a test, and the store listing said subscriptions were available while
# the binary could not sell one.
#
#   tool/build_release.sh aab     # app bundle, for Play
#   tool/build_release.sh apk     # apk, for a device
set -euo pipefail
cd "$(dirname "$0")/.."

[ -f .env ] || { echo "No .env — it holds the keys and is gitignored."; exit 1; }
set -a; . ./.env; set +a

: "${REVENUECAT_ANDROID_KEY:?REVENUECAT_ANDROID_KEY is missing from .env}"
case "$REVENUECAT_ANDROID_KEY" in
  goog_*) ;;
  *) echo "REVENUECAT_ANDROID_KEY does not look like a Play key (expected goog_...)"; exit 1 ;;
esac

TARGET="${1:-aab}"
case "$TARGET" in
  aab) CMD=(flutter build appbundle --release); OUT=build/app/outputs/bundle/release/app-release.aab ;;
  apk) CMD=(flutter build apk --release);       OUT=build/app/outputs/flutter-apk/app-release.apk ;;
  *) echo "usage: $0 [aab|apk]"; exit 1 ;;
esac

"${CMD[@]}" --dart-define=REVENUECAT_ANDROID_KEY="$REVENUECAT_ANDROID_KEY" \
  ${PLATEPATCH_API:+--dart-define=PLATEPATCH_API="$PLATEPATCH_API"}

# Proving it rather than trusting the flag: the key has to be in the binary.
echo "Checking the key actually made it in..."
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
case "$TARGET" in
  aab) unzip -o -q "$OUT" 'base/lib/arm64-v8a/libapp.so' -d "$WORK"; LIB="$WORK/base/lib/arm64-v8a/libapp.so" ;;
  apk) unzip -o -q "$OUT" 'lib/arm64-v8a/libapp.so'      -d "$WORK"; LIB="$WORK/lib/arm64-v8a/libapp.so" ;;
esac
# grep -c, not grep -q: -q closes the pipe on the first match, strings takes a
# SIGPIPE for it, and `set -o pipefail` then calls the whole check a failure —
# which is how this script first reported a key that was sitting right there.
if [ "$(strings "$LIB" | grep -c "^${REVENUECAT_ANDROID_KEY}$")" -ge 1 ]; then
  echo "OK — RevenueCat key is compiled into $OUT"
else
  echo "FAILED — the key is not in the binary. Do not upload $OUT." >&2
  exit 1
fi
