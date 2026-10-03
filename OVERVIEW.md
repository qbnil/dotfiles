# Arch Linux Dotfiles

Complete Arch Linux configuration managed with GNU Stow, ready to replicate my entire setup on a fresh system.

## Quick Start

```bash
git clone https://github.com/yourusername/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
```

## What's Included

### Custom Programs (with YOUR modifications)
- **vxwm**: Custom tiling window manager with your keybindings and modules
- **zlstatus**: Zig-based status bar with your customizations
- **dmenu**: Application launcher with your config
- **st-terminal**: Simple terminal with your patches and config
- **slock**: Screen locker with your settings

All include your actual source modifications, not just upstream code.

### Stow Packages
- `bash/` - Bash configuration
- `shell/` - Common shell environment (XDG paths, no secrets)
- `zsh/` - Zsh with custom prompt and keybindings
- `x11/` - X11 configuration and xinitrc
- `nvim/` - Neovim configuration
- `tmux/` - Tmux configuration
- `git/` - Git configuration
- `dunst/` - Notification daemon
- `mpd/` - Music Player Daemon
- `yazi/` - File manager
- `btop/` - System monitor
- `scripts/` - Personal utility scripts

### Bootstrap
- `packages-native.txt` - 148 native packages
- `packages-aur.txt` - 13 AUR packages
- `install.sh` - Automated installation script

## Security

API keys and secrets are handled securely:
- `secrets.sh.example` template provided
- Real `secrets.sh` is gitignored
- `xdg-env.sh` sources secrets automatically
- Never commits credentials

## Installation

The `install.sh` script:
1. Installs all packages (native + AUR)
2. Creates XDG directories
3. Backs up existing configs
4. Deploys all stow packages
5. Builds custom programs (vxwm, dmenu, st, slock, zlstatus)
6. Sets up systemd services

See full documentation in the comprehensive README.

## Repository Size

~215MB total (includes all custom program source code with your modifications)
