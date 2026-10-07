#!/usr/bin/env bash
# Dotfiles installation script for Arch Linux (bare metal AND virtual machines)
# Run as a normal user (NOT root) on a fresh Arch system:  ./install.sh
#
# Override VM auto-detection if needed:
#   DOTFILES_VM=1 ./install.sh    # force "this is a VM"
#   DOTFILES_VM=0 ./install.sh    # force "this is real hardware"

set -Eeuo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/dotfiles-backup-$(date +%Y%m%d-%H%M%S)"
JOBS="$(nproc 2>/dev/null || echo 2)"

FAILED_PKGS=()
FAILED_BUILDS=()
FAILED_STOW=()

# ----------------------------------------------------------------------------
# Output helpers
# ----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status()  { echo -e "${BLUE}==>${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}!${NC} $1"; }
print_error()   { echo -e "${RED}✗${NC} $1"; }

trap 'print_error "Script failed at line $LINENO (command: $BASH_COMMAND)"' ERR

# ----------------------------------------------------------------------------
# Preflight checks
# ----------------------------------------------------------------------------
if [ ! -f /etc/arch-release ]; then
    print_error "This script is designed for Arch Linux"
    exit 1
fi

if [ "$(id -u)" -eq 0 ]; then
    print_error "Do not run as root (makepkg/yay and stow into \$HOME need a normal user)."
    print_error "Create a user, add it to the wheel group, enable sudo, then re-run."
    exit 1
fi

if ! command -v sudo &>/dev/null; then
    print_error "sudo is not installed. As root run: pacman -S sudo, and add your user to wheel (visudo)."
    exit 1
fi

print_status "Checking internet connection..."
if ! curl -fsI --max-time 15 https://archlinux.org >/dev/null 2>&1; then
    print_error "No internet connection. In a VM check the network adapter / NAT, and that a"
    print_error "network service is running (e.g. systemctl enable --now dhcpcd or systemd-networkd)."
    exit 1
fi
print_success "Online"

# Ask for the sudo password once and keep the ticket alive during long builds
sudo -v
( while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) &
SUDO_KEEPALIVE_PID=$!
trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT

# ----------------------------------------------------------------------------
# Virtual machine detection
# ----------------------------------------------------------------------------
VM_TYPE="none"
if command -v systemd-detect-virt &>/dev/null; then
    VM_TYPE="$(systemd-detect-virt --vm 2>/dev/null || true)"
    [ -z "$VM_TYPE" ] && VM_TYPE="none"
fi

case "${DOTFILES_VM:-auto}" in
    1) IS_VM=true;  [ "$VM_TYPE" = "none" ] && VM_TYPE="unknown" ;;
    0) IS_VM=false ;;
    *) if [ "$VM_TYPE" != "none" ]; then IS_VM=true; else IS_VM=false; fi ;;
esac

if $IS_VM; then
    print_warning "Virtual machine detected ($VM_TYPE): skipping NVIDIA/GPU-specific packages and the NVIDIA suspend fix"
else
    print_status "Running on real hardware"
fi

# Packages that make no sense (or break) inside a VM
VM_SKIP_REGEX='^((lib32-)?(nvidia|opencl-nvidia|cuda|cudnn)|libva-nvidia-driver|egl-wayland|optimus-manager|envycontrol|bbswitch|supergfxctl)'

