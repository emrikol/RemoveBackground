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

# App icon: compile the Icon Composer document (Liquid Glass) with actool →
# Assets.car (modern) + main.icns (legacy fallback). Skipped gracefully if absent.
ICON="../main.icon"
if [ -d "$ICON" ] && xcrun --find actool >/dev/null 2>&1; then
  echo "→ compiling app icon (main.icon → Liquid Glass + .icns fallback)…"
  xcrun actool "$ICON" --compile "$RES" --app-icon main \
    --output-partial-info-plist "build/icon-partial.plist" \
    --platform macosx --minimum-deployment-target 26.0 --target-device mac \
    --output-format human-readable-text >/dev/null 2>&1 \
    || echo "   (icon compile failed; continuing without a custom icon)"
else
  echo "→ (no ../main.icon or actool; building without a custom icon)"
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
  <key>CFBundleShortVersionString</key><string>2.0</string>
  <key>CFBundleVersion</key><string>2</string>
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
