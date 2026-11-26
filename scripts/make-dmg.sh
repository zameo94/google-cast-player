#!/usr/bin/env bash
#
# Packages an already built application into a disk image.
#
# It never compiles: no xcodebuild, no compiler, no Xcode build phase. The bundle arrives
# as an argument, is validated, and is copied — never modified — into a disk image that is
# then verified. It needs no administrative rights, no Full Disk Access, no Accessibility,
# no Screen Recording and no Input Monitoring.
#
# Usage:
#   scripts/make-dmg.sh "build/Build/Products/Release/Google Cast Player.app"
#   scripts/make-dmg.sh <app> --pretty     also arrange the window through Finder (optional)
#   scripts/make-dmg.sh <app> --force      replace artifacts that already exist
#
# Output, under dist/:
#   <product>-<version>.dmg            the image to attach to a release
#   <product>-<version>.dmg.sha256     the digest, usable with `shasum -a 256 -c`
#   <product>-<version>.dmg.build.txt  commit, version and build time
#
# Without --pretty the image is produced with no AppleScript at all and the window keeps
# Finder's default layout. --pretty needs this terminal to be allowed to control Finder
# (System Settings > Privacy & Security > Automation); if the permission is missing the
# image is still produced, with the default layout, and the script says so. The permission
# is never a condition for packaging.
#
# Existing artifacts are never replaced silently: without --force the script refuses and
# lists what is in the way.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VOLUME_NAME="Google Cast Player"
LAYOUT="$ROOT/scripts/dmg-layout.conf"
BACKGROUND="$ROOT/assets/dmg-background.png"
OUT_DIR="$ROOT/dist"
PRETTY=0
FORCE=0
APP=""

usage() {
  sed -n '5,30p' "$0" | sed 's/^# \{0,1\}//'
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --pretty) PRETTY=1 ;;
    --force) FORCE=1 ;;
    -h|--help) usage; exit 0 ;;
    --)
      shift
      ;;
    -*)
      echo "error: unknown option $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [ -n "$APP" ]; then
        echo "error: only one application path is accepted." >&2
        exit 2
      fi
      APP="$1"
      ;;
  esac
  shift
done

if [ -z "$APP" ]; then
  echo "error: the path of the application bundle is required." >&2
  usage >&2
  exit 2
fi

# The input must be a macOS application bundle, not merely something that exists.
if [ ! -d "$APP" ]; then
  echo "error: no application bundle at $APP" >&2
  exit 1
fi
case "$APP" in
  *.app) ;;
  *)
    echo "error: $APP does not end in .app" >&2
    exit 1
    ;;
esac
APP="$(cd "$APP/.." && pwd)/$(basename "$APP")"
INFO_PLIST="$APP/Contents/Info.plist"
if [ ! -f "$INFO_PLIST" ]; then
  echo "error: $APP has no Contents/Info.plist, so it is not a macOS bundle." >&2
  exit 1
fi
EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO_PLIST" 2>/dev/null || true)"
if [ -z "$EXECUTABLE" ] || [ ! -x "$APP/Contents/MacOS/$EXECUTABLE" ]; then
  echo "error: $APP does not contain the executable its Info.plist names." >&2
  exit 1
fi
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST" 2>/dev/null || true)"
if [ -z "$VERSION" ]; then
  echo "error: $APP does not declare CFBundleShortVersionString." >&2
  exit 1
fi

# A bundled application that cannot be verified is not packaged.
echo "==> Verifying the signature of $(basename "$APP")"
codesign --verify --deep --strict "$APP"

APP_NAME="$(basename "$APP")"
# The bundle keeps the spaced name Finder shows; the download drops the spaces.
ARTIFACT_BASE="${APP_NAME%.app}"
ARTIFACT_BASE="${ARTIFACT_BASE// /}"
OUT="$OUT_DIR/$ARTIFACT_BASE-$VERSION.dmg"
SHA_FILE="$OUT.sha256"
BUILD_FILE="$OUT.build.txt"

if [ "$FORCE" -ne 1 ]; then
  existing=""
  for candidate in "$OUT" "$SHA_FILE" "$BUILD_FILE"; do
    if [ -e "$candidate" ]; then
      existing="$existing
  $candidate"
    fi
  done
  if [ -n "$existing" ]; then
    echo "error: these artifacts already exist:$existing" >&2
    echo "error: pass --force to replace them deliberately." >&2
    exit 1
  fi
fi

