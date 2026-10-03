#!/bin/sh

export XDG_SESSION_TYPE=x11

# Input setup - fast, but backgrounded anyway so it can't add up
xinput --set-prop "Elan Touchpad" "libinput Natural Scrolling Enabled" 1 &
xinput --set-prop 'pointer:''compx L7 Air' 'libinput Accel Profile Enabled' 0, 1 &
xinput --set-prop 'pointer:''compx L7 Air' 'libinput Accel Speed' 0 &

# xrandr --output HDMI-0 --primary --mode 1920x1080 --pos 0x0 \
#       --output DP-0 --mode 1920x1080 --pos -1920x0
# xrandr --output HDMI-0 --mode 1920x1080 --rate 240 --primary
# hsetroot -cover "$HOME/pictures/Wall-E-Desk/landscape-anime/wallhaven-w5ejkr.jpg"

# Kept synchronous: if vxwm or its bar read colors/fonts from Xresources at
# startup, this needs to land before `exec vxwm`. No Python involved - just
# reading the cache files your wallpaper-setter script already wrote last
# time you changed wallpaper (~/.Xresources is a symlink to
# ~/.cache/wal/colors.Xresources from that script), so this is a couple of
# file reads + xrdb, should be single-digit ms even on battery.
cat ~/.Xresources ~/.cache/wal/xrdb_extra 2>/dev/null | xrdb -merge

$HOME/.config/zlstatus/zig-out/bin/zlstatus &

# Wallpaper: reuse the cached path from the last time wal set one
# (~/.cache/wal/wal is a plain-text file containing that path) and blit it
# with xwallpaper instead of feh. xwallpaper is a tiny C binary with no
# interpreter startup and a minimal decode path, so it stays fast even when
# throttled on battery. Needs `xwallpaper` installed (pacman/apt package of
# the same name). --zoom scales to fill; swap for --stretch or --maximize
# if you prefer a different fit, or add `--output <name>` per monitor.
if [ -s "$HOME/.cache/wal/wal" ]; then
    xwallpaper --zoom "$(cat "$HOME/.cache/wal/wal")"
fi

# xcompmgr needs to see _XROOTPMAP_ID set before it starts compositing.
# Run after wallpaper is set to ensure it picks up the pixmap immediately.

#IMG=$(cat ~/.cache/wal/wal)
#hsetroot -cover "$IMG"
# wal -i "$IMG"

setxkbmap -layout us,ru -option "grp:win_space_toggle" &
dunst &
flameshot &

# xcompmgr -c -C -f -F -I 0.03 -O 0.03 -D 5 &
# Start compositor after wallpaper is set so it sees _XROOTPMAP_ID.
xcompmgr -CcfF -I.14 -O.22 -D8 -t-1 -l-3 -r0 -o.5 &
# xcompmgr -c -C &
# vcompmgr -c -o 0.9 &
# picom --config ~/.config/picom/picom.conf --xrender-sync-fence
# picomlaunch &

# for browser to be able to open file manager - backgrounded, it's a D-Bus
# round-trip via systemctl and doesn't need to finish before vxwm starts
systemctl --user import-environment DISPLAY XAUTHORITY XDG_CURRENT_DESKTOP &

/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 &

exec vxwm
