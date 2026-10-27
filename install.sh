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

# ----------------------------------------------------------------------------
# GPU detection (display controllers only: VGA 0x0300, 3D 0x0302)
# Reads /sys directly so it works before pciutils is installed.
# ----------------------------------------------------------------------------
HAS_NVIDIA=false
HAS_AMD=false
for dev in /sys/bus/pci/devices/*; do
    read -r dev_class < "$dev/class" 2>/dev/null || continue
    case "$dev_class" in
        0x0300*|0x0302*) ;;
        *) continue ;;
    esac
    read -r dev_vendor < "$dev/vendor" 2>/dev/null || continue
    case "$dev_vendor" in
        0x10de) HAS_NVIDIA=true ;;
        0x1002) HAS_AMD=true ;;
    esac
done

if $IS_VM; then
    print_warning "Virtual machine detected ($VM_TYPE): skipping NVIDIA/GPU-specific packages and the NVIDIA suspend fix"
else
    print_status "Running on real hardware"
    if $HAS_NVIDIA; then print_success "NVIDIA GPU detected"; fi
    if $HAS_AMD; then print_warning "AMD GPU detected: skipping NVIDIA-only system files and hook"; fi
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

APP_PKGS=(zsh neovim tmux dunst libnotify mpd mpc yazi thunar podman distrobox
          pipewire pipewire-pulse wireplumber networkmanager
          zram-generator xdg-utils ripgrep fd fzf
          udisks2 udisks2-btrfs gvfs gvfs-mtp thunar-volman polkit polkit-gnome upower)

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
            -e 's/^.*over existing target ([^ ]+) since .*$/\1/p' \
            -e 's/^.*existing target ([^ ]+) since .*$/\1/p')"
        if [ -z "$conflicts" ]; then
            print_error "Stow problem in '$pkg':"
            printf '%s\n' "$sim" >&2
            return 1
        fi
        while IFS= read -r f; do
            [ -n "$f" ] || continue
            # A directory may be reported because only one child conflicts.
            # Preserve the whole existing path only when it is a leaf conflict;
            # backing up a parent directory removes unrelated stowed siblings.
            if [ -d "$HOME/$f" ] && [ ! -L "$HOME/$f" ]; then
                continue
            fi
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

# Pre-create ~/.local/share/icons as a real directory. The cursor themes are
# exposed there (libXcursor searches it first), and creating it up front stops
# Stow from folding the whole dir into a symlink to the repo - otherwise tools
# that write to ~/.local/share/icons would write straight into dotfiles.
mkdir -p "$HOME/.local/share/icons"

print_status "Deploying XDG files with GNU Stow..."
cd "$DOTFILES_DIR"
for package in "${PACKAGES[@]}"; do
    if stow_pkg "$package"; then
        print_success "$package stowed"
    else
        FAILED_STOW+=("$package")
    fi
done

# Install tmux plugins via TPM after Stow has deployed tmux.conf.  Do this in
# an isolated server and wait for run-shell to finish: the old implementation
# used `run-shell -b` and killed the server immediately, which could terminate
# a git clone before TPM had installed the theme.
if command -v tmux &>/dev/null; then
    if [ -f "$HOME/.config/tmux/plugins/tpm/bin/install_plugins" ]; then
        print_status "Installing tmux plugins..."
        # A previous install run may have copied the config as root (or a
        # manually run `sudo stow` may have made the plugin tree root-owned).
        # TPM clones and updates as the normal user, so repair only this user
        # data directory and ask for sudo only when ownership actually needs
        # repair.
        tmux_plugins="$HOME/.config/tmux/plugins"
        if [ ! -w "$tmux_plugins" ] || [ ! -w "$tmux_plugins/tpm" ] || \
           find "$tmux_plugins" -maxdepth 2 ! -user "$USER" -print -quit 2>/dev/null | grep -q .; then
            print_warning "Tmux plugin directory is not writable by $USER"
            sudo -v
            sudo chown -R "$USER:$(id -gn)" "$tmux_plugins"
        fi
        tmux_log="/tmp/dotfiles-tmux-plugins.log"
        tmux_ok=false
        tmux_was_running=false
        tmux list-sessions >/dev/null 2>&1 && tmux_was_running=true || true
        # TPM helper scripts call plain `tmux` internally. Do not use a custom
        # -L socket here: those calls would inspect a different server and
        # report TMUX_PLUGIN_MANAGER_PATH as unknown.
        if $tmux_was_running; then
            # `-f` is ignored by an already-running server. Explicitly source
            # the just-stowed config so TPM's @plugin declarations and global
            # plugin path exist on that server too.
            tmux source-file "$HOME/.config/tmux/tmux.conf" >>"$tmux_log" 2>&1 || true
            tmux set-environment -g TMUX_PLUGIN_MANAGER_PATH "$tmux_plugins/" \
                >>"$tmux_log" 2>&1 || true
        fi
        tmux_session="dotfiles-install-$$"
        if $tmux_was_running; then
            tmux new-session -d -s "$tmux_session" 2>>"$tmux_log" || true
        else
            tmux -f "$HOME/.config/tmux/tmux.conf" \
                new-session -d -s "$tmux_session" 2>"$tmux_log" || true
        fi
        if tmux has-session -t "$tmux_session" 2>/dev/null; then
            if tmux run-shell \
                    "bash '$HOME/.config/tmux/plugins/tpm/bin/install_plugins'" \
                    >>"$tmux_log" 2>&1; then
                tmux_ok=true
            fi
            if ! $tmux_was_running; then
                tmux kill-server 2>/dev/null || true
            else
                tmux kill-session -t "$tmux_session" 2>/dev/null || true
            fi
        fi
        if $tmux_ok; then
            rm -f "$tmux_log"
            print_success "Tmux plugins installed"
        else
            print_error "Tmux plugin installation failed; full log: $tmux_log"
            tail -n 40 "$tmux_log" 2>/dev/null | sed 's/^/    /' || true
            FAILED_BUILDS+=("tmux-plugins")
        fi
    else
        print_warning "TPM is missing; tmux plugins were not installed"
        FAILED_BUILDS+=("tmux-plugins")
    fi
elif ! command -v tmux &>/dev/null; then
    print_error "tmux is not installed after package installation"
    FAILED_PKGS+=("tmux")
fi

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

# There is exactly one Xresources and it lives at ~/.config/x11/Xresources.
# It is generated by ~/.local/bin/xresources-gen (static Xft/cursor block + the
# current pywal palette), so it must NOT be tracked in the repo or stowed - a
# symlink into the repo would let pywal write straight into it. Preserve a
# legacy ~/.Xresources in the backup instead of deleting user data silently.
if [ -e "$HOME/.Xresources" ] || [ -L "$HOME/.Xresources" ]; then
    print_warning "~/.Xresources is legacy; moving it to backup"
    mkdir -p "$BACKUP_DIR/conflicts"
    mv "$HOME/.Xresources" "$BACKUP_DIR/conflicts/.Xresources"
fi

# Generate the single Xresources now so a fresh login has fonts/cursor settings
# even before the first wallpaper change (xrdb-reload regenerates it on every wal run).
if [ -x "$HOME/.local/bin/xresources-gen" ]; then
    "$HOME/.local/bin/xresources-gen" && print_success "~/.config/x11/Xresources generated"
fi

# Lowercase user directories are defined once, in ~/.config/user-dirs.dirs
# (stowed from config/). xdg-env.sh exports them as XDG_*_DIR.
print_status "Creating lowercase user directories..."
# shellcheck source=/dev/null
xdg_env="$HOME/.config/shell/xdg-env.sh"
xdg_env_source="$DOTFILES_DIR/config/.config/shell/xdg-env.sh"
mkdir -p "$HOME/.config/shell"
# The package can contain many legacy Stow conflicts; an earlier Stow run may
# leave this one file stale or missing even though the installer can continue.
# Ensure this environment file is always the exact repository version and is
# linked back to the repo so future pulls update it automatically.
if [ ! -L "$xdg_env" ] || [ "$(readlink -f "$xdg_env" 2>/dev/null || true)" != "$xdg_env_source" ]; then
    if [ -e "$xdg_env" ] || [ -L "$xdg_env" ]; then
        if ! cmp -s "$xdg_env" "$xdg_env_source"; then
            print_warning "Backing up stale ~/.config/shell/xdg-env.sh"
            mkdir -p "$BACKUP_DIR/conflicts/.config/shell"
            mv "$xdg_env" "$BACKUP_DIR/conflicts/.config/shell/xdg-env.sh"
        else
            rm -f "$xdg_env"
        fi
    fi
    ln -s "$xdg_env_source" "$xdg_env"
fi
. "$xdg_env"

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
mkdir -p "$XDG_MUSIC_DIR"/playlists
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
# Flameshot config (generated)
# ----------------------------------------------------------------------------
# Flameshot validates savePath as an *existing absolute directory* and does not
# expand "~" or "$HOME"; it also rewrites flameshot.ini itself, which would
# clobber a stowed symlink. So the repo keeps a username-free template in
# bootstrap/templates/ and we expand @HOME@ to the real path here.
# An existing flameshot.ini is never overwritten.
FLAMESHOT_TEMPLATE="$DOTFILES_DIR/bootstrap/templates/flameshot.ini"
FLAMESHOT_CONF="$HOME/.config/flameshot/flameshot.ini"
if [ -f "$FLAMESHOT_TEMPLATE" ] && [ ! -e "$FLAMESHOT_CONF" ]; then
    print_status "Creating flameshot config..."
    mkdir -p "$(dirname "$FLAMESHOT_CONF")"
    sed "s|@HOME@|$HOME|g" "$FLAMESHOT_TEMPLATE" > "$FLAMESHOT_CONF"
    print_success "flameshot config created at $FLAMESHOT_CONF"
fi

# ----------------------------------------------------------------------------
# Build suckless tools and custom programs
# ----------------------------------------------------------------------------
print_status "Building custom programs from ./src..."

for b in dmenu dmenu_run stest st vxwm zlstatus nsxiv slock dmenu-win; do
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
    local cur_user cur_group
    cur_user="$(id -un)"
    cur_group="$(id -gn)"
    print_status "Building slock..."
    if ( cd "$dir"          && { [ -f config.h.bak ] || cp config.h config.h.bak; }          && sed -i "s/^static const char \*user  = .*/static const char *user  = \"${cur_user}\";/" config.h          && sed -i "s/^static const char \*group = .*/static const char *group = \"${cur_group}\";/" config.h          && { make clean >/dev/null 2>&1 || true; }          && make -j"$JOBS" 2>&1 | tee "$log"          && sudo make PREFIX=/usr/local install 2>&1 | tee -a "$log"          && cp config.h.bak config.h && rm -f config.h.bak ); then
        print_success "slock -> /usr/local/bin/slock"
        rm -f "$log"
    else
        # restore config on failure
        [ -f config.h.bak ] && cp config.h.bak config.h && rm -f config.h.bak
        print_error "slock build failed; full log: $log"
        tail -n 40 "$log" 2>/dev/null | sed 's/^/    /' || true
        FAILED_BUILDS+=("slock")
    fi
}

