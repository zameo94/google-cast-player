#!/usr/bin/env bash
#
# Builds the Release application and packages it into a disk image with the usual
# drag-to-Applications window.
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
#
# The window layout is Finder state stored in the image's .DS_Store, which Finder only
# writes for a volume mounted under /Volumes. Writing it needs the terminal to be allowed
# to control Finder (System Settings > Privacy & Security > Automation); when that is not
# allowed the image is still produced with Finder's default layout and the script says so.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROJECT="GoogleCastPlayer.xcodeproj"
SCHEME="GoogleCastPlayer"
VOLUME_NAME="Google Cast Player"
MOUNT_POINT="/Volumes/$VOLUME_NAME"
BACKGROUND="$ROOT/assets/dmg-background.png"

if [ -d "$MOUNT_POINT" ]; then
  echo "error: a volume named \"$VOLUME_NAME\" is already mounted. Eject it and retry." >&2
  exit 1
fi

# Build outside the worktree, so no build output or scratch directory can be committed.
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/castplayer-dmg.XXXXXX")"
RW_IMAGE="$BUILD_DIR/read-write.dmg"
trap 'hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true; rm -rf "$BUILD_DIR"' EXIT

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

echo "==> Creating a writable image"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDRW \
  "$RW_IMAGE" >/dev/null

hdiutil attach "$RW_IMAGE" -nobrowse -noautoopen -quiet

BACKGROUND_FILE=""
if [ -f "$BACKGROUND" ]; then
  mkdir -p "$MOUNT_POINT/.background"
  cp "$BACKGROUND" "$MOUNT_POINT/.background/dmg-background.png"
  BACKGROUND_FILE="$MOUNT_POINT/.background/dmg-background.png"
fi

echo "==> Arranging the window"
if DMG_VOLUME_NAME="$VOLUME_NAME" DMG_BACKGROUND_FILE="$BACKGROUND_FILE" osascript <<'APPLESCRIPT' >/dev/null 2>&1
on run
	set diskName to system attribute "DMG_VOLUME_NAME"
	set backgroundPath to system attribute "DMG_BACKGROUND_FILE"
	tell application "Finder"
		tell disk diskName
			open
			set current view of container window to icon view
			set toolbar visible of container window to false
			set statusbar visible of container window to false
			set the bounds of container window to {300, 160, 900, 560}
			set theViewOptions to the icon view options of container window
			set arrangement of theViewOptions to not arranged
			set icon size of theViewOptions to 128
			if backgroundPath is not "" then
				set background picture of theViewOptions to (POSIX file backgroundPath)
			end if
			set position of item "GoogleCastPlayer.app" of container window to {150, 190}
			set position of item "Applications" of container window to {450, 190}
			update without registering applications
		end tell
		delay 2
		tell disk diskName to close
	end tell
end run
APPLESCRIPT
then
  if [ -f "$MOUNT_POINT/.DS_Store" ]; then
    echo "==> Window layout written"
  else
    echo "warning: Finder did not write the window layout; the image keeps the default one" >&2
  fi
else
  echo "warning: Finder layout skipped (automation not permitted); the image keeps the default layout" >&2
fi

echo "==> Detaching and compressing"
sync
hdiutil detach "$MOUNT_POINT" -quiet
hdiutil convert "$RW_IMAGE" -format UDZO -o "$OUT" >/dev/null

echo "==> Done"
ls -lh "$OUT"
shasum -a 256 "$OUT"
