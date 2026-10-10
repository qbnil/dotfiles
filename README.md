# Arch Linux Dotfiles

XDG-first Arch Linux configuration for a lightweight X11 desktop built around vxwm, managed with GNU Stow.

## Architecture

The repository intentionally separates **configuration**, **user data**, and **source code**:

```text
.
├── config/          # Stow package -> ~/.config
├── local/           # Stow package -> ~/.local
├── src/             # custom/vendored source code; never stowed
├── systemd/         # /etc configuration installed separately
├── bootstrap/       # pacman/yay package lists + install-time config templates
├── install.sh
└── test-stow.sh
```

This avoids the old pattern where complete source trees such as vxwm and dmenu were exposed as `~/.config/vxwm` and mixed with real application configuration.

## Home directory layout

After installation:

```text
~/.config/       -> dotfiles/config/.config/
~/.local/bin/    -> dotfiles/local/.local/bin/
~/.local/share/  -> dotfiles/local/.local/share/

~/.bashrc        -> ~/.config/bash/bashrc
~/.bash_profile  -> ~/.config/bash/bash_profile
~/.zshenv        -> ~/.config/zsh/zshenv
~/.xinitrc       -> ~/.config/x11/xinitrc

~/desktop
~/documents
~/downloads
~/music
~/pictures
~/public
~/templates
~/videos
```

The home directories are real lowercase directories created by `install.sh`. Their canonical paths are defined once, in `~/.config/user-dirs.dirs`, and they are not Stow links, so personal files placed there do not become part of the dotfiles repository.

`user-dirs.dirs` is the file browsers, GTK/Qt file dialogs and `xdg-user-dir` actually read, which is what makes downloads land in `~/downloads`. `shell/xdg-env.sh` sources it and exports the `XDG_*_DIR` variables, so the shell never keeps a second copy. `user-dirs.conf` sets `enabled=False` so `xdg-user-dirs-update` cannot recreate `~/Downloads` and friends.

The four dotfiles in `$HOME` are compatibility entrypoints required by Bash, Zsh and `startx`; their actual contents live in `~/.config`.

There is no `~/.Xresources`. Static X settings live in the tracked `~/.config/x11/Xresources`; pywal's palette is merged from `~/.cache/wal/colors.Xresources` at login and on every wallpaper change.

## Installation

This repository targets Arch Linux and expects to be run as a normal user:

```bash
git clone https://github.com/qbnil/dotfiles.git ~/dotfiles
cd ~/dotfiles
chmod +x install.sh
./install.sh
```

The installer:

1. Checks that the system is Arch Linux and that the user can use `sudo`.
2. Detects virtual machines and avoids hardware-specific NVIDIA setup there.
3. Installs the required native/AUR packages.
4. Creates an automatic timestamped backup of existing configuration.
5. Stows `config` and `local` into `$HOME`.
6. Creates lowercase user directories from the paths defined by `xdg-env.sh`.
7. Creates only the required compatibility links in `$HOME`.
8. Builds the programs in `src/` into `~/.local/bin` (with the setuid `slock` installed to `/usr/local/bin`).
9. Installs the repository's system-level files under `/etc` where applicable.

### Preview Stow changes

```bash
./test-stow.sh
```

### Manual Stow operations

```bash
cd ~/dotfiles
stow config local       # deploy
stow -R config local    # restow
stow -D config local    # remove links
```

## Custom programs

The following source trees live under `src/` and are rebuilt on a new machine:

- `src/vxwm`
- `src/dmenu`
- `src/st-terminal`
- `src/nsxiv`
- `src/slock`
- `src/zlstatus`

Normal programs install to `~/.local/bin`; `slock` is installed to `/usr/local/bin` because it requires setuid permissions.

To rebuild vxwm manually:

```bash
cd ~/dotfiles/src/vxwm
make clean
make -j"$(nproc)"
make PREFIX="$HOME/.local" install
```

For the rest, use the same pattern with their corresponding source directory. `zlstatus` is built with Zig:

```bash
cd ~/dotfiles/src/zlstatus
zig build -Dmode=X11 -Doptimize=ReleaseSmall
install -Dm755 zig-out/bin/zlstatus ~/.local/bin/zlstatus
```

## Window management features (vxwm)

`src/vxwm` carries a set of hand-rolled window management features on top of upstream dwm:

| Feature | Keys | Notes |
|---|---|---|
| Directional focus | `Super` + `h/j/k/l` | Moves focus by screen geometry via `focusdir`. |
| **Directional swap** | `Super+Shift` + `h/j/k/l` | Swaps the focused window with the nearest visible window left/down/up/right. Works in **every** layout (tile, monocle, grid, bstack, centeredmaster, deck) and with floating windows. |
| Move floating window | `Alt+Shift` + `h/j/k/l` | Keyboard move (50 px steps). |
| Resize floating window | `Alt+Ctrl+Shift` + `h/j/k/l` | Keyboard resize (50 px steps). |
| Toggle floating | `Alt+Shift+Space` | `togglefloating`. |
| Enhanced toggle floating | `Alt+e` | `enhancedtogglefloating`. |
| Monocle position indicator | — | The bar shows `[i/n]` (e.g. `[3/5]`) — the focused window's position among the visible windows — and updates immediately on every focus change. |

Design rules behind these binds:

- **Super keeps focus and layout, Super+Shift swaps, Alt owns everything floating.**
- Mouse binds (`Super+Drag` move/resize, `Super+Middle` toggle floating) intentionally stay on Super.
- `movestack` (`Mod+Ctrl+J/K`, tiled-only stack swap) was removed — `swapdir` superseded it; it is disabled with `MOVESTACK 0` in `modules.h`/`modules.def.h`.

