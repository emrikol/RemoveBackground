#!/bin/bash
# Pre-release audit for Remove Background — format/lint, release build, and bundle checks.
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
APP="$HOME/Applications/RemoveBackground.app"
ok=0; warn=0; fail=0
section(){ echo; echo "▶ $1"; echo "────────────────────────────────────────"; }
pass(){ echo "  ✓ $1"; ok=$((ok + 1)); }
warning(){ echo "  ⚠ $1"; warn=$((warn + 1)); }
bad(){ echo "  ✗ $1"; fail=$((fail + 1)); }

echo "Remove Background — audit ($(sw_vers -productVersion), $(uname -m))"

section "1. Format & lint"
if command -v swiftformat >/dev/null 2>&1; then
    swiftformat --lint RBGApp/Sources tools >/dev/null 2>&1 && pass "SwiftFormat clean" || bad "SwiftFormat: needs formatting"
else warning "swiftformat not installed"; fi
if command -v swiftlint >/dev/null 2>&1; then
    swiftlint lint --quiet 2>/dev/null | grep -q ' error:' && bad "SwiftLint errors" || pass "SwiftLint: no errors"
else warning "swiftlint not installed"; fi

section "2. Release build"
( cd RBGApp && swift build -c release ) >/dev/null 2>&1 && pass "release build succeeds" || bad "release build FAILED"

section "3. App bundle"
if [ -d "$APP" ]; then
    pass "installed at $APP"
    if codesign -dv "$APP" 2>&1 | grep -q "adhoc"; then
        warning "ad-hoc signed — notarize with a Developer ID for public release"
    else
        pass "code-signed (not ad-hoc)"
    fi
    if find "$APP/Contents/Resources" \( -name '*.mlmodelc' -o -name '*.onnx' -o -name '*.mlpackage' \) 2>/dev/null | grep -q .; then
        bad "models are bundled — they must stay runtime-downloaded"
    else
        pass "no models bundled (runtime-downloaded)"
    fi
    plutil -p "$APP/Contents/Info.plist" 2>/dev/null | grep -q CFBundleIconName && pass "app icon wired" || warning "no CFBundleIconName"
    echo "    bundle size: $(du -sh "$APP" | cut -f1)"
else
    warning "not installed — run ./RBGApp/build_app.sh"
fi

echo
echo "═══ $ok passed · $warn warnings · $fail failures ═══"
[ "$fail" -gt 0 ] && exit 1
exit 0
