#!/bin/bash
# Validate the CHANGELOG and a clean tree, then create an annotated release tag.
# Usage: ./scripts/create-release-tag.sh vX.Y.Z ["Release message"]
set -e
TAG="$1"
MSG="${2:-Release $1}"

[ -z "$TAG" ] && { echo "usage: $0 vX.Y.Z [message]"; exit 1; }
[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-.*)?$ ]] || { echo "❌ tag must look like vX.Y.Z"; exit 1; }
VER="${TAG#v}"

grep -q "## \[$VER\]" CHANGELOG.md || { echo "❌ no CHANGELOG entry for $VER"; exit 1; }
grep -qE "## \[$VER\] - [0-9]{4}-[0-9]{2}-[0-9]{2}" CHANGELOG.md \
    || { echo "❌ CHANGELOG entry for $VER needs a real date (YYYY-MM-DD)"; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "❌ working tree is not clean — commit first"; exit 1; }

git tag -a "$TAG" -m "$MSG"
echo "✓ created tag $TAG"
echo "  push it with: git push origin $TAG"
