#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
APP_DIR="$REPO_ROOT/dist/Logo Glow.app"
DEFAULT_NOTARY_PROFILE=logoglow

fail() {
    echo "error: $*" >&2
    exit 1
}

require_developer_id_identity() {
    if [[ -z "${CODESIGN_IDENTITY:-}" || "$CODESIGN_IDENTITY" == "-" ]]; then
        fail "set CODESIGN_IDENTITY to a Developer ID Application signing identity"
    fi
}

choose_notary_credentials() {
    local api_key_variables=(NOTARY_KEY_FILE NOTARY_KEY_ID NOTARY_ISSUER_ID)
    local any_api_key_variable_set=false
    local name

    for name in "${api_key_variables[@]}"; do
        if [[ -n "${!name:-}" ]]; then
            any_api_key_variable_set=true
        fi
    done

    if [[ "$any_api_key_variable_set" == false ]]; then
        NOTARY_AUTH=(--keychain-profile "${NOTARY_PROFILE:-$DEFAULT_NOTARY_PROFILE}")
        return
    fi

    for name in "${api_key_variables[@]}"; do
        if [[ -z "${!name:-}" ]]; then
            fail "API key notarization needs ${api_key_variables[*]}; $name is not set"
        fi
    done
    NOTARY_AUTH=(--key "$NOTARY_KEY_FILE" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
}

json_field() {
    local file="$1"
    local field="$2"
    plutil -extract "$field" raw -o - "$file" 2>/dev/null || true
}

notarize() {
    local file="$1"
    local response="$WORK_DIR/notary-response.json"
    local status
    local submission_id

    echo "==> Notarizing $(basename "$file")"
    xcrun notarytool submit "$file" "${NOTARY_AUTH[@]}" --wait --output-format json > "$response" || true

    status="$(json_field "$response" status)"
    if [[ "$status" == Accepted ]]; then
        return
    fi

    if [[ -s "$response" ]]; then
        cat "$response" >&2
    fi
    submission_id="$(json_field "$response" id)"
    if [[ -n "$submission_id" ]]; then
        xcrun notarytool log "$submission_id" "${NOTARY_AUTH[@]}" >&2 || true
    fi
    fail "Apple did not accept $(basename "$file") for notarization (status: ${status:-none})"
}

staple() {
    local file="$1"
    echo "==> Stapling $(basename "$file")"
    xcrun stapler staple "$file"
    xcrun stapler validate "$file"
}

require_developer_id_identity
choose_notary_credentials

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/logoglow-notary.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

"$SCRIPT_DIR/make-app.sh"
"$SCRIPT_DIR/verify-app.sh"

APP_ZIP="$WORK_DIR/Logo-Glow.zip"
ditto -c -k --keepParent "$APP_DIR" "$APP_ZIP"
notarize "$APP_ZIP"
staple "$APP_DIR"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist")"
DMG="$REPO_ROOT/dist/Logo-Glow-$VERSION.dmg"
"$SCRIPT_DIR/make-dmg.sh" "$DMG"

echo "==> Signing $(basename "$DMG")"
codesign --force --sign "$CODESIGN_IDENTITY" --timestamp "$DMG"
codesign --verify --strict --verbose=2 "$DMG"
notarize "$DMG"
staple "$DMG"

echo "==> Checking Gatekeeper"
spctl --assess --type execute --verbose=2 "$APP_DIR"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"

echo "==> Done: $DMG"
