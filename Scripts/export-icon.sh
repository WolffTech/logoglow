#!/bin/bash
# SPDX-FileCopyrightText: 2026 Nick Wolff <nick@wolff.tech>
# SPDX-License-Identifier: GPL-2.0-only

# Renders the editable Icon Composer document using the selected Xcode.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
DEVELOPER_DIR_PATH="$(xcode-select -p)"
ICTOOL="$DEVELOPER_DIR_PATH/../Applications/Icon Composer.app/Contents/Executables/ictool"

if [[ ! -x "$ICTOOL" ]]; then
    echo "error: Icon Composer's ictool was not found in the selected Xcode." >&2
    exit 1
fi

"$ICTOOL" "$REPO_ROOT/Assets/LogoGlow.icon" \
    --export-image \
    --output-file "$REPO_ROOT/Assets/LogoGlow.png" \
    --platform macOS \
    --rendition Default \
    --width 1024 --height 1024 --scale 1 \
    --design-generation 27

echo "Exported $REPO_ROOT/Assets/LogoGlow.png"
