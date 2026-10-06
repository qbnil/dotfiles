# XDG Base Directory Specification
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_STATE_HOME="$HOME/.local/state"

# Application-specific XDG overrides
export CARGO_HOME="$XDG_DATA_HOME/cargo"
export GOPATH="$XDG_DATA_HOME/go"
export GOBIN="$GOPATH/bin"
export GOMODCACHE="$XDG_CACHE_HOME/go/mod"
export NPM_CONFIG_USERCONFIG="$XDG_CONFIG_HOME/npm/npmrc"
export NPM_CONFIG_CACHE="$XDG_CACHE_HOME/npm"
export PYTHONSTARTUP="$XDG_CONFIG_HOME/python/pythonrc"
export PYTHON_HISTORY="$XDG_DATA_HOME/python/history"
export _JAVA_OPTIONS="-Djava.util.prefs.userRoot=$XDG_CONFIG_HOME/java"
export DOCKER_CONFIG="$XDG_CONFIG_HOME/docker"
export KUBECONFIG="$XDG_CONFIG_HOME/kube/config"
export GNUPGHOME="$XDG_CONFIG_HOME/gnupg"
export PASSWORD_STORE_DIR="$XDG_DATA_HOME/password-store"
export WGETRC="$XDG_CONFIG_HOME/wget/wgetrc"
export INPUTRC="$XDG_CONFIG_HOME/readline/inputrc"
export LESSHISTFILE="$XDG_CACHE_HOME/less_history"
export NODE_REPL_HISTORY="$XDG_DATA_HOME/node_repl_history"
export SQLITE_HISTORY="$XDG_DATA_HOME/sqlite_history"
export TERMINFO="$XDG_DATA_HOME/terminfo"
export TERMINFO_DIRS="$XDG_DATA_HOME/terminfo:/usr/share/terminfo"
export XINITRC="$HOME/.xinitrc"
export XPROFILE="$XDG_CONFIG_HOME/x11/xprofile"
export XRESOURCES="$XDG_CONFIG_HOME/x11/Xresources"
export FFMPEG_DATADIR="$XDG_CONFIG_HOME/ffmpeg"
export MOZ_PROFILE_DIR="$HOME/.config/waterfox"

# Default programs
export SYSTEMD_EDITOR="nvim"
export EDITOR="nvim"
export VISUAL="nvim"
export TERM="st"
export TERMINAL="st"
export MUSPLAYER="rmpc"
export BROWSER="waterfox"
export XCURSOR_THEME="phainon"

# Paths
export PATH="$HOME/.local/share/cargo/bin:$PATH"

# Zsh
export ZDOTDIR="$XDG_CONFIG_HOME/zsh"

# FZF
export FZF_DEFAULT_OPTS="--style minimal --color 16 --layout=reverse --height 30% --preview='bat -p --color=always {}'"
export FZF_CTRL_R_OPTS="--style minimal --color 16 --info inline --no-sort --no-preview"

# Man pages
export MANPAGER="less -R --use-color -Dd+r -Du+b"

# Less + termcap
export LESS="R --use-color -Dd+r -Du+b"
export LESS_TERMCAP_mb="$(printf '%b' '\[\033[1;31m\]')"
export LESS_TERMCAP_md="$(printf '%b' '\[\033[1;36m\]')"
export LESS_TERMCAP_me="$(printf '%b' '\[\033[0m\]')"
export LESS_TERMCAP_so="$(printf '%b' '\[\033[01;44;33m\]')"
export LESS_TERMCAP_se="$(printf '%b' '\[\033[0m\]')"
export LESS_TERMCAP_us="$(printf '%b' '\[\033[1;32m\]')"
export LESS_TERMCAP_ue="$(printf '%b' '\[\033[0m\]')"

# Source secrets file if it exists (API keys, tokens, etc.)
[ -f "$XDG_CONFIG_HOME/shell/secrets.sh" ] && source "$XDG_CONFIG_HOME/shell/secrets.sh"

# Prefer user-local binaries
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac

