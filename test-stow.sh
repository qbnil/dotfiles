#!/usr/bin/env bash
# Dry-run the XDG/Stow deployment without changing $HOME.
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; NC='\033[0m'
print_status()  { echo -e "${BLUE}==>${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_error()   { echo -e "${RED}✗${NC} $1"; }
print_warn()    { echo -e "${YELLOW}!${NC} $1"; }

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

command -v stow >/dev/null || { print_error "GNU Stow is not installed."; exit 1; }
print_success "GNU Stow is installed"

PACKAGES=(config local)
for pkg in "${PACKAGES[@]}"; do
    [ -d "$DOTFILES_DIR/$pkg" ] || { print_error "Missing package: $pkg"; exit 1; }
done

print_status "Stow dry-run:"
for pkg in "${PACKAGES[@]}"; do
    echo ""
    print_status "Package: $pkg"
    if out="$(stow -d "$DOTFILES_DIR" -t "$HOME" -n -v "$pkg" 2>&1)"; then
        printf '%s\n' "$out" | grep -E 'LINK|MKDIR|UNLINK' | sed 's/^/  /' || echo "  (nothing new)"
    else
        print_warn "conflicts / errors:"
        printf '%s\n' "$out" | sed 's/^/  /'
    fi
done

echo ""
print_status "Expected home layout:"
cat <<'TREE'
  ~/.config/                         -> config/.config/
  ~/.local/bin/                      -> local/.local/bin/
  ~/.local/share/honkai-star-rail-cursors -> local/.local/share/...
  ~/.bashrc                          -> ~/.config/bash/bashrc
  ~/.bash_profile                    -> ~/.config/bash/bash_profile
  ~/.zshenv                          -> ~/.config/zsh/zshenv
  ~/.xinitrc                         -> ~/.config/x11/xinitrc
  ~/desktop ~/documents ~/downloads ~/music ~/pictures
  ~/public ~/templates ~/videos      (real lowercase XDG user dirs)

  src/                               build sources only; never stowed
TREE
print_success "Dry-run complete."
