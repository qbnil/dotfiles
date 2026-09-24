#!/usr/bin/env bash
# final-organization.sh
# Final cleanup: move remaining items and verify

set -euo pipefail

# Move i-projects to .local/share
if [[ -d /home/kent/i-projects ]]; then
    echo "Moving i-projects to ~/.local/share..."
    mv /home/kent/i-projects/* /home/kent/.local/share/ 2>/dev/null || true
    mv /home/kent/i-projects/.* /home/kent/.local/share/ 2>/dev/null || true
    rmdir /home/kent/i-projects 2>/dev/null || true
    ln -sf /home/kent/.local/share/i-projects /home/kent/i-projects 2>/dev/null || true
    echo "✓ Moved i-projects to ~/.local/share/"
fi

# Move Desktop if it exists
if [[ -d /home/kent/Desktop ]]; then
    echo "Moving Desktop to ~/.local/share/..."
    mv /home/kent/Desktop/* /home/kent/.local/share/ 2>/dev/null || true
    mv /home/kent/Desktop/.* /home/kent/.local/share/ 2>/dev/null || true
    rmdir /home/kent/Desktop 2>/dev/null || true
    ln -sf /home/kent/.local/share/Desktop /home/kent/Desktop 2>/dev/null || true
    echo "✓ Moved Desktop to ~/.local/share/"
fi

# Clean up empty directories
echo "Cleaning empty directories..."
find /home/kent -maxdepth 1 -type d -empty 2>/dev/null | while read -r dir; do
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