# Patched Thunar (cut/copy tint). Same package name as the repo one, so
# pacman -U simply replaces the stock build. Built in a temp dir so the
# repo stays clean.
build_thunar_patched() {
    local dir="$DOTFILES_DIR/src/thunar" log=/tmp/dotfiles-build-thunar.log
    local want repo tmp

    [ -f "$dir/PKGBUILD" ] || { print_warning "src/thunar missing; keeping stock Thunar"; return 0; }
    for p in thunar-cut-copy-colors.patch thunar-square-highlight.patch thunar-drop-fill.patch; do
      if [ ! -f "$dir/$p" ]; then
        print_error "src/thunar/$p is missing"
        FAILED_BUILDS+=("thunar")
        return 0
      fi
    done
    # The patch targets one exact release. If the repo has moved on, building the
    # old version would DOWNGRADE Thunar (and can break thunar-volman/plugins).
    want="$(sed -n 's/^pkgver=//p' "$dir/PKGBUILD")"
    repo="$(pacman -Si thunar 2>/dev/null | awk '/^Version/{print $3}')"
    repo="${repo#*:}"; repo="${repo%-*}"
    if [ "$repo" != "$want" ]; then
        print_warning "Repo Thunar is $repo but the patch targets $want; keeping stock Thunar"
        print_warning "  update src/thunar/PKGBUILD + patch for the new version, then re-run"
        return 0
    fi

    tmp="$(mktemp -d)"
    print_status "Building patched Thunar $want..."
    if ( cd "$dir" \
         && BUILDDIR="$tmp" SRCDEST="$tmp" PKGDEST="$tmp" \
            makepkg -sif --noconfirm 2>&1 | tee "$log" ); then
        print_success "patched Thunar installed"
        rm -f "$log"
    else
        print_error "Thunar build failed; full log: $log"
        tail -n 40 "$log" 2>/dev/null | sed 's/^/    /' || true
        FAILED_BUILDS+=("thunar")
    fi
    rm -rf "$tmp"
}

