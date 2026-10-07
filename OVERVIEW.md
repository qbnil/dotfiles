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
- `config/` - everything under `~/.config` (bash, zsh, x11, shell, nvim, tmux, git, dunst, mpd, yazi, wal, …) plus the vendored sources
- `bin/` - Personal utility scripts (`~/.local/bin`)
- `share/` - Cursors (`~/.local/share`)
- `wallpapers/` - Wallpapers (`~/.local/share/wallpapers`)
- Home-level files (`~/.xinitrc`, `~/.zshenv`, `~/.bashrc`, …) are symlinked by `install.sh` to their copies in `~/.config`

### Bootstrap
- `packages-native.txt` - 148 native packages
- `packages-aur.txt` - 13 AUR packages

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