# ----------------------------------------------------------------------------
# Package helpers
# ----------------------------------------------------------------------------
# load_list FILE -> fills the LIST array (comments/blank lines removed, VM filter applied)
load_list() {
    local file="$1" name
    LIST=()
    [ -f "$file" ] || return 1
    while read -r name _; do
        [[ -z "$name" || "$name" == \#* ]] && continue
        if $IS_VM && [[ "$name" =~ $VM_SKIP_REGEX ]]; then
            print_warning "  VM: skipping $name"
            continue
        fi
        LIST+=("$name")
    done < "$file"
    return 0
}

# One missing package makes pacman abort the WHOLE transaction, so: try the whole
# batch first, then fall back to installing one by one and record what failed.
pacman_install() {
    [ "$#" -gt 0 ] || return 0
    if sudo pacman -S --needed --noconfirm "$@"; then
        return 0
    fi
    print_warning "Batch install failed, retrying package by package..."
    local p
    for p in "$@"; do
        sudo pacman -S --needed --noconfirm "$p" || FAILED_PKGS+=("$p")
    done
}

yay_install() {
    [ "$#" -gt 0 ] || return 0
    local flags=(-S --needed --noconfirm --removemake --answerdiff None --answerclean None --answeredit None)
    if yay "${flags[@]}" "$@"; then
        return 0
    fi
    print_warning "Batch AUR install failed, retrying package by package..."
    local p
    for p in "$@"; do
        yay "${flags[@]}" "$p" || FAILED_PKGS+=("AUR:$p")
    done
}

# ----------------------------------------------------------------------------
# Update system
# ----------------------------------------------------------------------------
print_status "Refreshing keyring and updating system packages..."
# A stale keyring (common with older ISOs / VM images) makes -Syu fail with PGP errors
sudo pacman -Sy --needed --noconfirm archlinux-keyring
sudo pacman -Su --noconfirm
print_success "System updated"

# ----------------------------------------------------------------------------
# Essential tooling (stow, git, build tools) - needed before anything else
# ----------------------------------------------------------------------------
print_status "Checking for GNU Stow..."
if ! command -v stow &>/dev/null; then
    print_status "Installing GNU Stow..."
    if ! sudo pacman -S --needed --noconfirm stow; then
        print_error "GNU Stow installation failed - cannot continue."
        exit 1
    fi
fi
print_success "GNU Stow is available"

print_status "Installing essential tools (git, base-devel)..."
CORE_PKGS=(base-devel git curl wget unzip rsync openssh)
pacman_install "${CORE_PKGS[@]}"
print_success "Essential tools installed"

# ----------------------------------------------------------------------------
# Packages the dotfiles/desktop need that might be missing from the lists
# (installed one-by-one fallback, so a wrong name never aborts the script)
# ----------------------------------------------------------------------------
print_status "Installing build dependencies, X11 stack, fonts and base apps..."

BUILD_DEPS=(libx11 libxft libxinerama libxrender libxcb fontconfig freetype2 imlib2 pkgconf zig)

X_PKGS=(xorg-server xorg-xinit xorg-xrandr xorg-xsetroot xorg-xrdb xorg-xset xorg-xprop
        xorg-xinput xorg-xev xf86-input-libinput xclip xdotool xcompmgr xwallpaper mesa)

# A missing font is a classic cause of dmenu/st crashes with Xft
FONT_PKGS=(ttf-dejavu ttf-liberation noto-fonts noto-fonts-emoji ttf-font-awesome
           ttf-jetbrains-mono ttf-jetbrains-mono-nerd ttf-nerd-fonts-symbols)

APP_PKGS=(zsh neovim tmux dunst libnotify mpd mpc yazi thunar
          pipewire pipewire-pulse wireplumber networkmanager
          zram-generator xdg-utils ripgrep fd fzf)

pacman_install "${BUILD_DEPS[@]}" "${X_PKGS[@]}" "${FONT_PKGS[@]}" "${APP_PKGS[@]}"

# VM guest tools (clipboard sharing, auto-resize, clean shutdown from host)
if $IS_VM; then
    print_status "Installing guest tools for $VM_TYPE..."
    case "$VM_TYPE" in
        kvm|qemu)  pacman_install qemu-guest-agent spice-vdagent ;;
        oracle)    pacman_install virtualbox-guest-utils ;;
        vmware)    pacman_install open-vm-tools gtkmm3 ;;
        *)         print_warning "No guest tools known for '$VM_TYPE', skipping" ;;
    esac
fi
print_success "Base packages installed"

# ----------------------------------------------------------------------------
# Packages from the repo lists
# ----------------------------------------------------------------------------
print_status "Installing native packages from packages-native.txt..."
if load_list "$DOTFILES_DIR/bootstrap/packages-native.txt"; then
    pacman_install "${LIST[@]}"
    print_success "Native packages processed"
else
    print_warning "packages-native.txt not found, skipping"
fi

# ----------------------------------------------------------------------------
# yay + AUR packages
# ----------------------------------------------------------------------------
if ! command -v yay &>/dev/null; then
    print_status "Installing yay AUR helper..."
    YAY_TMP="$(mktemp -d)"
    if git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$YAY_TMP/yay-bin" \
       && (cd "$YAY_TMP/yay-bin" && makepkg -si --noconfirm); then
        print_success "yay installed"
    else
        print_warning "yay installation failed - AUR packages will be skipped"
    fi
    rm -rf "$YAY_TMP"
fi

if command -v yay &>/dev/null; then
    print_status "Installing AUR packages..."
    if load_list "$DOTFILES_DIR/bootstrap/packages-aur.txt"; then
        yay_install "${LIST[@]}"
        print_success "AUR packages processed"
    else
        print_warning "packages-aur.txt not found, skipping"
    fi
