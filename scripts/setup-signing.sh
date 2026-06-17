#!/usr/bin/env bash
# One-time setup: create a stable self-signed code-signing identity so Touchy
# keeps its TCC permissions (Accessibility) across rebuilds.
#
# Why: ad-hoc signing (`codesign -s -`) gives the binary a new code identity on
# every build, and macOS ties the Accessibility grant to that identity — so each
# rebuild looks like a brand-new app and you have to re-grant. A real (even
# self-signed) certificate gives a stable Designated Requirement
# (identifier + certificate), so the grant persists.
set -euo pipefail

IDENTITY="Touchy Self-Signed"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
OPENSSL=/usr/bin/openssl   # LibreSSL: produces a .p12 the macOS keychain imports cleanly

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    echo "Signing identity '$IDENTITY' already exists — nothing to do."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cfg" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $IDENTITY
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

echo "Creating self-signed code-signing certificate…"
"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cfg" >/dev/null 2>&1
"$OPENSSL" pkcs12 -export -out "$TMP/id.p12" -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$IDENTITY" -passout pass:touchy >/dev/null 2>&1

echo "Importing into your login keychain…"
security import "$TMP/id.p12" -k "$KEYCHAIN" -P touchy -T /usr/bin/codesign >/dev/null

echo
echo "Your macOS login password is needed once so codesign can use the key without"
echo "prompting on every build."
read -r -s -p "Login password: " PW; echo
if ! security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PW" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "(Couldn't pre-authorize the key — codesign may prompt once; click 'Always Allow'.)"
fi

echo
echo "Done. Now run ./scripts/make-app.sh — it will sign with '$IDENTITY'."
echo "Grant Accessibility ONE more time for the freshly-signed app; rebuilds will keep it."
