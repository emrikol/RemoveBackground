# Releasing

Releases are automated by [`.github/workflows/release.yml`](.github/workflows/release.yml):
pushing a `vX.Y.Z` tag builds, signs (Developer ID + hardened runtime), notarizes,
packages a ZIP + DMG, signs the update + generates the Sparkle appcast, publishes a
GitHub Release, and updates the appcast on the `gh-pages` branch.

## One-time setup

1. **Add the GitHub secrets** (the workflow can't sign without them):

   ```sh
   ./scripts/setup-github-secrets.sh
   ```

   It auto-derives `KEYCHAIN_PASSWORD`, `NOTARIZATION_TEAM_ID`, and
   `SPARKLE_PRIVATE_KEY` (exported from your keychain), and prompts for
   `NOTARIZATION_APPLE_ID`, `NOTARIZATION_PASSWORD` (an app-specific password),
   `SIGNING_CERTIFICATE` (your Developer ID `.p12`, base64), and `SIGNING_PASSWORD`.
   Verify with `gh secret list -R emrikol/RemoveBackground`.

2. **Enable GitHub Pages** once the first release has created the `gh-pages` branch:
   Settings → Pages → Source: **`gh-pages`** branch. The appcast then lives at
   `https://emrikol.github.io/RemoveBackground/appcast.xml` (the `SUFeedURL` baked into
   the app).

## Cutting a release

```sh
# 1. Bump the version + write the CHANGELOG entry (## [X.Y.Z] - YYYY-MM-DD), commit.
# 2. Tag (validates the CHANGELOG) and push:
./scripts/create-release-tag.sh vX.Y.Z "Release vX.Y.Z"
git push origin vX.Y.Z
```

The tag push triggers the workflow. The version is taken from the tag and written into
`CFBundleShortVersionString` + `CFBundleVersion` (Sparkle compares `CFBundleVersion`, so
each release must increase it).

## Signing keys (reference)

- **Developer ID** identity is auto-detected from the keychain at build time (never
  hardcoded). `build_app.sh --release` signs with hardened runtime; `--notarize` also
  submits via the `notarytool` keychain profile and staples.
- **Sparkle EdDSA**: one developer key in your login Keychain; its **public** half is in
  `Info.plist` (`SUPublicEDKey`), the **private** half is exported only into the
  `SPARKLE_PRIVATE_KEY` GitHub secret — never committed.
