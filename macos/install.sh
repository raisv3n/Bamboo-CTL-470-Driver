#!/bin/zsh
# Installs BambooDriver.app into /Applications and starts it (it then registers itself to open at login).
# Works from the release zip (app next to this script) or the repo (macos/build/).
set -euo pipefail
cd "${0:A:h}"

SRC=BambooDriver.app
[[ -d $SRC ]] || SRC=build/BambooDriver.app
[[ -d $SRC ]] || { echo "BambooDriver.app not found; run ./build.sh first" >&2; exit 1; }

osascript -e 'tell application id "dev.local.BambooDriver" to quit' 2>/dev/null || true
pkill -x BambooDriver 2>/dev/null || true
sleep 1

DEST=/Applications/BambooDriver.app
if [[ -w /Applications ]]; then
    rm -rf "$DEST" && cp -R "$SRC" "$DEST"
else
    sudo rm -rf "$DEST" && sudo cp -R "$SRC" "$DEST"
fi
xattr -cr "$DEST"   # clear the download quarantine flag (app is not notarized)
open "$DEST"
echo "Installed $DEST"
echo "If the pen doesn't move the cursor: System Settings > Privacy & Security > Accessibility > enable BambooDriver."
