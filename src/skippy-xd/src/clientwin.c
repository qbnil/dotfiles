/* Skippy-xd
 *
 * Copyright (C) 2004 Hyriand <hyriand@thegraveyard.org>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */

#include "skippy.h"

static int
clientwin_action(ClientWin *cw, enum cliop action);

int
clientwin_cmp_func(dlist *l, void *data) {
	ClientWin *cw = (ClientWin *) l->data;
	return cw->src.window == (Window) data
		|| cw->wid_client == (Window) data
		|| cw == (ClientWin *) data;
}

void XRoundedRectTint(session_t *ps,
		Picture dst,
		XRenderColor *tint,
		int x, int y,
		int w, int h,
		int radius);

void clientwin_round_corners(ClientWin *cw);

void
clientwin_fill_shape(ClientWin *cw, Drawable drawable, GC gc, int offset, int expand)
{
	MainWin *mw = cw->mainwin;
	session_t *ps = mw->ps;

	float multiplier = clientwin_get_multiplier(cw);
	int radius = ps->o.cornerRadius * multiplier;

	for (int i = 0; i < mw->nmonitors; ++i) {
		int x = 0, y = 0, w = cw->mini.width, h = cw->mini.height;
		if (cw->mode == CLIDISP_DESKTOP && ps->o.pagingOnCurrentMonitor) {
			x = (int)(mw->monitor[i].x * multiplier + cw->x)
					+ mw->xoff[mw->active_monitor] + ps->o.leftFrameBorder - cw->mini.x;
			y = (int)(mw->monitor[i].y * multiplier + cw->y)
					+ mw->yoff[mw->active_monitor] + ps->o.topFrameBorder - cw->mini.y;
			w = mw->monitor[i].width * multiplier - ps->o.leftFrameBorder;
			h = mw->monitor[i].height * multiplier - ps->o.topFrameBorder;
		}

		if (w <= 0 || h <= 0)
			continue;
		x += offset - expand;
		y += offset - expand;
		w += expand * 2;
		h += expand * 2;
		int r = radius > 0 ? MIN(radius + expand, MIN(w / 2, h / 2)) : 0;
		if (r == 0) {
			XFillRectangle(ps->dpy, drawable, gc, x, y, w, h);
			continue;
		}
		int dia = r * 2;
		XFillArc(ps->dpy, drawable, gc, x, y, dia, dia, 90 * 64, 90 * 64);
		XFillArc(ps->dpy, drawable, gc, x + w - dia, y, dia, dia, 0, 90 * 64);
		XFillArc(ps->dpy, drawable, gc, x + w - dia, y + h - dia, dia, dia, 270 * 64, 90 * 64);
		XFillArc(ps->dpy, drawable, gc, x, y + h - dia, dia, dia, 180 * 64, 90 * 64);
		XFillRectangle(ps->dpy, drawable, gc, x + r, y, w - dia, r);
		XFillRectangle(ps->dpy, drawable, gc, x + r, y + h - r, w - dia, r);
		XFillRectangle(ps->dpy, drawable, gc, x, y + r, w, h - dia);
	}
}

static void
clientwin_render_desktop_cover_tint_border(ClientWin *cover, ClientWin *cw,
		XRenderColor *tint, int border)
{
	MainWin *mw = cover->mainwin;
	session_t *ps = mw->ps;

	if (!tint || !tint->alpha || border <= 0 || !cw->mapped || !cover->destination)
		return;

	int x = cw->mini.x - border - cover->src.x + mw->x - ps->o.leftFrameBorder;
	int y = cw->mini.y - border - cover->src.y + mw->y - ps->o.topFrameBorder;
	int w = cw->mini.width + border * 2 - ps->o.leftFrameBorder;
	int h = cw->mini.height + border * 2 - ps->o.topFrameBorder;
	if (x >= cover->mini.width || y >= cover->mini.height || x + w <= 0 || y + h <= 0)
		return;

	XRenderTintBorder(cw, cover->mini.window, cover->destination, tint,
			x, y, border);
}

static void
clientwin_render_desktop_cover_tint_borders(ClientWin *cover)
{
	MainWin *mw = cover->mainwin;
	session_t *ps = mw->ps;
	XRenderColor *focus_tint = ps->o.multiselect?
			&mw->multiselectTint : &mw->highlightTint;

	if (ps->o.highlight_tintBorder <= 0)
		return;

	foreach_dlist (mw->clients) {
		ClientWin *cw = iter->data;
		if (cw->focused)
			clientwin_render_desktop_cover_tint_border(cover, cw,
					focus_tint, ps->o.highlight_tintBorder);
		if (cw->multiselect)
			clientwin_render_desktop_cover_tint_border(cover, cw,
					&mw->highlightTint, ps->o.highlight_tintBorder);
	}

	foreach_dlist (mw->dminis) {
		ClientWin *cw = iter->data;
		if (cw->focused)
			clientwin_render_desktop_cover_tint_border(cover, cw,
					focus_tint, ps->o.highlight_tintBorder);
		if (cw->multiselect)
			clientwin_render_desktop_cover_tint_border(cover, cw,
					&mw->highlightTint, ps->o.highlight_tintBorder);
	}
}

int
clientwin_validate_panel(dlist *l, void *data) {
	ClientWin *cw = l->data;
	session_t *ps = cw->mainwin->ps;
	cw->paneltype = wm_identify_panel(ps, cw->wid_client);
	return cw->paneltype == WINTYPE_PANEL? ps->o.panel_show:
			cw->paneltype == WINTYPE_DESKTOP? ps->o.panel_show_desktop:
			0;
}

int
clientwin_filter_monitor(dlist *l, void *data) {
	ClientWin *cw = l->data;
	MonitorCoord *monitor = data;
	session_t *ps = cw->mainwin->ps;
	int midx = cw->src0.x + cw->src0.width / 2;
	int midy = cw->src0.y + cw->src0.height / 2;

	/* A floating layout can park a window off-screen (negative coordinates or
	 * beyond the root edge).  Clamp its centre to the root so it still lands on
	 * the nearest monitor instead of being dropped from the per-monitor layout
	 * (which used to leave its preview at 1x1 and hide the window). */
	int sw = DisplayWidth(ps->dpy, ps->screen);
	int sh = DisplayHeight(ps->dpy, ps->screen);
	if (sw > 0) {
		if (midx < 0)
			midx = 0;
		else if (midx >= sw)
			midx = sw - 1;
	}
	if (sh > 0) {
		if (midy < 0)
			midy = 0;
		else if (midy >= sh)
			midy = sh - 1;
	}

	return monitor->x <= midx && midx < monitor->x + monitor->width
		&& monitor->y <= midy && midy < monitor->y + monitor->height;
}

