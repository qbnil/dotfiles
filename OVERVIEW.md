# Arch Linux Dotfiles

An XDG-first Arch Linux desktop configuration managed with GNU Stow.

## Design

- `config/` is the only package containing application configuration and is stowed to `~/.config`.
- `local/` owns user executables and persistent XDG data under `~/.local`.
- `src/` contains vendored/custom program sources and is **never** stowed into `$HOME`.
- Standard XDG user directories are explicitly lowercase (`~/downloads`, `~/pictures`, etc.), defined in `user-dirs.dirs`.
- Only the unavoidable compatibility entrypoints remain directly in `$HOME`: `.bashrc`, `.bash_profile`, `.zshenv`, `.xinitrc`.
- `~/.Xresources` is gone; Xresources is kept under `~/.config/x11/`.

## Main components

- vxwm + zlstatus
- st
- dmenu
- nsxiv
- slock
- zsh + bash
- neovim
- tmux
- yazi
- mpd/rmpc
- dunst
- pywal16

## Install

```bash
git clone https://github.com/qbnil/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
```

For the exact deployment model, see [`STOW_STRUCTURE.md`](STOW_STRUCTURE.md). For the complete setup and troubleshooting guide, see [`README.md`](README.md).
