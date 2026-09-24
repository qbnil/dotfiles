#!/usr/bin/env bash
# home-status.sh
# Check home directory organization status against XDG spec

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

check_item() {
    local path="$1"
    local expected="$2"
    local name="$3"

    if [[ -e "$path" ]]; then
        if [[ -L "$path" ]]; then
            local target=$(readlink "$path")
            if [[ "$target" == "$expected" ]]; then
                echo -e "  ${GREEN}✓${NC} $name: symlink -> $target"
            else
                echo -e "  ${YELLOW}⚠${NC} $name: symlink -> $target (expected: $expected)"
            fi
        else
            echo -e "  ${RED}✗${NC} $name: regular file/dir at $path (should be in $expected)"
        fi
    else
        echo -e "  ${CYAN}○${NC} $name: not present"
    fi
}

check_dir() {
    local path="$1"
    local name="$2"

    if [[ -d "$path" ]]; then
        local count=$(find "$path" -mindepth 1 -maxdepth 1 | wc -l)
        echo -e "  ${GREEN}✓${NC} $name: exists ($count items)"
    else
        echo -e "  ${RED}✗${NC} $name: missing"
    fi
}

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              Home Directory Organization Status              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo

echo -e "${BLUE}XDG Base Directories:${NC}"
check_dir "$HOME/.config" "Config (~/.config)"
check_dir "$HOME/.local/share" "Data (~/.local/share)"
check_dir "$HOME/.local/bin" "Bin (~/.local/bin)"
check_dir "$HOME/.local/state" "State (~/.local/state)"
check_dir "$HOME/.cache" "Cache (~/.cache)"
echo

echo -e "${BLUE}Config Files (should be in ~/.config/):${NC}"
check_item "$HOME/.bashrc" "$HOME/.config/bash/bashrc" ".bashrc"
check_item "$HOME/.bash_profile" "$HOME/.config/bash/bash_profile" ".bash_profile"
check_item "$HOME/.bash_logout" "$HOME/.config/bash/bash_logout" ".bash_logout"
check_item "$HOME/.zshenv" "$HOME/.config/zsh/zshenv" ".zshenv"
check_item "$HOME/.gitconfig" "$HOME/.config/git/config" ".gitconfig"
check_item "$HOME/.xinitrc" "$HOME/.config/x11/xinitrc" ".xinitrc"
check_item "$HOME/.Xresources" "$HOME/.config/x11/Xresources" ".Xresources"
check_item "$HOME/.fehbg" "$HOME/.config/feh/fehbg" ".fehbg"
check_item "$HOME/.nvidia-settings-rc" "$HOME/.config/nvidia/settings-rc" ".nvidia-settings-rc"
check_item "$HOME/.ssh" "$HOME/.config/ssh" ".ssh"
echo

echo -e "${BLUE}Data Directories (should be in ~/.local/share/):${NC}"
check_item "$HOME/Documents" "$HOME/.local/share/documents" "Documents"
check_item "$HOME/Downloads" "$HOME/.local/share/downloads" "Downloads"
check_item "$HOME/Pictures" "$HOME/.local/share/pictures" "Pictures"
check_item "$HOME/Videos" "$HOME/.local/share/videos" "Videos"
check_item "$HOME/Music" "$HOME/.local/share/music" "Music"
check_item "$HOME/.fonts" "$HOME/.local/share/fonts" ".fonts"
check_item "$HOME/.icons" "$HOME/.local/share/icons" ".icons"
check_item "$HOME/.themes" "$HOME/.local/share/themes" ".themes"
echo

echo -e "${BLUE}XDG Environment Variables:${NC}"
for var in XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME; do
    if [[ -n "${!var:-}" ]]; then
        echo -e "  ${GREEN}✓${NC} $var=${!var}"
    else
        echo -e "  ${RED}✗${NC} $var not set"
    fi
done
echo

echo -e "${BLUE}Large Files in Home:${NC}"
find "$HOME" -maxdepth 1 -type f -size +100M 2>/dev/null | while read -r f; do
    size=$(du -sh "$f" | cut -f1)
    echo -e "  ${YELLOW}⚠${NC} $(basename "$f"): $size"
done

echo
echo -e "${BLUE}Dotfiles in Home Root (should be moved):${NC}"
find "$HOME" -maxdepth 1 -name ".*" -not -name "." -not -name ".." -not -name ".config" -not -name ".local" -not -name ".cache" -not -name ".claude" -not -name ".ssh" 2>/dev/null | sort | while read -r f; do
    echo -e "  ${YELLOW}○${NC} $(basename "$f")"
done

echo
echo -e "${BLUE}Backup Directories:${NC}"
if [[ -d "$HOME/.local/share/home-org-backup" ]]; then
    ls -1 "$HOME/.local/share/home-org-backup/" 2>/dev/null | while read -r d; do
        size=$(du -sh "$HOME/.local/share/home-org-backup/$d" 2>/dev/null | cut -f1)
        echo -e "  ${CYAN}↻${NC} $d ($size)"
    done
else
    echo -e "  ${CYAN}○${NC} No backups found"
fi