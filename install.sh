#!/usr/bin/env bash
# Dotfiles installation script for Arch Linux
# Run this script on a fresh Arch system to replicate the setup

set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/dotfiles-backup-$(date +%Y%m%d-%H%M%S)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}==>${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}!${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Check if running on Arch Linux
if [ ! -f /etc/arch-release ]; then
    print_error "This script is designed for Arch Linux"
    exit 1
fi

print_status "Starting dotfiles installation for Arch Linux"

# Update system
print_status "Updating system packages..."
sudo pacman -Syu --noconfirm

# Install native packages
print_status "Installing native packages from pacman..."
if [ -f "$DOTFILES_DIR/bootstrap/packages-native.txt" ]; then
    sudo pacman -S --needed --noconfirm - < "$DOTFILES_DIR/bootstrap/packages-native.txt" || {
        print_warning "Some native packages failed to install, continuing..."
    }
    print_success "Native packages installed"
else
    print_warning "packages-native.txt not found, skipping native package installation"
fi

# Install yay if not present
if ! command -v yay &> /dev/null; then
    print_status "Installing yay AUR helper..."
    cd /tmp
    git clone https://aur.archlinux.org/yay-bin.git
    cd yay-bin
    makepkg -si --noconfirm
    cd "$DOTFILES_DIR"
    print_success "yay installed"
fi

# Install AUR packages
print_status "Installing AUR packages..."
if [ -f "$DOTFILES_DIR/bootstrap/packages-aur.txt" ]; then
    yay -S --needed --noconfirm - < "$DOTFILES_DIR/bootstrap/packages-aur.txt" || {
        print_warning "Some AUR packages failed to install, continuing..."
    }
    print_success "AUR packages installed"
else
    print_warning "packages-aur.txt not found, skipping AUR package installation"
fi

# Create necessary directories
print_status "Creating XDG directories..."
mkdir -p "$HOME"/.config "$HOME"/.local/{bin,share,state} "$HOME"/.cache
print_success "XDG directories created"

# Backup existing configurations
if [ -d "$HOME/.config" ] && [ "$(ls -A "$HOME/.config" 2>/dev/null)" ]; then
    print_status "Backing up existing configurations to $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
    [ -d "$HOME/.config" ] && cp -a "$HOME/.config" "$BACKUP_DIR/" 2>/dev/null || true
    [ -d "$HOME/.local/bin" ] && cp -a "$HOME/.local/bin" "$BACKUP_DIR/" 2>/dev/null || true
    [ -d "$HOME/.local/share" ] && cp -a "$HOME/.local/share" "$BACKUP_DIR/" 2>/dev/null || true
    [ -f "$HOME/.bashrc" ] && cp "$HOME/.bashrc" "$BACKUP_DIR/" 2>/dev/null || true
    [ -f "$HOME/.bash_profile" ] && cp "$HOME/.bash_profile" "$BACKUP_DIR/" 2>/dev/null || true
    [ -f "$HOME/.xinitrc" ] && cp "$HOME/.xinitrc" "$BACKUP_DIR/" 2>/dev/null || true
    print_success "Backup created at $BACKUP_DIR"
fi

# Stow all packages
print_status "Deploying dotfiles with GNU Stow..."
cd "$DOTFILES_DIR"

# List of packages to stow
PACKAGES=(
    shell
    x11
    zsh
    bash
    nvim
    tmux
    git
    dunst
    mpd
    yazi
    btop
    scripts
    vxwm
    dmenu
    st
    slock
    zlstatus
)

for package in "${PACKAGES[@]}"; do
    if [ -d "$package" ]; then
        print_status "Stowing $package..."
        stow --target="$HOME" --restow --verbose=1 "$package" 2>&1 | grep -v "LINK:" || true
        print_success "$package stowed"
    fi
done

# Create secrets file template if it doesn't exist
if [ ! -f "$HOME/.config/shell/secrets.sh" ]; then
    print_status "Creating secrets template..."
    cat > "$HOME/.config/shell/secrets.sh" <<'EOSECRETS'
# Secrets and API keys - DO NOT COMMIT THIS FILE
# This file is sourced by xdg-env.sh

# Tailscale
export TAILSCALE_AUTHKEY=""
export TAILSCALE_API_KEY=""

# Gemini
export GEMINI_API_KEY=""

# Claude/Anthropic
export ANTHROPIC_AUTH_TOKEN=""

# OpenRouter
export OPENROUTER_API_KEY=""

# Add your other API keys and secrets here
EOSECRETS
    chmod 600 "$HOME/.config/shell/secrets.sh"
    print_success "Secrets template created at ~/.config/shell/secrets.sh"
    print_warning "Please edit ~/.config/shell/secrets.sh and add your API keys"
fi

# Build suckless tools and custom programs
print_status "Building custom programs..."

if [ -d "$HOME/.local/share/vxwm" ]; then
    print_status "Building vxwm..."
    cd "$HOME/.local/share/vxwm"
    make clean && make && install -Dm755 vxwm "$HOME/.local/bin/vxwm"
    print_success "vxwm built and installed"
fi

if [ -d "$HOME/.local/share/dmenu" ]; then
    print_status "Building dmenu..."
    cd "$HOME/.local/share/dmenu"
    make clean && make && install -Dm755 dmenu stest "$HOME/.local/bin/"
    print_success "dmenu built and installed"
fi

if [ -d "$HOME/.local/share/st-terminal" ]; then
    print_status "Building st..."
    cd "$HOME/.local/share/st-terminal"
    make clean && make && install -Dm755 st "$HOME/.local/bin/st"
    print_success "st built and installed"
fi

if [ -d "$HOME/.local/share/slock" ]; then
    print_status "Building slock..."
    cd "$HOME/.local/share/slock"
    make clean && make && sudo install -Dm4755 slock /usr/local/bin/slock
    print_success "slock built and installed"
fi

if [ -d "$HOME/.local/share/zlstatus" ]; then
    print_status "Building zlstatus..."
    cd "$HOME/.local/share/zlstatus"
    zig build && install -Dm755 zig-out/bin/zlstatus "$HOME/.local/bin/zlstatus"
    print_success "zlstatus built and installed"
fi

cd "$DOTFILES_DIR"

# Set up ZDOTDIR for zsh
if ! grep -q "ZDOTDIR" "$HOME/.zshenv" 2>/dev/null; then
    print_status "Setting up ZDOTDIR..."
    echo 'export ZDOTDIR="$HOME/.config/zsh"' > "$HOME/.zshenv"
    print_success "ZDOTDIR configured"
fi

# Enable zram if zram-generator is installed
if command -v zramctl &> /dev/null && [ -f /usr/lib/systemd/system-generators/zram-generator ]; then
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

# Enable systemd services
print_status "Enabling systemd services..."
systemctl --user enable --now pipewire pipewire-pulse wireplumber 2>/dev/null || true
sudo systemctl enable --now NetworkManager 2>/dev/null || true
print_success "Services enabled"

print_success "Dotfiles installation complete!"
echo ""
print_warning "Next steps:"
echo "  1. Edit ~/.config/shell/secrets.sh and add your API keys"
echo "  2. Review ~/.config/shell/xdg-env.sh for environment variables"
echo "  3. Log out and log back in to apply all changes"
echo "  4. Run 'startx' to start the X session with vxwm"
echo ""
print_status "Backup saved at: $BACKUP_DIR"