fi

# ----------------------------------------------------------------------------
# XDG directories
# ----------------------------------------------------------------------------
print_status "Creating XDG directories..."
mkdir -p "$HOME"/.config "$HOME"/.local/{bin,share,state} "$HOME"/.cache
print_success "XDG directories created"

# ----------------------------------------------------------------------------
# Backup existing configuration
# ----------------------------------------------------------------------------
print_status "Backing up existing configurations to $BACKUP_DIR"
mkdir -p "$BACKUP_DIR"
[ -d "$HOME/.config" ]      && cp -a "$HOME/.config"      "$BACKUP_DIR/" 2>/dev/null || true
[ -d "$HOME/.local/bin" ]   && cp -a "$HOME/.local/bin"   "$BACKUP_DIR/" 2>/dev/null || true
[ -d "$HOME/.local/share" ] && cp -a "$HOME/.local/share" "$BACKUP_DIR/" 2>/dev/null || true
for f in .bashrc .bash_profile .profile .zshenv .zshrc .xinitrc .Xresources; do
    [ -f "$HOME/$f" ] && cp -a "$HOME/$f" "$BACKUP_DIR/" 2>/dev/null || true
done
print_success "Backup created"

# ----------------------------------------------------------------------------
# Stow
# ----------------------------------------------------------------------------
# `config` owns ~/.config only. `local` owns ~/.local/{bin,share}.
# Buildable sources live in ./src and are never stowed into $HOME.
PACKAGES=(config local)

stow_pkg() {
    local pkg="$1" sim conflicts f
    sim="$(stow -d "$DOTFILES_DIR" -t "$HOME" -R -n "$pkg" 2>&1 || true)"
    if [ -n "$sim" ] && printf '%s\n' "$sim" | grep -qiE 'existing target|over existing target|conflict'; then
        conflicts="$(printf '%s\n' "$sim" | sed -n -E \
            -e 's/^[[:space:]]*\* existing target (is neither a link nor a directory|is not owned by stow): (.*)$/\2/p' \
            -e 's/^.*over existing target (.*) since .*$/\1/p')"
        if [ -z "$conflicts" ]; then
            print_error "Stow problem in '$pkg':"
            printf '%s\n' "$sim" >&2
            return 1
        fi
        while IFS= read -r f; do
            [ -n "$f" ] || continue
            print_warning "~/$f exists; moving it to backup"
            mkdir -p "$BACKUP_DIR/conflicts/$(dirname "$f")"
            mv "$HOME/$f" "$BACKUP_DIR/conflicts/$f"
        done <<< "$conflicts"
    fi
    stow -d "$DOTFILES_DIR" -t "$HOME" -R "$pkg"
}

