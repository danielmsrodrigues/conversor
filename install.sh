#!/bin/bash
# Conversor installer.
#   Install:   curl -fsSL https://raw.githubusercontent.com/danielmsrodrigues/conversor/main/install.sh | bash
#   Uninstall: curl -fsSL https://raw.githubusercontent.com/danielmsrodrigues/conversor/main/install.sh | bash -s -- --uninstall
#
# Files downloaded with curl don't get macOS's quarantine flag, so Gatekeeper
# doesn't block the app. We still clear the flag in case it is there.
set -euo pipefail

REPO="danielmsrodrigues/conversor"
ZIP_URL="https://github.com/$REPO/releases/latest/download/Conversor.zip"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

find_app() {
    for dir in /Applications "$HOME/Applications"; do
        [ -d "$dir/Conversor.app" ] && { echo "$dir/Conversor.app"; return; }
    done
}

if [ "${1:-}" = "--uninstall" ]; then
    APP="$(find_app)"
    if [ -z "$APP" ]; then echo "Conversor is not installed."; exit 0; fi
    pkill -x Conversor 2>/dev/null || true
    "$APP/Contents/MacOS/Conversor" --unregister 2>/dev/null || true
    "$LSREGISTER" -u "$APP" 2>/dev/null || true
    rm -rf "$APP"
    defaults delete pt.danielrodrigues.conversor 2>/dev/null || true
    /System/Library/CoreServices/pbs -update 2>/dev/null || true
    echo "✓ Conversor removed."
    exit 0
fi

MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
if [ "$MAJOR" -lt 26 ]; then
    echo "Conversor needs macOS 26 (Tahoe) or newer. This Mac has $(sw_vers -productVersion)." >&2
    exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading Conversor…"
curl -fsSL "$ZIP_URL" -o "$TMP/Conversor.zip"
ditto -x -k "$TMP/Conversor.zip" "$TMP"

DEST=/Applications
[ -w "$DEST" ] || DEST="$HOME/Applications"
mkdir -p "$DEST"

pkill -x Conversor 2>/dev/null || true
rm -rf "$DEST/Conversor.app"
ditto "$TMP/Conversor.app" "$DEST/Conversor.app"
xattr -dr com.apple.quarantine "$DEST/Conversor.app" 2>/dev/null || true

# Register the app and its right-click option, then start it quietly.
"$LSREGISTER" -f "$DEST/Conversor.app"
/System/Library/CoreServices/pbs -update
open -g "$DEST/Conversor.app" --args --background

echo "✓ Conversor installed in $DEST."
echo "  In Finder, right-click a file → Convert to…"
echo "  (If you don't see it yet, restart Finder: Option + right-click the Finder icon in the Dock → Relaunch.)"
