# Thunar (patched) — cut/copy visual distinction

A locally patched build of `thunar` for [Xfce](https://docs.xfce.org/xfce/thunar/start).

Normal Thunar 4.20 already ghosts icons at 50% for **cut** files, but it is
easy to miss, and **copied** files have no visual state at all. This patch
makes both unmistakable and ties the colours to the active **pywal** theme:

| state  | look                                                                 |
| ------ | -------------------------------------------------------------------- |
| cut    | icon faded to 35% + red tint (`thunar_cut_color`)                    |
| copy   | icon at full opacity + green tint (`thunar_copy_color`)              |

The two colours are not hard-coded in the binary. `thunar-icon-renderer.c`
resolves them via `gtk_style_context_lookup_color()` at render time, so you
can restyle them from CSS without rebuilding. `regenerate-gtk-theme.sh`
defines them *per wallpaper* (hue-rotated from the pywal accent so cut is
always red-ish and copy always green-ish):

```css
@define-color thunar_cut_color #875050;    /* cut   - red, hue-rotated from color6 */
@define-color thunar_copy_color #508750;   /* copy  - green, hue-rotated from color6 */
```

## Sidebar drop highlight

While dragging files over a sidebar entry (e.g. `dotfiles`), the row under the
pointer is now filled with a solid colour (like the selected row) and its text
is recoloured for contrast, instead of just getting an outline.
`thunar-drop-fill.patch` does this per cell renderer, so it only applies to
"drop into" (reorder lines are unchanged). Colour resolution:

1. `@define-color thunar_drop_color #rrggbb;` from gtk.css (use a pywal colour
   in `regenerate-gtk-theme.sh`, e.g. `{color4}`); optional
   `@define-color thunar_drop_fg_color #rrggbb;` for the text.
2. Otherwise: the current selection colour with the hue rotated ~36 degrees,
   text black/white by contrast.

Optional, to hide the leftover outline in gtk.css:
`treeview.view.dnd { border-color: transparent; }`

Notes: column spacing was moved into padding (identical layout) so the fill has
no gaps. Dropping onto the *currently selected* row keeps the normal selection
look (GTK skips cell backgrounds on selected rows).
`thunar-drop-subtle.patch` (faint overlay experiment, never in the PKGBUILD) is superseded.

## Patch contents (against thunar-4.20.10 release source)

- `thunar/thunar-clipboard-manager.[ch]` — new
  `thunar_clipboard_manager_has_copied_file()` (mirrors the existing `has_cutted_file`).
- `thunar/thunar-icon-renderer.c` — stronger cut fade (alpha 0.35), new
  per-icon tint helper, and tint dispatch on cut/copy state.

## Build & install

```sh
cd src/thunar
makepkg -si          # needs sudo for the final pacman -U
```

Restart Thunar afterwards (`pkill -x thunar; thunar &`) and the loading
spinner is also gone + file selection is the bright accent colour — both of
those live purely in `regenerate-gtk-theme.sh` (see `../local/`).

## Caveats

- This is a **custom binary**: a normal `pacman -Syu` will replace it with
  stock Thunar when Xfce bumps the version. Re-run `makepkg -si` after such
  updates to keep the patch.
- Building needs `base-devel` plus the `depends` list installed (all dev headers ship inside `glib2`/`gtk3` on Arch, so no `-devel` packages).
