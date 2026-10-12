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
- Building needs `base-devel` plus the `depends` list installed (all dev
  headers ship inside `glib2`/`gtk3` on Arch, so no `-devel` packages).