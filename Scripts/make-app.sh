#!/bin/bash
# SPDX-FileCopyrightText: 2026 Nick Wolff <nick@wolff.tech>
# SPDX-License-Identifier: GPL-2.0-only

# Assembles "Logo Glow.app" in dist/ from the SwiftPM release build.
# Safe to run from any cwd.
#
# APP_VERSION overrides CFBundleShortVersionString.
# BUILD_NUMBER overrides CFBundleVersion.
# CODESIGN_IDENTITY selects the signing identity (default "-", ad hoc).
# A real identity, e.g. "Developer ID Application: Name (TEAMID)", also
# enables the hardened runtime and a secure timestamp, as notarization
# requires.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

APP_NAME="Logo Glow"
EXECUTABLE="LogoGlow"
ICON_NAME="LogoGlow"
ICON_SOURCE="$REPO_ROOT/Assets/$ICON_NAME.icon"
DIST_DIR="$REPO_ROOT/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
APP_VERSION="${APP_VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"

if [[ -n "$APP_VERSION" && ! "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
    echo "error: APP_VERSION must be a semantic version (received: $APP_VERSION)" >&2
    exit 1
fi
if [[ -n "$BUILD_NUMBER" && ! "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
    echo "error: BUILD_NUMBER must be a positive integer (received: $BUILD_NUMBER)" >&2
    exit 1
fi

if ! ACTOOL="$(xcrun --find actool 2>/dev/null)"; then
    echo "error: actool not found; install Xcode and select it with xcode-select" >&2
    exit 1
fi

echo "==> Building (release)"
swift build --package-path "$REPO_ROOT" -c release

# Ask SwiftPM where products landed; the layout differs between build systems.
BIN_PATH="$(swift build --package-path "$REPO_ROOT" -c release --show-bin-path)"
MAIN_BIN="$BIN_PATH/$EXECUTABLE"
if [[ ! -x "$MAIN_BIN" ]]; then
    echo "error: expected product not found: $MAIN_BIN" >&2
    exit 1
fi

echo "==> Assembling $APP_DIR"
# Fresh bundle each run; never touch anything else in dist/.
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$MAIN_BIN" "$APP_DIR/Contents/MacOS/$EXECUTABLE"
cp "$SCRIPT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$REPO_ROOT/LICENSE" "$APP_DIR/Contents/Resources/LICENSE"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

# Compile the Icon Composer document straight into the bundle: Assets.car for
# the adaptive icon and an .icns fallback. Info.plist names both "LogoGlow".
echo "==> Compiling $(basename "$ICON_SOURCE")"
"$ACTOOL" \
    --compile "$APP_DIR/Contents/Resources" \
    --output-format human-readable-text \
    --warnings \
    --errors \
    --platform macosx \
    --minimum-deployment-target 27.0 \
    --target-device mac \
    --app-icon "$ICON_NAME" \
    --output-partial-info-plist /dev/null \
    "$ICON_SOURCE" >/dev/null
for resource in Assets.car "$ICON_NAME.icns"; do
    if [[ ! -f "$APP_DIR/Contents/Resources/$resource" ]]; then
        echo "error: actool did not produce $resource" >&2
        exit 1
    fi
done

APP_PLIST="$APP_DIR/Contents/Info.plist"
if [[ -n "$APP_VERSION" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$APP_PLIST"
fi
if [[ -n "$BUILD_NUMBER" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_PLIST"
fi

if [[ "$CODESIGN_IDENTITY" == "-" ]]; then
    echo "==> Codesigning (ad hoc)"
    SIGN_FLAGS=(--timestamp=none)
else
    echo "==> Codesigning ($CODESIGN_IDENTITY)"
    SIGN_FLAGS=(--options runtime --timestamp)
fi
codesign --force --sign "$CODESIGN_IDENTITY" "${SIGN_FLAGS[@]}" "$APP_DIR"

echo "==> Done: $APP_DIR"
codesign -dv "$APP_DIR"
