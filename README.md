# qbnil dotfiles

XDG-first Arch Linux configuration for my vxwm desktop, managed with GNU Stow.

## Layout

- `config/` — the portable, non-secret part of `~/.config`, including the lowercase `thunar` configuration.
- `bin/` — text scripts from `~/.local/bin`.
- `share/` — the currently retained part of `~/.local/share`, including complete managed repositories for dmenu, slock, st-terminal, vxwm and zlstatus, plus selected scripts, music and cursor assets. Nested upstream `.git` directories and compiled output are removed so these are owned by this repository.
- `bootstrap/` — package manifests and install helper.

The former `applications/` and `fonts/` packages are intentionally not present. Fonts and desktop entries can be recreated or installed separately.

## Excluded data

Caches, browser/application profiles, credentials, private keys, state, histories, build output, generated databases, and other reinstallable runtime data are excluded. `.local/state` is never managed here. The real secret-bearing files remain only on the machine:

- `~/.config/shell/secrets.sh`
- `~/.config/ghgrab/config.json`
- `~/.config/anthropic/credentials/`
- `~/.config/ssh/`

Rotate credentials that were present in the original environment file or GitHub configuration, then recreate them locally from `config/.config/shell/xdg-env.sh.example`.

## Personal data

The `share` package contains the local copies of your `archives`, `downloads`, `documents`, `music`, `pictures`, and `honkai-star-rail-cursors` directories. Running Stow for `share` links those directories back into `~/.local/share` on this machine. They are listed in `.gitignore`, so Git leaves them on disk but never commits or pushes them to GitHub.

Waterfox is not included; migrate that profile separately through Waterfox export/import tools.

## Install on a new machine

```sh
sudo pacman -S --needed - < bootstrap/packages-native.txt
# install AUR entries from bootstrap/packages-aur.txt separately
./bootstrap/install.sh
stow --target="$HOME" --no-folding config bin share
```

The helper performs a dry run first. Resolve conflicts by backing up real files; do not use `stow --adopt` without reviewing the resulting diff. Then create local secrets:

```sh
cp ~/.config/shell/xdg-env.sh.example ~/.config/shell/xdg-env.sh
chmod 600 ~/.config/shell/secrets.sh
$EDITOR ~/.config/shell/secrets.sh
```

Build the vendored source trees in `~/.local/share/{vxwm,dmenu,slock,st-terminal,nsxiv,vcompmgr,zlstatus}` as needed. Their complete Makefiles, README files, modified C/Zig files, configs and keybindings are already in this repository; no separate upstream clone or diff application is required. Install resulting programs into `~/.local/bin`, while keeping compiled output out of git. To incorporate future upstream work, add the desired upstream as a temporary remote or temporary checkout, merge/review into the vendored directory, then commit the resulting whole-tree update here.

## Maintenance and verification

```sh
git pull --ff-only
stow --target="$HOME" --no-folding --simulate --verbose config bin share
git diff --check
find . -type f -name '*.sh' -print0 | xargs -0 -r -n1 sh -n
git grep -nE 'ghp_|tskey-|sk-or-v1|BEGIN .*PRIVATE KEY|AUTH_TOKEN|API_KEY' -- . ':!README.md' || true
```

Keep large personal data out of git. Back it up separately before moving to another machine.