How it is implemented:

- `vxwm.c` — `monocle_symbol(Monitor*)` builds the `[i/n]` string; `monocle()` renders it and, crucially, `drawbar()` recomputes it on every redraw. Switching focus in monocle never triggers `arrange()`, which is exactly why the old symbol got stuck.
- `modules/directionalmove/directionalmove.c` — `swapdir()` replaced the tile-only `movedir()`. Tiled windows are exchanged in the tag's client list and the active layout re-arranges them; floating windows exchange their on-screen geometry (position *and* size) via `XMoveResizeWindow`.
- `modules/moveresizekbd/moveresizekbd.c` — `moveresize()` now returns unless the selected window is floating; the old silent fallback that also moved tiled windows is gone.
- `config.h` — bindings live behind the existing module flags (`MOVE_RESIZE_WITH_KEYBOARD`, `DIRECTIONAL_MOVE`, `ENHANCED_TOGGLE_FLOATING`); `ALTERNATE_MODKEY` is `Mod1Mask` (Alt).

Rebuild (as above), then restart the session with `rvx` to pick up the new binary.

## Shell configuration

`~/.config/shell/xdg-env.sh` is the central environment file. It sets:

- `XDG_CONFIG_HOME`
- `XDG_DATA_HOME`
- `XDG_CACHE_HOME`
- `XDG_STATE_HOME`
- `ZDOTDIR`
- editor/browser/terminal defaults
- application-specific XDG locations
- the XDG user directories (from `user-dirs.dirs`)
- `PATH`: `~/.local/bin` and `$CARGO_HOME/bin`, added once and never duplicated

Secrets belong in `~/.config/shell/secrets.sh`; this file is ignored by git.

## XDG user directories

`~/.config/user-dirs.dirs` deliberately defines the user directories in lowercase. The standard set is:

```text
~/desktop
~/documents
~/downloads
~/music
~/pictures
~/public
~/templates
~/videos
```

`install.sh` also moves anything left in the capitalised defaults (`~/Downloads`, `~/Pictures`, ...) into the lowercase directories without overwriting existing files.

Wallpapers and screenshots are kept under `~/pictures/` rather than creating additional mixed-case directories or putting personal media into the dotfiles repository.

## Colors, cursor and X resources

There is intentionally **no `~/.Xresources`**: pywal owns `~/.cache/wal/colors.Xresources`,
and `install.sh` removes any legacy `~/.Xresources` on purpose. Static X settings live in
the tracked `~/.config/x11/Xresources`.

X resources are merged in one canonical order, implemented **once** in
`local/.local/bin/xrdb-reload` (deployed to `~/.local/bin/xrdb-reload`). Later files win:

```text
1. ~/.config/x11/Xresources          static Xft (DPI, antialias, hinting) + fallback cursor
2. ~/.cache/wal/colors.Xresources    pywal palette
3. ~/.cache/wal/xrdb_extra           dwm.color0 / dwm.color6 for vxwm
4. ~/.config/vxpanel/Xresources      vxpanel's cursor theme / size  (merged LAST)
```

`xrdb-reload` first runs `wal-xrdb-extra` (which regenerates `xrdb_extra` from the palette),
then merges all four sources. It is called by:

- `xinitrc` at login, before `exec vxwm`;
- `pywal16` (the `wal -o` hook) after every wallpaper change;
- `rvx` in `reapply_colors()` on every WM restart.

Because vxpanel's file is merged last, the cursor chosen in vxpanel survives a reboot, a
wallpaper change and an `rvx` reload. vxpanel always writes that file to
`~/.config/vxpanel/Xresources`; its other persisted settings go to
`~/.config/vxpanel/startup.sh`, which `xinitrc` runs at login.

Cursor themes live in `local/.local/share/honkai-star-rail-cursors/`. Since libXcursor only
searches `~/.local/share/icons`, `~/.icons`, `/usr/share/icons` and `/usr/share/pixmaps`,
`local/.local/share/icons/<theme>` contains relative symlinks into the collection.
`install.sh` pre-creates `~/.local/share/icons` as a real directory so Stow links the themes
into it instead of folding the whole directory into a symlink back to the repo.

`XCURSOR_THEME` is deliberately **not** exported anywhere: the environment always wins over
`Xcursor.theme`, so exporting it would make the session ignore xrdb and defeat this pipeline.

To verify the live state:

```sh
~/.local/bin/xrdb-reload
xrdb -query | grep -Ei 'Xcursor|Xft|dwm\.color'
cat ~/.config/vxpanel/startup.sh
```

## Backups and migration

`install.sh` creates:

```text
~/dotfiles-backup-YYYYMMDD-HHMMSS/
```

Existing `.config`, `.local/bin`, `.local/share` and home-level compatibility files are preserved there before conflicting Stow targets are replaced.

If an old `~/.Xresources` exists, the installer moves it into the backup because the new configuration uses `~/.config/x11/Xresources`.

## Maintenance

Update the repository and restow:

```bash
cd ~/dotfiles
git pull
stow -R config local
```

Then rebuild custom programs if their source changed:

```bash
./install.sh
```

Check the resulting Stow plan at any time with:

```bash
./test-stow.sh
```

## Packages

Package lists are kept in `bootstrap/packages-native.txt` and `bootstrap/packages-aur.txt`.

## NVIDIA suspend fix

The repository also contains an optional NVIDIA suspend/resume fix under `systemd/`. The installer skips NVIDIA-specific system files in VMs.

The helper can be run after installation when needed:

```bash
~/.local/bin/fix-nvidia-suspend
```

## Security

Do not commit secrets, private keys or credentials. The repository's `.gitignore` covers common secret and build-artifact patterns.
