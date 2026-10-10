static void
drawlogo(Display *dpy, struct lock *lock, int color)
{
	int j;
	#ifdef XINERAMA
	int i;
	#endif
	int nrects = LENGTH(rectangles);
	int gridw = logow * logosize;
	int gridh = logoh * logosize;
	XRectangle rects[LENGTH(rectangles)];

	#if BLUR_PIXELATED_SCREEN_PATCH
	if (lock->bgmap) {
		lock->drawable = lock->bgmap;
	} else {
		/* screenshot unavailable: fall back to a solid background */
		XSetForeground(dpy, lock->gc, lock->colors[INIT]);
		XFillRectangle(dpy, lock->drawable, lock->gc, 0, 0, lock->x, lock->y);
	}
	#else
	XSetForeground(dpy, lock->gc, lock->colors[BACKGROUND]);
	XFillRectangle(dpy, lock->drawable, lock->gc, 0, 0, lock->x, lock->y);
	#endif // BLUR_PIXELATED_SCREEN_PATCH

	XSetForeground(dpy, lock->gc, lock->colors[color]);

#ifdef XINERAMA
	if (xinerama_screens && xinerama_nscreens > 0) {
		/* draw one logo, centred on each monitor */
		for (i = 0; i < xinerama_nscreens; i++) {
			int cx = xinerama_screens[i].x_org + xinerama_screens[i].width / 2;
			int cy = xinerama_screens[i].y_org + xinerama_screens[i].height / 2;

			for (j = 0; j < nrects; j++) {
				rects[j].x = cx - gridw / 2 + rectangles[j].x * logosize;
				rects[j].y = cy - gridh / 2 + rectangles[j].y * logosize;
				rects[j].width = rectangles[j].width * logosize;
				rects[j].height = rectangles[j].height * logosize;
			}
			XFillRectangles(dpy, lock->drawable, lock->gc, rects, nrects);
		}
	} else
#endif // XINERAMA
	{
		/* single monitor (or no Xinerama): centre on the lock window */
		int cx = lock->x / 2;
		int cy = lock->y / 2;

		for (j = 0; j < nrects; j++) {
			rects[j].x = cx - gridw / 2 + rectangles[j].x * logosize;
			rects[j].y = cy - gridh / 2 + rectangles[j].y * logosize;
			rects[j].width = rectangles[j].width * logosize;
			rects[j].height = rectangles[j].height * logosize;
		}
		XFillRectangles(dpy, lock->drawable, lock->gc, rects, nrects);
	}

	XCopyArea(dpy, lock->drawable, lock->win, lock->gc, 0, 0, lock->x, lock->y, 0, 0);
	XSync(dpy, False);
}
