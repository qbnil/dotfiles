# Stow structure

Each directory at the repo root is a **GNU Stow package** (mirrors paths under `$HOME`).

```bash
stow -d ~/dotfiles -t ~ <package>
```

## Packages

| Package | Links into `$HOME` |
|---------|---------------------|
| `bash/` | `~/.bashrc`, `~/.bash_profile` |
| `zsh/` | `~/.zshenv` (`ZDOTDIR=~/.config/zsh`) |
| `x11/` | `~/.xinitrc` |
| `config/` | `~/.config/{bash,zsh,nvim,tmux,shell,dunst,git,mpd,yazi,feh,flameshot,gtk-3.0,nvidia,wal,x11}/` |
| `bin/` | `~/.local/bin/` |
| `share/` | `~/.config/{vxwm,dmenu,st-terminal,nsxiv,slock,zlstatus}/` + `~/.local/share/honkai-star-rail-cursors/` |
| `wallpapers/` | `~/.local/share/wallpapers/` |

## Not stowed

| Path | Why |
|------|-----|
| `systemd/` | Installed under `/etc/` by `install.sh` |
| `bootstrap/` | Package lists only |

## Rules

1. **One owner per path** — app configs live only under `config/` (or `share/` for vendored source trees).
2. **Vendored sources** (vxwm, st, …) stay in `share/.config/` so builds run from `~/.config/vxwm` etc.
3. **No runtime state** in git (MPD DB, wal cache, secrets).
4. **`.xinitrc`** is only `x11/.xinitrc` → `~/.xinitrc`.
5. **Xresources** static file: `config/.config/x11/Xresources` → `~/.config/x11/Xresources`; colours from pywal at runtime.

## Adding a new app config

```bash
mkdir -p config/.config/myapp
# add files…
# restow
stow -d ~/dotfiles -t ~ -R config
```