build_user_make vxwm "$DOTFILES_DIR/src/vxwm"
build_user_make dmenu "$DOTFILES_DIR/src/dmenu"
build_user_make st "$DOTFILES_DIR/src/st-terminal"
build_user_make nsxiv "$DOTFILES_DIR/src/nsxiv"
build_user_make dmenu-win "$DOTFILES_DIR/src/dmenu-win"
build_slock
build_thunar_patched

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
for b in vxwm dmenu st zlstatus nsxiv dmenu-win; do
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
    elif $HAS_NVIDIA && ! $HAS_AMD; then
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
        # Warn after an nvidia-utils/dkms upgrade if the loaded kernel module
        # no longer matches userspace (otherwise Xorg dies with "no screens found").
        if [ -d "$DOTFILES_DIR/systemd/etc/pacman.d/hooks" ]; then
            sudo install -d /etc/pacman.d/hooks
            sudo install -Dm755 "$DOTFILES_DIR/systemd/etc/pacman.d/hooks/nvidia-mismatch-check" \
                /etc/pacman.d/hooks/nvidia-mismatch-check
            sudo install -Dm644 "$DOTFILES_DIR/systemd/etc/pacman.d/hooks/nvidia-mismatch-check.hook" \
                /etc/pacman.d/hooks/nvidia-mismatch-check.hook
            print_success "Installed NVIDIA reboot-check pacman hook"
        fi
    else
        print_warning "No NVIDIA GPU (or AMD GPU present) - skipping NVIDIA-only system files and hook"
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
# Docker (engine + Compose v2 plugin + buildx)
# ----------------------------------------------------------------------------
# Rootful Docker, the Arch default: docker.service listens on
# /var/run/docker.sock and the CLI talks to it. The packages are also listed in
# packages-native.txt; installing them again here is a no-op with --needed but
# keeps Compose available even if a list entry failed.
print_status "Configuring Docker..."
pacman_install docker docker-compose docker-buildx

