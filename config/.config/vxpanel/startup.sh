#!/bin/sh
xrdb -merge "$HOME/.config/vxpanel/Xresources"  # vxpanel:xres
pgrep -x xsettingsd >/dev/null || xsettingsd &  # vxpanel:xsettingsd
XCURSOR_THEME=Adwaita XCURSOR_SIZE=24 xsetroot -cursor_name left_ptr  # vxpanel:cursor
redshift -P -O 6500  # vxpanel:nightlight
