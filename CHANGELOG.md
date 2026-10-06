## 2026-10-06 — Stow cleanup

- **Removed** monolithic `config/` package (it duplicated bash/dunst/git/nvim/shell/tmux/x11/zsh and broke `stow`).
- **Completed** `zsh/` package: `.zshenv` at package root, full `.zshrc` + `.zprofile` under `.config/zsh/`.
- **Completed** `x11/` package: `.xinitrc` at package root (Stow → `~/.xinitrc`).
- **Split** unique apps into their own packages: `feh`, `flameshot`, `gtk`, `nvidia`, `wal`.
- **Dropped** wal-generated `Xresources`, MPD `database`, and other runtime state from the tree.
- **wallpapers/** now targets `~/.local/share/wallpapers/`.
- **Added** `.gitignore` for secrets, build artifacts, MPD state.
- Updated `install.sh` / `test-stow.sh` package lists and docs.

# Dotfiles Reorganization Changelog

## Changes Made

### 1. Improved Stow Installation Check
- **Before**: Stow was installed along with other packages, making it hard to catch installation failures early
- **After**: Stow installation is checked first and separately, with immediate failure if unavailable
- Script now verifies `stow` command is available before proceeding

### 2. Custom Program Compilation
- **Before**: Programs were built with `make` and installed to `~/.local/bin/`
- **After**: All custom programs are now compiled with `sudo make clean install` and installed to `/usr/local/bin/`
- This includes:
  - vxwm (window manager)
  - dmenu (launcher)
  - st (terminal)
  - slock (screen locker)
  - nsxiv (image viewer)
  - zlstatus (status bar)

### 3. Systemd Files Handling
- **Before**: Unclear handling of systemd files
- **After**: Systemd files are explicitly NOT stowed into `$HOME`
- Files in `systemd/etc/` are copied to system directories:
  - `systemd/etc/modprobe.d/*` → `/etc/modprobe.d/`
  - `systemd/etc/systemd/system/*` → `/etc/systemd/system/`
- Only installed on real hardware (skipped in VMs)

### 4. Clean Binary Management
- **Before**: Old binaries could conflict with new builds
- **After**: Old binaries are removed before building:
  - Removes from `/usr/local/bin/` (from previous sudo installs)
  - Removes from `~/.local/bin/` (from previous user installs)

### 5. Improved Package List
- **Before**: Included packages that shouldn't be stowed (vxwm, dmenu, picom)
- **After**: Clean package list with only stowable packages:
  - bash, bin, config, dunst, git, mpd, nvim, share, shell, tmux, wallpapers, x11, yazi, zsh
  - `systemd` package is explicitly excluded from stow

### 6. Enhanced Output and Feedback
- Added clear summary of symlinks created
- Shows which programs were successfully installed to `/usr/local/bin/`
- Better error reporting for failed builds
- References new STOW_STRUCTURE.md documentation

### 7. Library Check
- **Before**: Only checked vxwm, dmenu, st, zlstatus
- **After**: Also checks nsxiv for unresolved library dependencies

## File Structure

### Stow Packages (symlinked to $HOME)
```
bash/          → ~/.bashrc, ~/.bash_profile, ~/.config/bash/
bin/           → ~/.local/bin/
config/        → ~/.config/
dunst/         → ~/.config/dunst/
git/           → ~/.config/git/
mpd/           → ~/.config/mpd/
nvim/          → ~/.config/nvim/
share/         → ~/.local/share/
shell/         → ~/.config/shell/
tmux/          → ~/.config/tmux/
wallpapers/    → ~/.local/share/wallpapers/
x11/           → ~/.xinitrc, ~/.config/x11/
yazi/          → ~/.config/yazi/
zsh/           → ~/.config/zsh/
```

### Not Stowed
```
systemd/       → Installed to system directories (/etc/)
bootstrap/     → Installation resources
```

## Home Directory After Installation

Your home directory will be clean with organized symlinks:

```
~/
├── .bashrc                    → dotfiles/bash/.bashrc
├── .bash_profile              → dotfiles/bash/.bash_profile
├── .xinitrc                   → dotfiles/x11/.xinitrc
├── .zshenv                    → dotfiles/zsh/.zshenv (if exists)
├── .config/
│   ├── bash/                  → dotfiles/bash/.config/bash/
│   ├── dunst/                 → dotfiles/dunst/.config/dunst/
│   ├── git/                   → dotfiles/git/.config/git/
│   ├── mpd/                   → dotfiles/mpd/.config/mpd/
│   ├── nvim/                  → dotfiles/nvim/.config/nvim/
│   ├── shell/                 → dotfiles/shell/.config/shell/
│   ├── tmux/                  → dotfiles/tmux/.config/tmux/
│   ├── x11/                   → dotfiles/x11/.config/x11/
│   ├── yazi/                  → dotfiles/yazi/.config/yazi/
│   └── zsh/                   → dotfiles/zsh/.config/zsh/
└── .local/
    ├── bin/                   → dotfiles/bin/.local/bin/
    └── share/                 → dotfiles/share/.local/share/
```

## Testing

Run `./test-stow.sh` to see what symlinks would be created without actually installing anything.

## Installation

Run `./install.sh` to:
1. Install GNU Stow (if not already installed)
2. Install all required packages
3. Compile custom programs with `sudo make clean install`
4. Create all symlinks with Stow
5. Install systemd files to system directories
6. Set up services

## Documentation

- `STOW_STRUCTURE.md` - Detailed explanation of the Stow directory structure
- `README.md` - General dotfiles documentation
- `OVERVIEW.md` - Overview of the dotfiles configuration