int
clientwin_filter_func(dlist *l, void *data) {
	ClientWin *cw = l->data;
	MainWin *mw = cw->mainwin;
	session_t *ps = mw->ps;

	CARD32 current_desktop = (*(CARD32 *)data);
	CARD32 w_desktop = wm_get_window_desktop(ps, cw->wid_client);
	bool filtered_in = true;

	if (ps->o.desktops == NULL) {
		if (w_desktop != -1) {
			if (ps->o.mode == PROGMODE_PAGING)
				filtered_in = true;
			else
				filtered_in = w_desktop == current_desktop;
		}
	}
	else {
		bool filter_matched = false;
		bool matched_any_rule = false;
		bool has_positive_rule = false;

		// Sticky windows always shown
		if (w_desktop == (CARD32) -1)
			return wm_validate_window(mw->ps, cw->wid_client);

		const char *str = ps->o.desktops;
		int len = strlen(str);
		int anchor = 0;

		for (int i = 0; i <= len; i++) {
			if (str[i] == ',' || str[i] == '\0') {
				int token_len = i - anchor;
				bool negate = false;
				int start = anchor;

				if (str[start] == '!') {
					negate = true;
					start++;
					token_len--;
				}
				else
					has_positive_rule = true;

				char buffer[32];
				if (token_len >= (int)sizeof(buffer))
					token_len = sizeof(buffer) - 1;

				memcpy(buffer, str + start, token_len);
				buffer[token_len] = '\0';

				int desktop = atoi(buffer);

				bool rule_matches =
					(desktop == -1) ||
					(w_desktop == (CARD32)desktop);

				if (rule_matches) {
					matched_any_rule = true;
					filter_matched = !negate;
				}
				anchor = i + 1;
			}
		}

		filtered_in = matched_any_rule? filter_matched: !has_positive_rule;
	}

	if (filtered_in)
		return wm_validate_window(mw->ps, cw->wid_client);
	else
		return false;
}

int
clientwin_check_group_leader_func(dlist *l, void *data)
{
	ClientWin *cw = (ClientWin *)l->data;
	return wm_get_group_leader(cw->mainwin->ps->dpy, cw->wid_client) == *((Window*)data);
}

ClientWin *
clientwin_create(MainWin *mw, Window client) {
	session_t *ps = mw->ps;
	ClientWin *cw = NULL;

	XWindowAttributes attr = { };
	XGetWindowAttributes(ps->dpy, client, &attr);

	cw = smalloc(1, ClientWin);
	{
		static const ClientWin CLIENTWT_DEF = CLIENTWT_INIT;
		memcpy(cw, &CLIENTWT_DEF, sizeof(ClientWin));
	}

    cw->slots = 0;
	cw->force_mapped = false;
	cw->mainwin = mw;
	cw->wid_client = client;
	cw->origin = None;
	cw->destination = None;
	cw->shadow = None;
	cw->pixmap = None;
	cw->cpixmap = None;

	if (ps->o.includeFrame)
		cw->src.window = wm_find_frame(ps, client);
	if (!cw->src.window)
		cw->src.window = client;
	cw->mini.format = mw->format;

	{
		XSetWindowAttributes sattr = {
			.border_pixel = 0,
			.background_pixel = 0,
			.colormap = mw->colormap,
			.event_mask = ButtonPressMask | ButtonReleaseMask | KeyPressMask
				| KeyReleaseMask | PointerMotionMask | PropertyChangeMask | FocusChangeMask,
			.override_redirect = !ps->o.pseudoTrans,
		};
		cw->mini.window = XCreateWindow(ps->dpy,
				ps->o.pseudoTrans ? mw->window : ps->root,
				0, 0, 1, 1, 0,
				mw->depth, InputOutput, mw->visual,
				CWColormap | CWBackPixel | CWBorderPixel | CWEventMask | CWOverrideRedirect, &sattr);
	}
	if (!cw->mini.window)
		goto clientwin_create_err;

	{
		static const char *PREFIX = "skippy-xd preview window ";
		const int len = strlen(PREFIX) + 20;
		char *str = allocchk(malloc(len));
		snprintf(str, len, "%s%#010lx", PREFIX, cw->src.window);
		wm_wid_set_info(cw->mainwin->ps, cw->mini.window, str, None);
		free(str);
	}

	// Listen to events on the window. We don't want to miss any changes so
	// this is to be done as early as possible
	//XSelectInput(cw->mainwin->ps->dpy, cw->src.window, SubstructureNotifyMask | StructureNotifyMask);

	return cw;

clientwin_create_err:
	if (cw)
		clientwin_destroy(cw, False);

	return NULL;
}

/**
 * @brief Make an off-tag window drawable so a live preview can be captured.
 *
 * vxwm (a dwm fork with WINDOWMAP) unmaps windows on inactive tags, so their
 * contents are discarded and skippy-xd could only show a fallback icon.
 *
 * Simply calling XMapWindow() does not help: vxwm ignores MapRequest for
 * windows it already manages. We therefore set override_redirect while mapping
 * it, which bypasses the WM, and park it to the right of the virtual screen so
 * it never appears on the display. The position the window had before is kept
 * in SKIPPY_ORIG_POS_ATOM so the layout (and later activations) still see the
 * original geometry.
 *
 * The window is intentionally NOT unmapped again on exit: vxwm treats a
 * non-synthetic UnmapNotify as a withdrawal and would stop managing the
 * window. Leaving it mapped off-screen is invisible; vxwm moves it back on
 * screen when its tag is viewed.
 *
 * @return true if the window was parked by this call.
 */
bool
clientwin_force_map(ClientWin *cw) {
	session_t *ps = cw->mainwin->ps;
	XWindowAttributes wattr = { };
	Atom atom;

	if (!cw->src.window)
		return false;
	if (!XGetWindowAttributes(ps->dpy, cw->src.window, &wattr))
		return false;
	/* Leave windows alone that are already visible (either on the current
	 * tag, or parked off-screen by an earlier activation). */
	if (wattr.map_state == IsViewable)
		return false;
	/* Override-redirect windows are not managed by the WM and normally have
	 * no meaningful geometry to restore. */
	if (wattr.override_redirect)
		return false;

	/* Remember the root position used by the layout. */
	atom = XInternAtom(ps->dpy, SKIPPY_ORIG_POS_ATOM, False);
	{
		long pos[2] = { cw->src.x, cw->src.y };
		XChangeProperty(ps->dpy, cw->src.window, atom, XA_CARDINAL, 32,
				PropModeReplace, (unsigned char *) pos, 2);
	}

	XSetWindowAttributes swa = { .override_redirect = True };
	XChangeWindowAttributes(ps->dpy, cw->src.window, CWOverrideRedirect, &swa);

	/* Move before mapping so the window is never visible on screen. */
	{
		int screen = DefaultScreen(ps->dpy);
		int off_x = DisplayWidth(ps->dpy, screen) + wattr.width + 16;
		XMoveWindow(ps->dpy, cw->src.window, off_x, wattr.y);
	}
	XMapWindow(ps->dpy, cw->src.window);

	cw->force_mapped = true;
	return true;
}

/**
 * @brief Restore the attributes of a window parked by clientwin_force_map().
 *
 * The window is left mapped (off-screen) on purpose; see the comment above.
 */
