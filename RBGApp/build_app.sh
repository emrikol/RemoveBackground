#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# Build modes:
#   (no flags)  ad-hoc sign — for local development
#   --release   sign with a Developer ID + hardened runtime (notarization-ready)
#   --notarize  also submit to Apple's notary service + staple (implies --release)
MODE="adhoc"
NOTARIZE=0
for arg in "$@"; do
  case "$arg" in
    --release) MODE="release" ;;
    --notarize) MODE="release"; NOTARIZE=1 ;;
    -h|--help)
      echo "usage: $0 [--release] [--notarize]"
      echo "  (no flags)  ad-hoc sign (local dev)"
      echo "  --release   Developer ID + hardened runtime"
      echo "  --notarize  submit to Apple notary + staple (implies --release)"
      exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 1 ;;
  esac
done

# Developer ID identity is auto-detected from the keychain so this (anonymized) repo
# never hardcodes a real name. Override explicitly with: SIGN_IDENTITY="…" ./build_app.sh
SIGN_IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
  | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)".*/\1/')}"

# Version for both Info.plist keys. CI passes the release tag (e.g. VERSION=0.1.1).
# Sparkle compares CFBundleVersion, so it must increase every release.
VERSION="${VERSION:-0.1.0}"

APP="RemoveBackground"
STAGE="build/$APP.app"
MACOS="$STAGE/Contents/MacOS"
RES="$STAGE/Contents/Resources"

echo "→ swift build (release; statically links onnxruntime)…"
swift build -c release
BIN=".build/release/$APP"   # SwiftPM's stable release output path

echo "→ assembling ${STAGE}…"
rm -rf "$STAGE"; mkdir -p "$MACOS" "$RES" "$STAGE/Contents/Frameworks"
cp "$BIN" "$MACOS/$APP"

# Embed Sparkle.framework (built by SwiftPM) so the app can auto-update.
if [ -d ".build/release/Sparkle.framework" ]; then
  echo "→ embedding Sparkle.framework…"
  cp -R ".build/release/Sparkle.framework" "$STAGE/Contents/Frameworks/"
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS/$APP" 2>/dev/null || true
else
  echo "   ⚠ .build/release/Sparkle.framework not found — auto-update unavailable"
fi

# App icon: the modern Liquid Glass (macOS 26) icon, pre-compiled from main.icon with
# Xcode 26's actool and committed under AppIcon/. CI runners ship an older actool that
# can't compile the Icon Composer format, so we ship the prebuilt asset catalog directly.
# Regenerate after changing main.icon with: tools/compile-icon.sh
if [ -f AppIcon/Assets.car ]; then
  echo "→ app icon (Liquid Glass, prebuilt)…"
  cp AppIcon/Assets.car "$RES/Assets.car"
  [ -f AppIcon/main.icns ] && cp AppIcon/main.icns "$RES/main.icns"
else
  echo "→ ⚠ AppIcon/Assets.car missing — run tools/compile-icon.sh (needs Xcode 26), then commit"
fi

# No models are bundled. Every model — including the default RMBG-2.0 — is downloaded
# on demand at runtime and cached under ~/Library/Application Support/RemoveBackground/.
# So this build needs no model files; a fresh clone builds in one command.

cat > "$STAGE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Remove Background</string>
  <key>CFBundleDisplayName</key><string>Remove Background</string>
  <key>CFBundleIdentifier</key><string>com.emrikol.removebackground</string>
  <key>CFBundleExecutable</key><string>$APP</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.photography</string>
  <key>CFBundleIconName</key><string>main</string>
  <key>CFBundleIconFile</key><string>main</string>
  <key>SUFeedURL</key><string>https://emrikol.github.io/RemoveBackground/appcast.xml</string>
  <key>SUPublicEDKey</key><string>RrIa9Qh/+LN89ANE5QLzxKzya+RW9RQDTkKbS0wRWkI=</string>
  <key>SUEnableAutomaticChecks</key><false/>
</dict></plist>
PLIST
printf 'APPL????' > "$STAGE/Contents/PkgInfo"

if [ "$MODE" = "release" ]; then
  [ -n "$SIGN_IDENTITY" ] || { echo "✗ no 'Developer ID Application' identity found in keychain" >&2; exit 1; }
  echo "→ signing with Developer ID (hardened runtime)…"
  # --deep signs the embedded Sparkle.framework + its nested XPC services too. Never add
  # --identifier with --deep: it would overwrite the XPC bundle identifiers and break
  # auto-updates (Sparkle's Installer XPC needs its own identifier).
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$STAGE" 2>&1 | sed 's/^/   /'
else
  echo "→ ad-hoc code-signing (dev)…"
  codesign --force --deep --sign - "$STAGE" 2>&1 | sed 's/^/   /' || true
fi

if [ "$NOTARIZE" = "1" ]; then
  echo "→ notarizing (xcrun notarytool, keychain profile 'notarytool')…"
  ZIP="build/$APP-notarize.zip"
  rm -f "$ZIP"
  /usr/bin/ditto -c -k --keepParent "$STAGE" "$ZIP"
  xcrun notarytool submit "$ZIP" --keychain-profile "notarytool" --wait 2>&1 | tee build/notarize.log | sed 's/^/   /'
  if grep -q "status: Accepted" build/notarize.log; then
    echo "→ stapling + verifying…"
    xcrun stapler staple "$STAGE"
    spctl -a -vv "$STAGE" 2>&1 | sed 's/^/   /' || true
  else
    echo "   ⚠ notarization not Accepted — see build/notarize.log (not stapling)"
  fi
  rm -f "$ZIP"
fi

# Install single canonical copy to ~/Applications (move, don't copy → no duplicate)
INSTALL="$HOME/Applications/$APP.app"
pkill -x "$APP" 2>/dev/null || true
rm -rf "$INSTALL"; mkdir -p "$HOME/Applications"
mv "$STAGE" "$INSTALL"
echo "✓ installed $INSTALL  (mode: $MODE$([ "$NOTARIZE" = 1 ] && echo ", notarized"))"
du -sh "$INSTALL"
