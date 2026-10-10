/* Draws a burst of random blocks on every monitor to give visual feedback
 * for key presses. The blocks are drawn on top of the lock window and are
 * replaced on the next key press (the logo/background is re-copied first). */
static void
draw_key_feedback(Display *dpy, struct lock **locks, int screen)
{
	XGCValues gr_values;
	struct lock *lock = locks[screen];
	Window win = lock->win;
	Window root_win;
	int i, j, nmon = 0;
	int x, y;
	unsigned int w, h, bw, d;
	unsigned int bwid, bhei;
	int count;
	int mx[8], my[8];
	unsigned int mw[8], mh[8];
	XRectangle rects[64];

	gr_values.foreground = lock->colors[BLOCKS];
	GC gc = XCreateGC(dpy, win, GCForeground, &gr_values);

	/* size of a single feedback block */
	bwid = blocks_width > 0 ? (unsigned int)blocks_width
	                        : (unsigned int)(blocks_height > 0 ? blocks_height : 16);
	bhei = blocks_height > 0 ? (unsigned int)blocks_height : bwid;

#ifdef XINERAMA
	if (xinerama_screens && xinerama_nscreens > 0) {
		nmon = xinerama_nscreens;
		if (nmon > (int)LENGTH(mx))
			nmon = (int)LENGTH(mx);
		for (i = 0; i < nmon; i++) {
			mx[i] = xinerama_screens[i].x_org;
			my[i] = xinerama_screens[i].y_org;
			mw[i] = xinerama_screens[i].width;
			mh[i] = xinerama_screens[i].height;
		}
	}
#endif // XINERAMA
	if (nmon == 0) {
		XGetGeometry(dpy, win, &root_win, &x, &y, &w, &h, &bw, &d);
		mx[0] = 0;
		my[0] = 0;
		mw[0] = w;
		mh[0] = h;
		nmon = 1;
	}

	count = blocks_count;
	if (count < 1)
		count = 1;
	if (count > (int)LENGTH(rects))
		count = (int)LENGTH(rects);

	for (i = 0; i < nmon; i++) {
		if (mw[i] <= bwid || mh[i] <= bhei)
			continue;
		for (j = 0; j < count; j++) {
			rects[j].x = mx[i] + (int)(rand() % (mw[i] - bwid));
			rects[j].y = my[i] + (int)(rand() % (mh[i] - bhei));
			rects[j].width = bwid;
			rects[j].height = bhei;
		}
		XFillRectangles(dpy, win, gc, rects, count);
	}

	XFreeGC(dpy, gc);
	XSync(dpy, False);
}