void
clientwin_unforce_map(ClientWin *cw) {
	session_t *ps;

	if (!cw->force_mapped)
		return;

	ps = cw->mainwin->ps;
	if (cw->src.window) {
		XWindowAttributes wattr = { };
		if (XGetWindowAttributes(ps->dpy, cw->src.window, &wattr)
				&& wattr.override_redirect) {
			XSetWindowAttributes swa = { .override_redirect = False };
			XChangeWindowAttributes(ps->dpy, cw->src.window,
					CWOverrideRedirect, &swa);
		}
	}

	cw->force_mapped = false;
}

client_disp_mode_t
clientwin_get_disp_mode(session_t *ps, ClientWin *cw, bool isViewable) {
	for (client_disp_mode_t *p = ps->o.clientDisplayModes; *p; p++) {
		switch (*p) {
			case CLIDISP_THUMBNAIL_ICON:
				if (isViewable && cw->origin && cw->icon_pict)
					return *p;
				break;
			case CLIDISP_THUMBNAIL:
				if (isViewable && cw->origin)
					return *p;
				break;
			case CLIDISP_ZOMBIE_ICON:
				if (cw->shadow && cw->icon_pict != NULL)
					return *p;
				break;
			case CLIDISP_ZOMBIE:
				if (cw->shadow) return *p;
				break;
			case CLIDISP_ICON:
				if (cw->icon_pict) return *p;
				break;
			case CLIDISP_FILLED:
			case CLIDISP_NONE:
				return *p;
			case CLIDISP_DESKTOP:
				return *p;
		}
	}

	return CLIDISP_NONE;
}

bool
clientwin_update(ClientWin *cw) {
	session_t *ps = cw->mainwin->ps;

	/* Geometry was captured before the window was parked off-screen (see
	 * clientwin_force_map()), so leave it alone. */
	if (cw->force_mapped)
		return true;

	XWindowAttributes wattr = { };
	XGetWindowAttributes(ps->dpy, cw->src.window, &wattr);

	{
		Window tmpwin = None;
		XTranslateCoordinates(ps->dpy, cw->src.window, wattr.root,
				-wattr.border_width, -wattr.border_width,
				&cw->src.x, &cw->src.y, &tmpwin);

		if (wattr.width == 0 && wattr.height == 0) {
			XGetWindowAttributes(ps->dpy, cw->wid_client, &wattr);
			XTranslateCoordinates(ps->dpy, cw->wid_client, wattr.root,
					-wattr.border_width, -wattr.border_width,
					&cw->src.x, &cw->src.y, &tmpwin);
		}
	}

	cw->src.width = wattr.width;
	cw->src.height = wattr.height;
	cw->x = cw->src0.x = cw->src.x;
	cw->y = cw->src0.y = cw->src.y;
	cw->src0.width = cw->src.width;
	cw->src0.height = cw->src.height;

	/* A window parked off-screen by an earlier skippy-xd activation still
	 * reports its off-screen position. Restore the position it had before
	 * being parked so the layout is unchanged. */
	{
		int screen = DefaultScreen(ps->dpy);
		if (cw->src.x >= DisplayWidth(ps->dpy, screen)) {
			Atom atom = XInternAtom(ps->dpy, SKIPPY_ORIG_POS_ATOM, False);
			Atom type;
			int format;
			unsigned long nitems = 0, after = 0;
			unsigned char *data = NULL;

			if (XGetWindowProperty(ps->dpy, cw->src.window, atom, 0, 2,
					False, XA_CARDINAL, &type, &format, &nitems, &after,
					&data) == Success && data) {
				if (format == 32 && nitems >= 2) {
					long *pos = (long *) data;
					cw->x = cw->src0.x = cw->src.x = pos[0];
					cw->y = cw->src0.y = cw->src.y = pos[1];
				}
				XFree(data);
			}
		}
	}

	return true;
}

bool
clientwin_update3(ClientWin *cw) {
	session_t *ps = cw->mainwin->ps;

	clientwin_free_res2(ps, cw);

	XWindowAttributes wattr = { };
	XGetWindowAttributes(ps->dpy, cw->src.window, &wattr);
	bool isViewable = wattr.map_state == IsViewable;

	cw->zombie = !isViewable;

	cw->src.format = XRenderFindVisualFormat(ps->dpy, wattr.visual);

	if (ps->o.tooltip_show && !cw->tooltip)
		cw->tooltip = tooltip_create(cw->mainwin);

	if (isViewable) {
		static XRenderPictureAttributes pa = { .subwindow_mode = IncludeInferiors };

		if (cw->origin)
			free_picture(ps, &cw->origin);
		cw->origin = XRenderCreatePicture(ps->dpy,
				cw->src.window, cw->src.format, CPSubwindowMode, &pa);
		XRenderSetPictureFilter(ps->dpy, cw->origin, FilterBest, 0, 0);

		if (!cw->redirected) {
			XCompositeRedirectWindow(ps->dpy, cw->src.window,
					CompositeRedirectAutomatic);
			cw->redirected = true;
		}

		if (cw->cpixmap)
			free_pixmap(ps, &cw->cpixmap);
		cw->cpixmap = XCompositeNameWindowPixmap(ps->dpy, cw->src.window);

		if (cw->shadow)
			free_picture(ps, &cw->shadow);
		cw->shadow = XRenderCreatePicture(ps->dpy,
			cw->cpixmap, cw->src.format, CPSubwindowMode, &pa);
		XRenderSetPictureFilter(ps->dpy, cw->shadow, FilterBest, 0, 0);
	}

	// Get window icon
	if (cw->icon_pict)
		free_pictw(ps, &cw->icon_pict);
	cw->icon_pict = simg_load_icon(ps, cw->wid_client, ps->o.iconSize);
	if (!cw->icon_pict && ps->o.iconDefault)
		cw->icon_pict = clone_pictw(ps, ps->o.iconDefault);

	// Get window icon for filler
	if (cw->icon_pict_filler)
		free_pictw(ps, &cw->icon_pict_filler);
	cw->icon_pict_filler = simg_load_icon(ps, cw->wid_client, ps->o.fillerIconSize);
	if (!cw->icon_pict_filler && ps->o.iconFiller)
		cw->icon_pict_filler = clone_pictw(ps, ps->o.iconFiller);

	// modes are CLIDISP_THUMBNAIL_ICON, CLIDISP_THUMBNAIL, CLIDISP_ZOMBIE,
	// CLIDISP_ZOMBIE_ICON, CLIDISP_ICON, CLIDISP_FILLED, CLIDISP_NONE
	// if we ever got a thumbnail for the window,
	// the mode for that window always will be thumbnail
	cw->mode = clientwin_get_disp_mode(ps, cw, isViewable);
	printfdf(false, "(): (%#010lx): %d", cw->wid_client, cw->mode);

	return true;
}

static inline bool
clientwin_update2_desktop(session_t *ps, MainWin *mw, ClientWin *cw) {
	if (cw->pict_filled)
		free_pictw(ps, &cw->pict_filled);
	cw->pict_filled = simg_postprocess(ps,
			clone_pictw(ps, ps->o.fillSpec.img),
			ps->o.fillSpec.mode,
			1, 1,
			ps->o.fillSpec.alg, ps->o.fillSpec.valg,
			&ps->o.fillSpec.c);
	return cw->pict_filled;
}

