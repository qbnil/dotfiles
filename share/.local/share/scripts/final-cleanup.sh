#!/usr/bin/env bash
# final-organization.sh
# Final cleanup: move remaining items and verify

set -euo pipefail

# Move i-projects to .local/share
if [[ -d $HOME/i-projects ]]; then
    echo "Moving i-projects to ~/.local/share..."
    mv $HOME/i-projects/* $HOME/.local/share/ 2>/dev/null || true
    mv $HOME/i-projects/.* $HOME/.local/share/ 2>/dev/null || true
    rmdir $HOME/i-projects 2>/dev/null || true
    ln -sf $HOME/.local/share/i-projects $HOME/i-projects 2>/dev/null || true
    echo "✓ Moved i-projects to ~/.local/share/"
fi

# Move Desktop if it exists
if [[ -d $HOME/Desktop ]]; then
    echo "Moving Desktop to ~/.local/share/..."
    mv $HOME/Desktop/* $HOME/.local/share/ 2>/dev/null || true
    mv $HOME/Desktop/.* $HOME/.local/share/ 2>/dev/null || true
    rmdir $HOME/Desktop 2>/dev/null || true
    ln -sf $HOME/.local/share/Desktop $HOME/Desktop 2>/dev/null || true
    echo "✓ Moved Desktop to ~/.local/share/"
fi

# Clean up empty directories
echo "Cleaning empty directories..."
find $HOME -maxdepth 1 -type d -empty 2>/dev/null | while read -r dir; do
    local dirname=$(basename "$dir")
    case "$dirname" in
        Documents|Downloads|Pictures|Videos|Music|Templates|Public|Desktop|i-projects) continue ;;
        *)
            if [[ ! -L "$dir" ]]; then
                rmdir "$dir" 2>/dev/null && echo "✓ Removed empty directory: $dirname"
            fi
        ;;
    esac
done