#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
APP_DIR="$REPO_ROOT/dist/Logo Glow.app"
INFO_PLIST="$APP_DIR/Contents/Info.plist"
EXECUTABLE="$APP_DIR/Contents/MacOS/LogoGlow"
SPARKLE_FRAMEWORK="$APP_DIR/Contents/Frameworks/Sparkle.framework"

fail() {
    echo "error: $*" >&2
    exit 1
}

expect_plist_value() {
    local key="$1"
    local expected="$2"
    local actual
    actual="$(/usr/libexec/PlistBuddy -c "Print :$key" "$INFO_PLIST")"
    if [[ "$actual" != "$expected" ]]; then
        fail "Info.plist $key is '$actual', expected '$expected'"
    fi
}

expect_in_signature() {
    local pattern="$1"
    local description="$2"
    if ! grep -qE "$pattern" <<< "$SIGNATURE"; then
        fail "signature check failed: $description"
    fi
}

echo "==> Checking bundle contents"
if [[ ! -x "$EXECUTABLE" ]]; then
    fail "missing executable: $EXECUTABLE"
fi
for resource in Assets.car LogoGlow.icns LICENSE ThirdPartyLicenses/Sparkle.txt; do
    if [[ ! -s "$APP_DIR/Contents/Resources/$resource" ]]; then
        fail "missing or empty resource: $resource"
    fi
done
if [[ ! -x "$SPARKLE_FRAMEWORK/Versions/B/Sparkle" ]]; then
    fail "missing Sparkle.framework binary"
fi
if [[ ! -L "$SPARKLE_FRAMEWORK/Sparkle" ]]; then
    fail "Sparkle.framework lost its versioned symlink layout"
fi

echo "==> Checking Sparkle linkage"
RPATHS="$(otool -l "$EXECUTABLE" | awk '/LC_RPATH/ { getline; getline; print $2 }')"
if ! grep -qx '@executable_path/../Frameworks' <<< "$RPATHS"; then
    fail "executable is missing the bundle-relative Frameworks rpath"
fi
if grep -qE '\.build|artifacts' <<< "$RPATHS"; then
    fail "build-machine rpath leaked into the executable: $RPATHS"
fi

echo "==> Checking Info.plist"
plutil -lint "$INFO_PLIST"
expect_plist_value CFBundleIdentifier tech.wolff.LogoGlow
expect_plist_value CFBundleExecutable LogoGlow
expect_plist_value LSMinimumSystemVersion 27.0
expect_plist_value SUFeedURL https://github.com/WolffTech/logoglow/releases/latest/download/appcast.xml
SPARKLE_PUBLIC_KEY="$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$INFO_PLIST")"
if [[ ! "$SPARKLE_PUBLIC_KEY" =~ ^[A-Za-z0-9+/]{43}=$ ]]; then
    fail "SUPublicEDKey is not an Ed25519 public key: $SPARKLE_PUBLIC_KEY"
fi
if [[ -n "${APP_VERSION:-}" ]]; then
    expect_plist_value CFBundleShortVersionString "$APP_VERSION"
fi
if [[ -n "${BUILD_NUMBER:-}" ]]; then
    expect_plist_value CFBundleVersion "$BUILD_NUMBER"
fi

echo "==> Checking architecture"
ARCHITECTURES="$(lipo -archs "$EXECUTABLE")"
if [[ "$ARCHITECTURES" != arm64 ]]; then
    fail "executable is built for '$ARCHITECTURES', expected 'arm64'"
fi

echo "==> Checking code signature"
codesign --verify --strict --verbose=2 "$SPARKLE_FRAMEWORK"
codesign --verify --strict --deep --verbose=2 "$APP_DIR"
if [[ -n "${EXPECTED_TEAM_ID:-}" ]]; then
    SIGNATURE="$(codesign --display --verbose=4 "$APP_DIR" 2>&1)"
    expect_in_signature "^TeamIdentifier=$EXPECTED_TEAM_ID\$" "not signed by team $EXPECTED_TEAM_ID"
    expect_in_signature '^CodeDirectory .*flags=.*\(runtime\)' "hardened runtime is not enabled"
    expect_in_signature '^Timestamp=' "no secure timestamp"
fi

echo "==> Verified: $APP_DIR"
