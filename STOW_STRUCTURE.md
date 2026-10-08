# Stow & XDG structure

The repository follows one simple rule: **configuration is data, build sources are not home-directory data**.
GNU Stow only deploys the two packages below.

```text
~/dotfiles/
├── config/                 # Stow package -> ~/.config/
│   └── .config/
│       ├── bash/
│       ├── zsh/
│       ├── x11/
│       ├── shell/
│       ├── user-dirs.dirs
│       ├── user-dirs.conf
│       ├── nvim/
│       ├── tmux/
│       ├── git/
│       ├── yazi/
│       ├── dunst/
│       ├── mpd/
│       └── ...
├── local/                  # Stow package -> ~/.local/
│   └── .local/
│       ├── bin/
│       └── share/
│           ├── honkai-star-rail-cursors/   # cursor theme collection
│           └── icons/                      # relative symlinks to usable themes
├── src/                    # build sources; never stowed
│   ├── vxwm/
│   ├── dmenu/
│   ├── st-terminal/
│   ├── nsxiv/
│   ├── slock/
│   └── zlstatus/
├── systemd/                # copied to /etc by install.sh
└── bootstrap/              # package lists
```

## What appears in `$HOME`

The intended result is deliberately boring:

```text
~
├── .bashrc          -> ~/.config/bash/bashrc
├── .bash_profile    -> ~/.config/bash/bash_profile
├── .zshenv          -> ~/.config/zsh/zshenv
├── .xinitrc         -> ~/.config/x11/xinitrc
├── .config/         -> dotfiles/config/.config/*
├── .local/          -> dotfiles/local/.local/*
├── desktop/
├── documents/
├── downloads/
├── music/
├── pictures/
├── public/
├── templates/
└── videos/
```

`~/.bashrc`, `~/.bash_profile`, `~/.zshenv` and `~/.xinitrc` are compatibility entrypoints required by their respective programs. Their actual configuration remains under `~/.config`.

There is intentionally **no `~/.Xresources`**. The tracked Xresources file is `~/.config/x11/Xresources`; pywal updates that XDG path directly.

## Lowercase XDG directories

`config/.config/user-dirs.dirs` is the single source of truth for the lowercase user directories:

- `~/desktop`
- `~/documents`
- `~/downloads`
- `~/music`
- `~/pictures`
- `~/public`
- `~/templates`
- `~/videos`

`shell/xdg-env.sh` sources that file and exports `XDG_DOWNLOAD_DIR` and friends; `install.sh` creates the directories. `user-dirs.conf` (`enabled=False`) stops `xdg-user-dirs-update` from regenerating the capitalised defaults.

## Cursor themes

The cursor theme collection lives in `local/.local/share/honkai-star-rail-cursors/`, but
**libXcursor does not search that directory**. Its search path is:

```text
~/.local/share/icons  ->  ~/.icons  ->  /usr/share/icons  ->  /usr/share/pixmaps
```

Without a link in the right place, a theme like `phainon` silently falls back to
the default theme, and vxpanel cannot even list it.

`local/.local/share/icons/<theme>` therefore contains relative symlinks to each
usable Xcursor theme in the collection. Stow deploys them into
`~/.local/share/icons/` - the first directory Xcursor searches - so the theme
selected via `Xcursor.theme` (vxpanel merges it into the X resource database),
GTK or `XCURSOR_THEME` actually resolves.

`install.sh` pre-creates `~/.local/share/icons` as a real directory before
stowing, so Stow links the themes *into* it instead of folding the whole
directory into a symlink back to the repo (which would make anything writing to
`~/.local/share/icons` write into the dotfiles repo).

`herta/` and `robin/` ship only Windows `.ani` files, so they are not Xcursor
themes and are deliberately not linked.

`Xcursor.theme` only covers applications that start *after* it is set. Two
things are missed: the root (desktop) cursor, and vxwm's own bar/resize/move
cursors, which are built with the legacy `XCreateFontCursor` API. vxwm links
libXcursor/libXfixes and themes both itself, synchronously in `setup()` (see
`theme_cursors()` in `src/vxwm/vxwm.c`), so nothing has to run after it at
login.

The chosen theme is stored as data in `~/.config/vxpanel/Xresources` - not in
`startup.sh` and not in the tracked `config/.config/x11/Xresources` (that file is
shared/versioned; the choice is per-machine runtime state). `xinitrc` merges the
vxpanel file right after the tracked one, so `Xcursor.theme` (and `Xft.dpi`, ...)
are in the X resource database before `exec vxwm` with no delay. When you change
the theme live, vxpanel calls `local/.local/bin/cursor-theme` to refresh the
running session (it loads the cursor through libXcursor, defines it on the root
window, and re-images every named cursor server-side with `XFixes`). GTK apps
are handled separately through `gtk-cursor-theme-name` via gsettings/xsettingsd,
which is why vxpanel writes those too.

## Stow commands

```bash
cd ~/dotfiles
stow config local
```

Preview:

```bash
./test-stow.sh
```

Remove the links:

```bash
stow -D config local
```

Restow after an update:

```bash
stow -R config local
```

## Why source code is outside Stow

`vxwm`, `dmenu`, `st`, `nsxiv`, `slock` and `zlstatus` are programs, not user configuration. Keeping their source under `src/` prevents a large compiler tree from appearing as `~/.config/vxwm`, avoids polluting XDG config with build artifacts, and makes rebuilds independent of the deployed dotfiles.