# Scripts in local/.local/bin must be executable (stow symlinks to these files,
# and zip/copy transfers can drop the mode bits).
chmod +x "$DOTFILES_DIR"/local/.local/bin/* 2>/dev/null || true

print_status "Deploying XDG files with GNU Stow..."
cd "$DOTFILES_DIR"
for package in "${PACKAGES[@]}"; do
    if stow_pkg "$package"; then
        print_success "$package stowed"
    else
        FAILED_STOW+=("$package")
    fi
done

# These are conventional compatibility entrypoints that some programs require.
# Their real contents live under ~/.config.
link_home() {
    local src="$HOME/.config/$1" dst="$HOME/$2"
    [ -e "$src" ] || { print_warning "$src missing; skipping ~/$2"; return 0; }
    if [ -e "$dst" ] || [ -L "$dst" ]; then
        if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
            return 0
        fi
        print_warning "~/$2 exists; moving it to backup"
        mkdir -p "$BACKUP_DIR/conflicts"
        mv "$dst" "$BACKUP_DIR/conflicts/$2"
    fi
    ln -s "$src" "$dst"
    print_success "~/$2 -> $src"
}

print_status "Creating compatibility links..."
link_home x11/xinitrc .xinitrc
link_home zsh/zshenv .zshenv
link_home bash/bashrc .bashrc
link_home bash/bash_profile .bash_profile

# ~/.Xresources is no longer needed: Xresources now lives in ~/.config/x11/.
# Preserve an existing file in the backup instead of deleting user data silently.
if [ -e "$HOME/.Xresources" ] || [ -L "$HOME/.Xresources" ]; then
    print_warning "~/.Xresources is legacy; moving it to backup"
    mkdir -p "$BACKUP_DIR/conflicts"
    mv "$HOME/.Xresources" "$BACKUP_DIR/conflicts/.Xresources"
fi

# Lowercase user directories are defined once, in ~/.config/user-dirs.dirs
# (stowed from config/). xdg-env.sh exports them as XDG_*_DIR.
print_status "Creating lowercase user directories..."
# shellcheck source=/dev/null
. "$HOME/.config/shell/xdg-env.sh"

# Move leftovers from the capitalised defaults (~/Downloads -> ~/downloads, ...)
# without overwriting anything: files that already exist at the target stay put.
migrate_dir() {
    local target="$1" legacy
    legacy="$(dirname "$target")/$(basename "$target" | sed 's/^./\U&/')"
    [ "$legacy" != "$target" ] && [ -d "$legacy" ] && [ ! -L "$legacy" ] || return 0
    mkdir -p "$target"
    find "$legacy" -mindepth 1 -maxdepth 1 -exec mv -n -t "$target" {} + 2>/dev/null || true
    if rmdir "$legacy" 2>/dev/null; then
        print_success "migrated $legacy -> $target"
    else
        print_warning "$legacy not empty after migration; left in place - review it manually"
    fi
}

for dir in "$XDG_DESKTOP_DIR" "$XDG_DOCUMENTS_DIR" "$XDG_DOWNLOAD_DIR" "$XDG_MUSIC_DIR" \
           "$XDG_PICTURES_DIR" "$XDG_PUBLICSHARE_DIR" "$XDG_TEMPLATES_DIR" "$XDG_VIDEOS_DIR"; do
    migrate_dir "$dir"
    mkdir -p "$dir"
done
mkdir -p "$XDG_PICTURES_DIR"/{screenshots,wallpapers}
mkdir -p "$HOME/.local/state/mpd" "$HOME/.cache/mpd"
print_success "desktop documents downloads music pictures public templates videos"

print_status "Home layout:"
echo "  ~/.config/       -> $DOTFILES_DIR/config/.config"
echo "  ~/.local/bin/    -> $DOTFILES_DIR/local/.local/bin"
echo "  ~/.local/share/  -> $DOTFILES_DIR/local/.local/share"
echo "  ~/desktop/ documents/ downloads/ music/ pictures/ public/ templates/ videos/"
echo "  ~/.bashrc ~/.bash_profile ~/.zshenv ~/.xinitrc -> ~/.config/*"
echo ""

# ----------------------------------------------------------------------------
# Secrets template
# ----------------------------------------------------------------------------
mkdir -p "$HOME/.config/shell"
if [ ! -f "$HOME/.config/shell/secrets.sh" ]; then
    print_status "Creating secrets file..."
    if [ -f "$HOME/.config/shell/secrets.sh.example" ]; then
        cp "$HOME/.config/shell/secrets.sh.example" "$HOME/.config/shell/secrets.sh"
    else
        cat > "$HOME/.config/shell/secrets.sh" <<'EOSECRETS'
# Secrets and API keys - DO NOT COMMIT THIS FILE
# This file is sourced by xdg-env.sh

# Tailscale configuration
export TAILSCALE_API_KEY=""
export TAILSCALE_TAILNET=""  # Your tailnet email (e.g., your-email@example.com)
export TAILSCALE_TARGET_DEVICE=""  # Device hostname to target for removal
export TAILSCALE_AUTH_KEY=""  # Your Tailscale auth key for tailscale up
export TAILSCALE_EXIT_NODE=""  # Exit node IP (optional, e.g., 100.xxx.xxx.xxx)

# Gemini
export GEMINI_API_KEY=""

# Claude/Anthropic
export ANTHROPIC_AUTH_TOKEN=""

# OpenRouter
export OPENROUTER_API_KEY=""

# Add your other API keys and secrets here
EOSECRETS
    fi
    chmod 600 "$HOME/.config/shell/secrets.sh"
    print_success "Secrets file created at ~/.config/shell/secrets.sh"
    print_warning "Please edit ~/.config/shell/secrets.sh and add your API keys"
fi

# ----------------------------------------------------------------------------
# Build suckless tools and custom programs
# ----------------------------------------------------------------------------
print_status "Building custom programs from ./src..."

for b in dmenu dmenu_run stest st vxwm zlstatus nsxiv slock; do
    if [ -e "$HOME/.local/bin/$b" ]; then
        rm -f "$HOME/.local/bin/$b"
    fi
done
hash -r

build_user_make() {
    local name="$1" dir="$2"
    local log="/tmp/dotfiles-build-${name}.log"
    [ -d "$dir" ] || { print_warning "Source missing: $dir"; FAILED_BUILDS+=("$name"); return 0; }
    print_status "Building $name..."
    if ( cd "$dir"          && { make clean >/dev/null 2>&1 || true; }          && make -j"$JOBS" 2>&1 | tee "$log"          && make PREFIX="$HOME/.local" install 2>&1 | tee -a "$log" ); then
        print_success "$name -> ~/.local/bin"
        rm -f "$log"
    else
        print_error "$name build failed; full log: $log"
        tail -n 40 "$log" 2>/dev/null | sed 's/^/    /' || true
        FAILED_BUILDS+=("$name")
    fi
}

build_slock() {
    local dir="$DOTFILES_DIR/src/slock" log=/tmp/dotfiles-build-slock.log
    print_status "Building slock..."
    if ( cd "$dir"          && { make clean >/dev/null 2>&1 || true; }          && make -j"$JOBS" 2>&1 | tee "$log"          && sudo make PREFIX=/usr/local install 2>&1 | tee -a "$log" ); then
        print_success "slock -> /usr/local/bin/slock"
        rm -f "$log"
    else
        print_error "slock build failed; full log: $log"
        tail -n 40 "$log" 2>/dev/null | sed 's/^/    /' || true
        FAILED_BUILDS+=("slock")
    fi
}

build_user_make vxwm "$DOTFILES_DIR/src/vxwm"
build_user_make dmenu "$DOTFILES_DIR/src/dmenu"
build_user_make st "$DOTFILES_DIR/src/st-terminal"
build_user_make nsxiv "$DOTFILES_DIR/src/nsxiv"
build_slock

if [ -d "$DOTFILES_DIR/src/zlstatus" ]; then
    print_status "Building zlstatus..."
    log=/tmp/dotfiles-build-zlstatus.log
    if ( cd "$DOTFILES_DIR/src/zlstatus" \
         && zig build -Dmode=X11 -Doptimize=ReleaseSmall --summary all 2>&1 | tee "$log" \
         && install -Dm755 zig-out/bin/zlstatus "$HOME/.local/bin/zlstatus" ); then
        print_success "zlstatus -> ~/.local/bin/zlstatus"
        rm -f "$log"
    else
        print_error "zlstatus build failed; full log: $log"
        tail -n 40 "$log" 2>/dev/null | sed 's/^/    /' || true
        FAILED_BUILDS+=("zlstatus")
    fi
fi

cd "$DOTFILES_DIR"
for b in vxwm dmenu st zlstatus nsxiv; do
    if [ -x "$HOME/.local/bin/$b" ] && ldd "$HOME/.local/bin/$b" 2>/dev/null | grep -q 'not found'; then
        print_warning "$b has unresolved libraries:"
        ldd "$HOME/.local/bin/$b" | grep 'not found' || true
    fi
done

# ----------------------------------------------------------------------------
# Install systemd files (to system directories, not stowed into $HOME)
# ----------------------------------------------------------------------------
if [ -d "$DOTFILES_DIR/systemd/etc" ]; then
    print_status "Installing systemd configuration files..."
    if $IS_VM; then
        print_warning "Running in VM - skipping NVIDIA-specific systemd files"
    else
        # Install /etc files for NVIDIA suspend fix on real hardware
        if [ -d "$DOTFILES_DIR/systemd/etc/modprobe.d" ]; then
            sudo cp -r "$DOTFILES_DIR/systemd/etc/modprobe.d/"* /etc/modprobe.d/ 2>/dev/null || true
            print_success "Installed modprobe.d configuration"
        fi
        if [ -d "$DOTFILES_DIR/systemd/etc/systemd" ]; then
            sudo cp -r "$DOTFILES_DIR/systemd/etc/systemd/"* /etc/systemd/system/ 2>/dev/null || true
            sudo systemctl daemon-reload
            print_success "Installed systemd services"
        fi
    fi
fi

# ----------------------------------------------------------------------------
# zram
# ----------------------------------------------------------------------------
if command -v zramctl &>/dev/null && [ -f /usr/lib/systemd/system-generators/zram-generator ]; then
    print_status "Configuring zram..."
    sudo mkdir -p /etc/systemd/zram-generator.conf.d
    sudo tee /etc/systemd/zram-generator.conf.d/zram.conf > /dev/null <<EOZRAM
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
EOZRAM
    sudo systemctl daemon-reload
    print_success "zram configured"
fi

# ----------------------------------------------------------------------------
# Services
# ----------------------------------------------------------------------------
print_status "Enabling services..."

# User services need a running user session bus; ignore failure (e.g. over ssh)
systemctl --user enable --now pipewire pipewire-pulse wireplumber 2>/dev/null \
    || print_warning "Could not enable user audio services now; they will start on next login"

# Don't fight an existing network stack: switching to NetworkManager while
# systemd-networkd/dhcpcd/iwd manages the VM's NIC can kill the connection.
if systemctl is-active --quiet systemd-networkd 2>/dev/null \
   || systemctl is-active --quiet dhcpcd 2>/dev/null \
   || systemctl is-active --quiet iwd 2>/dev/null; then
    print_warning "Another network service is active; NOT enabling NetworkManager (avoids conflicts)"
else
    sudo systemctl enable --now NetworkManager 2>/dev/null || true
fi

if $IS_VM; then
    case "$VM_TYPE" in
        kvm|qemu)
            sudo systemctl enable --now spice-vdagentd.socket 2>/dev/null || true
            sudo systemctl enable --now qemu-guest-agent.service 2>/dev/null || true
            ;;
        oracle) sudo systemctl enable --now vboxservice.service 2>/dev/null || true ;;
        vmware) sudo systemctl enable --now vmtoolsd.service vmware-vmblock-fuse.service 2>/dev/null || true ;;
    esac
fi
print_success "Services configured"

# ----------------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------------
echo ""
print_success "Dotfiles installation finished!"
echo ""

if [ "${#FAILED_PKGS[@]}" -gt 0 ]; then
    print_warning "Packages that failed to install:"
    printf '     - %s\n' "${FAILED_PKGS[@]}"
    if printf '%s\n' "${FAILED_PKGS[@]}" | grep -qx 'pipewire-jack'; then
        echo "       (pipewire-jack conflicts with jack2. Fix with:)"
        echo "         sudo pacman -Rdd jack2 && sudo pacman -S pipewire-jack"
        echo "       or just ignore it if you do not need JACK compatibility."
    fi
    echo ""
fi
if [ "${#FAILED_BUILDS[@]}" -gt 0 ]; then
    print_warning "Builds that failed: ${FAILED_BUILDS[*]}"
    echo "     Logs (if present): /tmp/dotfiles-build-<name>.log"
    echo "     Rebuild a single program after fixing:"
    echo "       cd ~/dotfiles/src/vxwm && make clean && make -j$(nproc) && make PREFIX="$HOME/.local" install"
    echo ""
fi
if [ "${#FAILED_STOW[@]}" -gt 0 ]; then
    print_warning "Stow packages that failed: ${FAILED_STOW[*]}"
    echo ""
fi

print_status "Summary of installed programs:"
echo "  Custom programs:"
for prog in vxwm dmenu st nsxiv zlstatus; do
    if [ -x "$HOME/.local/bin/$prog" ]; then
        echo "    ✓ $prog -> ~/.local/bin/$prog"
    else
        echo "    ✗ $prog (build failed or not found)"
    fi
done
if [ -x /usr/local/bin/slock ]; then
    echo "    ✓ slock -> /usr/local/bin/slock"
else
    echo "    ✗ slock (build failed or not found)"
fi
echo ""

print_warning "Next steps:"
echo "  1. Configure personal information:"
echo "     - Edit ~/.config/git/config and replace YOUR_EMAIL@example.com"
echo "     - Replace YOUR_NAME with your actual name"
echo "  2. Edit ~/.config/shell/secrets.sh and add your API keys"
echo "  3. Review ~/.config/shell/xdg-env.sh (environment) and ~/.config/user-dirs.dirs (XDG user directories)"
if [ ! -d "/usr/lib/modules/$(uname -r)" ]; then
    echo "  4. REBOOT now (kernel was upgraded)"
else
    echo "  4. Log out and log back in to apply all changes"
fi
echo "  5. Run 'startx' to start your X session"
if $IS_VM && [[ "$VM_TYPE" == "kvm" || "$VM_TYPE" == "qemu" ]]; then
    echo "  6. (QEMU) Add `spice-vdagent &` to ~/.xinitrc for clipboard sharing"
fi
echo ""
print_status "Backup saved at: $BACKUP_DIR"
print_status "See STOW_STRUCTURE.md for the XDG/Stow layout"