static inline bool
clientwin_update2_filled(session_t *ps, MainWin *mw, ClientWin *cw) {
	float scale = cw->paneltype == WINTYPE_PANEL
			   || cw->paneltype == WINTYPE_DESKTOP
		? 1.0f : clientwin_get_multiplier(cw);
	int width = cw->mini.width > 0 ? cw->mini.width
				: cw->src.width * scale;
	int height = cw->mini.height > 0 ? cw->mini.height
				: cw->src.height * scale;

	if (cw->pict_filled)
		free_pictw(ps, &cw->pict_filled);
	cw->pict_filled = simg_postprocess(ps,
			clone_pictw(ps, ps->o.fillSpec.img),
			ps->o.fillSpec.mode,
			width, height,
			ps->o.fillSpec.alg, ps->o.fillSpec.valg,
			&ps->o.fillSpec.c);
	return cw->pict_filled;
}

static inline bool
clientwin_update2_icon(session_t *ps, MainWin *mw, ClientWin *cw) {
	float scale = cw->paneltype == WINTYPE_PANEL
			   || cw->paneltype == WINTYPE_DESKTOP
		? 1.0f : clientwin_get_multiplier(cw);
	int width = cw->mini.width > 0 ? cw->mini.width
				: cw->src.width * scale;
	int height = cw->mini.height > 0 ? cw->mini.height
				: cw->src.height * scale;

	if (cw->icon_pict_filled)
		free_pictw(ps, &cw->icon_pict_filled);

	cw->icon_pict_filled = simg_postprocess(ps,
			clone_pictw(ps, cw->icon_pict_filler),
			ps->o.iconFillSpec.mode,
			width, height,
			ps->o.iconFillSpec.alg, ps->o.iconFillSpec.valg,
			&ps->o.iconFillSpec.c);
	return cw->icon_pict_filled;
}

bool
clientwin_update2(ClientWin *cw) {
	MainWin *mw = cw->mainwin;
	session_t *ps = mw->ps;

	clientwin_free_res2(ps, cw);

	switch (cw->mode) {
		case CLIDISP_DESKTOP:
			if (!ps->o.pseudoTrans)
				clientwin_update2_desktop(ps, mw, cw);
			break;
		case CLIDISP_NONE:
			break;
		case CLIDISP_FILLED:
			clientwin_update2_filled(ps, mw, cw);
			break;
		case CLIDISP_ICON:
			clientwin_update2_icon(ps, mw, cw);
			break;
		case CLIDISP_ZOMBIE:
		case CLIDISP_ZOMBIE_ICON:
		case CLIDISP_THUMBNAIL:
		case CLIDISP_THUMBNAIL_ICON:
			break;
	}

	return true;
}

void
clientwin_destroy(ClientWin *cw, bool destroyed) {
	MainWin *mw = cw->mainwin;
	session_t * const ps = mw->ps;

	if (ps->o.pseudoTrans || cw->mode != CLIDISP_DESKTOP)
		free_picture(ps, &cw->origin);
	free_picture(ps, &cw->destination);
	free_picture(ps, &cw->shadow);
	free_pixmap(ps, &cw->pixmap);
	cw->pixmap_width = 0;
	cw->pixmap_height = 0;
	free_pixmap(ps, &cw->cpixmap);
	free_pictw(ps, &cw->icon_pict);
	free_pictw(ps, &cw->icon_pict_filler);
	free_pictw(ps, &cw->icon_pict_filled);
	free_pictw(ps, &cw->pict_filled);

	if (cw->tooltip)
		tooltip_destroy(cw->tooltip);

	if (cw->src.window && !destroyed) {
		free_damage(ps, &cw->damage);
		// Stop listening to events, this should be safe because we don't
		// monitor window re-map anyway
		XSelectInput(ps->dpy, cw->src.window, 0);

		if (cw->redirected)
			XCompositeUnredirectWindow(ps->dpy, cw->src.window, CompositeRedirectAutomatic);
	}

	if (cw->mini.window) {
		// Somehow it doesn't work without unmapping firstly
		XUnmapWindow(ps->dpy, cw->mini.window);
		XDestroyWindow(ps->dpy, cw->mini.window);
	}

	free(cw);
}

