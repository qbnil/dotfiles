#!/usr/bin/env bash
# Dry-run GNU Stow against $HOME — shows what would be linked without changing anything.
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; NC='\033[0m'
print_status()  { echo -e "${BLUE}==>${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_error()   { echo -e "${RED}✗${NC} $1"; }
print_warn()    { echo -e "${YELLOW}!${NC} $1"; }

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v stow &>/dev/null; then
    print_error "GNU Stow is not installed. Install it with: sudo pacman -S stow"
    exit 1
fi
print_success "GNU Stow is installed"
echo ""

PACKAGES=(
    config
    bin
    share
    wallpapers
)

print_status "Packages present in repo:"
for pkg in "${PACKAGES[@]}"; do
    if [ -d "$DOTFILES_DIR/$pkg" ]; then
        echo "  ✓ $pkg"
    else
        echo "  ✗ $pkg (missing)"
    fi
done
echo ""

print_status "Dry-run (no files modified):"
echo ""
for pkg in "${PACKAGES[@]}"; do
    [ -d "$DOTFILES_DIR/$pkg" ] || continue
    print_status "Package: $pkg"
    # -n = no-act, -v = verbose
    if out="$(stow -d "$DOTFILES_DIR" -t "$HOME" -n -v "$pkg" 2>&1)"; then
        printf '%s\n' "$out" | grep -E 'LINK|MKDIR|UNLINK' | sed 's/^/  /' || echo "  (nothing new)"
    else
        print_warn "  conflicts / errors:"
        printf '%s\n' "$out" | sed 's/^/  /'
    fi
    echo ""
done

print_status "Expected home layout after install.sh:"
cat << 'TREE'
  ~/.config/*                    -> config/.config/*   (stow)
  ~/.local/bin/                  -> bin/.local/bin/    (stow)
  ~/.local/share/*               -> share/, wallpapers/ (stow)
  ~/.xinitrc                     -> ~/.config/x11/xinitrc      (link_home)
  ~/.zshenv                      -> ~/.config/zsh/zshenv       (link_home)
  ~/.bashrc, .bash_profile, .bash_logout -> ~/.config/bash/*   (link_home)
TREE
echo ""
print_success "Dry-run complete. Run ./install.sh on a fresh Arch system to apply."
