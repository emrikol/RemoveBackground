#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP="RemoveBackground"
STAGE="build/$APP.app"
MACOS="$STAGE/Contents/MacOS"
RES="$STAGE/Contents/Resources"

echo "→ swift build (release; statically links onnxruntime)…"
swift build -c release
BIN=".build/release/$APP"   # SwiftPM's stable release output path

echo "→ assembling ${STAGE}…"
rm -rf "$STAGE"; mkdir -p "$MACOS" "$RES"
cp "$BIN" "$MACOS/$APP"

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
</dict></plist>
PLIST
printf 'APPL????' > "$STAGE/Contents/PkgInfo"

echo "→ ad-hoc code-signing…"
codesign --force --deep --sign - "$STAGE" 2>&1 | sed 's/^/   /' || true

# Install single canonical copy to ~/Applications (move, don't copy → no duplicate)
INSTALL="$HOME/Applications/$APP.app"
pkill -x "$APP" 2>/dev/null || true
rm -rf "$INSTALL"; mkdir -p "$HOME/Applications"
mv "$STAGE" "$INSTALL"
echo "✓ installed $INSTALL"
du -sh "$INSTALL"