# shell/xdg-env.sh sets DOCKER_CONFIG=~/.config/docker, so Docker must not use
# ~/.docker. Docker writes config.json, contexts/, buildx/ and cli-plugins/ into
# that directory at runtime, so create it as a real directory - Stow only links
# individual files below ~/.config and would never own this one.
mkdir -p "${DOCKER_CONFIG:-$HOME/.config/docker}"

# Membership in the docker group is what allows the CLI to open the socket
# without sudo. It only takes effect in new sessions.
if ! id -nG "$(id -un)" | grep -qw docker; then
    sudo usermod -aG docker "$(id -un)"
    print_warning "Added $(id -un) to the 'docker' group - log out and back in before using docker without sudo"
fi

sudo systemctl enable --now docker.service 2>/dev/null \
    || print_warning "Could not enable docker.service now"

# CLI-only check: it does not contact the daemon, so it also passes on the first
# run, before the group change has been applied to a login session.
if command -v docker &>/dev/null && docker compose version &>/dev/null; then
    print_success "Docker $(docker --version | awk '{print $3}' | tr -d ,) with Compose $(docker compose version --short 2>/dev/null || echo v2)"
else
    print_warning "docker compose plugin missing - install it with: sudo pacman -S docker docker-compose docker-buildx"
fi

# ----------------------------------------------------------------------------
# Rootless Podman + Distrobox
# ----------------------------------------------------------------------------
# This is the container setup used by this profile: Distrobox runs rootless on
# Podman, so no Docker-group membership or rootful Podman service is required.
# Podman is daemonless and the local API socket is not needed by Distrobox.
print_status "Configuring rootless Podman and Distrobox..."
pacman_install podman distrobox
if command -v podman >/dev/null 2>&1 && command -v distrobox >/dev/null 2>&1; then
    print_success "Rootless Podman $(podman --version | awk '{print $3}') and Distrobox $(distrobox version 2>/dev/null | head -1) are available"
    if [ "${DOTFILES_CREATE_DISTROBOX:-0}" = "1" ] && [ -x "$DOTFILES_DIR/bootstrap/setup-distrobox.sh" ]; then
        DISTROBOX_BUILD=1 "$DOTFILES_DIR/bootstrap/setup-distrobox.sh"
    else
        print_warning "Kali Distrobox creation skipped (run DOTFILES_CREATE_DISTROBOX=1 ./install.sh to create it)"
    fi
