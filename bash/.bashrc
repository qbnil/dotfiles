# ~/.bashrc — thin wrapper; real config lives under XDG
[[ $- != *i* ]] && return
[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/bash/bashrc" ] && . "${XDG_CONFIG_HOME:-$HOME/.config}/bash/bashrc"
