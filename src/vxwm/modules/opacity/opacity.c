/* opacity - per-window transparency via _NET_WM_WINDOW_OPACITY
 *
 * Needs a running compositor in client-side mode (xcompmgr -c or vcompmgr -c).
 * Without one, setting the property is a harmless no-op visually.
 *
 * Two global levels, applied automatically:
 *   - focused   (config.h opacity_focused)   set in focus()
 *   - unfocused (config.h opacity_unfocused) set in unfocus()
 *
 * A window that the user has adjusted by hand keeps its own value; the global
 * values only apply to windows that were never touched. Otherwise alt-tabbing
 * back and forth would keep resetting a per-window choice.
 */

#include <X11/Xatom.h>

/* Tunables live in config.h. These are the live, mutable copies the keybinds
   adjust, seeded from config.h on first use. */
static unsigned int opacity_focused_v   = opacity_focused;
static unsigned int opacity_unfocused_v = opacity_unfocused;
static unsigned int opacity_step_v      = opacity_step;
static unsigned int opacity_min_v       = opacity_min;
static unsigned int opacity_max_v       = opacity_max;
static Bool opacity_enabled = True;

static unsigned int
opacity_clamp(int percent)
{
	if (percent > (int)opacity_max_v)
		percent = (int)opacity_max_v;
	if (percent < (int)opacity_min_v)
		percent = (int)opacity_min_v;
	return (unsigned int)percent;
}

/* 0-100 -> 32-bit value _NET_WM_WINDOW_OPACITY expects (0xffffffff = opaque) */
static unsigned int
opacity_scale(unsigned int percent)
{
	if (percent > 100)
		percent = 100;
	return (unsigned int)(((unsigned long)percent * 0xffffffffUL) / 100UL);
}

static void
opacity_apply(Client *c, unsigned int percent)
{
	unsigned int value;

	if (!c)
		return;
	percent = opacity_clamp((int)percent);
	c->opacity = percent;
	value = opacity_scale(percent);
	XChangeProperty(dpy, c->win, netatom[NetWMWindowOpacity], XA_CARDINAL, 32,
	                PropModeReplace, (unsigned char *)&value, 1);
}

/* opacity the window should show right now, honouring a per-window override */
static unsigned int
opacity_for(Client *c, int focused)
{
	if (!c)
		return 100;
	if (c->opacity_set)
		return c->opacity;
	return focused ? opacity_focused_v : opacity_unfocused_v;
}

/* re-apply the right value to every visible window, after a global change */
static void
opacity_refreshall(void)
{
	Monitor *m;
	Client *c;

	for (m = mons; m; m = m->next)
		for (c = m->stack; c; c = c->snext)
			if (ISVISIBLE(c))
				opacity_apply(c, opacity_enabled
				              ? opacity_for(c, c == m->sel)
				              : 100);
}

/* adjust the focused window's own opacity, and pin it as a per-window choice.
   arg->i > 0 means more opaque, matching the Up/Down binds in config.h. */
void
incopacity(const Arg *arg)
{
	Client *c = selmon->sel;
	int p;

	if (!c || !arg)
		return;
	c->opacity_set = 1;
	p = (int)opacity_for(c, 1)
	    + (arg->i > 0 ? (int)opacity_step_v : -(int)opacity_step_v);
	opacity_apply(c, opacity_clamp(p));
}

/* Adjust the global default for unfocused windows, and refresh everything so the
   change is visible at once rather than one window at a time. Nothing on screen
   changes when only one window is visible, so echo the new value in the bar. */
void
incopacityunfocused(const Arg *arg)
{
	int p, visible = 0;
	Client *c;
	Monitor *m;

	if (!arg)
		return;
	p = (int)opacity_unfocused_v
	    + (arg->i > 0 ? (int)opacity_step_v : -(int)opacity_step_v);
	opacity_unfocused_v = opacity_clamp(p);
	opacity_refreshall();

	for (m = mons; m; m = m->next)
		for (c = m->stack; c; c = c->snext)
			if (ISVISIBLE(c))
				visible++;
	if (visible < 2) {
		snprintf(stext, sizeof stext, "unfocused opacity %d%%",
		         (int)opacity_unfocused_v);
		updatestatus();
	}
}

void
resetopacity(const Arg *arg)
{
	Client *c = selmon->sel;

	(void)arg;
	if (!c)
		return;
	/* drop the override and snap back to whatever the globals say */
	c->opacity_set = 0;
	opacity_apply(c, opacity_for(c, 1));
}

void
toggleopacity(const Arg *arg)
{
	(void)arg;

	opacity_enabled = !opacity_enabled;
	opacity_refreshall();
}
