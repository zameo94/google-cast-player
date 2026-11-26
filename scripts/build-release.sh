#!/usr/bin/env bash
#
# Builds the Release application.
#
# It compiles only: no disk images, no mounts, no AppleScript, no administrative rights.
# The result goes to a predictable directory, so packaging can take the bundle as an
# argument and never needs to compile anything itself.
#
# Usage:
#   scripts/build-release.sh
#
# Output:
#   build/Build/Products/Release/<product>.app   and the path, on the last line
#   build/xcodebuild.log                         the full build log, kept on success and failure
#   build/.built-commit                          the commit a clean build came from
#
# A dirty working tree is refused by default, so a release artifact corresponds to a
# committed revision. Set ALLOW_DIRTY=1 for a throw-away build while developing.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROJECT="GoogleCastPlayer.xcodeproj"
SCHEME="GoogleCastPlayer"
OUT_DIR="$ROOT/build"
LOG="$OUT_DIR/xcodebuild.log"

if [ "${ALLOW_DIRTY:-0}" != "1" ] && [ -n "$(git status --porcelain)" ]; then
  echo "error: the working tree is not clean. Commit or stash the changes, or set ALLOW_DIRTY=1 for a development build." >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
# Build products are not application content: keeping them out of the Spotlight index
# avoids offering a second copy of the application next to the installed one.
touch "$OUT_DIR/.metadata_never_index"

echo "==> Building $SCHEME (Release)"
if ! xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$OUT_DIR" \
  build >"$LOG" 2>&1
then
  echo "error: the Release build failed. The full log is at $LOG; its last lines:" >&2
  tail -40 "$LOG" >&2
  exit 1
fi

PRODUCTS="$OUT_DIR/Build/Products/Release"
APP_COUNT="$(find "$PRODUCTS" -maxdepth 1 -name '*.app' | wc -l | tr -d ' ')"
if [ "$APP_COUNT" -ne 1 ]; then
  echo "error: expected exactly one application in $PRODUCTS, found $APP_COUNT" >&2
  exit 1
fi
APP="$(find "$PRODUCTS" -maxdepth 1 -name '*.app' | head -1)"

# A release artifact must be traceable to a commit: the marker is written only by a build
# made from a clean tree, and make-dmg.sh refuses to package a default bundle without it.
if [ "${ALLOW_DIRTY:-0}" != "1" ]; then
  git rev-parse HEAD > "$OUT_DIR/.built-commit"
fi

echo "==> Built $(basename "$APP")"
echo "==> Log: $LOG"
printf '%s\n' "$APP"
