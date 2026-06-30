#!/bin/bash
# One-time: set the GitHub Actions secrets the release workflow needs.
# Auto-derives what it can (Team ID, a random keychain password, the exported Sparkle
# private key) and prompts for the rest. Nothing is written to the repo.
#
# Requires: gh (authenticated), your Developer ID cert + Sparkle key in the keychain.
set -euo pipefail
REPO="emrikol/RemoveBackground"
cd "$(git rev-parse --show-toplevel)"
echo "Setting GitHub secrets for $REPO …"
echo

# 1. KEYCHAIN_PASSWORD — random; only unlocks the throwaway CI keychain.
gh secret set KEYCHAIN_PASSWORD -R "$REPO" -b "$(openssl rand -base64 32)"
echo "✓ KEYCHAIN_PASSWORD (random)"

# 2. NOTARIZATION_TEAM_ID — read from the Developer ID identity.
TEAM=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 \
  | sed -E 's/.*\(([A-Z0-9]+)\)".*/\1/')
if [ -n "$TEAM" ]; then gh secret set NOTARIZATION_TEAM_ID -R "$REPO" -b "$TEAM"; echo "✓ NOTARIZATION_TEAM_ID ($TEAM)"; fi

# 3. SPARKLE_PRIVATE_KEY — exported from the keychain (same key whose public half is in Info.plist).
GK=$(find . /tmp /private/tmp -name generate_keys 2>/dev/null | head -1)
if [ -n "${GK:-}" ]; then
  TMPK=$(mktemp); "$GK" -x "$TMPK" >/dev/null 2>&1 || true
  if [ -s "$TMPK" ]; then gh secret set SPARKLE_PRIVATE_KEY -R "$REPO" < "$TMPK"; echo "✓ SPARKLE_PRIVATE_KEY"; fi
  rm -f "$TMPK"
else
  echo "⚠ generate_keys not found — run 'swift build' in RBGApp first, then re-run for SPARKLE_PRIVATE_KEY"
fi

# 4–7. Credentials only you have.
echo
read -r -p "Apple ID email (developer account): " APPLE_ID
[ -n "$APPLE_ID" ] && gh secret set NOTARIZATION_APPLE_ID -R "$REPO" -b "$APPLE_ID" && echo "✓ NOTARIZATION_APPLE_ID"
read -r -s -p "App-specific password (appleid.apple.com → App-Specific Passwords): " ASP; echo
[ -n "$ASP" ] && gh secret set NOTARIZATION_PASSWORD -R "$REPO" -b "$ASP" && echo "✓ NOTARIZATION_PASSWORD"
echo
echo "Developer ID certificate: in Keychain Access, export the 'Developer ID Application: …'"
echo "identity as a .p12 (set a password), then:"
read -r -p "  Path to the .p12: " P12
read -r -s -p "  .p12 password: " P12PW; echo
if [ -f "${P12/#\~/$HOME}" ]; then
  base64 -i "${P12/#\~/$HOME}" | tr -d '\n' | gh secret set SIGNING_CERTIFICATE -R "$REPO"; echo "✓ SIGNING_CERTIFICATE"
  gh secret set SIGNING_PASSWORD -R "$REPO" -b "$P12PW"; echo "✓ SIGNING_PASSWORD"
else
  echo "⚠ .p12 not found — skipped SIGNING_CERTIFICATE / SIGNING_PASSWORD"
fi

echo
echo "Done. Verify: gh secret list -R $REPO"
echo "Then enable Pages once: Settings → Pages → Source: 'gh-pages' branch (created on first release)."