if [ "$PRETTY" -eq 1 ]; then
  if [ ! -f "$LAYOUT" ]; then
    echo "error: $LAYOUT is missing; it holds the window geometry." >&2
    exit 1
  fi
  # The layout file is data, not shell: only the known keys are read and every value must
  # be an integer, so a modified file cannot execute anything.
  while IFS='=' read -r key value; do
    case "$key" in
      ''|'#'*) continue ;;
      WINDOW_LEFT|WINDOW_TOP|WINDOW_RIGHT|WINDOW_BOTTOM|APP_X|APPS_X|ICON_Y)
        case "$value" in
          ''|*[!0-9]*)
            echo "error: $key in $LAYOUT must be an integer, found \"$value\"" >&2
            exit 1
            ;;
        esac
        printf -v "$key" '%s' "$value"
        ;;
    esac
  done < "$LAYOUT"
  for key in WINDOW_LEFT WINDOW_TOP WINDOW_RIGHT WINDOW_BOTTOM APP_X APPS_X ICON_Y; do
    if [ -z "${!key:-}" ]; then
      echo "error: $LAYOUT is missing $key" >&2
      exit 1
    fi
  done
  MOUNT_POINT="/Volumes/$VOLUME_NAME"
  if mount | grep -qF " on $MOUNT_POINT ("; then
    echo "error: a volume named \"$VOLUME_NAME\" is already mounted. Eject it and retry." >&2
    exit 1
  fi
  if [ -d "$MOUNT_POINT" ] && ! rmdir "$MOUNT_POINT" 2>/dev/null; then
    echo "error: $MOUNT_POINT exists, is not empty, and nothing is mounted on it. Inspect it by hand." >&2
    exit 1
  fi
else
  MOUNT_POINT=""
fi

# Everything temporary is created by this run, under a directory this run owns.
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/castplayer-dmg.XXXXXX")"
MOUNTED=0

cleanup() {
  status=$?
  if [ "$MOUNTED" -eq 1 ]; then
    if hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || hdiutil detach "$TMP_DIR/mnt" -quiet 2>/dev/null; then
      MOUNTED=0
    else
      echo "warning: a volume could not be detached; keeping $TMP_DIR so its image is not removed" >&2
      exit "$status"
    fi
  fi
  rm -rf "$TMP_DIR"
  exit "$status"
}
trap cleanup EXIT

STAGE="$TMP_DIR/stage"
RW_IMAGE="$TMP_DIR/read-write.dmg"
FINAL_IMAGE="$TMP_DIR/final.dmg"

echo "==> Staging the disk image contents"
mkdir -p "$STAGE"
# A copy, so the original bundle is never modified.
ditto "$APP" "$STAGE/$APP_NAME"
ln -s /Applications "$STAGE/Applications"

echo "==> Creating a writable image"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGE" \
  -format UDRW \
  "$RW_IMAGE" >/dev/null

echo "==> Mounting"
if [ "$PRETTY" -eq 1 ]; then
  # Finder only writes window state for a volume under /Volumes.
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

  echo "==> Arranging the window (optional, through Finder)"
  FINDER_LOG="$TMP_DIR/osascript.log"
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
      echo "warning: Finder automation is not permitted; the image keeps the default layout." >&2
      echo "warning: this is optional. Allow Automation only if you want the custom window." >&2
    else
      echo "warning: the Finder layout failed; the image keeps the default layout:" >&2
      sed 's/^/  /' "$FINDER_LOG" >&2
    fi
  fi

  # Set after the layout on purpose: Finder removes the icon file when it opens a volume
  # that already carries one.
  if [ -f "$APP/Contents/Resources/AppIcon.icns" ] && command -v SetFile >/dev/null; then
    cp "$APP/Contents/Resources/AppIcon.icns" "$MOUNT_POINT/.VolumeIcon.icns"
    SetFile -a C "$MOUNT_POINT" 2>/dev/null || echo "warning: the volume icon could not be set" >&2
  fi
else
  # No Finder, no AppleScript: a private mount point that never pollutes /Volumes.
  mkdir -p "$TMP_DIR/mnt"
  hdiutil attach "$RW_IMAGE" -mountpoint "$TMP_DIR/mnt" -nobrowse -noautoopen >/dev/null
  if [ ! -d "$TMP_DIR/mnt/Applications" ] && [ ! -L "$TMP_DIR/mnt/Applications" ]; then
    echo "error: the image was not mounted as expected at $TMP_DIR/mnt" >&2
    exit 1
  fi
  MOUNTED=1
fi

echo "==> Detaching"
sync
if ! hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null && ! hdiutil detach "$TMP_DIR/mnt" -quiet 2>/dev/null; then
  echo "error: the volume is busy and could not be detached. Eject it in Finder and retry." >&2
  exit 1
fi
MOUNTED=0

echo "==> Compressing"
hdiutil convert "$RW_IMAGE" -format UDZO -o "$FINAL_IMAGE" >/dev/null

echo "==> Verifying the image"
hdiutil verify "$FINAL_IMAGE" >/dev/null

DIGEST="$(shasum -a 256 "$FINAL_IMAGE" | awk '{print $1}')"

echo "==> Writing the artifacts"
mkdir -p "$OUT_DIR"
mv "$FINAL_IMAGE" "$OUT"
printf '%s  %s\n' "$DIGEST" "$(basename "$OUT")" > "$SHA_FILE"
{
  echo "artifact: $(basename "$OUT")"
  echo "sha256: $DIGEST"
  echo "application: $APP_NAME"
  echo "version: $VERSION"
  echo "source: $APP"
  echo "commit: $(git rev-parse HEAD 2>/dev/null || echo unknown)"
  echo "built: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$BUILD_FILE"

echo "==> Done"
ls -lh "$OUT" "$SHA_FILE" "$BUILD_FILE"
echo
echo "Digest: $DIGEST"
echo "Verify with: shasum -a 256 -c \"$(basename "$SHA_FILE")\""
