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
print_status "Installing essential tools (stow, git, base-devel)..."
CORE_PKGS=(base-devel git stow curl wget unzip rsync openssh)
pacman_install "${CORE_PKGS[@]}"
if ! command -v stow &>/dev/null; then
    print_error "GNU Stow could not be installed - cannot continue."
    exit 1
fi
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
          zram-generator xdg-utils xdg-user-dirs ripgrep fd fzf)

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
for f in .bashrc .bash_profile .bash_logout .profile .zshenv .zshrc .xinitrc .Xresources; do
    [ -f "$HOME/$f" ] && cp -a "$HOME/$f" "$BACKUP_DIR/" 2>/dev/null || true
done
print_success "Backup created"

# ----------------------------------------------------------------------------
# Stow
# ----------------------------------------------------------------------------
# Note: the 'systemd' package is intentionally NOT here. It holds files for /etc
# (NVIDIA suspend fix); stowing it into $HOME would just create ~/etc.
# On real NVIDIA hardware use ~/.local/bin/fix-nvidia-suspend instead.
PACKAGES=(
    bash
    bin
    config
    dunst
    git
    mpd
    nvim
    share
    shell
    tmux
    wallpapers
    x11
    yazi
    zsh
    vxwm
    dmenu
    picom
)

# Stow refuses to touch files that already exist (e.g. the default ~/.bashrc on a
# fresh install). Move those aside into the backup, then stow.
stow_pkg() {
    local pkg="$1" sim conflicts f attempt
    for attempt in 1 2 3; do
        if sim="$(stow -d "$DOTFILES_DIR" -t "$HOME" -R -n "$pkg" 2>&1)"; then
            break
        fi
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
            print_warning "  Conflict: ~/$f exists, moving to backup"
            mkdir -p "$BACKUP_DIR/conflicts/$(dirname "$f")"
            mv "$HOME/$f" "$BACKUP_DIR/conflicts/$f"
        done <<< "$conflicts"
    done
    stow -d "$DOTFILES_DIR" -t "$HOME" -R "$pkg"
}

print_status "Deploying dotfiles with GNU Stow..."
cd "$DOTFILES_DIR"
for package in "${PACKAGES[@]}"; do
    if [ -d "$DOTFILES_DIR/$package" ]; then
        print_status "Stowing $package..."
        if stow_pkg "$package"; then
            print_success "$package stowed"
        else
            FAILED_STOW+=("$package")
        fi
    fi
done

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
print_status "Building custom programs..."

# Stale copies in /usr/local/bin (from an earlier 'sudo make install' or copied from
# another machine) shadow the freshly built ones and can crash against the VM's
# libraries (e.g. "free(): invalid pointer"). Move them aside.
for b in dmenu dmenu_run stest st vxwm zlstatus; do
    if [ -e "/usr/local/bin/$b" ]; then
        print_warning "Stale /usr/local/bin/$b found, moving to $b.bak"
        sudo mv -f "/usr/local/bin/$b" "/usr/local/bin/$b.bak"
    fi
done
hash -r

# build_make NAME DIR BIN...   (clean build, then install binaries to ~/.local/bin)
build_make() {
    local name="$1" dir="$2"; shift 2
    [ -d "$dir" ] || return 0
    print_status "Building $name..."
    if ( cd "$dir" \
         && { make clean >/dev/null 2>&1 || true; } \
         && rm -f ./*.o \
         && make -j"$JOBS" \
         && install -Dm755 -t "$HOME/.local/bin" "$@" ); then
        print_success "$name built and installed"
    else
        print_error "$name build failed (continuing)"
        FAILED_BUILDS+=("$name")
    fi
}

build_make vxwm "$HOME/.local/share/vxwm"        vxwm
build_make dmenu "$HOME/.local/share/dmenu"       dmenu stest
build_make st    "$HOME/.local/share/st-terminal" st

if [ -d "$HOME/.local/share/slock" ]; then
    print_status "Building slock..."
    if ( cd "$HOME/.local/share/slock" \
         && { make clean >/dev/null 2>&1 || true; } \
         && make -j"$JOBS" \
         && sudo install -Dm4755 slock /usr/local/bin/slock ); then
        print_success "slock built and installed"
    else
        print_error "slock build failed (continuing)"
        FAILED_BUILDS+=("slock")
    fi
fi

if [ -d "$HOME/.local/share/zlstatus" ]; then
    print_status "Building zlstatus..."
    if command -v zig &>/dev/null \
       && ( cd "$HOME/.local/share/zlstatus" \
            && zig build \
            && install -Dm755 zig-out/bin/zlstatus "$HOME/.local/bin/zlstatus" ); then
        print_success "zlstatus built and installed"
    else
        print_error "zlstatus build failed (is zig installed? low RAM in the VM?) (continuing)"
        FAILED_BUILDS+=("zlstatus")
    fi
fi

cd "$DOTFILES_DIR"

# Sanity check: are all shared libraries of the built binaries resolvable?
for b in vxwm dmenu st zlstatus; do
    if [ -x "$HOME/.local/bin/$b" ] && ldd "$HOME/.local/bin/$b" 2>/dev/null | grep -q 'not found'; then
        print_warning "$b has unresolved libraries:"
        ldd "$HOME/.local/bin/$b" | grep 'not found' || true
    fi
done

# ----------------------------------------------------------------------------
# ZDOTDIR for zsh
# ----------------------------------------------------------------------------
if ! grep -q "ZDOTDIR" "$HOME/.zshenv" 2>/dev/null; then
    print_status "Setting up ZDOTDIR..."
    echo 'export ZDOTDIR="$HOME/.config/zsh"' >> "$HOME/.zshenv"
    print_success "ZDOTDIR configured"
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

if [ "${#FAILED_PKGS[@]}" -gt 0 ]; then
    print_warning "Packages that failed to install:"
    printf '     - %s\n' "${FAILED_PKGS[@]}"
fi
if [ "${#FAILED_BUILDS[@]}" -gt 0 ]; then
    print_warning "Builds that failed: ${FAILED_BUILDS[*]}"
fi
if [ "${#FAILED_STOW[@]}" -gt 0 ]; then
    print_warning "Stow packages that failed: ${FAILED_STOW[*]}"
fi

echo ""
print_warning "Next steps:"
echo "  1. Configure personal information:"
echo "     - Edit ~/.config/git/config and replace YOUR_EMAIL@example.com with your email"
echo "     - Replace YOUR_NAME with your actual name"
echo "  2. Edit ~/.config/shell/secrets.sh and add your API keys"
echo "  3. Review ~/.config/shell/xdg-env.sh for environment variables"
if [ ! -d "/usr/lib/modules/$(uname -r)" ]; then
    echo "  4. REBOOT now (the kernel was upgraded during this run)"
else
    echo "  4. Log out and log back in to apply all changes"
fi
echo "  5. Make sure ~/.local/bin is in your PATH, then run 'startx'"
if $IS_VM && [[ "$VM_TYPE" == "kvm" || "$VM_TYPE" == "qemu" ]]; then
    echo "  6. (QEMU) For clipboard sharing / auto-resize add 'spice-vdagent &' to your ~/.xinitrc"
    echo "     and use a virtio or qxl display with SPICE in your VM settings"
fi
echo ""
print_status "Backup saved at: $BACKUP_DIR"
