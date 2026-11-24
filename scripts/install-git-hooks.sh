#!/usr/bin/env bash
#
# Installs or removes the repository Git hooks.
#
#   scripts/install-git-hooks.sh              install the pre-commit review gate
#   scripts/install-git-hooks.sh --uninstall  remove it again
#
# The hook scripts live in scripts/hooks/ and run the Gentleman Guardian Angel
# review configured by the local, untracked `.gga` file (see .gga.example).

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
REPOSITORY_ROOT="$(git rev-parse --show-toplevel)"
SOURCE_DIR="$REPOSITORY_ROOT/scripts/hooks"
HOOKS_DIR="$(git -C "$REPOSITORY_ROOT" rev-parse --git-path hooks)"

if [[ -n "$(git config --get core.hooksPath || true)" ]]; then
  echo "$SCRIPT_NAME: core.hooksPath is set; resolve it before installing repository hooks." >&2
  exit 1
fi

install_hooks() {
  mkdir -p "$HOOKS_DIR"

  for hook_source in "$SOURCE_DIR"/*; do
    [[ -f "$hook_source" ]] || continue
    local hook_name
    hook_name="$(basename "$hook_source")"
    local hook_target="$HOOKS_DIR/$hook_name"

    if [[ -f "$hook_target" && ! -L "$hook_target" ]] \
      && ! cmp --silent "$hook_source" "$hook_target"; then
      echo "$SCRIPT_NAME: refusing to overwrite the existing $hook_name hook." >&2
      echo "$SCRIPT_NAME: review and merge $hook_source manually, then rerun." >&2
      exit 1
    fi

    cp "$hook_source" "$hook_target"
    chmod +x "$hook_target"
    echo "$SCRIPT_NAME: installed $hook_name"
  done
}

uninstall_hooks() {
  for hook_source in "$SOURCE_DIR"/*; do
    [[ -f "$hook_source" ]] || continue
    local hook_name
    hook_name="$(basename "$hook_source")"
    local hook_target="$HOOKS_DIR/$hook_name"

    if [[ -f "$hook_target" ]]; then
      rm "$hook_target"
      echo "$SCRIPT_NAME: removed $hook_name"
    fi
  done
}

case "${1:-}" in
  "")
    install_hooks
    ;;
  --uninstall)
    uninstall_hooks
    ;;
  *)
    echo "usage: $SCRIPT_NAME [--uninstall]" >&2
    exit 64
    ;;
esac
