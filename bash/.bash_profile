# ~/.bash_profile — thin wrapper
[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/bash/bash_profile" ] && . "${XDG_CONFIG_HOME:-$HOME/.config}/bash/bash_profile"
[[ -f ~/.bashrc ]] && . ~/.bashrc