static void
clientwin_repaint(ClientWin *cw, const XRectangle *pbound)
{
	MainWin *mw = cw->mainwin;
	session_t *ps = mw->ps;
	Picture source = None;
	int s_x = 0, s_y = 0, s_w = cw->mini.width, s_h = cw->mini.height;
	if (pbound) {
		s_x = pbound->x;
		s_y = pbound->y;
		s_w = pbound->width;
		s_h = pbound->height;
	}

	switch (cw->mode) {
		case CLIDISP_DESKTOP:
			source = cw->origin;
			break;
		case CLIDISP_NONE:
			break;
		case CLIDISP_FILLED:
			if (!cw->pict_filled) return;
			source = cw->pict_filled->pict;
			break;
		case CLIDISP_ICON:
			if (!cw->icon_pict_filled) return;
			source = cw->icon_pict_filled->pict;
			break;
		case CLIDISP_ZOMBIE:
		// We will draw the icon later
		case CLIDISP_ZOMBIE_ICON:
			source = cw->shadow;
			break;
		case CLIDISP_THUMBNAIL:
		// We will draw the icon later
		case CLIDISP_THUMBNAIL_ICON:
			source = cw->origin;
			break;
	}

	if (!source) return;

	// Drawing main picture
	{
		Picture mask = mw->normalPicture;
		if (cw->zombie)
			mask = mw->shadowPicture;

		if (!ps->o.pseudoTrans) {
			XRenderComposite(ps->dpy, PictOpSrc, source, mask,
					cw->destination, s_x, s_y, 0, 0, s_x, s_y, s_w, s_h);
		}
		else {
			XRenderComposite(ps->dpy, PictOpSrc, mw->background, None,
					cw->destination, cw->mini.x + s_x, cw->mini.y + s_y, 0, 0,
					s_x, s_y, s_w, s_h);
			XRenderComposite(ps->dpy, PictOpOver, source, mask,
					cw->destination, s_x, s_y, 0, 0, s_x, s_y, s_w, s_h);
		}

		if (ps->o.background
				 && ((cw->paneltype == WINTYPE_PANEL && ps->o.panel_tinting)
				 || (cw->paneltype == WINTYPE_DESKTOP && ps->o.desktopTinting)))
			XRenderComposite(ps->dpy, PictOpOver, ps->o.background->pict, None,
					cw->destination, s_x, s_y, 0, 0, s_x, s_y, s_w, s_h);

		if (!ps->o.pseudoTrans && cw->paneltype == WINTYPE_DESKTOP)
			clientwin_render_desktop_cover_tint_borders(cw);

		if (ps->o.mode == PROGMODE_PAGING && cw->paneltype == WINTYPE_DESKTOP
				&& mw->ps->o.preservePages && ps->o.desktopTinting) {
			foreach_dlist (mw->dminis) {
				ClientWin *dwin = (ClientWin *) iter->data;

				int leftborder = 0, topborder = 0;
				if (wm_get_fullscreen(ps, cw->wid_client)) {
					leftborder = ps->o.leftFrameBorder;
					topborder = ps->o.topFrameBorder;
				}

				for (int i = 0; i < mw->nmonitors; ++i)
				{
					int x = dwin->mini.x + mw->monitor[i].x - cw->mini.x + leftborder;
					int y = dwin->mini.y + mw->monitor[i].y - cw->mini.y + topborder;
					int width = mw->monitor[i].width * mw->multiplier[mw->active_monitor];
					int height = mw->monitor[i].height * mw->multiplier[mw->active_monitor];

					XRoundedRectComposite(mw->ps,
							source, cw->destination,
							x, y, x, y, width, height,
							ps->o.cornerRadius * mw->multiplier[mw->active_monitor]);
				}
			}
		}

		if ((CLIDISP_ZOMBIE_ICON == cw->mode || CLIDISP_THUMBNAIL_ICON == cw->mode)
		&& cw->paneltype == WINTYPE_WINDOW) {
			assert(cw->icon_pict && cw->icon_pict->pict);
			img_composite_params_t params = IMG_COMPOSITE_PARAMS_INIT;
			simg_get_composite_params(cw->icon_pict,
					cw->mini.width, cw->mini.height,
					ps->o.iconSpec.mode, ps->o.iconSpec.alg, ps->o.iconSpec.valg,
					&params);
			simg_composite(ps, cw->icon_pict, cw->destination,
					cw->mini.width, cw->mini.height, &params, NULL, mask, pbound);
		}
	}

	// Tinting
	if (cw->paneltype == WINTYPE_WINDOW)
	{
		for (int j=0; j<2; j++) {
			XRenderColor *tint = None;
			bool tint_window = false;
			if (j == 0 && cw->focused) {
				if (ps->o.multiselect) {
					tint = &mw->multiselectTint;
					tint_window = ps->o.highlight_tintWindow;
				}
				else {
					tint = &mw->highlightTint;
					tint_window = ps->o.highlight_tintWindow;
				}
			}
			if (j == 1 && cw->multiselect) {
				tint = &mw->highlightTint;
				tint_window = ps->o.highlight_tintWindow;
			}

			if (tint && tint->alpha && tint_window) {
				if (cw->mode == CLIDISP_DESKTOP && ps->o.pagingOnCurrentMonitor)
				{
					for (int i = 0; i < mw->nmonitors; ++i)
					{
						s_x = mw->monitor[i].x * mw->multiplier[mw->active_monitor];
						s_y = mw->monitor[i].y * mw->multiplier[mw->active_monitor];
						s_w = mw->monitor[i].width * mw->multiplier[mw->active_monitor];
						s_h = mw->monitor[i].height * mw->multiplier[mw->active_monitor];

						XRoundedRectTint(mw->ps,
								cw->destination, tint,
								s_x, s_y, s_w, s_h, ps->o.cornerRadius * mw->multiplier[mw->active_monitor]);

						XClearArea(mw->ps->dpy, cw->mini.window, s_x, s_y, s_w, s_h, False);
					}
				}
				else {
					XRenderFillRectangle(mw->ps->dpy, PictOpOver,
							cw->destination, tint, s_x, s_y, s_w, s_h);
					XClearArea(mw->ps->dpy, cw->mini.window, s_x, s_y, s_w, s_h, False);
				}
			}
		}

		if (ps->o.tooltip_show && ps->o.mode != PROGMODE_PAGING)
			tooltip_draw(cw->tooltip, ps->o.multiselect? cw->multiselect: cw->focused);
	}

	XClearArea(mw->ps->dpy, cw->mini.window, s_x, s_y, s_w, s_h, False);
}

void
clientwin_render(ClientWin *cw) {
	MainWin *mw = cw->mainwin;
	session_t *ps = mw->ps;
	if (ps->o.mode == PROGMODE_PAGING && !ps->o.pagingOnCurrentMonitor) {
		foreach_dlist (mw->dminis) {
			ClientWin *cw2 = iter->data;
			cw2->focused = mw->client_to_focus
				&& cw2->slots == mw->client_to_focus->slots;
			clientwin_repaint(cw2, NULL);
			if (cw2->tooltip)
				clientwin_tooltip(cw2);
		}
	}
	clientwin_repaint(cw, NULL);
}

void
clientwin_repair(ClientWin *cw) {
	session_t *ps = cw->mainwin->ps;

	int nrects = 0;
	XRectangle *rects = NULL;

	{
		XserverRegion rgn = XFixesCreateRegion(ps->dpy, 0, 0);
		XDamageSubtract(ps->dpy, cw->damage, None, rgn);
		if (cw->mode >= CLIDISP_ZOMBIE)
			rects = XFixesFetchRegion(ps->dpy, rgn, &nrects);
		XFixesDestroyRegion(ps->dpy, rgn);
	}
	for (int i = 0; i < nrects; i++) {
		XRectangle r = {
			.x = rects[i].x * cw->factor,
			.y = rects[i].y * cw->factor,
			.width = rects[i].width * cw->factor,
			.height = rects[i].height * cw->factor,
		};
		clientwin_repaint(cw, &r);
	}

	if (rects)
		XFree(rects);
	
	cw->damaged = false;
}

void
clientwin_schedule_repair(ClientWin *cw, XRectangle *area)
{
	cw->damaged = true;
}

void XRoundedRectTint(session_t *ps,
		Picture dst,
		XRenderColor *tint,
		int x, int y,
		int w, int h,
		int radius)
{
	if (radius == 0)
		return XRenderFillRectangle(ps->dpy,
				PictOpOver, dst, tint,
				x, y, w, h);

	Pixmap pm;
	Picture mask = XRoundedRectMask(ps, w, h, radius, &pm);
	Picture src = XRenderCreateSolidFill(ps->dpy, tint);

	XRenderComposite(ps->dpy, PictOpOver, src, mask, dst,
			0, 0, 0, 0, x, y, w, h);

	XRenderFreePicture(ps->dpy, src);
	XRenderFreePicture(ps->dpy, mask);
	XFreePixmap(ps->dpy, pm);
}

