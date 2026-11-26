#!/usr/bin/env bash
#
# Builds the Release application and packages it into a disk image with the usual
# drag-to-Applications window.
#
# Run by the maintainer before publishing a release, never by someone who installs the
# app. The image is attached to a GitHub release, with its checksum and a small build
# record next to it; nothing is committed, so the git history stays free of binaries.
#
# Usage:
#   scripts/make-dmg.sh
#
# Output, under dist/:
#   <product>-<version>.dmg            the disk image to attach to the release
#   <product>-<version>.dmg.sha256     the digest, usable with `shasum -a 256 -c`
#   <product>-<version>.dmg.build.txt  commit, version and build time
#
# The working tree must be clean: an artifact must correspond to committed source, not to
# whatever happened to be in the tree.
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
BACKGROUND="$ROOT/assets/dmg-background.png"
LAYOUT="$ROOT/scripts/dmg-layout.conf"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
MOUNT_POINT="/Volumes/$VOLUME_NAME"

if [ ! -f "$LAYOUT" ]; then
  echo "error: $LAYOUT is missing; it holds the window geometry shared with the artwork." >&2
  exit 1
fi
# shellcheck source=scripts/dmg-layout.conf
. "$LAYOUT"

BUILD_DIR=""
MOUNTED=0

cleanup() {
  status=$?
  if [ "$MOUNTED" -eq 1 ]; then
    if hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null; then
      MOUNTED=0
    else
      echo "warning: the volume could not be detached; it is still mounted at $MOUNT_POINT" >&2
      echo "warning: keeping $BUILD_DIR, because deleting it would remove the image behind the mounted volume" >&2
      exit "$status"
    fi
  fi
  if [ -n "$BUILD_DIR" ]; then
    rm -rf "$BUILD_DIR"
  fi
  exit "$status"
}
trap cleanup EXIT

if [ -n "$(git status --porcelain)" ]; then
  echo "error: the working tree is not clean. Commit or stash the changes first, so the image matches a committed revision." >&2
  exit 1
fi

if mount | grep -qF " on $MOUNT_POINT ("; then
  echo "error: a volume named \"$VOLUME_NAME\" is already mounted. Eject it and retry." >&2
  exit 1
fi
if [ -d "$MOUNT_POINT" ]; then
  # An interrupted run can leave the mount point directory behind; a plain directory is
  # not a mounted volume, so it cannot be ejected and must not block the next run.
  if rmdir "$MOUNT_POINT" 2>/dev/null; then
    echo "==> Removed a stale mount point left by an earlier run"
  else
    echo "error: $MOUNT_POINT exists, is not empty, and nothing is mounted on it. Inspect it by hand." >&2
    exit 1
  fi
fi

# Everything temporary lives outside the worktree, so no build output can be committed.
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/castplayer-dmg.XXXXXX")"
RW_IMAGE="$BUILD_DIR/read-write.dmg"
BUILD_LOG="$BUILD_DIR/xcodebuild.log"

echo "==> Building $SCHEME (Release)"
if ! xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$BUILD_DIR" \
  build >"$BUILD_LOG" 2>&1
then
  FAILURE_LOG="$ROOT/dist/xcodebuild-failure.log"
  mkdir -p "$ROOT/dist"
  cp "$BUILD_LOG" "$FAILURE_LOG"
  echo "error: the Release build failed." >&2
  echo "error: the full log is kept at $FAILURE_LOG; its last lines:" >&2
  tail -40 "$BUILD_LOG" >&2
  exit 1
fi

# The built bundle is the source of truth for the application name, so nothing has to
# restate it: the product, the bundle and the artifact all come from here.
PRODUCTS="$BUILD_DIR/Build/Products/Release"
APP_COUNT="$(find "$PRODUCTS" -maxdepth 1 -name '*.app' | wc -l | tr -d ' ')"
if [ "$APP_COUNT" -ne 1 ]; then
  echo "error: expected exactly one application in $PRODUCTS, found $APP_COUNT" >&2
  exit 1
fi
APP="$(find "$PRODUCTS" -maxdepth 1 -name '*.app' | head -1)"
APP_NAME="$(basename "$APP")"
# The bundle keeps the spaced name Finder shows; the download drops the spaces.
ARTIFACT_BASE="${APP_NAME%.app}"
ARTIFACT_BASE="${ARTIFACT_BASE// /}"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
STAGE="$BUILD_DIR/stage"
OUT_DIR="$ROOT/dist"
OUT="$OUT_DIR/$ARTIFACT_BASE-$VERSION.dmg"

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

# The mount point is explicit, so no parsing of the attach output is needed and no
# later step depends on an assumed path. The preflight proved the point was free.
hdiutil attach "$RW_IMAGE" -mountpoint "$MOUNT_POINT" -nobrowse -noautoopen >/dev/null
if [ ! -d "$MOUNT_POINT" ]; then
  echo "error: the image was not mounted at $MOUNT_POINT" >&2
  exit 1
fi
MOUNTED=1

