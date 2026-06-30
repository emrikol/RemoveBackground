#!/bin/bash
# Install the project git hooks into .git/hooks.
set -e
ROOT="$(git rev-parse --show-toplevel)"
for h in pre-commit pre-push; do
    cp "$ROOT/hooks/$h" "$ROOT/.git/hooks/$h"
    chmod +x "$ROOT/.git/hooks/$h"
    echo "installed $h"
done
echo "✓ git hooks installed"
