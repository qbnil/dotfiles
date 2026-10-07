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
├── bootstrap/       # pacman/yay package lists
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

The home directories are real lowercase directories created by `install.sh`. Their canonical paths are defined in `~/.config/shell/xdg-env.sh`; they are not Stow links, so personal files placed there do not become part of the dotfiles repository.

This repository deliberately does **not** use `xdg-user-dirs` or `~/.config/user-dirs.dirs`: that would introduce a second source of truth for the same directories.

The four dotfiles in `$HOME` are compatibility entrypoints required by Bash, Zsh and `startx`; their actual contents live in `~/.config`.

There is no `~/.Xresources`. The tracked Xresources file is `~/.config/x11/Xresources`, and the pywal helper updates that XDG path.

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

## Shell configuration

`~/.config/shell/xdg-env.sh` is the central environment file. It sets:

- `XDG_CONFIG_HOME`
- `XDG_DATA_HOME`
- `XDG_CACHE_HOME`
- `XDG_STATE_HOME`
- `ZDOTDIR`
- editor/browser/terminal defaults
- application-specific XDG locations
- the user-local executable path

Secrets belong in `~/.config/shell/secrets.sh`; this file is ignored by git.

## XDG user directories

`~/.config/shell/xdg-env.sh` deliberately defines the user directories in lowercase. The standard set is:

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

Wallpapers and screenshots are kept under `~/pictures/` rather than creating additional mixed-case directories or putting personal media into the dotfiles repository.

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