void clientwin_round_corners(ClientWin *cw) {
	session_t* ps = cw->mainwin->ps;
	int w = cw->mini.width;
	int h = cw->mini.height;
	XGCValues xgcv;
	Pixmap mask = XCreatePixmap(ps->dpy, cw->mini.window, w, h, 1);
	GC shape_gc = XCreateGC(ps->dpy, mask, 0, &xgcv);

	int radius = ps->o.cornerRadius * clientwin_get_multiplier(cw);
	int dia = 2 * radius;

	XSetForeground(ps->dpy, shape_gc, 0);
	XFillRectangle(ps->dpy, mask, shape_gc, 0, 0, w, h);
	XSetForeground(ps->dpy, shape_gc, 1);

	if (ps->o.mode == PROGMODE_PAGING && ps->o.preservePages
			&& cw->mode == CLIDISP_DESKTOP)
		clientwin_fill_shape(cw, mask, shape_gc, 0, 0);
	else {
		if (dia > 0) {
			XFillArc(ps->dpy, mask, shape_gc, 0, 0, dia, dia, 0, 360 * 64);
			XFillArc(ps->dpy, mask, shape_gc, w-dia-1, 0, dia, dia, 0, 360 * 64);
			XFillArc(ps->dpy, mask, shape_gc, 0, h-dia-1, dia, dia, 0, 360 * 64);
			XFillArc(ps->dpy, mask, shape_gc, w-dia-1, h-dia-1, dia, dia, 0, 360 * 64);
		}
		XFillRectangle(ps->dpy, mask, shape_gc, radius, 0, w-dia, h);
		XFillRectangle(ps->dpy, mask, shape_gc, 0, radius, w, h-dia);
	}
	XShapeCombineMask(ps->dpy, cw->mini.window, ShapeBounding, 0, 0, mask, ShapeSet);
	XFreePixmap(ps->dpy, mask);
	XFreeGC(ps->dpy, shape_gc);
}

void clientwin_prepmove(ClientWin *cw)
{
	float multiplier = clientwin_get_multiplier(cw);
	int width = MAX(cw->src.width, cw->src.width * multiplier);
	int height = MAX(cw->src.height, cw->src.height * multiplier);

	if (width <= 0 || height <= 0)
		return;

	if (cw->pixmap && cw->destination
			&& cw->pixmap_width == width && cw->pixmap_height == height)
		return;

	if (cw->pixmap)
		XFreePixmap(cw->mainwin->ps->dpy, cw->pixmap);

	if (cw->destination)
		XRenderFreePicture(cw->mainwin->ps->dpy, cw->destination);

	cw->pixmap = XCreatePixmap(cw->mainwin->ps->dpy, cw->mini.window,
			width, height, cw->mainwin->depth);
	XSetWindowBackgroundPixmap(cw->mainwin->ps->dpy,
			cw->mini.window, cw->pixmap);

	cw->destination = XRenderCreatePicture(cw->mainwin->ps->dpy,
			cw->pixmap, cw->mini.format, 0, 0);
	cw->pixmap_width = width;
	cw->pixmap_height = height;
}

void
clientwin_move(ClientWin *cw, float f, int x, int y, float timeslice)
{
	MainWin *mw = cw->mainwin;
	session_t *ps = mw->ps;

	cw->mini.x = cw->src.x + (cw->x - cw->src.x + x) * timeslice;
	cw->mini.y = cw->src.y + (cw->y - cw->src.y + y) * timeslice;

	cw->factor = f;
	cw->mini.width = cw->src.width * f;
	cw->mini.height = cw->src.height * f;

	int leftborder = ps->o.leftFrameBorder, topborder = ps->o.topFrameBorder;
	if (wm_get_fullscreen(ps, cw->wid_client))
		leftborder = topborder = 0;

	cw->mini.x += leftborder;
	cw->mini.y += topborder;
	XMoveResizeWindow(cw->mainwin->ps->dpy, cw->mini.window,
			cw->mini.x, cw->mini.y,
			cw->mini.width, cw->mini.height);

	if (cw->paneltype == WINTYPE_WINDOW)
		clientwin_round_corners(cw);
}

void
clientwin_map(ClientWin *cw) {
	session_t *ps = cw->mainwin->ps;
	
	if (!cw->mode)
		return;

	if (cw->origin) {
		free_damage(ps, &cw->damage);
		cw->damage = XDamageCreate(ps->dpy, cw->src.window, XDamageReportDeltaRectangles);
		if (cw->paneltype == WINTYPE_WINDOW)
			XRenderSetPictureTransform(ps->dpy, cw->origin, &cw->mainwin->transform);
	}

	if (cw->shadow) {
		free_damage(ps, &cw->damage);
		cw->damage = XDamageCreate(ps->dpy, cw->src.window, XDamageReportDeltaRectangles);
		if (cw->paneltype == WINTYPE_WINDOW)
			XRenderSetPictureTransform(ps->dpy, cw->shadow, &cw->mainwin->transform);
	}

	clientwin_render(cw);

	XMapWindow(ps->dpy, cw->mini.window);
	XRaiseWindow(ps->dpy, cw->mini.window);
	cw->mapped = true;

	if (ps->o.tooltip_show && ps->o.mode != PROGMODE_PAGING
			&& cw->paneltype == WINTYPE_WINDOW)
		clientwin_tooltip(cw);
}

void
clientwin_unmap(ClientWin *cw) {
	session_t *ps = cw->mainwin->ps;

	free_damage(ps, &cw->damage);
	free_picture(ps, &cw->destination);
	free_pixmap(ps, &cw->pixmap);
	cw->pixmap_width = 0;
	cw->pixmap_height = 0;

	XUnmapWindow(ps->dpy, cw->mini.window);
	XSetWindowBackgroundPixmap(ps->dpy, cw->mini.window, None);
	cw->mapped = false;

	cw->focused = false;

	if (cw->tooltip)
		tooltip_unmap(cw->tooltip);
}

void
childwin_focus(ClientWin *cw) {
	if (!cw)
		return;

	session_t * const ps = cw->mainwin->ps;

	if (ps->o.moveMouse)
		XWarpPointer(ps->dpy, None, cw->wid_client,
				0, 0, 0, 0, cw->src.width / 2, cw->src.height / 2);
	XRaiseWindow(ps->dpy, cw->wid_client);
	wm_activate_window(ps, cw->wid_client);
	XFlush(ps->dpy);
}

static int
quick_key_cmp(const void *pa, const void *pb) {
	const ClientWin *a = *(ClientWin * const *) pa;
	const ClientWin *b = *(ClientWin * const *) pb;

	if (a->monitor != b->monitor)
		return a->monitor - b->monitor;
	if (a->x != b->x)
		return a->x - b->x;
	return a->y - b->y;
}

/**
 * @brief Give every preview a one-key quick-select marker.
 *
 * Pressing a marker jumps straight to that window without navigating to it
 * first. Keys already used by the switcher (hjkl navigation, n/p next/prev)
 * are skipped. Digits are used only when there are more than 20 windows.
 * Markers are assigned left to right so the labels read naturally.
 */
void
clientwin_assign_quick_keys(MainWin *mw) {
	static const char markers[] = "abcdefgimoqrstuvwxyz123456789";
	const size_t nmarkers = sizeof(markers) - 1;
	session_t *ps = mw->ps;
	ClientWin **arr;
	size_t n, i;

	foreach_dlist_vn(cl, mw->clients) {
		ClientWin *cw = cl->data;
		cw->quick_keycode = 0;
		cw->quick_label[0] = '\0';
	}

	n = dlist_len(mw->clientondesktop);
	if (!n)
		return;

	arr = malloc(n * sizeof *arr);
	if (!arr)
		return;

	i = 0;
	foreach_dlist_vn(cl, mw->clientondesktop) {
		if (i < n)
			arr[i++] = cl->data;
	}
	n = i;
	qsort(arr, n, sizeof *arr, quick_key_cmp);

	for (i = 0; i < n && i < nmarkers; i++) {
		ClientWin *cw = arr[i];
		const char key[2] = { markers[i], '\0' };
		KeySym ksym = XStringToKeysym(key);
		KeyCode code = ksym ? XKeysymToKeycode(ps->dpy, ksym) : 0;
		if (!code)
			continue;

		cw->quick_keycode = code;
		cw->quick_label[0] = key[0];
		cw->quick_label[1] = '\0';
	}

	free(arr);
}

