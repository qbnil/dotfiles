#!/bin/bash
# regenerate-gtk-theme.sh - Regenerate GTK theme from pywal colors
# Run after: wal -i <wallpaper>
# Writes a real theme (~/.themes/pywal-A or pywal-B, alternating) and pushes the
# new theme name to running GTK3 apps via xsettingsd, so they reload live.

set -euo pipefail

WAL_CACHE="$HOME/.cache/wal"
GTK_SETTINGS="$HOME/.config/gtk-3.0/settings.ini"
XS_CONF="$HOME/.config/xsettingsd/xsettingsd.conf"

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

# Alternate between two theme names so the name always changes
STATE="$WAL_CACHE/gtk-theme-toggle"
[[ "$(cat "$STATE" 2>/dev/null)" == "A" ]] && NEW=B || NEW=A
echo "$NEW" > "$STATE"
THEME="pywal-$NEW"
THEME_DIR="$HOME/.themes/$THEME/gtk-3.0"
mkdir -p "$THEME_DIR"
GTK_CSS="$THEME_DIR/gtk.css"

cat > "$GTK_CSS" << EOF
/* Pywal GTK3 theme - auto-generated from wallpaper */

/* Window decorations: no GTK frame at all, so apps like Waterfox only show
   the window manager's own border (same as Thunar, follows focus + palette) */
decoration, decoration:backdrop {
    border: none;
    border-radius: 0;
    box-shadow: none;
    margin: 0;
}

/* Base styling */
* {
    background-color: $BG;
    color: $FG;
    outline-width: 1px;
    outline-offset: -1px;
}
window { background-color: $BG; }
entry {
    background-image: none;
    background-color: $BG;
    color: $FG;
    border-color: $C8;
}
entry:focus { border-color: $C4; }

/* Menu bar: spacing, underline on hover (no background) */
menubar > menuitem, menubar menuitem {
    padding: 4px 10px;
    border: none;
    border-bottom: 2px solid transparent;
    background-color: $BG;
    color: $FG;
}
menubar > menuitem:hover, menubar > menuitem:selected {
    background-color: $BG;
    color: $FG;
    border-bottom: 2px solid $C4;
}

/* Buttons: flat, no theme gradient (the gradient is what made them white) */
button {
    background-image: none;
    background-color: transparent;
    color: $FG;
    border-color: transparent;
    border-style: none;
    box-shadow: none;
    text-shadow: none;
}
button:hover { background-image: none; background-color: $C8; color: $FG; }
button:active, button:checked { background-image: none; background-color: $C4; color: $BG; }
button:disabled { color: $C8; }

/* Checkboxes / radio buttons */
check, radio {
    background-image: none;
    background-color: $BG;
    color: $FG;
    border: 1px solid $C8;
    box-shadow: none;
}
check:checked, radio:checked {
    background-color: $C4;
    color: $BG;
    border-color: $C4;
}

sidebar, .sidebar, paned > sidebar {
    background-color: $BG;
    color: $FG;
    border-color: $C8;
}
treeview {
    background-color: $BG;
    color: $FG;
}
treeview:selected, treeview:selected:focus,
treeview:selected:hover, treeview:selected:backdrop {
    background-color: $C6;
    color: $BG;
}
treeview:hover { background-color: $C1; }

/* Thin selection borders in lists and icon views */
row:selected, treeview:selected, iconview:selected {
    border-width: 1px;
}

/* Drag-selection rectangle: border only, no fill. Thunar's window has an alpha channel,
   so semi-transparent fills punch through to the desktop wallpaper. */
rubberband, .rubberband, iconview rubberband, treeview rubberband {
    background-color: transparent;
    background-image: none;
    border: 1px solid $C4;
}

/* Selected items (files, folders, text). Same look in every state - active, hovered,
   and window unfocused (:backdrop) - so switching windows changes nothing.
   Catch-all on purpose: Thunar's icon view is a custom widget (ExoIconView) whose CSS
   node name varies between versions. Opaque mix() instead of alpha(): Thunar's window
   has an alpha channel and semi-transparent fills show the wallpaper through it. */
