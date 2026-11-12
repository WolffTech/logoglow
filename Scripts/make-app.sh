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
cp -R "$REPO_ROOT/ThirdPartyLicenses" "$APP_DIR/Contents/Resources/ThirdPartyLicenses"
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

echo "==> Embedding Sparkle.framework"
ARTIFACTS_DIR="$REPO_ROOT/.build/artifacts"
SPARKLE_SOURCE="$(find "$ARTIFACTS_DIR" -type d -name Sparkle.framework -path "*macos*" -print -quit)"
if [[ -z "$SPARKLE_SOURCE" ]]; then
    echo "error: Sparkle.framework not found under $ARTIFACTS_DIR" >&2
    exit 1
fi
FRAMEWORKS_DIR="$APP_DIR/Contents/Frameworks"
SPARKLE_FRAMEWORK="$FRAMEWORKS_DIR/Sparkle.framework"
mkdir -p "$FRAMEWORKS_DIR"
cp -R "$SPARKLE_SOURCE" "$SPARKLE_FRAMEWORK"

MAIN_EXECUTABLE="$APP_DIR/Contents/MacOS/$EXECUTABLE"
while read -r rpath; do
    if [[ "$rpath" == *.build* || "$rpath" == *artifacts* ]]; then
        install_name_tool -delete_rpath "$rpath" "$MAIN_EXECUTABLE"
    fi
done < <(otool -l "$MAIN_EXECUTABLE" | awk '/LC_RPATH/ { getline; getline; print $2 }')
install_name_tool -add_rpath "@executable_path/../Frameworks" "$MAIN_EXECUTABLE"

if [[ "$CODESIGN_IDENTITY" == "-" ]]; then
    echo "==> Codesigning (ad hoc)"
    SIGN_FLAGS=(--timestamp=none)
else
    echo "==> Codesigning ($CODESIGN_IDENTITY)"
    SIGN_FLAGS=(--options runtime --timestamp)
fi
for xpc in "$SPARKLE_FRAMEWORK/Versions/B/XPCServices/"*.xpc; do
    codesign --force --sign "$CODESIGN_IDENTITY" "${SIGN_FLAGS[@]}" \
        --preserve-metadata=entitlements "$xpc"
done
codesign --force --sign "$CODESIGN_IDENTITY" "${SIGN_FLAGS[@]}" "$SPARKLE_FRAMEWORK/Versions/B/Autoupdate"
codesign --force --sign "$CODESIGN_IDENTITY" "${SIGN_FLAGS[@]}" "$SPARKLE_FRAMEWORK/Versions/B/Updater.app"
codesign --force --sign "$CODESIGN_IDENTITY" "${SIGN_FLAGS[@]}" "$SPARKLE_FRAMEWORK"
codesign --force --sign "$CODESIGN_IDENTITY" "${SIGN_FLAGS[@]}" "$APP_DIR"

echo "==> Done: $APP_DIR"
codesign -dv "$APP_DIR"
