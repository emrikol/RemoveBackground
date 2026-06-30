#!/bin/bash
# One command to set ALL GitHub Actions release secrets — no copy-paste.
# It exports your keys itself (macOS will ask you to "Allow" a couple of times) and
# pushes everything straight to GitHub. Nothing is written to the repo; temp files are
# created in a private dir and deleted on exit.
#
# Requires: gh (authenticated); your Developer ID cert + Sparkle key in the login keychain.
set -uo pipefail
REPO="emrikol/RemoveBackground"
cd "$(git rev-parse --show-toplevel)" 2>/dev/null || true
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
ok(){ echo "  ✓ $1"; }
warn(){ echo "  ⚠ $1"; }

echo "Setting all release secrets for $REPO"
echo "(If macOS pops up 'security/codesign wants to use a key', click Allow.)"
echo

# 1. KEYCHAIN_PASSWORD — random; only unlocks the throwaway CI keychain.
gh secret set KEYCHAIN_PASSWORD -R "$REPO" -b "$(openssl rand -base64 32)" >/dev/null && ok "KEYCHAIN_PASSWORD"

# 2. NOTARIZATION_TEAM_ID — read from the Developer ID identity.
TEAM=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 \
  | sed -E 's/.*\(([A-Z0-9]+)\)".*/\1/')
[ -n "$TEAM" ] && gh secret set NOTARIZATION_TEAM_ID -R "$REPO" -b "$TEAM" >/dev/null && ok "NOTARIZATION_TEAM_ID ($TEAM)"

# 3. SPARKLE_PRIVATE_KEY — exported from the keychain.
GK=$(find . /tmp /private/tmp -name generate_keys 2>/dev/null | head -1)
if [ -n "${GK:-}" ] && "$GK" -x "$TMP/sparkle.key" >/dev/null 2>&1 && [ -s "$TMP/sparkle.key" ]; then
  gh secret set SPARKLE_PRIVATE_KEY -R "$REPO" < "$TMP/sparkle.key" >/dev/null && ok "SPARKLE_PRIVATE_KEY"
else
  warn "Sparkle key export failed — run 'swift build' in RBGApp, then re-run (and click Allow)."
fi

# 4. SIGNING_CERTIFICATE + SIGNING_PASSWORD — export Developer ID identity to a .p12.
P12PW=$(openssl rand -base64 16)
if security export -t identities -f pkcs12 -P "$P12PW" -o "$TMP/devid.p12" >/dev/null 2>&1 && [ -s "$TMP/devid.p12" ]; then
  base64 -i "$TMP/devid.p12" | tr -d '\n' | gh secret set SIGNING_CERTIFICATE -R "$REPO" >/dev/null && ok "SIGNING_CERTIFICATE"
  gh secret set SIGNING_PASSWORD -R "$REPO" -b "$P12PW" >/dev/null && ok "SIGNING_PASSWORD"
else
  warn "Developer ID .p12 export failed — click Allow when prompted, or export via Keychain Access."
fi

# 5. Apple ID + app-specific password — typed once (not stored locally in cleartext).
echo
read -r -p "Apple ID email (developer account): " APPLE_ID
[ -n "${APPLE_ID:-}" ] && gh secret set NOTARIZATION_APPLE_ID -R "$REPO" -b "$APPLE_ID" >/dev/null && ok "NOTARIZATION_APPLE_ID"
read -r -s -p "App-specific password (appleid.apple.com → App-Specific Passwords): " ASP; echo
[ -n "${ASP:-}" ] && gh secret set NOTARIZATION_PASSWORD -R "$REPO" -b "$ASP" >/dev/null && ok "NOTARIZATION_PASSWORD"

echo
echo "Done. Verify (expect 7): gh secret list -R $REPO"
