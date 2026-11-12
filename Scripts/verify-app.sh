#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
APP_DIR="$REPO_ROOT/dist/Logo Glow.app"
INFO_PLIST="$APP_DIR/Contents/Info.plist"
EXECUTABLE="$APP_DIR/Contents/MacOS/LogoGlow"

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
for resource in Assets.car LogoGlow.icns LICENSE; do
    if [[ ! -s "$APP_DIR/Contents/Resources/$resource" ]]; then
        fail "missing or empty resource: $resource"
    fi
done

echo "==> Checking Info.plist"
plutil -lint "$INFO_PLIST"
expect_plist_value CFBundleIdentifier tech.wolff.LogoGlow
expect_plist_value CFBundleExecutable LogoGlow
expect_plist_value LSMinimumSystemVersion 27.0
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
codesign --verify --strict --verbose=2 "$APP_DIR"
if [[ -n "${EXPECTED_TEAM_ID:-}" ]]; then
    SIGNATURE="$(codesign --display --verbose=4 "$APP_DIR" 2>&1)"
    expect_in_signature "^TeamIdentifier=$EXPECTED_TEAM_ID\$" "not signed by team $EXPECTED_TEAM_ID"
    expect_in_signature '^CodeDirectory .*flags=.*\(runtime\)' "hardened runtime is not enabled"
    expect_in_signature '^Timestamp=' "no secure timestamp"
fi

echo "==> Verified: $APP_DIR"
