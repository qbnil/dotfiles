#!/bin/sh
# Login shell setup - source centralized env
source "$HOME/.config/shell/xdg-env.sh"

# XDG_CURRENT_DESKTOP
export XDG_CURRENT_DESKTOP=dwm

# Date (evaluated at login)
export DATE=$(date "+%A, %B %e  %_I:%M%P")