BACKGROUND_FILE=""
if [ -f "$BACKGROUND" ]; then
  mkdir -p "$MOUNT_POINT/.background"
  cp "$BACKGROUND" "$MOUNT_POINT/.background/dmg-background.png"
  BACKGROUND_FILE="$MOUNT_POINT/.background/dmg-background.png"
fi

# The window geometry comes from scripts/dmg-layout.conf, which the background generator
# reads too: the image is drawn at twice these points, and the chevron is derived from the
# icon positions, so the two cannot drift apart.
echo "==> Arranging the window"
FINDER_LOG="$BUILD_DIR/osascript.log"
if DMG_VOLUME_NAME="$VOLUME_NAME" \
  DMG_BACKGROUND_FILE="$BACKGROUND_FILE" \
  DMG_APP_NAME="$APP_NAME" \
  DMG_LEFT="$WINDOW_LEFT" \
  DMG_TOP="$WINDOW_TOP" \
  DMG_RIGHT="$WINDOW_RIGHT" \
  DMG_BOTTOM="$WINDOW_BOTTOM" \
  DMG_APP_X="$APP_X" \
  DMG_APPS_X="$APPS_X" \
  DMG_ICON_Y="$ICON_Y" \
  osascript >"$FINDER_LOG" 2>&1 <<'APPLESCRIPT'
on run
	set diskName to system attribute "DMG_VOLUME_NAME"
	set backgroundPath to system attribute "DMG_BACKGROUND_FILE"
	set appName to system attribute "DMG_APP_NAME"
	set leftEdge to (system attribute "DMG_LEFT") as integer
	set topEdge to (system attribute "DMG_TOP") as integer
	set rightEdge to (system attribute "DMG_RIGHT") as integer
	set bottomEdge to (system attribute "DMG_BOTTOM") as integer
	set appX to (system attribute "DMG_APP_X") as integer
	set appsX to (system attribute "DMG_APPS_X") as integer
	set iconY to (system attribute "DMG_ICON_Y") as integer
	tell application "Finder"
		tell disk diskName
			open
			set current view of container window to icon view
			set toolbar visible of container window to false
			set statusbar visible of container window to false
			set the bounds of container window to {leftEdge, topEdge, rightEdge, bottomEdge}
			set theViewOptions to the icon view options of container window
			set arrangement of theViewOptions to not arranged
			set icon size of theViewOptions to 128
			if backgroundPath is not "" then
				set background picture of theViewOptions to (POSIX file backgroundPath)
			end if
			set position of item appName of container window to {appX, iconY}
			set position of item "Applications" of container window to {appsX, iconY}
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
  if grep -qE '\-1743|Not authori[sz]ed|not permitted' "$FINDER_LOG"; then
    echo "warning: Finder automation is not permitted, so the image keeps the default layout." >&2
    echo "warning: allow this terminal to control Finder in System Settings > Privacy & Security > Automation." >&2
  else
    echo "warning: the Finder layout failed, so the image keeps the default layout:" >&2
    sed 's/^/  /' "$FINDER_LOG" >&2
  fi
fi

# The volume icon is set after the window layout on purpose: Finder removes the icon file
# when it opens a volume that already carries one.
if [ -f "$APP/Contents/Resources/AppIcon.icns" ] && command -v SetFile >/dev/null; then
  cp "$APP/Contents/Resources/AppIcon.icns" "$MOUNT_POINT/.VolumeIcon.icns"
  if SetFile -a C "$MOUNT_POINT" 2>/dev/null; then
    echo "==> Volume icon set"
  else
    echo "warning: the volume icon could not be set" >&2
  fi
fi

# Leave no registration behind: every build would otherwise add a stale copy of the app
# that Spotlight and LaunchServices keep offering next to the installed one.
if [ -x "$LSREGISTER" ]; then
  "$LSREGISTER" -u "$MOUNT_POINT/$APP_NAME" >/dev/null 2>&1 || true
fi

echo "==> Detaching and compressing"
sync
if ! hdiutil detach "$MOUNT_POINT" -quiet; then
  echo "error: the volume is busy and could not be detached. Eject it in Finder and retry." >&2
  exit 1
fi
MOUNTED=0

hdiutil convert "$RW_IMAGE" -format UDZO -ov -o "$OUT" >/dev/null

echo "==> Verifying the image"
hdiutil verify "$OUT" >/dev/null

DIGEST="$(shasum -a 256 "$OUT" | awk '{print $1}')"
printf '%s  %s\n' "$DIGEST" "$(basename "$OUT")" > "$OUT.sha256"
{
  echo "artifact: $(basename "$OUT")"
  echo "sha256: $DIGEST"
  echo "application: $APP_NAME"
  echo "version: $VERSION"
  echo "commit: $(git rev-parse HEAD)"
  echo "built: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$OUT.build.txt"

if [ -x "$LSREGISTER" ]; then
  "$LSREGISTER" -u "$APP" >/dev/null 2>&1 || true
fi

echo "==> Done"
ls -lh "$OUT" "$OUT.sha256" "$OUT.build.txt"
echo
echo "Digest: $DIGEST"
echo "Verify with: shasum -a 256 -c \"$(basename "$OUT").sha256\""
