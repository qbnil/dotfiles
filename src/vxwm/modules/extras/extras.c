/* Ideas ported from chadwm (siduck/chadwm), rewritten for vxwm.
 * All layouts honour m->gappx (outer gap == inner gap, same as tile()/grid()),
 * m->mfact and m->nmaster, and use int math so no unsigned wrap-around. */

#if EXTRA_LAYOUTS

static int
extra_gap(Monitor *m)
{
#if GAPS
	return m->gappx;
#else
	(void)m;
	return 0;
#endif
}

void
bstack(Monitor *m)
{
	int i, n, nm, g = extra_gap(m);
	int x, y, w, h, mh, sy, sh, mx, sx, cw;
	Client *c;

	for (n = 0, c = nexttiled(m->clients); c; c = nexttiled(c->next), n++);
	if (n == 0)
		return;

	x = m->wx + g;
	y = m->wy + g;
	w = m->ww - 2 * g;
	h = m->wh - 2 * g;

	nm = MIN(MAX(m->nmaster, 0), n);
	if (nm > 0 && nm < n) {
		mh = (h - g) * m->mfact;
		sy = y + mh + g;
		sh = h - mh - g;
	} else {
		mh = h;  /* everything is master */
		sy = y;  /* or everything is stack */
		sh = h;
	}

	mx = sx = x;
	for (i = 0, c = nexttiled(m->clients); c; c = nexttiled(c->next), i++) {
		if (i < nm) {
			cw = (x + w - mx - g * (nm - 1 - i)) / (nm - i);
			resize(c, mx, y, cw - 2 * c->bw, mh - 2 * c->bw, 0);
			mx += cw + g;
		} else {
			cw = (x + w - sx - g * (n - 1 - i)) / (n - i);
			resize(c, sx, sy, cw - 2 * c->bw, sh - 2 * c->bw, 0);
			sx += cw + g;
		}
	}
}

void
centeredmaster(Monitor *m)
{
	int i, j, k, n, nm, ns, nl, nr, g = extra_gap(m);
	int x, y, w, h, mw, lw, rw, mx, lx, rx, my, ly, ry, ch;
	Client *c;

	for (n = 0, c = nexttiled(m->clients); c; c = nexttiled(c->next), n++);
	if (n == 0)
		return;

	x = m->wx + g;
	y = m->wy + g;
	w = m->ww - 2 * g;
	h = m->wh - 2 * g;

	nm = MIN(MAX(m->nmaster, 1), n);   /* at least one master in this layout */
	ns = n - nm;
	nr = (ns + 1) / 2;                 /* stack clients alternate right, left, ... */
	nl = ns / 2;

	if (ns == 0) {                     /* master only: full width */
		mw = w; mx = x;
		lw = rw = lx = rx = 0;
	} else if (nl == 0) {              /* one stack client: master left, stack right */
		mw = (w - g) * m->mfact;
		mx = x;
		rx = mx + mw + g;
		rw = w - mw - g;
		lw = lx = 0;
	} else {                           /* master centred, stacks on both sides */
		mw = (w - 2 * g) * m->mfact;
		lw = (w - 2 * g - mw) / 2;
		rw = w - 2 * g - mw - lw;
		lx = x;
		mx = lx + lw + g;
		rx = mx + mw + g;
	}

	my = ly = ry = y;
	for (i = 0, c = nexttiled(m->clients); c; c = nexttiled(c->next), i++) {
		if (i < nm) {
			ch = (y + h - my - g * (nm - 1 - i)) / (nm - i);
			resize(c, mx, my, mw - 2 * c->bw, ch - 2 * c->bw, 0);
			my += ch + g;
		} else {
			j = i - nm;
			k = j / 2;
			if (j % 2 == 0) {      /* right column */
				ch = (y + h - ry - g * (nr - 1 - k)) / (nr - k);
				resize(c, rx, ry, rw - 2 * c->bw, ch - 2 * c->bw, 0);
				ry += ch + g;
			} else {               /* left column */
				ch = (y + h - ly - g * (nl - 1 - k)) / (nl - k);
				resize(c, lx, ly, lw - 2 * c->bw, ch - 2 * c->bw, 0);
				ly += ch + g;
			}
		}
	}
}

