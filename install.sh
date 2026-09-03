#!/usr/bin/env bash
# Copies the widget into the Omarchy shell's plugin directory.
#
#   ./install.sh
#
# The backend is a separate package: https://github.com/Unnunoctio/gpvpn
# This widget neither installs nor manages it; it only drives it.

set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

PLUGIN_ID="unnunoctio.globalprotect"
PLUGIN_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$PLUGIN_ID"
MIN_CLI="0.1.0"

# --plugin is still accepted out of habit: it used to tell the widget apart from
# the backend, and this repo is now only the widget.
case "${1-}" in
  "" | --plugin) ;;
  *) echo "usage: $0 [--plugin]" >&2; exit 2 ;;
esac

# Omarchy's validator rejects symlinks inside a plugin, so this copies; plugin/
# is the source of truth and the only valid direction.
mkdir -p "$PLUGIN_DIR"
rsync -a --delete plugin/ "$PLUGIN_DIR/"
omarchy plugin validate "$PLUGIN_DIR"
echo "Widget copied to $PLUGIN_DIR"
echo

if ! command -v gpvpn >/dev/null; then
  echo "Backend missing: install it from https://github.com/Unnunoctio/gpvpn"
elif ! version="$(gpvpn --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')" || [[ -z $version ]]; then
  # gpvpn --version exists from 0.1.0 on: if it prints no version, it is older.
  echo "Backend is older than $MIN_CLI; update it or parts of the panel will misbehave"
else
  echo "Backend: gpvpn $version (needs >= $MIN_CLI)"
fi
echo "Add the widget with: omarchy plugin enable $PLUGIN_ID right"
