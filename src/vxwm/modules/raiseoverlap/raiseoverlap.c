/* Windows-OS style window switching: switching to a window that another window
 * lies on top of surfaces the switched-to window above its coverers.
 *
 * Plain dwm raises the window you click only when it floats, so a tiled window
 * that a floating one partially covers can take the focus and still stay under
 * the float forever - the visible strip of it can be clicked but never comes
 * out on top. This module closes that gap for every way of switching to a
 * window: clicking it, the keyboard focus keys, alt-tab and a panel's
 * _NET_ACTIVE_WINDOW. Hovering with the pointer deliberately does not raise
 * anything; only real switches do, like in Windows.
 *
 * The raise is surgical. X's real stacking order is read with XQueryTree()
 * (children come back bottom-to-top), every window above the target is tested,
 * and only the ones that actually overlap the target's rectangle are counted;
 * the target is then re-stacked just above the topmost of those. Windows that
 * overlap nothing are left completely alone, so pure tiling never raises
 * anything (tiled windows never cover each other) and unrelated floating
 * windows keep their relative order. Fullscreen windows are never counted as
 * coverers, and pinned ones are only ever passed by another pinned window, so
 * PINNED_WINDOWS_ALWAYS_ON_TOP keeps its meaning. */

/* rectangles of a and b (borders included) share at least one pixel */
static int
rectsoverlap(Client *a, Client *b)
{
	return MAX(a->x, b->x) < MIN(a->x + WIDTH(a), b->x + WIDTH(b))
	    && MAX(a->y, b->y) < MIN(a->y + HEIGHT(a), b->y + HEIGHT(b));
}

void
raiseoverlap(Client *c)
{
	Client *t;
	Window d1, d2, *wins = NULL, cover = None;
	XWindowChanges wc;
	unsigned int i, n;
	int above = 0;

	if (!c || c->isfullscreen)
		return; /* a fullscreen window already sits on top of everything */

	/* XQueryTree() lists root's children bottom-to-top: every window listed
	   after c is stacked above it, everything before it is below. */
	if (!XQueryTree(dpy, root, &d1, &d2, &wins, &n))
		return;
	for (i = 0; i < n; i++) {
		if (!above) {
			if (wins[i] == c->win)
				above = 1;
			continue; /* still below c: cannot be covering it */
		}
		if (!(t = wintoclient(wins[i])))
			continue; /* bar, panels, menus, docks: not ours to reorder */
		if (!ISVISIBLE(t) || t->isfullscreen)
			continue; /* windows of other tags; fullscreen stays on top */
		if (t->is_pinned && !c->is_pinned)
			continue; /* PINNED_WINDOWS_ALWAYS_ON_TOP is honoured */
		if (rectsoverlap(c, t))
			cover = t->win; /* keep the topmost window covering c */
	}
	XFree(wins);

	if (cover == None)
		return; /* nothing covers c: the stacking order stays untouched */

	/* put c right on top of its topmost coverer; everything else,
	   including windows that do not overlap c, keeps its place */
	wc.sibling = cover;
	wc.stack_mode = Above;
	XConfigureWindow(dpy, c->win, CWSibling|CWStackMode, &wc);
}
