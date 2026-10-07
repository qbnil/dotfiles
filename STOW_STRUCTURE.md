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

`config/.config/shell/xdg-env.sh` is the single source of truth for the lowercase user directories:

- `~/desktop`
- `~/documents`
- `~/downloads`
- `~/music`
- `~/pictures`
- `~/public`
- `~/templates`
- `~/videos`

`install.sh` sources that file and creates the directories. The repository does not use `xdg-user-dirs` or `user-dirs.dirs`.

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
