#!/bin/bash
# Regenerate the pre-compiled app icon from main.icon. Needs Xcode 26 (the Icon Composer
# "Liquid Glass" format). Run after changing main.icon, then commit RBGApp/AppIcon/.
set -euo pipefail
cd "$(dirname "$0")/.."   # repo root (mac/)
OUT="RBGApp/AppIcon"; mkdir -p "$OUT"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
xcrun actool main.icon --compile "$TMP" --app-icon main \
  --output-partial-info-plist "$TMP/partial.plist" \
  --platform macosx --minimum-deployment-target 26.0 --target-device mac \
  --output-format human-readable-text >/dev/null
cp "$TMP/Assets.car" "$OUT/Assets.car"
cp "$TMP/main.icns" "$OUT/main.icns"
echo "✓ regenerated $OUT/{Assets.car,main.icns} — commit them"
