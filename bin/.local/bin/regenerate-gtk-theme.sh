#!/bin/bash
# regenerate-gtk-theme.sh - Regenerate GTK theme from pywal colors
# Run after: wal -i <wallpaper>
# Or use: wal -t gtk3 && ./regenerate-gtk-theme.sh

set -euo pipefail

WAL_CACHE="$HOME/.cache/wal"
GTK_CSS="$HOME/.config/gtk-3.0/gtk.css"

if [[ ! -f "$WAL_CACHE/colors.json" ]]; then
    echo "Error: $WAL_CACHE/colors.json not found. Run 'wal' first."
    exit 1
fi

# Read colors from pywal JSON using python (no jq dependency)
read_colors() {
    python3 -c "
import json, sys
with open('$WAL_CACHE/colors.json') as f:
    c = json.load(f)
s = c['special']
print(f'BG={s[\"background\"]}')
print(f'FG={s[\"foreground\"]}')
print(f'C1={c[\"colors\"][\"color1\"]}')
print(f'C2={c[\"colors\"][\"color2\"]}')
print(f'C3={c[\"colors\"][\"color3\"]}')
print(f'C4={c[\"colors\"][\"color4\"]}')
print(f'C5={c[\"colors\"][\"color5\"]}')
print(f'C6={c[\"colors\"][\"color6\"]}')
print(f'C7={c[\"colors\"][\"color7\"]}')
print(f'C8={c[\"colors\"][\"color8\"]}')
"
}

eval "$(read_colors)"

cat > "$GTK_CSS" << EOF
/* Pywal GTK3 theme - auto-generated from wallpaper */

/* Window decorations - CRITICAL for browser borders */
decoration {
    border: 2px solid $C4;
    border-radius: 0;
    box-shadow: none;
    margin: 0;
}
decoration:backdrop {
    border-color: $C8;
}

/* Base styling */
* {
    background-color: $BG;
    color: $FG;
}
window { background-color: $BG; }
entry {
    background-color: $BG;
    color: $FG;
    border-color: $C8;
}
entry:focus { border-color: $C4; }
button {
    background-color: transparent;
    border-color: transparent;
    border-style: none;
}
button:hover { background-color: transparent; }
button:active { background-color: transparent; }
sidebar, .sidebar, paned > sidebar {
    background-color: $BG;
    color: $FG;
    border-color: $C8;
}
treeview {
    background-color: $BG;
    color: $FG;
}
treeview:selected {
    background-color: $C6;
    color: $BG;
}
treeview:hover { background-color: $C1; }
scrolledwindow { background-color: $BG; }
scrollbar { background-color: $BG; }
scrollbar slider {
    background-color: $C8;
    border-color: $C8;
}
scrollbar slider:hover { background-color: $C3; }
headerbar, .headerbar {
    background-color: $BG;
    color: $FG;
    border-color: $C8;
}
menu {
    background-color: $BG;
    color: $FG;
}
menuitem {
    background-color: $BG;
    color: $FG;
}
menuitem:hover {
    background-color: $C1;
    color: $BG;
}
notebook { background-color: $BG; }
notebook tab {
    background-color: $BG;
    color: $FG;
    border-color: $C8;
}
notebook tab:selected {
    background-color: $C1;
    color: $BG;
}
notebook tab:hover { background-color: $C4; }
toolbar {
    background-color: $BG;
    color: $FG;
}
statusbar {
    background-color: $BG;
    color: $FG;
}
paned { background-color: $BG; }
paned > separator { background-color: $C8; }
.popover {
    background-color: $BG;
    color: $FG;
}
dialog {
    background-color: $BG;
    color: $FG;
}
filechooser { background-color: $BG; }
progressbar { background-color: $BG; }
progressbar progress { background-color: $C1; }
levelbar { background-color: $BG; }
levelbar block { background-color: $C1; }
infobar {
    background-color: $BG;
    color: $FG;
}
link { color: $C4; }
visited { color: $C2; }
EOF

# Apply the theme
gsettings set org.gnome.desktop.interface gtk-theme 'Wal-Dark' 2>/dev/null || true

echo "✓ GTK3 theme regenerated at $GTK_CSS"