void
clientwin_tooltip(ClientWin *cw) {
	MainWin *mw = cw->mainwin;
	session_t *ps = mw->ps;

	if (cw->tooltip) {
		int len = 0;
		FcChar8 *label = NULL;

		if (cw->mode == CLIDISP_DESKTOP) {
			label = wm_get_desktop_name(mw->ps, cw->slots);
			len = strlen((char*)label);
		}
		else if (ps->o.tooltip_option == 0) {
			label = wm_get_window_title(ps, cw->wid_client, &len);

			if (!label)
				label = wm_get_window_title(ps, cw->mini.window, &len);
		}
		else {
			XClassHint *hints = allocchk(XAllocClassHint());
			if (hints) {
				XGetClassHint(ps->dpy, cw->wid_client, hints);
				if (hints->res_class)
					label = (unsigned char*)hints->res_class;
				else if (hints->res_name)
					label = (unsigned char*)hints->res_name;

				len = (!label) ? 0 : strlen((char*)label);

				//if (hints->res_class)
					//XFree(hints->res_class);
				if (hints->res_name)
					XFree(hints->res_name);
				if (hints)
					XFree(hints);
			}
		}

		if (label) {
			/* vxwm exposes its tag as _NET_WM_DESKTOP.  Prefix the normal
			 * title/class label so the chooser identifies the tag too. */
			long desktop = wm_get_window_desktop(ps, cw->wid_client);
			char tag[32];
			if (desktop == -1)
				snprintf(tag, sizeof tag, "[*] ");
			else
				snprintf(tag, sizeof tag, "[%ld] ", desktop + 1);

			/* Show the one-key quick-select marker (if any) first. */
			char prefix[48];
			if (cw->quick_label[0])
				snprintf(prefix, sizeof prefix, "%s: %s",
						cw->quick_label, tag);
			else
				snprintf(prefix, sizeof prefix, "%s", tag);

			size_t prefixlen = strlen(prefix);
			char *tagged = malloc(prefixlen + (size_t)len + 1);
			if (tagged) {
				memcpy(tagged, prefix, prefixlen);
				memcpy(tagged + prefixlen, label, (size_t)len);
				tagged[prefixlen + (size_t)len] = '\0';
				tooltip_map(cw->tooltip, cw, (FcChar8 *)tagged,
						(int)(prefixlen + (size_t)len));
				free(tagged);
			}
			free(label);
		}
	}

	tooltip_draw(cw->tooltip, ps->o.multiselect? cw->multiselect: cw->focused);
}

void
shadow_clientwindow(ClientWin* cw, enum cliop op) {
	MainWin *mw = cw->mainwin;
	session_t *ps = mw->ps;

	if (cw == mw->client_to_focus)
		mw->client_to_focus = NULL;
	if (cw == mw->client_to_focus_on_cancel)
		mw->client_to_focus_on_cancel = NULL;

	clientwin_action(cw, op);
	clientwin_unmap(cw);

	XFlush(ps->dpy);
	usleep(10000);

	clientwin_update(cw);
	clientwin_update3(cw);

	clientwin_prepmove(cw);
	clientwin_map(cw);

	focus_miniw(ps, cw);
}

int
close_clientwindow(ClientWin* cw, enum cliop op) {
	MainWin *mw = cw->mainwin;
	session_t *ps = mw->ps;

	if (cw == mw->client_to_focus)
		mw->client_to_focus = NULL;
	if (cw == mw->client_to_focus_on_cancel)
		mw->client_to_focus_on_cancel = NULL;

	clientwin_action(cw, op);
	focus_miniw_next(ps, cw);
	mainwin_render_borders(mw);
	XFlush(ps->dpy);

	{
		dlist *del = dlist_find(mw->clientondesktop,
				clientwin_cmp_func, (void *) cw->wid_client);
		mw->clientondesktop = dlist_remove(del);
	}

	{
		dlist *del = dlist_find(mw->clients,
				clientwin_cmp_func, (void *) cw->wid_client);
		mw->clients = dlist_remove(del);
	}

	{
		dlist *del = dlist_find(mw->focuslist,
				clientwin_cmp_func, (void *) cw->wid_client);
		mw->focuslist = dlist_remove(del);
	}

	clientwin_destroy((ClientWin *) cw, True);

	if (dlist_len(mw->focuslist) == 0)
		return 1;
	return 0;
}

int
select_clientwindow(ClientWin* cw, enum cliop op) {
	session_t *ps = cw->mainwin->ps;
	if (ps->o.multiselect) {
		cw->mainwin->client_to_focus->multiselect = !cw->mainwin->client_to_focus->multiselect;
		clientwin_render(cw);
		mainwin_render_borders(cw->mainwin);
		return 0;
	}
	else {
		return 1;
	}
}

