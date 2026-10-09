# Changelog

## Unreleased

- Cursor theme and pywal colours now survive reboot, `rvx` and wallpaper changes:
  - `vxpanel` always writes its cursor/DPI to `~/.config/vxpanel/Xresources` instead of depending on `~/.Xresources` being a pywal symlink (which `install.sh` removes).
  - New `~/.local/bin/xrdb-reload` merges the Xresources sources in one place (`x11/Xresources`, the pywal palette, `xrdb_extra`, then vxpanel last) and is now called by `xinitrc`, `rvx` and `pywal16`, so the cursor theme is never reset by a wallpaper change or WM restart.
  - `xinitrc` now runs `~/.config/vxpanel/startup.sh` (backgrounded, no-op until it exists), so every setting vxpanel saves there also persists across reboots.
- Removed committed `local/.local/bin/__pycache__` and added `local/.stow-local-ignore` so Stow never deploys Python bytecode.

- Added `~/.config/user-dirs.dirs` with lowercase paths (`XDG_DOWNLOAD_DIR=$HOME/downloads`, ...). Apps only honour these standard variables, so browser downloads and file dialogs now use `~/downloads`.
- Added `~/.config/user-dirs.conf` (`enabled=False`) so `xdg-user-dirs-update` never recreates `~/Downloads`.
- `shell/xdg-env.sh` now sources `user-dirs.dirs` and exports the `XDG_*_DIR` variables, replacing the unused `DOWNLOADS_DIR`-style ones.
- `~/.local/bin` (and `$CARGO_HOME/bin`) are added to `PATH` once, in `xdg-env.sh`, with de-duplication; redundant PATH edits were removed from `xinitrc` and `.zshrc`.
- `install.sh` creates the directories from `XDG_*_DIR` and migrates existing `~/Downloads`, `~/Pictures`, ... into the lowercase ones without overwriting files.
- yazi: added lowercase folder icons.

## 2026-10-07 — XDG/Stow cleanup

- Reduced the Stow model to two packages: `config` -> `~/.config` and `local` -> `~/.local`.
- Moved custom/vendored program sources from `config/.config/*` to `src/`.
- Removed the empty `~/.bash_logout` deployment.
- Kept only the unavoidable `.bashrc`, `.bash_profile`, `.zshenv` and `.xinitrc` compatibility links in `$HOME`.
- Added explicit lowercase XDG user directories: `desktop`, `documents`, `downloads`, `music`, `pictures`, `public`, `templates`, `videos`.
- Moved wallpaper/screenshots paths to `~/pictures`.
- Removed the runtime `~/.Xresources` symlink; Xresources is now managed at `~/.config/x11/Xresources`.
- Custom programs now build directly from `src/` and install to `~/.local/bin`, except setuid `slock`.
- Fixed the Arch X11 include/library paths in `src/slock/config.mk`.
- Rewrote Stow documentation and dry-run tooling to match the actual repository.

## Earlier history

The repository previously went through several Stow reorganizations. Older entries described intermediate layouts (`bin/`, `share/`, `wallpapers/`, and vendored sources under `~/.config`). Those layouts are intentionally superseded by the structure documented in `STOW_STRUCTURE.md`.