*:selected:not(menuitem),
*:selected:focus:not(menuitem),
*:selected:hover:not(menuitem),
*:selected:active:not(menuitem),
*:selected:backdrop:not(menuitem) {
    background-color: mix($BG, $C4, 0.35);
    background-image: none;
    color: $FG;
    -gtk-icon-effect: none;
    -gtk-icon-filter: none;
}

/* Unfocused window: no dimming or icon effects anywhere */
*:backdrop {
    -gtk-icon-effect: none;
    -gtk-icon-filter: none;
}

scrolledwindow { background-color: $BG; }
scrollbar { background-color: $BG; }
scrollbar slider {
    background-color: $C8;
    border-color: $C8;
}
scrollbar slider:hover { background-color: $C3; }
headerbar, .headerbar {
    background-image: none;
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
/* Dropdown items: faint highlight + underline only, no box/outline.
   The label/box inside an item must be transparent, otherwise the global
   '* { background-color }' rule paints over the highlight and leaves a frame. */
menu menuitem, menubar > menuitem {
    outline: none;
    box-shadow: none;
}
menuitem *, menuitem label, menuitem box, menuitem box > * {
    background-color: transparent;
    border: none;
    outline: none;
    box-shadow: none;
}
menu menuitem {
    border: none;
    border-bottom: 2px solid transparent;
}
menu menuitem:hover, menu menuitem:selected {
    background-color: mix($BG, $FG, 0.12);
    color: $FG;
    border: none;
    border-bottom: 2px solid $C4;
}

/* Tabs: underline on the selected tab only */
notebook { background-color: $BG; }
notebook > header {
    border: none;
    background-color: $BG;
}
notebook > header > tabs > tab {
    background-color: $BG;
    color: $FG;
    border: none;
    border-bottom: 2px solid transparent;
    padding: 4px 12px;
    min-height: 0;
}
notebook > header > tabs > tab:not(:checked) {
    border-bottom: 2px solid transparent;
}
notebook > header > tabs > tab:checked,
notebook > header > tabs > tab:checked:hover,
notebook > header > tabs > tab:checked:backdrop {
    border-bottom: 2px solid $C4;
}

toolbar {
    background-color: $BG;
    color: $FG;
}
statusbar {
    background-color: $BG;
    color: $FG;
}

/* Pane divider between sidebar and files: 1px line instead of a thick bar */
paned { background-color: $BG; }
paned > separator {
    background-color: $C8;
    background-image: none;
    min-width: 1px;
    min-height: 1px;
}

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

/* ================================================================
   Spacing only. Appended; nothing above is changed.
   Deliberately NO button rules (no button, toolbar button, path bar button,
   header button or dialog button styling) so buttons behave exactly as in
   the original theme.
   ================================================================ */

/* Text entries (path field, search, rename) */
entry {
    padding: 4px 8px;
    min-height: 22px;
}

/* Context menus and dropdowns */
menu { padding: 4px 0; }
menu menuitem { padding: 5px 12px; }

/* File chooser places sidebar (Home, Desktop, documents, ...): roomier rows and a gap
   between icon and name. Labels/boxes transparent so the selection tint shows. */
placessidebar row {
    padding: 6px 10px;
    min-height: 24px;
}
placessidebar row label, placessidebar row box, placessidebar row image {
    background-color: transparent;
}
placessidebar row image { margin-right: 8px; }

/* Bars (containers only) */
toolbar { padding: 2px 4px; }
statusbar { padding: 4px 8px; }
filechooser actionbar, filechooser .dialog-action-area { padding: 6px 8px; }

/* ---- File chooser: path bar dividers + underline-only selection ---- */

/* Path bar: padding and a thin divider between folders, so it reads
   kent | .local | share | documents instead of one run-together word. Only the path
   bar's own buttons are touched; the scroll arrows (slider buttons) are left alone. */
pathbar button:not(.slider-button), .path-bar button:not(.slider-button) {
    padding: 3px 10px;
    margin: 0;
    border-style: none none none solid;
    border-width: 0 0 2px 1px;
    border-color: transparent transparent transparent $C8;
}
pathbar button:first-child, .path-bar button:first-child {
    border-left-color: transparent;
}
/* Hovered folder: underline only, no fill */
pathbar button:not(.slider-button):hover, .path-bar button:not(.slider-button):hover {
    background-color: transparent;
    color: $FG;
    border-bottom-color: $C8;
}
/* Current folder: underline only, no fill */
pathbar button:not(.slider-button):checked, pathbar button:not(.slider-button):checked:hover,
.path-bar button:not(.slider-button):checked, .path-bar button:not(.slider-button):checked:hover {
    background-color: transparent;
    color: $FG;
    border-bottom-color: $C4;
}

/* Places sidebar (Home, Desktop, ...): no fill, no box, no focus outline - just an
   underline for the selected and hovered entry. */
placessidebar row:selected, placessidebar row:selected:focus,
placessidebar row:selected:hover, placessidebar row:selected:backdrop {
    background-color: $BG;
    background-image: none;
    color: $FG;
    outline: none;
    border-bottom: 2px solid $C4;
}
placessidebar row:hover:not(:selected) {
    background-color: $BG;
    background-image: none;
    outline: none;
    border-bottom: 2px solid $C8;
}
placessidebar row:focus { outline: none; }

/* Main file list in the picker: NO underline. Only files you actually select get
   the filled highlight; hovering and keyboard focus show nothing. */
filechooser treeview:selected, filechooser treeview:selected:focus,
filechooser treeview:selected:hover, filechooser treeview:selected:backdrop {
    background-color: mix($BG, $C4, 0.35);
    background-image: none;
    color: $FG;
    outline: none;
    border: none;
}
filechooser treeview:hover:not(:selected) {
    background-color: $BG;
    border: none;
}
filechooser treeview:focus { outline: none; }

/* ---- Drag-selection zone: glassy tint from the pywal accent ----
   Semi-transparent accent fill with a soft top-to-bottom sheen and a solid accent
   border, like the Windows selection rectangle. This overrides the border-only
   rectangle defined earlier. If the wallpaper shows through the window while dragging
   (Thunar's window has an alpha channel), delete this block to go back to border-only. */
rubberband, .rubberband, *.rubberband,
iconview rubberband, treeview rubberband,
iconview.rubberband, treeview.rubberband {
    background-color: alpha($C4, 0.18);
    background-image: linear-gradient(to bottom, alpha($FG, 0.10), alpha($FG, 0.02));
    border: 1px solid $C4;
}

/* ---- Button spacing (nvidia-settings, dialogs, file chooser, ...) ----
   Padding and a small gap between buttons so labels like "Apply  Detect Displays"
   don't touch. Spacing only: no min-width / min-height, no colour changes. */
button {
    padding: 4px 12px;
    margin: 2px;
}
/* The global '* { background-color }' rule paints every button label with the window
   background, which covers the button's hover/checked colour once there is padding.
   Make the contents transparent so the colour shows behind the label. */
button label, button image, button box {
    background-color: transparent;
}
/* Small arrow buttons (path bar scroll arrows) and spin buttons stay compact */
button.slider-button, pathbar button.slider-button {
    padding: 3px 6px;
    margin: 0;
}
spinbutton button {
    padding: 2px 6px;
    margin: 0;
}
/* Check boxes and radio buttons: gap between the box and its text */
check, radio {
    margin-right: 6px;
}

/* ---- Hover highlights for widgets that had none ----
   Faint opaque tint (mix, not alpha, so it never shows the wallpaper through). */

/* Popover menus (GTK3 "modelbutton" items): used by many apps instead of classic menus */
modelbutton:hover, modelbutton:focus {
    background-color: mix($BG, $FG, 0.12);
    color: $FG;
}
modelbutton *, modelbutton label, modelbutton box, modelbutton image {
    background-color: transparent;
}

/* List rows (settings lists, listbox-based sidebars). Their label/box children would
   otherwise paint the window background over the hover tint. */
row:hover {
    background-color: mix($BG, $FG, 0.08);
}
row label, row box, row image {
    background-color: transparent;
}

/* Tabs: underline on hover, like the selected tab's underline but dimmer */
notebook > header > tabs > tab:hover:not(:checked) {
    border-bottom: 2px solid $C8;
}

/* Thunar icon view: faint tint on the item under the pointer.
   (Not applied to the file chooser's list, which stays highlight-on-select only.) */
iconview:hover:not(:selected) {
    background-color: mix($BG, $FG, 0.08);
}

/* ---- Distinct input boxes, labelled sections, lean borders (nvidia-settings etc.) ---- */

/* Drop-downs (combo boxes): thin 1px border + faint fill so each one reads as an input
   box. Plain action buttons (Apply, Reset, ...) stay flat. */
combobox button, combobox button.combo, button.combo, combobox box.linked > button {
    margin: 0;
    padding: 3px 8px;
    border: 1px solid $C8;
    background-color: mix($BG, $FG, 0.06);
    box-shadow: none;
    outline: none;
}
combobox button:hover, button.combo:hover {
    background-color: mix($BG, $FG, 0.12);
    border-color: $C4;
}
combobox box.linked > button { border-left-width: 0; }

/* Text entries and number fields: same thin border and fill */
entry, spinbutton {
    border: 1px solid $C8;
    background-color: mix($BG, $FG, 0.06);
    box-shadow: none;
}
entry:focus, spinbutton:focus {
    border-color: $C4;
    box-shadow: none;
}
/* spin button: its inner entry has no border of its own (avoids a double frame) */
spinbutton entry {
    border: none;
    background-color: transparent;
}
spinbutton button {
    border: none;
    border-left: 1px solid $C8;
}

/* Sliders: visible track and handle */
scale trough {
    background-color: mix($BG, $FG, 0.15);
    border: none;
    min-height: 4px;
    min-width: 4px;
}
scale trough highlight { background-color: $C4; }
scale slider {
    background-color: $C4;
    border: none;
    min-width: 12px;
    min-height: 12px;
}

/* Sections: thin outline around grouped controls, accent-coloured section titles */
frame > border {
    border: 1px solid mix($BG, $FG, 0.20);
}
frame > label {
    color: $C4;
    padding: 0 6px;
}
separator {
    background-color: mix($BG, $FG, 0.20);
    min-width: 1px;
    min-height: 1px;
}

/* Tree lists (Thunar sidebar: Places / Devices / Network, nvidia-settings menu, ...):
   selected item = full background highlight in the accent tint, no border, no underline. */
treeview:selected, treeview:selected:focus,
treeview:selected:hover, treeview:selected:backdrop {
    background-color: mix($BG, $C4, 0.40);
    background-image: none;
    color: $FG;
    outline: none;
    border: none;
}

/* File chooser filter drop-down ("All Files"): same background as the dialog, thin border,
   comfortable padding. The lighter fill used for drop-downs elsewhere looked out of
   place next to the flat Cancel / Open buttons. */
filechooser combobox button, filechooser combobox button.combo,
filechooser button.combo, filechooser combobox box.linked > button {
    background-color: $BG;
    border: 1px solid $C8;
    padding: 4px 14px;
    margin: 4px 8px;
}
filechooser combobox button:hover, filechooser combobox button.combo:hover,
filechooser button.combo:hover {
    background-color: mix($BG, $FG, 0.08);
    border-color: $C4;
}
EOF

# The old user gtk.css would override the theme (user priority), so empty it
mkdir -p "$HOME/.config/gtk-3.0"
: > "$HOME/.config/gtk-3.0/gtk.css"

# Keep settings.ini in sync for apps that start without XSETTINGS
if grep -q '^gtk-theme-name' "$GTK_SETTINGS" 2>/dev/null; then
    sed -i "s|^gtk-theme-name.*|gtk-theme-name=$THEME|" "$GTK_SETTINGS"
fi

# Push the new theme name to running GTK3 apps
mkdir -p "$(dirname "$XS_CONF")"; touch "$XS_CONF"
if grep -q '^Net/ThemeName' "$XS_CONF"; then
    sed -i "s|^Net/ThemeName.*|Net/ThemeName \"$THEME\"|" "$XS_CONF"
else
    echo "Net/ThemeName \"$THEME\"" >> "$XS_CONF"
fi
if pgrep -x xsettingsd >/dev/null; then
    pkill -HUP -x xsettingsd
else
    (xsettingsd >/dev/null 2>&1 &)
fi

# File pickers are often drawn by the GTK portal, which only reads the theme when it starts.
# It is respawned on demand, so killing it makes the next dialog use the new colors.
pkill -f xdg-desktop-portal-gtk 2>/dev/null || true

echo "✓ GTK3 theme regenerated: $THEME"