else
    print_warning "Podman/Distrobox setup incomplete"
fi

# ----------------------------------------------------------------------------
# Services
# ----------------------------------------------------------------------------
print_status "Enabling services..."

# User services need a running user session bus; ignore failure (e.g. over ssh)
systemctl --user enable --now pipewire pipewire-pulse wireplumber 2>/dev/null \
    || print_warning "Could not enable user audio services now; they will start on next login"

# MPD user service (playlist_directory is ~/music/playlists, created above)
systemctl --user enable --now mpd 2>/dev/null \
    || print_warning "Could not enable mpd now; it will start on next login"

# zlstatus draws the vxwm bar text. Enable it so it also starts under a display
# manager; xinitrc restarts it once X is up. The unit runs the installed
# ~/.local/bin/zlstatus, which install.sh builds below.
if [ -f "$HOME/.config/systemd/user/zlstatus.service" ]; then
    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable zlstatus.service 2>/dev/null \
        || print_warning "Could not enable zlstatus.service; it will be started by xinitrc"
fi

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
else
    # QEMU/libvirt host: virt-manager/virsh manage VMs (qemu-desktop, libvirt
    # and friends come from packages-native.txt).
    if command -v virsh &>/dev/null; then
        print_status "Setting up QEMU/libvirt host..."
        if ! id -nG "$(id -un)" | grep -qw libvirt; then
            sudo usermod -aG libvirt "$(id -un)"
            print_warning "Added $(id -un) to 'libvirt' group (re-login to use virsh without sudo)"
        fi
        sudo systemctl enable --now libvirtd.service 2>/dev/null \
            || print_warning "Could not enable libvirtd now"
        # Default NAT network. libvirt ships /etc/libvirt/qemu/networks/default.xml,
        # so it is normally already defined; only autostart/start it.
        if ! sudo virsh net-info default &>/dev/null; then
            sudo virsh net-define /etc/libvirt/qemu/networks/default.xml 2>/dev/null || true
        fi
        sudo virsh net-autostart default 2>/dev/null || true
        sudo virsh net-start default 2>/dev/null || true
        print_success "QEMU/libvirt host configured"
    fi
fi

# Btrfs snapshot integration (only meaningful on a btrfs root; this is what
# grub-btrfsd + the snapper timers need to actually run)
if [ "$(findmnt -no FSTYPE / 2>/dev/null)" = "btrfs" ]; then
    if command -v snapper &>/dev/null && [ ! -f /etc/snapper/configs/root ]; then
        sudo snapper -c root create-config / 2>/dev/null \
            || print_warning "Could not create snapper root config"
    fi
    if [ -f /etc/snapper/configs/root ]; then
        sudo systemctl enable --now snapper-timeline.timer snapper-cleanup.timer 2>/dev/null \
            || print_warning "Could not enable snapper timers"
        sudo systemctl enable --now grub-btrfsd.service 2>/dev/null \
            || print_warning "Could not enable grub-btrfsd"
    fi
fi

# Tailscale
sudo systemctl enable --now tailscaled 2>/dev/null \
    || print_warning "Could not enable tailscaled now"

# Use Tailscale's local DNS proxy when Tailscale is enabled. This avoids using
# broken or captive-network DNS advertised by some Wi-Fi DHCP servers while
# keeping MagicDNS names available. zlstatus treats 100.100.100.100 as valid
# DNS only while tailscaled is running.
if command -v tailscale >/dev/null 2>&1; then
    sudo tailscale set --accept-dns=true 2>/dev/null \
        || print_warning "Could not enable Tailscale DNS; run: sudo tailscale set --accept-dns=true"
fi

# Tor
sudo systemctl enable --now tor.service 2>/dev/null \
    || print_warning "Could not enable tor now"

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
for prog in vxwm dmenu st nsxiv zlstatus dmenu-win tmux; do
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
    echo "  6. (QEMU) SPICE clipboard + auto-resize start automatically from ~/.xinitrc"
fi
echo ""
print_status "Backup saved at: $BACKUP_DIR"
print_status "See STOW_STRUCTURE.md for the XDG/Stow layout"