int
clientwin_handle(ClientWin *cw, XEvent *ev) {
	if (! cw)
		return 1;

	MainWin *mw = cw->mainwin;
	session_t *ps = mw->ps;
	XKeyEvent * const evk = &ev->xkey;

	if (ev->type == KeyPress)
	{
		report_key(ev);
		report_key_modifiers(evk);
		if (debuglog) fputs("\n", stdout);

		/* One-key quick select: jump straight to the window whose marker
		 * was pressed, without navigating to it first. */
		foreach_dlist_vn(qiter, mw->clientondesktop) {
			ClientWin *qc = qiter->data;
			if (!qc->quick_keycode || qc->quick_keycode != evk->keycode)
				continue;

			if (ps->o.multiselect) {
				qc->multiselect = !qc->multiselect;
				clientwin_render(qc);
				mainwin_render_borders(mw);
				return 0;
			}

			mw->client_to_focus = qc;
			mw->refocus = false;
			return 1;
		}

		if (arr_keycodes_includes(cw->mainwin->keycodes_Up, evk->keycode))
			focus_up(cw->mainwin->client_to_focus);
		else if (arr_keycodes_includes(cw->mainwin->keycodes_Down, evk->keycode))
			focus_down(cw->mainwin->client_to_focus);
		else if (arr_keycodes_includes(cw->mainwin->keycodes_Left, evk->keycode))
			focus_left(cw->mainwin->client_to_focus);
		else if (arr_keycodes_includes(cw->mainwin->keycodes_Right, evk->keycode))
			focus_right(cw->mainwin->client_to_focus);
		else if (arr_keycodes_includes(cw->mainwin->keycodes_Prev, evk->keycode))
			focus_miniw_prev(ps, cw->mainwin->client_to_focus);
		else if (arr_keycodes_includes(cw->mainwin->keycodes_Next, evk->keycode))
			focus_miniw_next(ps, cw->mainwin->client_to_focus);
		cw->mainwin->pressed_key = true;
	}

	else if (ev->type == KeyRelease) {
		printfdf(false, "(): else if (ev->type == KeyRelease) {");
		printfdf(false, "(): keycode: %d:", evk->keycode);

		if (cw->mainwin->pressed_key) {
			if (arr_keycodes_includes(cw->mainwin->keycodes_Cancel, evk->keycode))
			{
				mw->refocus = true;
				return 1;
			}
			else if (arr_keycodes_includes(cw->mainwin->keycodes_Select, evk->keycode))
			{
				return select_clientwindow(cw, CLIENTOP_FOCUS);
			}

			if (mw->client_to_focus->mode != CLIDISP_DESKTOP) {
				if (arr_keycodes_includes(mw->keycodes_Iconify, evk->keycode)) {
					shadow_clientwindow(cw, CLIENTOP_ICONIFY);
				}
				else if (arr_keycodes_includes(mw->keycodes_Shade, evk->keycode)) {
					shadow_clientwindow(cw, CLIENTOP_SHADE_EWMH);
				}
				else if (arr_keycodes_includes(mw->keycodes_Close, evk->keycode)) {
					return close_clientwindow(cw, CLIENTOP_CLOSE_EWMH);
				}
			}
		}
		else
			printfdf(false, "(): KeyRelease %u ignored.", evk->keycode);
    }

	else if (ev->type == ButtonPress) {
		cw->mainwin->pressed_mouse = true;
		/* if (ev->xbutton.button == 1)
			cw->mainwin->pressed = cw; */
	}
	else if (ev->type == ButtonRelease) {
		printfdf(false, "(): else if (ev->type == ButtonRelease) {");
		const unsigned button = ev->xbutton.button;
		if (cw->mainwin->pressed_mouse) {
			if (button < MAX_MOUSE_BUTTONS) {
				if (mw->client_to_focus->mode != CLIDISP_DESKTOP) {
					if (ps->o.bindings_miwMouse[button] == CLIENTOP_DESTROY
					 || ps->o.bindings_miwMouse[button] == CLIENTOP_CLOSE_EWMH
					 || ps->o.bindings_miwMouse[button] == CLIENTOP_CLOSE_ICCCM)
						return close_clientwindow(cw, ps->o.bindings_miwMouse[button]);
					else if(ps->o.bindings_miwMouse[button] == CLIENTOP_ICONIFY
						 || ps->o.bindings_miwMouse[button] == CLIENTOP_SHADE_EWMH) {
						shadow_clientwindow(cw, ps->o.bindings_miwMouse[button]);
						return 0;
					}
				}

				//CLIENTOP_FOCUS, CLIENTOP_PREV, CLIENTOP_NEXT,
				return clientwin_action(cw,
						ps->o.bindings_miwMouse[button]);
			}
		}
		else
			printfdf(false, "(): ButtonRelease %u ignored.", button);
	}

	else if (ev->type == FocusIn) {
		printfdf(false, "(): else if (ev->type == FocusIn) {");
		XFocusChangeEvent *evf = &ev->xfocus;

		// for debugging XEvents
		// see: https://tronche.com/gui/x/xlib/events/input-focus/normal-and-grabbed.html
		printfdf(false, "(): main window id = %#010lx", cw->mainwin->window);
		printfdfWindowName(ps, "(): client window = ", cw->mainwin->window);
		printfdf(false, "(): client window id = %#010lx", cw->wid_client);
		printfdfXFocusChangeEvent(ps, evf, false);

		// printfef("(): usleep(10000);");
		// usleep(10000);

		// if (evf->detail == NotifyWhileGrabbed)
		if (evf->detail == NotifyNonlinear || evf->detail == NotifyAncestor)
			cw->focused = true;

		clientwin_render(cw);
		mainwin_render_borders(cw->mainwin);

		if (debuglog) fputs("\n", stdout);
		XFlush(ps->dpy);
	} else if (ev->type == FocusOut) {
		printfdf(false, "(): else if (ev->type == FocusOut) {");
		XFocusChangeEvent *evf = &ev->xfocus;

		// for debugging XEvents
		// see: https://tronche.com/gui/x/xlib/events/input-focus/normal-and-grabbed.html
		printfdf(false, "(): main window id = %#010lx", cw->mainwin->window);
		printfdfWindowName(ps, "(): client window = ", cw->mainwin->window);
		printfdf(false, "(): client window id = %#010lx", cw->wid_client);
		printfdfXFocusChangeEvent(ps, evf, false);

		// printfef("(): usleep(10000);");
		// usleep(10000);

		// if (evf->detail == NotifyWhileGrabbed)
		if (evf->detail == NotifyNonlinear || evf->detail == NotifyPointer)
			cw->focused = false;

		clientwin_render(cw);
		mainwin_render_borders(cw->mainwin);

		if (debuglog) fputs("\n", stdout);
		XFlush(ps->dpy);

	} else if(ev->type == MotionNotify) {
		printfdf(false, "(): else if (ev->type == MotionNotify) {");

		if (cw->mainwin->client_to_focus != cw) {
			XSetInputFocus(ps->dpy, cw->mini.window, RevertToParent, CurrentTime);
			cw->mainwin->client_to_focus = cw;
		}
	} else if(ev->type == LeaveNotify) {
		printfdf(false, "(): else if (ev->type == LeaveNotify) {");
	}
	return 0;
}

static int
clientwin_action(ClientWin *cw, enum cliop action) {
	MainWin *mw = cw->mainwin;
	session_t * const ps = mw->ps;
	const Window wid = cw->wid_client;

	switch (action) {
		case CLIENTOP_NO:
			break;
		case CLIENTOP_FOCUS:
			return select_clientwindow(cw, CLIENTOP_FOCUS);
		case CLIENTOP_ICONIFY:
			/* A parked preview belongs to another tag and is kept mapped
			 * off-screen on purpose. Iconifying it would unmap it behind
			 * skippy-xd's back and desynchronise the WM, so ignore the
			 * request for those windows. */
			if (!cw->force_mapped)
				XIconifyWindow(ps->dpy, wid, ps->screen);
			break;
		case CLIENTOP_SHADE_EWMH:
			if (!cw->force_mapped)
				wm_shade_window_ewmh(ps, wid);
			break;
		case CLIENTOP_CLOSE_ICCCM:
			wm_close_window_icccm(ps, wid);
			break;
		case CLIENTOP_CLOSE_EWMH:
			wm_close_window_ewmh(ps, wid);
			break;
		case CLIENTOP_DESTROY:
			XDestroyWindow(cw->mainwin->ps->dpy, wid);
			break;
		case CLIENTOP_PREV:
			focus_miniw_prev(ps, cw->mainwin->client_to_focus);
			break;
		case CLIENTOP_NEXT:
			focus_miniw_next(ps, cw->mainwin->client_to_focus);
			break;
	}

	return 0;
}
