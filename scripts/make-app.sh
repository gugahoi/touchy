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

echo "[1/4] Building (${CONFIG})"
swift build -c "$CONFIG" --package-path "$ROOT" >/dev/null
BIN_PATH="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)/${BIN_NAME}"

echo "[2/4] Assembling ${APP}"
rm -rf "$APP"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "$BIN_PATH" "${APP}/Contents/MacOS/${BIN_NAME}"
cp "${ROOT}/Resources/Info.plist" "${APP}/Contents/Info.plist"

echo "[3/4] Ad-hoc codesigning"
codesign --force --deep --sign - "$APP"

echo "[4/4] Verifying signature"
codesign --verify --verbose "$APP" 2>&1 | sed 's/^/  /'

echo "Built ${APP}"
echo "Run:  open \"${APP}\"   (or move it to /Applications first)"
