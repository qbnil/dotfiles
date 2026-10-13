# Changelog

## Unreleased

- Xresources is now a single generated file: `~/.config/x11/Xresources` is rebuilt by the new `~/.local/bin/xresources-gen` (static Xft/cursor block + the current pywal palette). This removes the duplicate `~/.Xresources` - pywal's palette previously reached the session through two symlinks into `~/.cache/wal/colors.Xresources` - and makes the static Xft/cursor settings actually apply (the old tracked `config/.config/x11/Xresources` was shadowed by the palette symlink). `Xft.dpi` is intentionally **not** set, so fonts keep using the real screen DPI instead of a hard-coded 96.
  - `xrdb-reload` now runs `xresources-gen`, then merges `~/.config/x11/Xresources`, `~/.cache/wal/xrdb_extra` and `~/.config/vxpanel/Xresources` (vxpanel last). `xinitrc`, `rvx` and `pywal16` are unchanged callers.
  - `config/.config/x11/Xresources` is deleted and git-ignored: the live file must never be tracked/stowed, or pywal would write straight into the repository through the Stow symlink.
  - `vxpanel` always writes its cursor/DPI to `~/.config/vxpanel/Xresources` (no longer probes `~/.Xresources`).

- Wallpaper now appears immediately after `wallpapermenu` (or vxpanel). pywal sets the wallpaper with `feh`, but `feh` is launched in the background and needs ~180 ms to decode a 4K image, so the hook's repaint fired against the *old* pixmap and `xcompmgr` kept showing the previous wallpaper until some unrelated event (keypress, tag switch, launching an app). Callers now pass `wal -n` (skip pywal's own setter) and `pywal16` sets the wallpaper itself with the tiny `xwallpaper` binary (synchronous, also used at login) *before* forcing a single `xrefresh`. `vxpanel`'s `after()` fallback also calls `xrdb-reload` now instead of rebuilding the merge itself.

- vxwm: features borrowed from [chadwm](https://github.com/siduck/chadwm), as a new `modules/extras` module with its own switches in `modules.h`:
  - `EXTRA_LAYOUTS`: bottom stack `TTT`, centered master `|M|` and deck `[D]`, appended after the existing four layouts so `layouts[0..3]` keep their meaning. All of them honour `gappx`, `mfact` and `nmaster`.
  - `LAYOUT_CYCLE`: `Super+Ctrl+,` / `Super+Ctrl+.` steps through the tiling layouts (floating is skipped; it keeps its own bind).
  - `SHIFTVIEW`: `Super+Left` / `Super+Right` move to the previous/next tag and wrap around.
  - `MOVESTACK`: `Super+Ctrl+j` / `Super+Ctrl+k` swap the focused tiled window up/down the stack in any layout (`movedir` only works in `tile`).
  - Brightness keys (`XF86MonBrightnessUp/Down`) call `brightnessctl set 5%+/5%-`; `brightnessctl` added to `bootstrap/packages-native.txt`.
- vxwm fix: `up_vol`, `down_vol` and `mute_vol` were not NULL-terminated, but `spawn()` hands them to `execvp()`, which reads until NULL (undefined behaviour). They are terminated now.
- Cheatsheet (`Super+/`) lists the new binds.

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
