# Changelog

## Unreleased

- New custom `skippy-xd` window switcher, vendored in `src/skippy-xd` and built by `install.sh` with meson/ninja (Chipmunk2D is vendored under `subprojects/`, so no network is required). `Alt+Tab` / `Alt+Shift+Tab` now open it instead of `dmenu-win`; `Super+w` still opens the searchable `dmenu-win` list. It shows live previews for windows on **all tags**, labels each preview with its tag (`[1]`, `[2]`, ...), keeps `h/j/k/l` navigation, selects with `Return`/`space` and cancels with `Esc` without changing tags. Windows on inactive tags are parked off-screen only while the switcher is open, so previews stay live and the WM keeps managing them normally afterwards; a watchdog resets `override_redirect` if the switcher is killed. Every preview also gets a one-key marker (`a`, `b`, `c`, ..., skipping `h/j/k/l/n/p`; digits after 20 windows) - pressing it jumps straight to that window and its tag. The stock `1/2/3` iconify/shade/close actions are disabled so a stray number key cannot destroy a window. User config is stowed from `config/.config/skippy-xd/skippy-xd.rc`.

- skippy-xd: windows on a tag in vxwm's floating layout are no longer missing from the switcher. Floating mode spreads windows over a virtual canvas that can place them partly or fully outside the root (negative `Y`, or past the right edge). The per-monitor filter used the window centre as-is and dropped anything outside a monitor, so those previews stayed 1x1 and only one window from the tag appeared. The centre is now clamped to the root before choosing a monitor, so every window gets a preview and a quick-jump marker.

- Fresh installs kept losing the custom vxwm bindings. `config.h` is tracked and carries the real configuration, but `config.def.h` was still the generic upstream template, so any build that regenerated `config.h` (a fresh checkout whose timestamps make `make` run `cp config.def.h config.h`) silently dropped the Alt+Tab window chooser, `Alt+\`/`Alt+Shift+\` window cycling, the Arch logo, the audio/brightness keys and the other custom binds. `config.def.h` now mirrors `config.h`; a regenerated config builds and behaves identically. `install.sh` now also reports `dmenu-win` in its build checks and installed-program summary.

- zlstatus: the user unit pointed at `%h/.config/zlstatus/zig-out/bin/zlstatus`, a development path that does not exist on a fresh install, even though `install.sh` installs to `~/.local/bin/zlstatus`. `ExecStart` now uses `~/.local/bin/zlstatus`, `install.sh` enables the unit, and `xinitrc` restarts it once X is running (with a direct-launch fallback when the user bus is unavailable). This also stops the stale development binary from shadowing a rebuild.

- dunst: notifications started at `offset = 10x10`, so their top edge sat behind the 34px vxwm bar. The offset is now `10x44`, which clears the bar on every monitor.

- Docker is now part of the base install. `docker`, `docker-compose` (the Compose **v2 plugin**, so the command is `docker compose`) and `docker-buildx` were added to `bootstrap/packages-native.txt`. `install.sh` installs them as well, enables `docker.service`, adds the user to the `docker` group (with an explicit warning that a re-login is required) and pre-creates `$DOCKER_CONFIG` (`~/.config/docker`) as a real directory - `shell/xdg-env.sh` already keeps Docker out of `~/.docker`, and Docker writes `config.json`, `contexts/`, `buildx/` and `cli-plugins/` there at runtime, so Stow must not own it. The installer's verification is CLI-only (`docker compose version`), so it succeeds before the group change applies. README gained a Docker section covering install, group/relogin behaviour, XDG paths and everyday Compose commands.

- vxpanel: the night light and the per-output software brightness no longer overwrite each other. Both own the CRTC gamma ramp, and `xrandr --output … --brightness` reset it to neutral, so touching *Brightness (software)* (or the `xrandr --brightness` line `startup.sh` wrote) wiped the `redshift` colour filter - and vice versa. The Display page now applies the colour first and then scales each output's ramp by its brightness factor via `XRRGet/SetCrtcGamma` (ctypes), so the two compose per output. `startup.sh` keeps a single `vxpanel --apply-display` line that replays the whole composition at login, and the colour-temperature slider gained a live label (`warm`, `neutral - no warm filter`, …) that makes the direction obvious (lower K = warmer, 6500K = off).

- vxpanel: sliders now remember their values across launches. The night-light temperature and per-output software-brightness sliders were hardcoded to their defaults on start (so `Color temperature` always snapped back to 4500K even though `startup.sh` kept the real value at login). Both now persist to `config.json` and restore on launch; `Reset` returns the temperature to `NIGHT_DEFAULT` (4500K). A note near the slider marks 4500K as the default. Backlight, volume and pointer-speed sliders already restored from live system state, so they were left as-is.

- Comfort/QoL additions, all declared in `bootstrap/packages-native.txt`:
  - `zsh-autosuggestions` - the source line in `.zshrc` was present but commented out, so the feature never loaded. Uncommented; it pairs with the already-live `zsh-syntax-highlighting`.
  - `brightnessctl` was already in the package list but not present on the live system, so the `XF86MonBrightnessUp/Down` binds (`brightnessctl set 5%+/-`) did nothing.
  - `redshift` - `vxpanel`'s Display page auto-detects `redshift`/`gammastep`; with it installed the night-light colour-temperature slider appears and works.
  - `bat` + `fd` - `FZF_DEFAULT_OPTS` already previews with `bat`, so the preview was broken without it; `fd` gives fzf a faster default walker.
  - `eza` + `zoxide` - new shared `~/.config/shell/alias` (sourced by both `bashrc` and `.zshrc`) aliases `ls`/`ll`/`la`/`lt` to eza and enables zoxide's `z`/`zi`. All guarded by `command -v`, so the file is a no-op until the packages are installed.
- `~/.config/shell/alias` added (sourced by `bashrc` and `.zshrc`); documented in the README "Shell configuration" section.

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
- vxwm: an Arch logo (Nerd Font `U+F303`) now sits in the far-left bar slot, before the tag numbers, and left-clicking it opens `vxpanel`. New `ARCH_ICON` switch in `modules.h`; the glyph and the command are `ARCH_ICON_GLYPH` / `archiconcmd` in `config.h`. A short vertical rule is drawn between the logo and the first tag so the icon does not sit right against the numbers; it is sized and spaced by `ARCH_ICON_SEP_W` / `ARCH_ICON_SEP_H` / `ARCH_ICON_SEP_GAP` / `ARCH_ICON_TAG_GAP` (set the width to 0 to drop it), and `ARCH_ICON_SEP_H` matches the height of the `|` the window title shows between `OC` and the title text so the rule reads as the same separator. The logo, gaps and rule are all painted in the normal scheme so the slot matches the rest of the bar. Icon and rule share one `ClkArchIcon` click region, so the rest of the status keeps its existing `ClkStatusText` bind (the network menu). No `zlstatus` change: the bar is drawn by vxwm.

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
