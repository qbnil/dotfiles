#!/bin/sh
# Login shell setup - source centralized env
. "${XDG_CONFIG_HOME:-$HOME/.config}/shell/xdg-env.sh"

# XDG_CURRENT_DESKTOP
export XDG_CURRENT_DESKTOP=vxwm

# Date (evaluated at login)
export DATE=$(date "+%A, %B %e  %_I:%M%P")
