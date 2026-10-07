# Changelog

## Unreleased

- Removed `xdg-user-dirs` and `~/.config/user-dirs.dirs`; lowercase home directories are now defined only by `~/.config/shell/xdg-env.sh`.
- `install.sh` creates those directories from the exported path variables instead of invoking `xdg-user-dirs-update`.

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
