#!/usr/bin/env bash
#
# Builds the Release application and packages it into a compressed disk image.
#
# Run by the maintainer before publishing a release, never by someone who installs the
# app. The image is attached to a GitHub release; it is not committed to the repository,
# so the git history stays free of binaries.
#
# Usage:
#   scripts/make-dmg.sh
#
# Output:
#   dist/GoogleCastPlayer-<version>.dmg  plus its SHA256, printed on the last line.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROJECT="GoogleCastPlayer.xcodeproj"
SCHEME="GoogleCastPlayer"
VOLUME_NAME="Google Cast Player"

# Build outside the worktree, so no build output or scratch directory can be committed.
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/castplayer-dmg.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT

echo "==> Building $SCHEME (Release)"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$BUILD_DIR" \
  build >/dev/null

APP="$BUILD_DIR/Build/Products/Release/$SCHEME.app"
if [ ! -d "$APP" ]; then
  echo "error: the build produced no application at $APP" >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
STAGE="$BUILD_DIR/stage"
OUT_DIR="$ROOT/dist"
OUT="$OUT_DIR/GoogleCastPlayer-$VERSION.dmg"

echo "==> Verifying the signature of the built application"
codesign --verify --deep --strict "$APP"

echo "==> Staging the disk image contents"
mkdir -p "$STAGE" "$OUT_DIR"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "==> Creating $OUT"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$OUT" >/dev/null

echo "==> Done"
ls -lh "$OUT"
shasum -a 256 "$OUT"
