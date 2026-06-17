#!/usr/bin/env bash
# Assemble Touchy.app from the SwiftPM build and ad-hoc codesign it.
#
# TCC (Accessibility / permissions) tracks an app by bundle id + code signature.
# We use a stable bundle id and a real .app bundle so the grant sticks. Ad-hoc
# signing (`-`) means a rebuild can change the binary hash and require re-granting
# Accessibility once; that's expected for personal/dev builds.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-release}"
APP="${ROOT}/Touchy.app"
BIN_NAME="Touchy"

echo "[1/5] Building (${CONFIG})"
swift build -c "$CONFIG" --package-path "$ROOT" >/dev/null
BIN_PATH="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)/${BIN_NAME}"

echo "[2/5] Assembling ${APP}"
rm -rf "$APP"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "$BIN_PATH" "${APP}/Contents/MacOS/${BIN_NAME}"
cp "${ROOT}/Resources/Info.plist" "${APP}/Contents/Info.plist"
[[ -f "${ROOT}/Resources/MenuBarIcon.png" ]] && \
    cp "${ROOT}/Resources/MenuBarIcon.png" "${APP}/Contents/Resources/MenuBarIcon.png"

echo "[3/5] Building app icon"
ICON_SRC="${ROOT}/Resources/AppIcon.png"
if [[ -f "$ICON_SRC" ]]; then
    ICONSET="$(mktemp -d)/Touchy.iconset"
    mkdir -p "$ICONSET"
    # name:px pairs for the standard macOS iconset
    for spec in \
        icon_16x16:16 icon_16x16@2x:32 \
        icon_32x32:32 icon_32x32@2x:64 \
        icon_128x128:128 icon_128x128@2x:256 \
        icon_256x256:256 icon_256x256@2x:512 \
        icon_512x512:512 icon_512x512@2x:1024 ; do
        name="${spec%:*}"; px="${spec#*:}"
        sips -z "$px" "$px" "$ICON_SRC" --out "${ICONSET}/${name}.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "${APP}/Contents/Resources/Touchy.icns"
    rm -rf "$(dirname "$ICONSET")"
else
    echo "  (no Resources/AppIcon.png — skipping icon)"
fi

echo "[4/5] Codesigning"
# Pick a STABLE signing identity so the Accessibility (TCC) grant survives
# rebuilds. Priority: explicit override -> dedicated self-signed -> any Apple
# Development cert -> ad-hoc (which loses the grant every build).
IDS="$(security find-identity -v -p codesigning 2>/dev/null || true)"
if [[ -n "${TOUCHY_SIGN_ID:-}" ]]; then
    SIGN_ID="$TOUCHY_SIGN_ID"
elif grep -q "Touchy Self-Signed" <<<"$IDS"; then
    SIGN_ID="Touchy Self-Signed"
elif grep -q "Apple Development:" <<<"$IDS"; then
    SIGN_ID="$(awk -F'"' '/Apple Development:/ {print $2; exit}' <<<"$IDS")"
else
    SIGN_ID="-"
fi

if [[ "$SIGN_ID" == "-" ]]; then
    codesign --force --deep --sign - "$APP"
    echo "  ad-hoc signed — run ./scripts/setup-signing.sh once so the grant survives rebuilds"
else
    codesign --force --deep --sign "$SIGN_ID" "$APP"
    echo "  signed with '${SIGN_ID}' (stable identity; Accessibility grant survives rebuilds)"
fi

echo "[5/5] Verifying signature"
codesign --verify --verbose "$APP" 2>&1 | sed 's/^/  /'

echo "Built ${APP}"
echo "Run:  open \"${APP}\"   (or move it to /Applications first)"
