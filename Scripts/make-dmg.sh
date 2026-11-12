#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
APP_NAME="Logo Glow"
APP_DIR="$REPO_ROOT/dist/$APP_NAME.app"

fail() {
    echo "error: $*" >&2
    exit 1
}

if (( $# > 1 )); then
    echo "usage: $0 [output.dmg]" >&2
    exit 2
fi
if [[ ! -d "$APP_DIR" ]]; then
    fail "$APP_DIR not found; run Scripts/make-app.sh first"
fi

if (( $# == 1 )); then
    DMG="$1"
else
    VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist")"
    DMG="$REPO_ROOT/dist/Logo-Glow-$VERSION.dmg"
fi
if [[ "$DMG" != *.dmg ]]; then
    fail "output path must end in .dmg (received: $DMG)"
fi

echo "==> Staging $APP_NAME.app with an Applications shortcut"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/logoglow-dmg.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
ditto "$APP_DIR" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

echo "==> Creating $DMG"
mkdir -p "$(dirname "$DMG")"
hdiutil create "$DMG" \
    -ov \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -fs HFS+ \
    -format UDZO

echo "==> Verifying $DMG"
hdiutil verify "$DMG"
