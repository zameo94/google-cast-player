#!/usr/bin/env bash
#
# Builds a Release application from the current commit and packages it into a verified
# disk image. One command for the whole artifact: compile, package, checksum, record.
#
# It grants no privilege of its own: it runs scripts/build-release.sh and then
# scripts/make-dmg.sh, so every rule of those two stages still holds. The working tree
# must be clean, the bundle is validated and its signature verified, the image is
# verified, and existing artifacts are never replaced silently.
#
# Usage:
#   scripts/make-release.sh              build and package with the default window layout
#   scripts/make-release.sh --pretty     also arrange the window through Finder
#   scripts/make-release.sh --force      replace artifacts that already exist
#
# Output, under dist/:
#   <product>-<version>.dmg            the image to attach to a release
#   <product>-<version>.dmg.sha256     the digest, usable with `shasum -a 256 -c`
#   <product>-<version>.dmg.build.txt  commit, version and build time

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

usage() {
  sed -n '3,19p' "$0" | sed 's/^# \{0,1\}//'
}

PRETTY=0
FORCE=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --pretty) PRETTY=1 ;;
    --force) FORCE=1 ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "error: unknown option $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

# A release artifact must be traceable to a commit. A development build is still possible
# through scripts/build-release.sh ALLOW_DIRTY=1, but it is not a release.
if [ "${ALLOW_DIRTY:-0}" = "1" ]; then
  echo "error: ALLOW_DIRTY is a development build, not a release artifact." >&2
  echo "error: commit the work, or run scripts/build-release.sh directly." >&2
  exit 2
fi

OUTPUT_FILE="$(mktemp)"
cleanup() { rm -f "$OUTPUT_FILE"; }
trap cleanup EXIT

echo "==> Step 1 of 2: build"
if ! "$ROOT/scripts/build-release.sh" | tee "$OUTPUT_FILE"; then
  echo "error: the Release build failed; nothing was packaged." >&2
  exit 1
fi

APP="$(tail -1 "$OUTPUT_FILE")"
if [ ! -d "$APP" ]; then
  echo "error: the build did not report an application path; nothing was packaged." >&2
  exit 1
fi

echo
echo "==> Step 2 of 2: package"
PACKAGE_ARGS=("$APP")
if [ "$PRETTY" -eq 1 ]; then
  PACKAGE_ARGS+=(--pretty)
fi
if [ "$FORCE" -eq 1 ]; then
  PACKAGE_ARGS+=(--force)
fi
"$ROOT/scripts/make-dmg.sh" "${PACKAGE_ARGS[@]}"