void
deck(Monitor *m)
{
	int i, n, nm, g = extra_gap(m);
	int x, y, w, h, mw, sx, sw, my, ch;
	Client *c;

	for (n = 0, c = nexttiled(m->clients); c; c = nexttiled(c->next), n++);
	if (n == 0)
		return;

	x = m->wx + g;
	y = m->wy + g;
	w = m->ww - 2 * g;
	h = m->wh - 2 * g;

	nm = MIN(MAX(m->nmaster, 0), n);
	if (n > nm) {
		mw = nm ? (w - g) * m->mfact : 0;
		sx = nm ? x + mw + g : x;
		sw = nm ? w - mw - g : w;
		snprintf(m->ltsymbol, sizeof m->ltsymbol, "D%d", n - nm);
	} else {
		mw = w;
		sx = sw = 0;
	}

	my = y;
	for (i = 0, c = nexttiled(m->clients); c; c = nexttiled(c->next), i++) {
		if (i < nm) {
			ch = (y + h - my - g * (nm - 1 - i)) / (nm - i);
			resize(c, x, my, mw - 2 * c->bw, ch - 2 * c->bw, 0);
			my += ch + g;
		} else {
			/* every stack client gets the same box; focus order decides who is on top */
			resize(c, sx, y, sw - 2 * c->bw, h - 2 * c->bw, 0);
		}
	}
}

#endif /* EXTRA_LAYOUTS */

#if LAYOUT_CYCLE
/* Cycle through the layouts that actually tile. The floating layout is skipped on
 * purpose: it keeps its own bind and setlayout() does extra canvas work for it. */
void
cyclelayout(const Arg *arg)
{
	const Layout *cur = curlayout(selmon);
	int n = LENGTH(layouts), idx = 0, i, k, j;
	Arg a;

	for (i = 0; i < n; i++)
		if (&layouts[i] == cur) {
			idx = i;
			break;
		}
	for (k = 1; k <= n; k++) {
		j = ((idx + (arg->i > 0 ? k : -k)) % n + n) % n;
		if (layouts[j].arrange) {
			a.v = &layouts[j];
			setlayout(&a);
			return;
		}
	}
}
#endif

#if SHIFTVIEW
void
shiftview(const Arg *arg)
{
	Arg shifted;
	unsigned int cur = selmon->tagset[selmon->seltags] & TAGMASK;
	int nt = LENGTH(tags);

	if (cur == TAGMASK)  /* "all tags" view: nothing sensible to rotate */
		return;
	if (arg->i > 0)
		shifted.ui = (cur << 1) | (cur >> (nt - 1));
	else
		shifted.ui = (cur >> 1) | (cur << (nt - 1));
	shifted.ui &= TAGMASK;
	view(&shifted);
}
#endif

#if MOVESTACK
/* Swap the selected tiled client with the next/previous visible tiled one in the
 * client list. Works in every layout (movedir only handles tile()). */
void
movestack(const Arg *arg)
{
	Client *sel = selmon->sel, *c = NULL, *p = NULL, *pc = NULL, *i, *temp;

	if (!sel || sel->isfloating)
		return;

	if (arg->i > 0) {
		for (c = sel->next; c && (!ISVISIBLE(c) || c->isfloating); c = c->next);
		if (!c)
			for (c = selmon->clients; c && (!ISVISIBLE(c) || c->isfloating); c = c->next);
	} else {
		for (i = selmon->clients; i != sel; i = i->next)
			if (ISVISIBLE(i) && !i->isfloating)
				c = i;
		if (!c)
			for (; i; i = i->next)
				if (ISVISIBLE(i) && !i->isfloating)
					c = i;
	}
	if (!c || c == sel)
		return;

	/* predecessors of sel and c in the list */
	for (i = selmon->clients; i && (!p || !pc); i = i->next) {
		if (i->next == sel)
			p = i;
		if (i->next == c)
			pc = i;
	}

	temp = sel->next == c ? sel : sel->next;
	sel->next = c->next == sel ? c : c->next;
	c->next = temp;
	if (p && p != c)
		p->next = c;
	if (pc && pc != sel)
		pc->next = sel;
	if (sel == selmon->clients)
		selmon->clients = c;
	else if (c == selmon->clients)
		selmon->clients = sel;

	arrange(selmon);
}
#endif
