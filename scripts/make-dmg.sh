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
#   scripts/make-dmg.sh                       use the bundle build-release.sh produced
#   scripts/make-dmg.sh "path/to/App.app"     package a specific bundle
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
# Relative arguments belong to the directory the caller is in, which is not the directory
# this script moves to.
INVOCATION_DIR="$PWD"
# Both paths are resolved from the caller's directory, while it is still the current one:
# $0 can be "make-dmg.sh", "./make-dmg.sh", "scripts/make-dmg.sh" or absolute.
SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
cd "$ROOT"

VOLUME_NAME="Google Cast Player"
LAYOUT="$ROOT/scripts/dmg-layout.conf"
BACKGROUND="$ROOT/assets/dmg-background.png"
OUT_DIR="$ROOT/dist"
PRETTY=0
FORCE=0
APP=""

usage() {
  sed -n '5,32p' "$SCRIPT_PATH" | sed 's/^# \{0,1\}//'
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
  # No argument: take the bundle build-release.sh produces. Exactly one is expected; the
  # script refuses to guess between zero and several, so a stale or duplicated build
  # cannot be packaged by accident.
  BUILD_PRODUCTS="$ROOT/build/Build/Products/Release"
  if [ ! -d "$BUILD_PRODUCTS" ]; then
    echo "error: no bundle to package. Run scripts/build-release.sh first, or pass a path." >&2
    usage >&2
    exit 2
  fi
  FOUND="$(find "$BUILD_PRODUCTS" -maxdepth 1 -name '*.app' | sort)"
  COUNT="$(printf '%s\n' "$FOUND" | grep -c . || true)"
  if [ "$COUNT" -ne 1 ]; then
    echo "error: expected exactly one application in $BUILD_PRODUCTS, found $COUNT." >&2
    if [ -n "$FOUND" ]; then
      printf '%s\n' "$FOUND" | sed 's/^/  /' >&2
    fi
    echo "error: pass the bundle path explicitly." >&2
    exit 2
  fi
  APP="$FOUND"
  echo "==> Packaging $APP"
  echo "==> (from the build directory; no compilation involved)"
fi

# A relative path belongs to the directory the caller is in, which is not the repository
# root this script moved to. Resolve it before it is used.
case "$APP" in
  /*) ;;
  *) APP="$INVOCATION_DIR/$APP" ;;
esac

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
codesign --verify --strict "$APP"

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
DEVICE=""

cleanup() {
  status=$?
  if [ -n "$DEVICE" ]; then
    if hdiutil detach "$DEVICE" -quiet 2>/dev/null; then
      DEVICE=""
    else
      echo "warning: a volume could not be detached; keeping $TMP_DIR so its image is not removed" >&2
      exit "$status"
    fi
  fi
  rm -rf "$TMP_DIR"
  exit "$status"
}
trap cleanup EXIT

# Attaches our own image and records the device and the real mount point it was given.
# Working from the device, never from an assumed path, is what keeps a detach away from a
# volume this run did not mount.
attach_image() {
  local expected="$1" output
  output="$(hdiutil attach "$RW_IMAGE" -mountpoint "$expected" -nobrowse -noautoopen)"
  DEVICE="$(printf '%s\n' "$output" | awk -F'\t' 'NF >= 3 && $NF ~ /^\// { gsub(/ /, "", $1); print $1; exit }')"
  MOUNT_POINT="$(printf '%s\n' "$output" | awk -F'\t' 'NF >= 3 && $NF ~ /^\// { print $NF; exit }')"
  if [ -z "$DEVICE" ] || [ -z "$MOUNT_POINT" ]; then
    echo "error: the image was not mounted:" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi
  # hdiutil reports physical paths, while mktemp can hand out a path under /var that is
  # really /private/var, so the comparison resolves both before deciding.
  local expected_real actual_real
  expected_real="$(cd "$expected" 2>/dev/null && pwd -P || true)"
  actual_real="$(cd "$MOUNT_POINT" 2>/dev/null && pwd -P || true)"
  if [ -z "$expected_real" ] || [ "$actual_real" != "$expected_real" ]; then
    echo "error: the image mounted at $MOUNT_POINT instead of $expected; not touching it." >&2
    echo "error: eject any volume with the same name and retry." >&2
    exit 1
  fi
}

# Attaches without a fixed name, so every run gets a volume name of its own and cannot
# collide with anything already mounted. Used only by the optional Finder layout.
attach_image_unique() {
  local output
  output="$(hdiutil attach "$RW_IMAGE" -nobrowse -noautoopen)"
  DEVICE="$(printf '%s\n' "$output" | awk -F'\t' 'NF >= 3 && $NF ~ /^\/Volumes\// { gsub(/ /, "", $1); print $1; exit }')"
  MOUNT_POINT="$(printf '%s\n' "$output" | awk -F'\t' 'NF >= 3 && $NF ~ /^\/Volumes\// { print $NF; exit }')"
  if [ -z "$DEVICE" ] || [ -z "$MOUNT_POINT" ]; then
    echo "error: the image was not mounted:" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi
}

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
  # Finder only writes window state for a volume under /Volumes, and /Volumes cannot be
  # written by a normal user, so the volume name itself carries the uniqueness and is
  # renamed to the final name after the layout is written.
  attach_image_unique

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

  # The background is a Finder setting: if the layout was not written, the image would
  # carry 152 KB of a picture nothing displays. It was copied by this run, so this run
  # removes it.
  if [ ! -f "$MOUNT_POINT/.DS_Store" ] && [ -d "$MOUNT_POINT/.background" ]; then
    rm -rf -- "$MOUNT_POINT/.background"
  fi

  echo "==> Naming the volume"
  if ! diskutil rename "$MOUNT_POINT" "$VOLUME_NAME" >/dev/null; then
    echo "error: the volume could not be renamed to \"$VOLUME_NAME\"." >&2
    exit 1
  fi
  MOUNT_POINT="/Volumes/$VOLUME_NAME"
  if [ ! -d "$MOUNT_POINT" ]; then
    echo "error: after the rename the volume is not at $MOUNT_POINT; another volume may already use that name." >&2
    exit 1
  fi

  # Set after the layout and the rename, on purpose: Finder removes the icon file when it
  # opens a volume that already carries one.
  if [ -f "$APP/Contents/Resources/AppIcon.icns" ] && command -v SetFile >/dev/null; then
    cp "$APP/Contents/Resources/AppIcon.icns" "$MOUNT_POINT/.VolumeIcon.icns"
    SetFile -a C "$MOUNT_POINT" 2>/dev/null || echo "warning: the volume icon could not be set" >&2
  fi
else
  # No Finder, no AppleScript: a private mount point that never pollutes /Volumes.
  mkdir -p "$TMP_DIR/mnt"
  attach_image "$TMP_DIR/mnt"
  if [ ! -d "$MOUNT_POINT/Applications" ] && [ ! -L "$MOUNT_POINT/Applications" ]; then
    echo "error: the image does not contain the expected Applications link" >&2
    exit 1
  fi
fi

echo "==> Detaching"
sync
if ! hdiutil detach "$DEVICE" -quiet; then
  echo "error: the volume is busy and could not be detached. Eject it in Finder and retry." >&2
  exit 1
fi
DEVICE=""

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
