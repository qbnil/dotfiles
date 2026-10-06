# Stow structure

GNU Stow packages live at the repo root. Each package **mirrors paths relative to `$HOME`**.

```
stow -d ~/dotfiles -t ~ <package>
```

creates symlinks so that e.g. `bash/.bashrc` becomes `~/.bashrc`.

## Packages (stowed into `$HOME`)

| Package     | What it links |
|-------------|----------------|
| `bash/`     | `~/.bashrc`, `~/.bash_profile`, `~/.config/bash/` |
| `zsh/`      | `~/.zshenv`, `~/.config/zsh/` (`ZDOTDIR`) |
| `x11/`      | `~/.xinitrc` |
| `shell/`    | `~/.config/shell/` (shared XDG env + secrets example) |
| `nvim/`     | `~/.config/nvim/` |
| `tmux/`     | `~/.config/tmux/` |
| `dunst/`    | `~/.config/dunst/` |
| `git/`      | `~/.config/git/` |
| `mpd/`      | `~/.config/mpd/` |
| `yazi/`     | `~/.config/yazi/` |
| `feh/`      | `~/.config/feh/` |
| `flameshot/`| `~/.config/flameshot/` |
| `gtk/`      | `~/.config/gtk-3.0/` |
| `nvidia/`   | `~/.config/nvidia/` |
| `wal/`      | `~/.config/wal/templates/` |
| `bin/`      | `~/.local/bin/` |
| `share/`    | `~/.config/{vxwm,st-terminal,dmenu,slock,nsxiv,zlstatus}/` + `~/.local/share/honkai-star-rail-cursors/` |
| `wallpapers/` | `~/.local/share/wallpapers/` |

## Not stowed

| Path        | Why |
|-------------|-----|
| `systemd/`  | System files under `/etc/` — installed by `install.sh` with `sudo` |
| `bootstrap/`| Package lists only |
| `install.sh`, docs | Not configuration |

## Rules that keep Stow reliable

1. **One owner per path** — never put the same file in two packages (the old monolithic `config/` package was removed for this reason).
2. **No runtime state in packages** — MPD database, wal-generated `colors.Xresources`, browser profiles, etc. stay out of the tree.
3. **Home-level entry points** — `.zshenv`, `.bashrc`, and `.xinitrc` live at package roots (`zsh/`, `bash/`, `x11/`) and stow directly into `~`.
4. **`.Xresources` is not stowed** — your live setup points it at `~/.cache/wal/colors.Xresources` (pywal). `xinitrc` merges that at session start.
5. **Secrets** — copy `~/.config/shell/secrets.sh.example` → `secrets.sh` (gitignored).

## Conflict handling

`install.sh` dry-runs each package, moves any conflicting real files into a timestamped backup under `~/dotfiles-backup-…/conflicts/`, then stows with `-R` (restow).

## Adding a new app

```bash
mkdir -p newapp/.config/newapp
# put config files under newapp/.config/newapp/
# add "newapp" to PACKAGES in install.sh and test-stow.sh
stow -d ~/dotfiles -t ~ newapp
```
