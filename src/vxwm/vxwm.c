/* See LICENSE file for copyright and license details.
This wm is forked from dwm 6.7 (but keeps up with all dwm's updates), thanks suckless for their incredible work on dwm!
Infinite tags module is heavily inspired from 5element which is inspired from the hevel wayland compositor.

vxwm 2.2 // by wh1tepearl

I just realised that i haven't commenting the entire code, sure i can perfectly read it but for the people that want to fork vxwm/make something with vxwm's code it is a pain in the ass.
From this moment, i'll try to comment the code and also make it more readable.

*/

// Modules configuration is in modules.h
// Config is in config.h

#include <errno.h>
#include <locale.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <X11/cursorfont.h>
#include <X11/keysym.h>
#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <X11/Xproto.h>
#include <X11/Xutil.h>
#include <X11/XF86keysym.h>
#ifdef XINERAMA
#include <X11/extensions/Xinerama.h>
#endif /* XINERAMA */
#include <X11/Xft/Xft.h>

#include "modules.h"
#include "drw.h"
#include "util.h"

#if INFINITE_TAGS && !WINDOWMAP
    #undef WINDOWMAP
    #define WINDOWMAP 1
#endif

#if ENHANCED_TOGGLE_FLOATING && !FLOATING_LAYOUT_FLOATS_WINDOWS
  #undef FLOATING_LAYOUT_FLOATS_WINDOWS
  #define FLOATING_LAYOUT_FLOATS_WINDOWS 1
#endif

/* macros */
#define BUTTONMASK              (ButtonPressMask|ButtonReleaseMask)
#define CLEANMASK(mask)         (mask & ~(numlockmask|LockMask) & (ShiftMask|ControlMask|Mod1Mask|Mod2Mask|Mod3Mask|Mod4Mask|Mod5Mask))
#define INTERSECT(x,y,w,h,m)    (MAX(0, MIN((x)+(w),(m)->wx+(m)->ww) - MAX((x),(m)->wx)) \
                               * MAX(0, MIN((y)+(h),(m)->wy+(m)->wh) - MAX((y),(m)->wy)))
#define ISVISIBLE(C)            ((C->tags & C->mon->tagset[C->mon->seltags]))
#define MOUSEMASK               (BUTTONMASK|PointerMotionMask)
#define WIDTH(X)                ((X)->w + 2 * (X)->bw)
#define HEIGHT(X)               ((X)->h + 2 * (X)->bw)
#define TAGMASK                 ((1 << LENGTH(tags)) - 1)
#define TEXTW(X)                (drw_fontset_getwidth(drw, (X)) + lrpad)

#if !WINDOWMAP
  #if !PDWM_LIKE_TAGS_ANIMATION
    #if !SLOWER_TAGS_ANIMATION
      #define SHOWHIDEPROFILE XMoveWindow(dpy, c->win, WIDTH(c) * -2, c->y);  // Vanilla
    #else
      #define SHOWHIDEPROFILE XMoveWindow(dpy, c->win, WIDTH(c) * -1, c->y);  // Slower vanilla
    #endif
  #else
    #if !SLOWER_TAGS_ANIMATION
      #define SHOWHIDEPROFILE XMoveWindow(dpy, c->win, c->mon->wx + c->mon->ww / 2, -(HEIGHT(c) * 3) / 2);  // pdwm vanilla
    #else
      #define SHOWHIDEPROFILE XMoveWindow(dpy, c->win, c->mon->wx + c->mon->ww / 2, -(HEIGHT(c)));  // Slower pdwm
    #endif
  #endif
#else
  #define SHOWHIDEPROFILE 		if (c->ismapped) { \
			                          window_unmap(dpy, c->win, root, 1); \
			                          c->ismapped = 0; \
		                          } 
#endif

/* This is purely for a bit less sucky config */
#if !XRDB
#define MAYBE_CONST const
#else
#define MAYBE_CONST
#endif

/* enums */
enum { CurNormal, CurResize, CurMove,
#if BETTER_RESIZE && BR_CHANGE_CURSOR
       CurNW, CurNE, CurSW, CurSE,  // corner cursors
       CurN, CurS, CurE, CurW,       // edge cursors
#endif
       CurLast }; /* cursor */

enum { SchemeNorm, SchemeSel }; /* color schemes */
enum { NetSupported, NetWMName, NetWMState, NetWMCheck,
       NetWMFullscreen, NetActiveWindow, NetWMWindowType,
#if !EWMH_TAGS
       NetWMWindowTypeDialog, NetClientList, NetLast }; /* EWMH atoms */
#else //EWMH_TAGS 
       NetWMWindowTypeDialog, NetClientList, NetDesktopNames, NetDesktopViewport, NetNumberOfDesktops, NetCurrentDesktop, NetDesktopNum, NetWMWindowOpacity, NetLast }; /* EWMH atoms */
#endif
enum { WMProtocols, WMDelete, WMState, WMTakeFocus, WMLast }; /* default atoms */
enum { ClkTagBar, ClkLtSymbol, ClkStatusText, ClkWinTitle,
       ClkClientWin, ClkRootWin, ClkLast }; /* clicks */

typedef union {
	int i;
	unsigned int ui;
	float f;
	const void *v;
} Arg;

typedef struct {
	unsigned int click;
	unsigned int mask;
	unsigned int button;
	void (*func)(const Arg *arg);
	const Arg arg;
} Button;

typedef struct Monitor Monitor;
typedef struct Client Client;
struct Client {
	char name[256];
	float mina, maxa;
	int x, y, w, h;
	int oldx, oldy, oldw, oldh;
	int basew, baseh, incw, inch, maxw, maxh, minw, minh, hintsvalid;
	int bw, oldbw;
	unsigned int tags;
	int isfixed, isfloating, isurgent, neverfocus, oldstate, isfullscreen;
	int stripsz[2];
	int fslot; /* floating-canvas slot (1-based), 0 = none */   /* own size in [H] / [V], in 1/1000 of the screen; 0 = default */
	Client *next;
	Client *snext;
	Monitor *mon;
	Window win;
#if INFINITE_TAGS
  int saved_cx, saved_cy;
  int saved_cw, saved_ch;
  int was_on_canvas;
  int is_pinned;
#endif
#if WINDOWMAP
  int ismapped;
#endif
#if ENHANCED_TOGGLE_FLOATING
  int sfx, sfy, sfw, sfh;
  #if RESTORE_SIZE_AND_POS_ETF
    int wasmanuallyedited;
  #endif
#endif
#if OPACITY
  unsigned int opacity;      /* current 0-100 opacity applied to this window */
  unsigned int opacity_set;  /* 1 if the user picked this value by hand */
#endif
};

typedef struct {
	unsigned int mod;
	KeySym keysym;
	void (*func)(const Arg *);
	const Arg arg;
} Key;

typedef struct {
	const char *symbol;
	void (*arrange)(Monitor *);
} Layout;

#if INFINITE_TAGS
typedef struct {
    int cx, cy;
    int saved_cx, saved_cy;
} CanvasOffset;
#endif

struct Monitor {
	char ltsymbol[16];
	float mfact;
	int nmaster;
	int num;
	int by;               /* bar geometry */
	int mx, my, mw, mh;   /* screen size */
	int wx, wy, ww, wh;   /* window area  */
#if GAPS
  int gappx;            /* gaps between windows */
#endif
	unsigned int seltags;
	unsigned int sellt;
	unsigned int tagset[2];
	int showbar;
	int topbar;
	Client *clients;
	Client *sel;
	Client *stack;
	Monitor *next;
	Window barwin;
	const Layout *lt[2];
#if PER_TAG_LAYOUT
  const Layout **pertaglt;
  unsigned int *pertagsellt;
  float *pertagmfact;      /* master size of each tag; m->mfact is the one of the shown tag */
#endif
#if INFINITE_TAGS
  CanvasOffset *canvas;
#endif
#if EXTERNAL_BARS
  int strut_top, strut_bottom, strut_left, strut_right;
#endif
};

typedef struct {
	const char *class;
	const char *instance;
	const char *title;
	unsigned int tags;
	int isfloating;
	int monitor;
} Rule;

/* function declarations */
static void applyrules(Client *c);
static int applysizehints(Client *c, int *x, int *y, int *w, int *h, int interact);
static void arrange(Monitor *m);
static void arrangemon(Monitor *m);
static void attach(Client *c);
static void attachstack(Client *c);
static void buttonpress(XEvent *e);
static void checkotherwm(void);
static void cleanup(void);
static void cleanupmon(Monitor *mon);
static void clientmessage(XEvent *e);
static void configure(Client *c);
static void configurenotify(XEvent *e);
static void configurerequest(XEvent *e);
static Monitor *createmon(void);
static void destroynotify(XEvent *e);
static void detach(Client *c);
static void detachstack(Client *c);
static Monitor *dirtomon(int dir);
static void drawbar(Monitor *m);
static void drawbars(void);
static void enternotify(XEvent *e);
static void expose(XEvent *e);
static void focus(Client *c);
static void focusin(XEvent *e);
static void focusmon(const Arg *arg);
static void focusstack(const Arg *arg) __attribute__((unused)); /* kept for config.h binds; unused while they are commented out */
static Atom getatomprop(Client *c, Atom prop);
static int getrootptr(int *x, int *y);
static long getstate(Window w);
static int gettextprop(Window w, Atom atom, char *text, unsigned int size);
static void grabbuttons(Client *c, int focused);
static void grabkeys(void);
static void incnmaster(const Arg *arg);
static void keypress(XEvent *e);
static void killclient(const Arg *arg);
static void manage(Window w, XWindowAttributes *wa);
static void mappingnotify(XEvent *e);
static void maprequest(XEvent *e);
static void monocle(Monitor *m);
static void monocle_symbol(Monitor *m);
static void motionnotify(XEvent *e);
static void movemouse(const Arg *arg);
static Client *nexttiled(Client *c);
static void pop(Client *c);
static void propertynotify(XEvent *e);
static void quit(const Arg *arg);
static Monitor *recttomon(int x, int y, int w, int h);
static void resize(Client *c, int x, int y, int w, int h, int interact);
static void resizeclient(Client *c, int x, int y, int w, int h);
static void resizemouse(const Arg *arg);
static void restack(Monitor *m);
static void run(void);
static void scan(void);
static int sendevent(Client *c, Atom proto);
static void sendmon(Client *c, Monitor *m);
static void setclientstate(Client *c, long state);
static void setfocus(Client *c);
static void setfullscreen(Client *c, int fullscreen);
static void setlayout(const Arg *arg);
static void setmfact(const Arg *arg);
static void setup(void);
static void seturgent(Client *c, int urg);
static void showhide(Client *c);
static void spawn(const Arg *arg);
static void tag(const Arg *arg);
static void tagmon(const Arg *arg);
static void tile(Monitor *m);
static void grid(Monitor *m);
static void floatspread(Monitor *m);
static int floatgap(Monitor *m);

static void floatresolve(Client *c);
static void floatfix(Monitor *m, Client *keep, int margin);

static void floatreveal(Client *c);
static void floatplace(Client *c, int tx, int ty, Monitor *m, Client *skip);
static int floatfocus(int dir);
static int floatbusy = 0;
#define FLOAT_W 0.75f  /* window size as share of the work area */
#define FLOAT_H 0.78f

static void strip(Monitor *m);
static void vstrip(Monitor *m);
static void focusstrip(const Arg *arg);
static void stripresize(const Arg *arg);
static int stripnoscroll = 0; /* set while a mouse hover changes focus: don't scroll */
static int stripbusy = 0;     /* reentrancy guard for the focus() hook */
static void togglebar(const Arg *arg);
static void togglefloating(const Arg *arg);
static void toggletag(const Arg *arg);
static void toggleview(const Arg *arg);
static void unfocus(Client *c, int setfocus);
static void unmanage(Client *c, int destroyed);
static void unmapnotify(XEvent *e);
static void updatebarpos(Monitor *m);
static void updatebars(void);
static void updateclientlist(void);
static int updategeom(void);
static void updatenumlockmask(void);
static void updatesizehints(Client *c);
static void updatestatus(void);
static void updatetitle(Client *c);
static void updatewindowtype(Client *c);
static void updatewmhints(Client *c);
static void view(const Arg *arg);
static Client *wintoclient(Window w);
static Monitor *wintomon(Window w);
static int xerror(Display *dpy, XErrorEvent *ee);
static int xerrordummy(Display *dpy, XErrorEvent *ee);
static int xerrorstart(Display *dpy, XErrorEvent *ee);
static void swapmaster(const Arg *arg);
static const Layout *curlayout(Monitor *m);
#if PER_TAG_LAYOUT
static void setcurlayout(Monitor *m, const Layout *l);
static void loadtaglayout(Monitor *m);
#endif

#include "modules/vxwm_includes.h"

/* variables */
static const char broken[] = "broken";
static char stext[256];
static int screen;
static int sw, sh;           /* X display screen geometry width, height */
static int bh;               /* bar height */
static int lrpad;            /* sum of left and right padding for text */

#if BAR_PADDING
static int tvp;              /* top vertical padding for bar */
static int bvp;              /* bottom vertical padding for bar */
static int lsp;              /* left side padding for bar */
static int rsp;              /* right side padding for bar */
#endif

static int (*xerrorxlib)(Display *, XErrorEvent *);
static unsigned int numlockmask = 0;
static void (*handler[LASTEvent]) (XEvent *) = {
	[ButtonPress] = buttonpress,
	[ClientMessage] = clientmessage,
	[ConfigureRequest] = configurerequest,
	[ConfigureNotify] = configurenotify,
	[DestroyNotify] = destroynotify,
	[EnterNotify] = enternotify,
	[Expose] = expose,
	[FocusIn] = focusin,
	[KeyPress] = keypress,
	[MappingNotify] = mappingnotify,
	[MapRequest] = maprequest,
	[MotionNotify] = motionnotify,
	[PropertyNotify] = propertynotify,
	[UnmapNotify] = unmapnotify
};
static Atom wmatom[WMLast], netatom[NetLast];
static int running = 1;
static Cur *cursor[CurLast];
static Clr **scheme;
static Display *dpy;
static Drw *drw;
static Monitor *mons, *selmon;
static Window root, wmcheckwin;

/* configuration, allows nested code to access above variables */
#include "config.h"
#include "modules/vxwm_includes.c"

/* compile-time check if all tags fit into an unsigned int bit array. */
struct NumTags { char limitexceeded[LENGTH(tags) > 31 ? -1 : 1]; };

/* function implementations */
void
applyrules(Client *c)
{
	const char *class, *instance;
	unsigned int i;
	const Rule *r;
	Monitor *m;
	XClassHint ch = { NULL, NULL };

	/* rule matching */
	c->isfloating = 0;
	c->tags = 0;
	XGetClassHint(dpy, c->win, &ch);
	class    = ch.res_class ? ch.res_class : broken;
	instance = ch.res_name  ? ch.res_name  : broken;

	for (i = 0; i < LENGTH(rules); i++) {
		r = &rules[i];
		if ((!r->title || strstr(c->name, r->title))
		&& (!r->class || strstr(class, r->class))
		&& (!r->instance || strstr(instance, r->instance)))
		{
			c->isfloating = r->isfloating;
			c->tags |= r->tags;
			for (m = mons; m && m->num != r->monitor; m = m->next);
			if (m)
				c->mon = m;
		}
	}
	if (ch.res_class)
		XFree(ch.res_class);
	if (ch.res_name)
		XFree(ch.res_name);
	c->tags = c->tags & TAGMASK ? c->tags & TAGMASK : c->mon->tagset[c->mon->seltags];
}

int
applysizehints(Client *c, int *x, int *y, int *w, int *h, int interact)
{
	int baseismin;
	Monitor *m = c->mon;

	/* set minimum possible */
	*w = MAX(1, *w);
	*h = MAX(1, *h);
	if (interact) {
#if INFINITE_TAGS
	if (selmon->lt[selmon->sellt]->arrange != NULL) {
#endif
		if (*x > sw)
			*x = sw - WIDTH(c);
		if (*y > sh)
			*y = sh - HEIGHT(c);
		if (*x + *w + 2 * c->bw < 0)
			*x = 0;
		if (*y + *h + 2 * c->bw < 0)
			*y = 0;
#if INFINITE_TAGS
	}
#endif
	}
#if INFINITE_TAGS
	else if (m->lt[m->sellt]->arrange == NULL) {
		/* floating canvas: windows may live anywhere, never pull them back on screen */
	}
#endif
	else {
		if (*x >= m->wx + m->ww)
			*x = m->wx + m->ww - WIDTH(c);
		if (*y >= m->wy + m->wh)
			*y = m->wy + m->wh - HEIGHT(c);
		if (*x + *w + 2 * c->bw <= m->wx)
			*x = m->wx;
		if (*y + *h + 2 * c->bw <= m->wy)
			*y = m->wy;
	}
	if (*h < bh)
		*h = bh;
	if (*w < bh)
		*w = bh;
	if (resizehints || c->isfloating || !c->mon->lt[c->mon->sellt]->arrange) {
		if (!c->hintsvalid)
			updatesizehints(c);
		/* see last two sentences in ICCCM 4.1.2.3 */
		baseismin = c->basew == c->minw && c->baseh == c->minh;
		if (!baseismin) { /* temporarily remove base dimensions */
			*w -= c->basew;
			*h -= c->baseh;
		}
		/* adjust for aspect limits */
		if (c->mina > 0 && c->maxa > 0) {
			if (c->maxa < (float)*w / *h)
				*w = *h * c->maxa + 0.5;
			else if (c->mina < (float)*h / *w)
				*h = *w * c->mina + 0.5;
		}
		if (baseismin) { /* increment calculation requires this */
			*w -= c->basew;
			*h -= c->baseh;
		}
		/* adjust for increment value */
		if (c->incw)
			*w -= *w % c->incw;
		if (c->inch)
			*h -= *h % c->inch;
		/* restore base dimensions */
		*w = MAX(*w + c->basew, c->minw);
		*h = MAX(*h + c->baseh, c->minh);
		if (c->maxw)
			*w = MIN(*w, c->maxw);
		if (c->maxh)
			*h = MIN(*h, c->maxh);
	}
	return *x != c->x || *y != c->y || *w != c->w || *h != c->h;
}

#if PER_TAG_LAYOUT
/* Index of the tag currently shown on this monitor. Same idea as
   getcurrenttag() but always available, even without INFINITE_TAGS. */
static int
currenttagidx(Monitor *m)
{
	unsigned int i;
	for (i = 0; i < LENGTH(tags) && !(m->tagset[m->seltags] & (1 << i)); i++);
	return i < LENGTH(tags) ? (int)i : 0;
}
#endif

/* Layout of the tag currently shown on this monitor. Available regardless of
   PER_TAG_LAYOUT so modules can call it unconditionally. */
const Layout *
curlayout(Monitor *m)
{
#if PER_TAG_LAYOUT
	return m->pertaglt[currenttagidx(m)];
#else
	return m->lt[m->sellt];
#endif
}

#if PER_TAG_LAYOUT
/* Assign a layout to the tag currently shown on this monitor. The
   per-monitor lt[]/sellt pair is kept in sync because plenty of code still
   reads the layout through m->lt[m->sellt]. */
void
setcurlayout(Monitor *m, const Layout *l)
{
	m->pertaglt[currenttagidx(m)] = l;
	m->lt[0] = l;
	m->sellt = 0;
}

/* Re-apply the stored layout of the tag now being shown. Called on tag
   switch so m->lt/m->sellt follow the tag. */
void
loadtaglayout(Monitor *m)
{
	m->lt[0] = curlayout(m);
	m->sellt = 0;
	m->mfact = m->pertagmfact[currenttagidx(m)];
}
#endif

void
arrange(Monitor *m)
{
#if WINDOWMAP
	XGrabServer(dpy);
#endif
	if (m)
		showhide(m->stack);
	else for (m = mons; m; m = m->next)
		showhide(m->stack);
#if WINDOWMAP
	XUngrabServer(dpy);
	XSync(dpy, False);
#endif
	if (m) {
		arrangemon(m);
		restack(m);
	} else for (m = mons; m; m = m->next)
		arrangemon(m);
}

void
arrangemon(Monitor *m)
{
	const Layout *lt = m->lt[m->sellt];

#if PER_TAG_LAYOUT
	lt = curlayout(m);
#endif
	strncpy(m->ltsymbol, lt->symbol, sizeof m->ltsymbol - 1);
  m->ltsymbol[sizeof m->ltsymbol - 1] = '\0';
	if (lt->arrange)
		lt->arrange(m);
}

void
attach(Client *c)
{
	c->next = c->mon->clients;
	c->mon->clients = c;
}

void
attachstack(Client *c)
{
	c->snext = c->mon->stack;
	c->mon->stack = c;
}

void
buttonpress(XEvent *e)
{
#if !OCCUPIED_TAGS_DECORATION
	unsigned int i, x, click;
#else
  unsigned int i, x, click, occ;
#endif
	Arg arg = {0};
	Client *c;
	Monitor *m;
	XButtonPressedEvent *ev = &e->xbutton;

	click = ClkRootWin;
	/* focus monitor if necessary */
	if ((m = wintomon(ev->window)) && m != selmon) {
		unfocus(selmon->sel, 1);
		selmon = m;
		focus(NULL);
	}
	if (ev->window == selmon->barwin) {
#if !OCCUPIED_TAGS_DECORATION
		i = x = 0;
#else 
		i = x = occ = 0;
		/* Bitmask of occupied tags */
		for (c = m->clients; c; c = c->next)
			occ |= c->tags;
#endif
		do
#if !OCCUPIED_TAGS_DECORATION
			x += TEXTW(tags[i]);
#else 
			x += TEXTW(occ & 1 << i ? occupiedtags[i] : tags[i]);
#endif
		while (ev->x >= x && ++i < LENGTH(tags));
		if (i < LENGTH(tags)) {
			click = ClkTagBar;
			arg.ui = 1 << i;
		} else if (ev->x < x + TEXTW(selmon->ltsymbol))
			click = ClkLtSymbol;
		else if (ev->x > selmon->ww - (int)TEXTW(stext) + lrpad - 2)
			click = ClkStatusText;
		else
			click = ClkWinTitle;
	} else if ((c = wintoclient(ev->window))) {
		focus(c);
		restack(selmon);
		if (ev->button != Button4 && ev->button != Button5)
			XAllowEvents(dpy, ReplayPointer, CurrentTime);
		click = ClkClientWin;
	}
	for (i = 0; i < LENGTH(buttons); i++)
		if (click == buttons[i].click && buttons[i].func && buttons[i].button == ev->button
		&& CLEANMASK(buttons[i].mask) == CLEANMASK(ev->state))
			buttons[i].func(click == ClkTagBar && buttons[i].arg.i == 0 ? &arg : &buttons[i].arg);
	if ((ev->button == Button4 || ev->button == Button5) && click == ClkClientWin)
		XAllowEvents(dpy, AsyncPointer, CurrentTime);
}

void
checkotherwm(void)
{
	xerrorxlib = XSetErrorHandler(xerrorstart);
	/* this causes an error if some other window manager is running */
	XSelectInput(dpy, DefaultRootWindow(dpy), SubstructureRedirectMask);
	XSync(dpy, False);
	XSetErrorHandler(xerror);
	XSync(dpy, False);
}

void
cleanup(void)
{
	Arg a = {.ui = ~0};
	Layout foo = { "", NULL };
	Monitor *m;
	size_t i;

	view(&a);
#if PER_TAG_LAYOUT
	setcurlayout(selmon, &foo);
#else
	selmon->lt[selmon->sellt] = &foo;
#endif
	for (m = mons; m; m = m->next)
		while (m->stack)
			unmanage(m->stack, 0);
	XUngrabKey(dpy, AnyKey, AnyModifier, root);
	while (mons)
		cleanupmon(mons);
	for (i = 0; i < CurLast; i++)
		drw_cur_free(drw, cursor[i]);
	for (i = 0; i < LENGTH(colors); i++)
		drw_scm_free(drw, scheme[i], 3);
	free(scheme);
	XDestroyWindow(dpy, wmcheckwin);
	drw_free(drw);
	XSync(dpy, False);
	XSetInputFocus(dpy, PointerRoot, RevertToPointerRoot, CurrentTime);
	XDeleteProperty(dpy, root, netatom[NetActiveWindow]);
}

void
cleanupmon(Monitor *mon)
{
	Monitor *m;

	if (mon == mons)
		mons = mons->next;
	else {
		for (m = mons; m && m->next != mon; m = m->next);
		m->next = mon->next;
	}
	XUnmapWindow(dpy, mon->barwin);
	XDestroyWindow(dpy, mon->barwin);
#if INFINITE_TAGS
  free(mon->canvas);
#endif
#if PER_TAG_LAYOUT
  free(mon->pertagmfact);
#endif
  free(mon);

}

void
clientmessage(XEvent *e)
{
	XClientMessageEvent *cme = &e->xclient;
	Client *c = wintoclient(cme->window);
	unsigned int i;

	if (!c)
		return;
	if (cme->message_type == netatom[NetWMState]) {
		if (cme->data.l[1] == netatom[NetWMFullscreen]
		|| cme->data.l[2] == netatom[NetWMFullscreen])
			setfullscreen(c, (cme->data.l[0] == 1 /* _NET_WM_STATE_ADD    */
				|| (cme->data.l[0] == 2 /* _NET_WM_STATE_TOGGLE */ && !c->isfullscreen)));
	} else if (cme->message_type == netatom[NetActiveWindow]) {
		for (i = 0; i < LENGTH(tags) && !((1 << i) & c->tags); i++);
		if (i < LENGTH(tags)) {
			const Arg a = {.ui = 1 << i};
			selmon = c->mon;
			/* view() with TAG_TO_TAG treats "switch to the tag I'm
			   already on" as a toggle back to the previous tag, and the
			   other tagset[] slot is stale. Only call it when it would
			   actually move; otherwise just raise the window. */
			if ((a.ui & TAGMASK) != selmon->tagset[selmon->seltags])
				view(&a);
			focus(c);
			restack(selmon);
		}
	}
}

void
configure(Client *c)
{
	XConfigureEvent ce;

	ce.type = ConfigureNotify;
	ce.display = dpy;
	ce.event = c->win;
	ce.window = c->win;
	ce.x = c->x;
	ce.y = c->y;
	ce.width = c->w;
	ce.height = c->h;
	ce.border_width = c->bw;
	ce.above = None;
	ce.override_redirect = False;
	XSendEvent(dpy, c->win, False, StructureNotifyMask, (XEvent *)&ce);
}

void
configurenotify(XEvent *e)
{
	Monitor *m;
	Client *c;
	XConfigureEvent *ev = &e->xconfigure;
	int dirty;

	/* TODO: updategeom handling sucks, needs to be simplified */
	if (ev->window == root) {
		dirty = (sw != ev->width || sh != ev->height);
		sw = ev->width;
		sh = ev->height;
		if (updategeom() || dirty) {
			drw_resize(drw, sw, bh);
			updatebars();
			for (m = mons; m; m = m->next) {
				for (c = m->clients; c; c = c->next)
					if (c->isfullscreen)
						resizeclient(c, m->mx, m->my, m->mw, m->mh);
#if !BAR_PADDING
				XMoveResizeWindow(dpy, m->barwin, m->wx, m->by, m->ww, bh);
#else
        XMoveResizeWindow(dpy, m->barwin, m->wx + lsp, m->by + (m->topbar ? tvp : bvp), m->ww - lsp - rsp, bh);
#endif
			}
			focus(NULL);
			arrange(NULL);
		}
	}
}

void
configurerequest(XEvent *e)
{
	Client *c;
	Monitor *m;
	XConfigureRequestEvent *ev = &e->xconfigurerequest;
	XWindowChanges wc;

	if ((c = wintoclient(ev->window))) {
		if (ev->value_mask & CWBorderWidth)
			c->bw = ev->border_width;
#if INFINITE_TAGS
		else if (c->fslot && !c->mon->lt[c->mon->sellt]->arrange) {
			/* slot window on the floating canvas: the layout owns its position,
			 * the client may only ask for another size */
			if (ev->value_mask & CWWidth) { c->oldw = c->w; c->w = ev->width; }
			if (ev->value_mask & CWHeight) { c->oldh = c->h; c->h = ev->height; }
			c->oldx = c->x; c->oldy = c->y;
			if (ISVISIBLE(c))
				XMoveResizeWindow(dpy, c->win, c->x, c->y, c->w, c->h);
			configure(c);
			if ((ev->value_mask & (CWWidth|CWHeight)) && c->mon == selmon)
				floatresolve(c);
		}
#endif
		else if (c->isfloating || !selmon->lt[selmon->sellt]->arrange) {
			m = c->mon;
			if (ev->value_mask & CWX) {
				c->oldx = c->x;
				c->x = m->mx + ev->x;
			}
			if (ev->value_mask & CWY) {
				c->oldy = c->y;
				c->y = m->my + ev->y;
			}
			if (ev->value_mask & CWWidth) {
				c->oldw = c->w;
				c->w = ev->width;
			}
			if (ev->value_mask & CWHeight) {
				c->oldh = c->h;
				c->h = ev->height;
			}
			if ((c->x + c->w) > m->mx + m->mw && c->isfloating)
				c->x = m->mx + (m->mw / 2 - WIDTH(c) / 2); /* center in x direction */
			if ((c->y + c->h) > m->my + m->mh && c->isfloating)
				c->y = m->my + (m->mh / 2 - HEIGHT(c) / 2); /* center in y direction */
			if ((ev->value_mask & (CWX|CWY)) && !(ev->value_mask & (CWWidth|CWHeight)))
				configure(c);
			if (ISVISIBLE(c))
				XMoveResizeWindow(dpy, c->win, c->x, c->y, c->w, c->h);
#if INFINITE_TAGS
			if (c->mon->lt[c->mon->sellt]->arrange == NULL &&
			    (ev->value_mask & (CWWidth|CWHeight)) && c->mon == selmon)
				floatresolve(c);
#endif
		} else
			configure(c);
	} else {
		wc.x = ev->x;
		wc.y = ev->y;
		wc.width = ev->width;
		wc.height = ev->height;
		wc.border_width = ev->border_width;
		wc.sibling = ev->above;
		wc.stack_mode = ev->detail;
		XConfigureWindow(dpy, ev->window, ev->value_mask, &wc);
	}
	XSync(dpy, False);
}

Monitor *
createmon(void)
{
	Monitor *m;

	m = ecalloc(1, sizeof(Monitor));
	m->tagset[0] = m->tagset[1] = 1;
	m->mfact = mfact;
	m->nmaster = nmaster;
	m->showbar = showbar;
	m->topbar = topbar;
#if GAPS
  m->gappx = gappx;
#endif
	m->lt[0] = &layouts[0];
	m->lt[1] = &layouts[1 % LENGTH(layouts)];
	strncpy(m->ltsymbol, layouts[0].symbol, sizeof m->ltsymbol);
#if PER_TAG_LAYOUT
  m->pertaglt = ecalloc(LENGTH(tags), sizeof(const Layout *));
  m->pertagsellt = ecalloc(LENGTH(tags), sizeof(unsigned int));
  m->pertagmfact = ecalloc(LENGTH(tags), sizeof(float));
  {
      unsigned int t;
      for (t = 0; t < LENGTH(tags); t++) {
          m->pertaglt[t] = &layouts[0];
          m->pertagsellt[t] = 0;
          m->pertagmfact[t] = mfact;
      }
  }
#endif
#if INFINITE_TAGS
  m->canvas = ecalloc(LENGTH(tags), sizeof(CanvasOffset));
  unsigned int i;
  for (i = 0; i < LENGTH(tags); i++) {
      m->canvas[i].cx = 0;
      m->canvas[i].cy = 0;
  }
#endif
	return m;
}

void
destroynotify(XEvent *e)
{
	Client *c;
	XDestroyWindowEvent *ev = &e->xdestroywindow;

	if ((c = wintoclient(ev->window)))
		unmanage(c, 1);
#if EXTERNAL_BARS
  externalbars_unregister(ev->window);
#endif
}

void
detach(Client *c)
{
	Client **tc;

	for (tc = &c->mon->clients; *tc && *tc != c; tc = &(*tc)->next);
	*tc = c->next;
}

void
detachstack(Client *c)
{
	Client **tc, *t;

	for (tc = &c->mon->stack; *tc && *tc != c; tc = &(*tc)->snext);
	*tc = c->snext;

	if (c == c->mon->sel) {
		for (t = c->mon->stack; t && !ISVISIBLE(t); t = t->snext);
		c->mon->sel = t;
	}
}

Monitor *
dirtomon(int dir)
{
	Monitor *m = NULL;

	if (dir > 0) {
		if (!(m = selmon->next))
			m = mons;
	} else if (selmon == mons)
		for (m = mons; m->next; m = m->next);
	else
		for (m = mons; m->next != selmon; m = m->next);
	return m;
}

void
drawbar(Monitor *m)
{
	int x, w, tw = 0;
	int boxs = drw->fonts->h / 9;
	int boxw = drw->fonts->h / 6 + 2;
	unsigned int i, occ = 0, urg = 0;
#if OCCUPIED_TAGS_DECORATION
  const char *tagtext;	
#endif
  Client *c;
	if (!m->showbar)
		return;

	/* draw status first so it can be overdrawn by tags later */
	if (m == selmon) { /* status is only drawn on selected monitor */
		drw_setscheme(drw, scheme[SchemeNorm]);
		tw = TEXTW(stext) - lrpad + 2; /* 2px right padding */
#if !BAR_PADDING
		drw_text(drw, m->ww - tw, 0, tw, bh, 0, stext, 0);
#else
    drw_text(drw, m->ww - tw - lsp - rsp, 0, tw, bh, 0, stext, 0);
#endif
	}

	for (c = m->clients; c; c = c->next) {
		occ |= c->tags;
		if (c->isurgent)
			urg |= c->tags;
	}
	x = 0;
	for (i = 0; i < LENGTH(tags); i++) {
#if !OCCUPIED_TAGS_DECORATION
		w = TEXTW(tags[i]);
		drw_setscheme(drw, scheme[m->tagset[m->seltags] & 1 << i ? SchemeSel : SchemeNorm]);
		drw_text(drw, x, 0, w, bh, lrpad / 2, tags[i], urg & 1 << i);
		if (occ & 1 << i)
			drw_rect(drw, x + boxs, boxs, boxw, boxw,
				m == selmon && selmon->sel && selmon->sel->tags & 1 << i,
				urg & 1 << i);
#else
		tagtext = occ & 1 << i ? occupiedtags[i] : tags[i];
		w = TEXTW(tagtext);
		drw_setscheme(drw, scheme[m->tagset[m->seltags] & 1 << i ? SchemeSel : SchemeNorm]);
		drw_text(drw, x, 0, w, bh, lrpad / 2, tagtext, urg & 1 << i);
#endif
		x += w;
	}

	/* keep the monocle "[i/n]" indicator current even when only focus changed */
	if (curlayout(m)->arrange == monocle)
		monocle_symbol(m);

	w = TEXTW(m->ltsymbol);
	drw_setscheme(drw, scheme[SchemeNorm]);
	x = drw_text(drw, x, 0, w, bh, lrpad / 2, m->ltsymbol, 0);

#if INFINITE_TAGS && IT_SHOW_COORDINATES_IN_BAR

  #if COORDINATES_DIVISOR <= 0
    #undef COORDINATES_DIVISOR
    #define COORDINATES_DIVISOR 1
  #endif

  #ifndef COORDINATES_STYLE
    #define COORDINATES_STYLE "[x%d y%d]"
  #endif

  if (selmon->lt[selmon->sellt]->arrange == NULL) {
    int tagidx = getcurrenttag(m);
    char coords[64];
    snprintf(coords, sizeof(coords), COORDINATES_STYLE, 
      m->canvas[tagidx].cx / COORDINATES_DIVISOR,
      m->canvas[tagidx].cy / COORDINATES_DIVISOR);
    w = TEXTW(coords);
    drw_setscheme(drw, scheme[SchemeNorm]);
    drw_text(drw, x, 0, w, bh, lrpad / 2, coords, 0);
    x += w;
  }

#endif

	if ((w = m->ww - tw - x) > bh) {
		if (m->sel) {
#if !ALT_CENTER_OF_BAR_COLOR
			drw_setscheme(drw, scheme[m == selmon ? SchemeSel : SchemeNorm]);
#else
      drw_setscheme(drw, scheme[m == selmon ? SchemeNorm : SchemeNorm]);
#endif
#if !BAR_PADDING
			drw_text(drw, x, 0, w, bh, lrpad / 2, m->sel->name, 0);
#else
      drw_text(drw, x, 0, w - lsp - rsp, bh, lrpad / 2, m->sel->name, 0);
#endif
			if (m->sel->isfloating)
				drw_rect(drw, x + boxs, boxs, boxw, boxw, m->sel->isfixed, 0);
		} else {
			drw_setscheme(drw, scheme[SchemeNorm]);
#if !BAR_PADDING
			drw_rect(drw, x, 0, w, bh, 1, 1);
#else
      drw_rect(drw, x, 0, w - lsp - rsp, bh, 1, 1);
#endif
		}
	}
	drw_map(drw, m->barwin, 0, 0, m->ww, bh);
}

void
drawbars(void)
{
	Monitor *m;

	for (m = mons; m; m = m->next)
		drawbar(m);
}

void
enternotify(XEvent *e)
{
	Client *c;
	Monitor *m;
	XCrossingEvent *ev = &e->xcrossing;

	if ((ev->mode != NotifyNormal || ev->detail == NotifyInferior) && ev->window != root)
		return;
	c = wintoclient(ev->window);
	m = c ? c->mon : wintomon(ev->window);
	if (m != selmon) {
		unfocus(selmon->sel, 1);
		selmon = m;
	} else if (!c || c == selmon->sel)
		return;
	stripnoscroll = 1;
	focus(c);
	stripnoscroll = 0;
}

void
expose(XEvent *e)
{
	Monitor *m;
	XExposeEvent *ev = &e->xexpose;

	if (ev->count == 0 && (m = wintomon(ev->window)))
		drawbar(m);
}

void
focus(Client *c)
{
	int explicitfocus = (c != NULL);

	if (!c || !ISVISIBLE(c))
		for (c = selmon->stack; c && !ISVISIBLE(c); c = c->snext);
	if (selmon->sel && selmon->sel != c)
		unfocus(selmon->sel, 0);
	if (c) {
		if (c->mon != selmon)
			selmon = c->mon;
		if (c->isurgent)
			seturgent(c, 0);
		detachstack(c);
		attachstack(c);
		grabbuttons(c, 1);
		XSetWindowBorder(dpy, c->win, scheme[SchemeSel][ColBorder].pixel);
#if OPACITY
		if (opacity_enabled)
			opacity_apply(c, opacity_for(c, 1));
#endif
		setfocus(c);
	} else {
		XSetInputFocus(dpy, root, RevertToPointerRoot, CurrentTime);
		XDeleteProperty(dpy, root, netatom[NetActiveWindow]);
	}
	selmon->sel = c;
	drawbars();
	/* scrolling strips: slide the row so the explicitly focused window is in
	 * view. focus(NULL) callers (view, manage, unmanage...) arrange themselves,
	 * and hover focus must not scroll or windows move under the pointer.
	 * WINDOWMAP's window_map()/window_unmap() call focus(NULL) from inside arrange(),
	 * so the guard also keeps this from ever recursing. */
	if (explicitfocus && !stripnoscroll && c && c->fslot)
		floatreveal(c);
	if (explicitfocus && !stripnoscroll && !stripbusy) {
		const Layout *sl = curlayout(selmon);
		if (sl->arrange == strip || sl->arrange == vstrip) {
			stripbusy = 1;
			arrange(selmon);
			stripbusy = 0;
		}
	}
}

/* there are some broken focus acquiring clients needing extra handling */
void
focusin(XEvent *e)
{
	XFocusChangeEvent *ev = &e->xfocus;

	if (selmon->sel && ev->window != selmon->sel->win)
		setfocus(selmon->sel);
}

void
focusmon(const Arg *arg)
{
	Monitor *m;

	if (!mons->next)
		return;
	if ((m = dirtomon(arg->i)) == selmon)
		return;
	unfocus(selmon->sel, 0);
	selmon = m;
	focus(NULL);
}

void
focusstack(const Arg *arg)
{
	Client *c = NULL, *i;

	if (!selmon->sel || (selmon->sel->isfullscreen && lockfullscreen))
		return;
	if (arg->i > 0) {
		for (c = selmon->sel->next; c && !ISVISIBLE(c); c = c->next);
		if (!c)
			for (c = selmon->clients; c && !ISVISIBLE(c); c = c->next);
	} else {
		for (i = selmon->clients; i != selmon->sel; i = i->next)
			if (ISVISIBLE(i))
				c = i;
		if (!c)
			for (; i; i = i->next)
				if (ISVISIBLE(i))
					c = i;
	}
	if (c) {
		focus(c);
#if INFINITE_TAGS
    centerwindow(NULL);
#endif
#if WARP_TO_CLIENT && WARP_TO_CENTER_OF_WINDOW_AFFECTED_BY_FOCUSSTACK
    warptoclient(c);
#endif   
		restack(selmon);
	}
}

Atom
getatomprop(Client *c, Atom prop)
{
	int format;
	unsigned long nitems, dl;
	unsigned char *p = NULL;
	Atom da, atom = None;

	if (XGetWindowProperty(dpy, c->win, prop, 0L, sizeof atom, False, XA_ATOM,
		&da, &format, &nitems, &dl, &p) == Success && p) {
		if (nitems > 0 && format == 32)
			atom = *(long *)p;
		XFree(p);
	}
	return atom;
}

int
getrootptr(int *x, int *y)
{
	int di;
	unsigned int dui;
	Window dummy;

	return XQueryPointer(dpy, root, &dummy, &dummy, x, y, &di, &di, &dui);
}

long
getstate(Window w)
{
	int format;
	long result = -1;
	unsigned char *p = NULL;
	unsigned long n, extra;
	Atom real;

	if (XGetWindowProperty(dpy, w, wmatom[WMState], 0L, 2L, False, wmatom[WMState],
		&real, &format, &n, &extra, &p) != Success)
		return -1;
	if (n != 0 && format == 32)
		result = *(long *)p;
	XFree(p);
	return result;
}

int
gettextprop(Window w, Atom atom, char *text, unsigned int size)
{
	char **list = NULL;
	int n;
	XTextProperty name;

	if (!text || size == 0)
		return 0;
	text[0] = '\0';
	if (!XGetTextProperty(dpy, w, &name, atom) || !name.nitems)
		return 0;
	if (name.encoding == XA_STRING) {
		strncpy(text, (char *)name.value, size - 1);
	} else if (XmbTextPropertyToTextList(dpy, &name, &list, &n) >= Success && n > 0 && *list) {
		strncpy(text, *list, size - 1);
		XFreeStringList(list);
	}
	text[size - 1] = '\0';
	XFree(name.value);
	return 1;
}

void
grabbuttons(Client *c, int focused)
{
	updatenumlockmask();
	{
		unsigned int i, j;
		unsigned int modifiers[] = { 0, LockMask, numlockmask, numlockmask|LockMask };
		XUngrabButton(dpy, AnyButton, AnyModifier, c->win);
		if (!focused)
			XGrabButton(dpy, AnyButton, AnyModifier, c->win, False,
				BUTTONMASK, GrabModeSync, GrabModeSync, None, None);
		for (i = 0; i < LENGTH(buttons); i++)
			if (buttons[i].click == ClkClientWin)
				for (j = 0; j < LENGTH(modifiers); j++)
					XGrabButton(dpy, buttons[i].button,
						buttons[i].mask | modifiers[j],
						c->win, False, BUTTONMASK,
						// use GrabModeSync for scroll wheel btns so when executing binds with the scroll wheel, windows dont get the scroll input. */
						(buttons[i].button == Button4 || buttons[i].button == Button5)
							? GrabModeSync : GrabModeAsync,
						GrabModeSync, None, None);
	}
}

void
grabkeys(void)
{
	updatenumlockmask();
	{
		unsigned int i, j, k;
		unsigned int modifiers[] = { 0, LockMask, numlockmask, numlockmask|LockMask };
		int start, end, skip;
		KeySym *syms;

		XUngrabKey(dpy, AnyKey, AnyModifier, root);
		XDisplayKeycodes(dpy, &start, &end);
		syms = XGetKeyboardMapping(dpy, start, end - start + 1, &skip);
		if (!syms)
			return;
		for (k = start; k <= end; k++)
			for (i = 0; i < LENGTH(keys); i++)
				/* skip modifier codes, we do that ourselves */
				if (keys[i].keysym == syms[(k - start) * skip])
					for (j = 0; j < LENGTH(modifiers); j++)
						XGrabKey(dpy, k,
							 keys[i].mod | modifiers[j],
							 root, True,
							 GrabModeAsync, GrabModeAsync);
		XFree(syms);
	}
}

#if WARP_TO_CLIENT && WARP_TO_CENTER_OF_WINDOW_AFFECTED_BY_INCNMASTER
//  LARP_TO_CLIENT
void
incnmaster(const Arg *arg)
{
	Client *c;
	unsigned int n;
	
	Client *moved = NULL;
	
	for (n = 0, c = nexttiled(selmon->clients); c; c = nexttiled(c->next), n++);
	
	if (arg->i > 0) {
		moved = nexttiled(selmon->clients);
		for (n = 0; moved && n < selmon->nmaster; n++)
			moved = nexttiled(moved->next);
	} else if (arg->i < 0 && selmon->nmaster > 0) {
		moved = nexttiled(selmon->clients);
		for (n = 1; moved && n < selmon->nmaster; n++)
			moved = nexttiled(moved->next);
	}
	
	selmon->nmaster = MAX(selmon->nmaster + arg->i, 0);
	arrange(selmon);
	
	if (moved)
		warptoclient(moved);
}

#else

void
incnmaster(const Arg *arg)
{
	selmon->nmaster = MAX(selmon->nmaster + arg->i, 0);
	arrange(selmon);
}

#endif

#ifdef XINERAMA
static int
isuniquegeom(XineramaScreenInfo *unique, size_t n, XineramaScreenInfo *info)
{
	while (n--)
		if (unique[n].x_org == info->x_org && unique[n].y_org == info->y_org
		&& unique[n].width == info->width && unique[n].height == info->height)
			return 0;
	return 1;
}
#endif /* XINERAMA */

void
keypress(XEvent *e)
{
	unsigned int i;
	KeySym keysym;
	XKeyEvent *ev;

	ev = &e->xkey;
	keysym = XKeycodeToKeysym(dpy, (KeyCode)ev->keycode, 0);
	for (i = 0; i < LENGTH(keys); i++)
		if (keysym == keys[i].keysym
		&& CLEANMASK(keys[i].mod) == CLEANMASK(ev->state)
		&& keys[i].func)
			keys[i].func(&(keys[i].arg));
}

void
killclient(const Arg *arg)
{
	if (!selmon->sel)
		return;
	if (!sendevent(selmon->sel, wmatom[WMDelete])) {
		XGrabServer(dpy);
		XSetErrorHandler(xerrordummy);
		XSetCloseDownMode(dpy, DestroyAll);
		XKillClient(dpy, selmon->sel->win);
		XSync(dpy, False);
		XSetErrorHandler(xerror);
		XUngrabServer(dpy);
	}
}

void
manage(Window w, XWindowAttributes *wa)
{
	Client *c, *t = NULL;
	Window trans = None;
	XWindowChanges wc;

	c = ecalloc(1, sizeof(Client));
	c->win = w;
#if WINDOWMAP
  c->ismapped = 0;
#endif
	/* geometry */
	c->x = c->oldx = wa->x;
	c->y = c->oldy = wa->y;
	c->w = c->oldw = wa->width;
	c->h = c->oldh = wa->height;
	c->oldbw = wa->border_width;
#if ENHANCED_TOGGLE_FLOATING
  c->sfx = c->x;
  c->sfy = c->y;
  c->sfw = c->w;
  c->sfh = c->h;
#endif
	updatetitle(c);
	if (XGetTransientForHint(dpy, w, &trans) && (t = wintoclient(trans))) {
		c->mon = t->mon;
		c->tags = t->tags;
	} else {
		c->mon = selmon;
		applyrules(c);
	}
#if FLOATING_LAYOUT_FLOATS_WINDOWS
  if (selmon->lt[selmon->sellt]->arrange == NULL)
    c->isfloating = 1;
#endif
	if (c->x + WIDTH(c) > c->mon->wx + c->mon->ww)
		c->x = c->mon->wx + c->mon->ww - WIDTH(c);
	if (c->y + HEIGHT(c) > c->mon->wy + c->mon->wh)
		c->y = c->mon->wy + c->mon->wh - HEIGHT(c);
  if (strcmp(c->name, "flameshot") != 0) {
    c->x = MAX(c->x, c->mon->wx);
    c->y = MAX(c->y, c->mon->wy);
  }
	c->bw = borderpx;

	wc.border_width = c->bw;
	XConfigureWindow(dpy, w, CWBorderWidth, &wc);
	XSetWindowBorder(dpy, w, scheme[SchemeNorm][ColBorder].pixel);
	configure(c); /* propagates border_width, if size doesn't change */
	updatewindowtype(c);
	updatesizehints(c);
	updatewmhints(c);
#if CENTER_NEW_FLOATING_WINDOWS && !NEW_WINDOWS_APPEAR_UNDER_CURSOR
  c->x = c->mon->wx + (c->mon->ww - WIDTH(c)) / 2;
  c->y = c->mon->wy + (c->mon->wh - HEIGHT(c)) / 2;
#endif
#if NEW_FLOATING_WINDOWS_APPEAR_UNDER_CURSOR
  int mx, my, di;
  unsigned int dui;
  Window dw;
  XQueryPointer(dpy, root, &dw, &dw, &mx, &my, &di, &di, &dui);
    
  c->x = mx - c->w / 2;
  c->y = my - c->h / 2;
#endif
#if INFINITE_TAGS
	/* floating layout: give a new window its own free slot on the canvas */
	if (c->mon == selmon && curlayout(selmon)->arrange == NULL && !trans && !c->isfixed) {
		Client *o;
		for (o = c->mon->clients; o; o = o->next)
			if ((o->tags & c->tags) && !o->fslot && !o->isfullscreen && !o->is_pinned)
				break; /* workspace has free-placed windows: keep default placement */
		if (!o) {
			c->fslot = 1;
			c->w = MAX((int)(c->mon->ww * FLOAT_W) - 2 * c->bw, 1);
			c->h = MAX((int)(c->mon->wh * FLOAT_H) - 2 * c->bw, 1);
			floatplace(c, c->mon->wx + (c->mon->ww - WIDTH(c)) / 2,
			           c->mon->wy + (c->mon->wh - HEIGHT(c)) / 2, c->mon, 0);
		}
	}
#endif
	XSelectInput(dpy, w, EnterWindowMask|FocusChangeMask|PropertyChangeMask|StructureNotifyMask);
	grabbuttons(c, 0);
	if (!c->isfloating)
		c->isfloating = c->oldstate = trans != None || c->isfixed;
	if (c->isfloating)
		XRaiseWindow(dpy, c->win);
	attach(c);
	attachstack(c);
	#if EWMH_TAGS
	updatewmdesktop(c);
	#endif
	XChangeProperty(dpy, root, netatom[NetClientList], XA_WINDOW, 32, PropModeAppend,
		(unsigned char *) &(c->win), 1);
	XMoveResizeWindow(dpy, c->win, c->x + 2 * sw, c->y, c->w, c->h); /* some windows require this */
	setclientstate(c, NormalState);
	if (c->mon == selmon)
		unfocus(selmon->sel, 0);
	c->mon->sel = c;
	arrange(c->mon);
	XMapWindow(dpy, c->win);
	focus(NULL);
#if INFINITE_TAGS
	if (c->fslot) {
		floatfix(c->mon, c, floatgap(c->mon));
		floatreveal(c);
	}
#endif
#if WARP_TO_CLIENT && WARP_TO_CENTER_OF_NEW_WINDOW 
  warptoclient(c);
#endif
}

void
mappingnotify(XEvent *e)
{
	XMappingEvent *ev = &e->xmapping;

	XRefreshKeyboardMapping(ev);
	if (ev->request == MappingKeyboard)
		grabkeys();
}

void
maprequest(XEvent *e)
{
	static XWindowAttributes wa;
	XMapRequestEvent *ev = &e->xmaprequest;
 
	if (!XGetWindowAttributes(dpy, ev->window, &wa) || wa.override_redirect)
		return;
#if EXTERNAL_BARS
	if (externalbars_hasstrut(ev->window)) {
		externalbars_register(ev->window);
		XMapWindow(dpy, ev->window);
		XSelectInput(dpy, ev->window, PropertyChangeMask|StructureNotifyMask);
		return;
	}
#endif
	if (!wintoclient(ev->window))
		manage(ev->window, &wa);
}

/* Fill m->ltsymbol with "[i/n]" where n is the number of visible windows and i
 * the 1-based position of the focused window among them. Kept separate from
 * monocle() so the bar (drawbar) can refresh the number after a plain focus
 * change without re-running the whole arrange. */
static void
monocle_symbol(Monitor *m)
{
	unsigned int n = 0, i = 0;
	Client *c;

	for (c = m->clients; c; c = c->next)
		if (ISVISIBLE(c)) {
			n++;
			if (c == m->sel)
				i = n;
		}
	if (n > 0) /* override layout symbol, e.g. "[3/5]" means window 3 of 5 */
		snprintf(m->ltsymbol, sizeof m->ltsymbol, "[%d/%d]", i, n);
}

void
monocle(Monitor *m)
{
	Client *c;

	monocle_symbol(m);
	for (c = nexttiled(m->clients); c; c = nexttiled(c->next))
		resize(c, m->wx, m->wy, m->ww - 2 * c->bw, m->wh - 2 * c->bw, 0);
}

void
motionnotify(XEvent *e)
{
	static Monitor *mon = NULL;
	Monitor *m;
	XMotionEvent *ev = &e->xmotion;

	if (ev->window != root)
		return;
	if ((m = recttomon(ev->x_root, ev->y_root, 1, 1)) != mon && mon) {
		unfocus(selmon->sel, 1);
		selmon = m;
		focus(NULL);
	}
	mon = m;
}

void
movemouse(const Arg *arg)
{
	int x, y, ocx, ocy, nx, ny;
	Client *c, *cc, *p;
	Monitor *m;
	XEvent ev;
#if LOCK_MOVE_RESIZE_REFRESH_RATE
	Time lasttime = 0;
#endif
#if ZOOM
  float zoom_val = zoom_value();
#endif

	if (!(c = selmon->sel) || c->isfullscreen)
		return;
	restack(selmon);
	ocx = c->x;
	ocy = c->y;
	if (XGrabPointer(dpy, root, False, MOUSEMASK, GrabModeAsync, GrabModeAsync,
		None, cursor[CurMove]->cursor, CurrentTime) != GrabSuccess)
		return;
	if (!getrootptr(&x, &y))
		return;
	do {
		XMaskEvent(dpy, MOUSEMASK|ExposureMask|SubstructureRedirectMask, &ev);
		switch (ev.type) {
		case ConfigureRequest:
		case Expose:
		case MapRequest:
			handler[ev.type](&ev);
			break;
		case MotionNotify:
#if LOCK_MOVE_RESIZE_REFRESH_RATE
			if ((ev.xmotion.time - lasttime) <= (1000 / refreshrate))
				continue;
			lasttime = ev.xmotion.time;
#endif
#if !ZOOM
			nx = ocx + (ev.xmotion.x - x);
			ny = ocy + (ev.xmotion.y - y);
#else
      nx = ocx + (ev.xmotion.x - x) / zoom_val;
			ny = ocy + (ev.xmotion.y - y) / zoom_val;
#endif
			if (abs(selmon->wx - nx) < snap)
				nx = selmon->wx;
			else if (abs((selmon->wx + selmon->ww) - (nx + WIDTH(c))) < snap)
				nx = selmon->wx + selmon->ww - WIDTH(c);
			if (abs(selmon->wy - ny) < snap)
				ny = selmon->wy;
			else if (abs((selmon->wy + selmon->wh) - (ny + HEIGHT(c))) < snap)
				ny = selmon->wy + selmon->wh - HEIGHT(c);
#if MOVE_IN_TILED
			if (selmon->lt[selmon->sellt]->arrange && !c->isfloating) {
				if ((m = recttomon(ev.xmotion.x_root, ev.xmotion.y_root, 1, 1)) != selmon) {
					sendmon(c, m);
					selmon = m;
					focus(NULL);
				}
				for (cc = c->mon->clients; cc; cc = cc->next)
					if (cc != c && !cc->isfloating && ISVISIBLE(cc)
					&& ev.xmotion.x_root > cc->x && ev.xmotion.x_root < cc->x + cc->w
					&& ev.xmotion.y_root > cc->y && ev.xmotion.y_root < cc->y + cc->h)
						break;
				if (cc) {
					Client *ps = NULL, *pf = NULL;
					for (p = c->mon->clients; p; p = p->next) {
						if (p->next == c) ps = p;
						if (p->next == cc) pf = p;
					}
					if (c->next == cc) {
						if (ps) ps->next = cc; else c->mon->clients = cc;
						c->next = cc->next;
						cc->next = c;
					} else if (cc->next == c) {
						if (pf) pf->next = c; else c->mon->clients = c;
						cc->next = c->next;
						c->next = cc;
					} else {
						if (ps) ps->next = cc; else c->mon->clients = cc;
						if (pf) pf->next = c; else c->mon->clients = c;
						Client *tmp = c->next;
						c->next = cc->next;
						cc->next = tmp;
					}
					focus(c);
					arrange(c->mon);
				}
				break;
			}
#else
			if (!c->isfloating && selmon->lt[selmon->sellt]->arrange
			&& (abs(nx - c->x) > snap || abs(ny - c->y) > snap))
				togglefloating(NULL);
#endif
			if (!selmon->lt[selmon->sellt]->arrange || c->isfloating)
				resize(c, nx, ny, c->w, c->h, 1);
			break;
		}
	} while (ev.type != ButtonRelease);
	XUngrabPointer(dpy, CurrentTime);
	if ((m = recttomon(c->x, c->y, c->w, c->h)) != selmon) {
		sendmon(c, m);
		selmon = m;
		focus(NULL);
	}
#if ENHANCED_TOGGLE_FLOATING && RESTORE_SIZE_AND_POS_ETF
	c->wasmanuallyedited = 1;
	if (c->isfloating) {
		c->sfx = c->x; c->sfy = c->y;
		c->sfw = c->w; c->sfh = c->h;
	}
#endif
}

Client *
nexttiled(Client *c)
{
	for (; c && (c->isfloating || !ISVISIBLE(c)); c = c->next);
	return c;
}

void
pop(Client *c)
{
	detach(c);
	attach(c);
	focus(c);
	arrange(c->mon);
}

void
propertynotify(XEvent *e)
{
	Client *c;
	Window trans;
	XPropertyEvent *ev = &e->xproperty;

#if EXTERNAL_BARS
  if (ev->atom == XInternAtom(dpy, "_NET_WM_STRUT_PARTIAL", False) ||
      ev->atom == XInternAtom(dpy, "_NET_WM_STRUT", False)) {
    if (ev->state == PropertyNewValue)
      externalbars_register(ev->window);
    else
      externalbars_unregister(ev->window);
    return;
  }
#endif

	if ((ev->window == root) && (ev->atom == XA_WM_NAME))
		updatestatus();
	else if (ev->state == PropertyDelete)
		return; /* ignore */
	else if ((c = wintoclient(ev->window))) {
		switch(ev->atom) {
		default: break;
		case XA_WM_TRANSIENT_FOR:
			if (!c->isfloating && (XGetTransientForHint(dpy, c->win, &trans)) &&
				(c->isfloating = (wintoclient(trans)) != NULL))
				arrange(c->mon);
			break;
		case XA_WM_NORMAL_HINTS:
			c->hintsvalid = 0;
			break;
		case XA_WM_HINTS:
			updatewmhints(c);
			drawbars();
			break;
		}
		if (ev->atom == XA_WM_NAME || ev->atom == netatom[NetWMName]) {
			updatetitle(c);
			if (c == c->mon->sel)
				drawbar(c->mon);
		}
		if (ev->atom == netatom[NetWMWindowType])
			updatewindowtype(c);
	}
}

void
quit(const Arg *arg)
{
	running = 0;
}

Monitor *
recttomon(int x, int y, int w, int h)
{
	Monitor *m, *r = selmon;
	int a, area = 0;

	for (m = mons; m; m = m->next)
		if ((a = INTERSECT(x, y, w, h, m)) > area) {
			area = a;
			r = m;
		}
	return r;
}

void
resize(Client *c, int x, int y, int w, int h, int interact)
{
	if (applysizehints(c, &x, &y, &w, &h, interact))
		resizeclient(c, x, y, w, h);
}

void
resizeclient(Client *c, int x, int y, int w, int h)
{
	XWindowChanges wc;
	int sizechanged = (c->w != w || c->h != h);

	c->oldx = c->x; c->x = wc.x = x;
	c->oldy = c->y; c->y = wc.y = y;
	c->oldw = c->w; c->w = wc.width = w;
	c->oldh = c->h; c->h = wc.height = h;
	wc.border_width = c->bw;
	XConfigureWindow(dpy, c->win, CWX|CWY|CWWidth|CWHeight|CWBorderWidth, &wc);
	configure(c);
	XSync(dpy, False);
#if INFINITE_TAGS
	/* a window on the floating canvas changed size: reflow its neighbours */
	if (sizechanged && (c->fslot || c->isfloating) && !floatbusy &&
	    c->mon == selmon && !curlayout(c->mon)->arrange) {
		floatresolve(c);
	}
#endif
}

#if !BETTER_RESIZE
void
resizemouse(const Arg *arg)
{
	int ocx, ocy, nw, nh;
	Client *c;
	Monitor *m;
	XEvent ev;
#if LOCK_MOVE_RESIZE_REFRESH_RATE
	Time lasttime = 0;
#endif
	if (!(c = selmon->sel))
		return;
	if (c->isfullscreen) /* no support resizing fullscreen windows by mouse */
		return;
	restack(selmon);
	ocx = c->x;
	ocy = c->y;
	if (XGrabPointer(dpy, root, False, MOUSEMASK, GrabModeAsync, GrabModeAsync,
		None, cursor[CurResize]->cursor, CurrentTime) != GrabSuccess)
		return;
	XWarpPointer(dpy, None, c->win, 0, 0, 0, 0, c->w + c->bw - 1, c->h + c->bw - 1);
	do {
		XMaskEvent(dpy, MOUSEMASK|ExposureMask|SubstructureRedirectMask, &ev);
		switch(ev.type) {
		case ConfigureRequest:
		case Expose:
		case MapRequest:
			handler[ev.type](&ev);
			break;
		case MotionNotify:
#if LOCK_MOVE_RESIZE_REFRESH_RATE
			if ((ev.xmotion.time - lasttime) <= (1000 / refreshrate))
				continue;
			lasttime = ev.xmotion.time;
#endif
			nw = MAX(ev.xmotion.x - ocx - 2 * c->bw + 1, 1);
			nh = MAX(ev.xmotion.y - ocy - 2 * c->bw + 1, 1);
			if (c->mon->wx + nw >= selmon->wx && c->mon->wx + nw <= selmon->wx + selmon->ww
			&& c->mon->wy + nh >= selmon->wy && c->mon->wy + nh <= selmon->wy + selmon->wh)
			{
#if !RESIZING_WINDOWS_IN_ALL_LAYOUTS_FLOATS_THEM
				if (!c->isfloating && selmon->lt[selmon->sellt]->arrange
				&& (abs(nw - c->w) > snap || abs(nh - c->h) > snap))
					togglefloating(NULL);
#else
      	if (!c->isfloating && (abs(nw - c->w) > snap || abs(nh - c->h) > snap))
					togglefloating(NULL);
#endif
			}
			if (!selmon->lt[selmon->sellt]->arrange || c->isfloating)
#if USE_RESIZECLIENT_FUNC   
        resizeclient(c, c->x, c->y, nw, nh);
#else
        resize(c, c->x, c->y, nw, nh, 1);
#endif
			break;
		}
	} while (ev.type != ButtonRelease);
	XWarpPointer(dpy, None, c->win, 0, 0, 0, 0, c->w + c->bw - 1, c->h + c->bw - 1);
	XUngrabPointer(dpy, CurrentTime);
	while (XCheckMaskEvent(dpy, EnterWindowMask, &ev));
	if ((m = recttomon(c->x, c->y, c->w, c->h)) != selmon) {
		sendmon(c, m);
		selmon = m;
		focus(NULL);
	}
#if ENHANCED_TOGGLE_FLOATING && RESTORE_SIZE_AND_POS_ETF
  c->wasmanuallyedited = 1;
  if (c->isfloating) {
    c->sfx = c->x;
    c->sfy = c->y;
    c->sfw = c->w;
    c->sfh = c->h;
  }
#endif
}
#endif //BETTER_RESIZE



void
restack(Monitor *m)
{
	Client *c;
	XEvent ev;
	XWindowChanges wc;
#if EXTERNAL_BARS && EXTERNAL_BARS_ALWAYS_ON_TOP 
  ExternalBarStrut *exb;
#endif

	drawbar(m);
	if (!m->sel)
		return;
	if (m->sel->isfloating || !m->lt[m->sellt]->arrange)
		XRaiseWindow(dpy, m->sel->win);
	if (m->lt[m->sellt]->arrange) {
		wc.stack_mode = Below;
		wc.sibling = m->barwin;
		for (c = m->stack; c; c = c->snext)
			if (!c->isfloating && ISVISIBLE(c)) {
				XConfigureWindow(dpy, c->win, CWSibling|CWStackMode, &wc);
				wc.sibling = c->win;
			}
	}
#if BAR_ALWAYS_ON_TOP 
  else {
    if (m->sel && m->sel->isfullscreen)
      return;
    wc.stack_mode = Below;
    wc.sibling = m->barwin;
    for (c = m->stack; c; c = c->snext) {
      if (ISVISIBLE(c) && !c->isfixed && !c->isfullscreen) {
        XConfigureWindow(dpy, c->win, CWSibling|CWStackMode, &wc);
        wc.sibling = c->win;
      }
    }
    XRaiseWindow(dpy, m->barwin);
#endif
#if EXTERNAL_BARS && EXTERNAL_BARS_ALWAYS_ON_TOP
    for (exb = ebarstruts; exb; exb = exb->next)
      XRaiseWindow(dpy, exb->win);
#endif
#if INFINITE_TAGS && PINNED_WINDOWS_ALWAYS_ON_TOP
    for (c = m->stack; c; c = c->snext)
      if (ISVISIBLE(c) && c->is_pinned)
        XRaiseWindow(dpy, c->win);
#endif
#if BAR_ALWAYS_ON_TOP
  }
#endif
	XSync(dpy, False);
	while (XCheckMaskEvent(dpy, EnterWindowMask, &ev));
}

void
run(void)
{
	XEvent ev;
	/* main event loop */
	XSync(dpy, False);
	while (running && !XNextEvent(dpy, &ev))
		if (handler[ev.type])
			handler[ev.type](&ev); /* call handler */
}

void
scan(void)
{
    unsigned int i, num;
    Window d1, d2, *wins = NULL;
    XWindowAttributes wa;
 
#if EXTERNAL_BARS
    externalbars_begin_scan();
#endif
    if (XQueryTree(dpy, root, &d1, &d2, &wins, &num)) {
        for (i = 0; i < num; i++) {
            if (!XGetWindowAttributes(dpy, wins[i], &wa)
            || wa.override_redirect || XGetTransientForHint(dpy, wins[i], &d1))
                continue;
            if (wa.map_state == IsViewable || getstate(wins[i]) == IconicState) {
#if EXTERNAL_BARS
                if (externalbars_hasstrut(wins[i])) {
                    externalbars_register(wins[i]);
                    continue;
                }
#endif
                manage(wins[i], &wa);
            }
        }
        for (i = 0; i < num; i++) { /* now the transients */
            if (!XGetWindowAttributes(dpy, wins[i], &wa))
                continue;
            if (XGetTransientForHint(dpy, wins[i], &d1)
            && (wa.map_state == IsViewable || getstate(wins[i]) == IconicState))
                manage(wins[i], &wa);
        }
        if (wins)
            XFree(wins);
    }
#if EXTERNAL_BARS
    externalbars_end_scan();
#endif
}

void
sendmon(Client *c, Monitor *m)
{
	if (c->mon == m)
		return;
	unfocus(c, 1);
	detach(c);
	detachstack(c);
	c->mon = m;
	c->tags = m->tagset[m->seltags]; /* assign tags of target monitor */
	attach(c);
	attachstack(c);
	#if EWMH_TAGS
	updatewmdesktop(c);
	#endif
	if (c->isfullscreen)
		resizeclient(c, m->mx, m->my, m->mw, m->mh);
	focus(NULL);
	arrange(NULL);
}

void
setclientstate(Client *c, long state)
{
	long data[] = { state, None };

	XChangeProperty(dpy, c->win, wmatom[WMState], wmatom[WMState], 32,
		PropModeReplace, (unsigned char *)data, 2);
}

int
sendevent(Client *c, Atom proto)
{
	int n;
	Atom *protocols;
	int exists = 0;
	XEvent ev;

	if (XGetWMProtocols(dpy, c->win, &protocols, &n)) {
		while (!exists && n--)
			exists = protocols[n] == proto;
		XFree(protocols);
	}
	if (exists) {
		ev.type = ClientMessage;
		ev.xclient.window = c->win;
		ev.xclient.message_type = wmatom[WMProtocols];
		ev.xclient.format = 32;
		ev.xclient.data.l[0] = proto;
		ev.xclient.data.l[1] = CurrentTime;
		XSendEvent(dpy, c->win, False, NoEventMask, &ev);
	}
	return exists;
}

void
setfocus(Client *c)
{
	if (!c->neverfocus)
		XSetInputFocus(dpy, c->win, RevertToPointerRoot, CurrentTime);
  XChangeProperty(dpy, root, netatom[NetActiveWindow], XA_WINDOW, 32,
  PropModeReplace, (unsigned char *)&c->win, 1);
	sendevent(c, wmatom[WMTakeFocus]);
}

void
setfullscreen(Client *c, int fullscreen)
{
	if (fullscreen && !c->isfullscreen) {
		XChangeProperty(dpy, c->win, netatom[NetWMState], XA_ATOM, 32,
			PropModeReplace, (unsigned char*)&netatom[NetWMFullscreen], 1);
		c->isfullscreen = 1;
		c->oldstate = c->isfloating;
		c->oldbw = c->bw;
		c->bw = 0;
		c->isfloating = 1;
		resizeclient(c, c->mon->mx, c->mon->my, c->mon->mw, c->mon->mh);
		XRaiseWindow(dpy, c->win);
	} else if (!fullscreen && c->isfullscreen){
		XChangeProperty(dpy, c->win, netatom[NetWMState], XA_ATOM, 32,
			PropModeReplace, (unsigned char*)0, 0);
		c->isfullscreen = 0;
		c->isfloating = c->oldstate;
		c->bw = c->oldbw;
		c->x = c->oldx;
		c->y = c->oldy;
		c->w = c->oldw;
		c->h = c->oldh;
		resizeclient(c, c->x, c->y, c->w, c->h);
		arrange(c->mon);
	}
}

void
setlayout(const Arg *arg)
{
#if PER_TAG_LAYOUT
    const Layout *old_layout = curlayout(selmon);
    const Layout *new_layout;

    if (arg && arg->v)
        new_layout = (const Layout *)arg->v;
    else if (arg && !arg->v)
        new_layout = selmon->lt[selmon->sellt ^ 1];
    else
        new_layout = old_layout == &layouts[0] ? &layouts[1] : &layouts[0];

    if (new_layout == old_layout) {
#if INFINITE_TAGS
        /* pressing the floating key again: put the windows back in their slots */
        if (new_layout->arrange == NULL) {
            homecanvas(NULL);
            floatspread(selmon);
            if (selmon->sel)
                floatreveal(selmon->sel);
        }
#endif
        return;
    }

    setcurlayout(selmon, new_layout);
#else
#if INFINITE_TAGS
    const Layout *temp_new_layout = (arg && arg->v) ? (Layout *)arg->v : selmon->lt[selmon->sellt ^ 1];
    if (temp_new_layout == selmon->lt[selmon->sellt]) return;

    const Layout *old_layout = selmon->lt[selmon->sellt];
#endif
    if (!arg || !arg->v || arg->v != selmon->lt[selmon->sellt])
        selmon->sellt ^= 1;
    if (arg && arg->v)
        selmon->lt[selmon->sellt] = (Layout *)arg->v;
#if INFINITE_TAGS
    const Layout *new_layout = selmon->lt[selmon->sellt];
#endif
#endif /* PER_TAG_LAYOUT */

#if INFINITE_TAGS
    if (old_layout->arrange == NULL && new_layout->arrange != NULL) {
        save_canvas_positions(selmon);
        homecanvas(NULL);
        Client *c;
        for (c = selmon->clients; c; c = c->next)
            if (!c->isfixed) c->isfloating = 0;
    }

    if (new_layout->arrange == NULL) {
        restore_canvas_positions(selmon);

        Client *c;
        for (c = selmon->clients; c; c = c->next)
            c->isfloating = 1;

        /* entering floating from a tiled layout: lay the windows of this
         * workspace out side by side without overlap */
        if (old_layout->arrange != NULL) {
            homecanvas(NULL);
            floatspread(selmon);
            if (selmon->sel)
                floatreveal(selmon->sel);
        }
    }
#endif

    strncpy(selmon->ltsymbol, curlayout(selmon)->symbol, sizeof selmon->ltsymbol - 1);
    selmon->ltsymbol[sizeof selmon->ltsymbol - 1] = '\0';
    arrange(selmon);
}
/* arg > 1.0 will set mfact absolutely */
void
setmfact(const Arg *arg)
{
	float f;

	if (!arg || !selmon->lt[selmon->sellt]->arrange)
		return;
	f = arg->f < 1.0 ? arg->f + selmon->mfact : arg->f - 1.0;
	if (f < 0.05 || f > 0.95)
		return;
	selmon->mfact = f;
#if PER_TAG_LAYOUT
	selmon->pertagmfact[currenttagidx(selmon)] = f;
#endif
	arrange(selmon);
}

void
setup(void)
{
	int i;
	XSetWindowAttributes wa;
	Atom utf8string;
	struct sigaction sa;

	/* do not transform children into zombies when they terminate */ //this comment got me giggling so hard man, lol
	sigemptyset(&sa.sa_mask);
	sa.sa_flags = SA_NOCLDSTOP | SA_NOCLDWAIT | SA_RESTART;
	sa.sa_handler = SIG_IGN;
	sigaction(SIGCHLD, &sa, NULL);

	/* clean up any zombies (inherited from .xinitrc etc) immediately */
	while (waitpid(-1, NULL, WNOHANG) > 0);

	/* init screen */
	screen = DefaultScreen(dpy);
	sw = DisplayWidth(dpy, screen);
	sh = DisplayHeight(dpy, screen);
	root = RootWindow(dpy, screen);
	drw = drw_create(dpy, screen, root, sw, sh);
	if (!drw_fontset_create(drw, fonts, LENGTH(fonts)))
		die("no fonts could be loaded.");
	lrpad = drw->fonts->h;
#if !BAR_HEIGHT
	bh = drw->fonts->h + 2;
#else
  bh = user_bh ? user_bh : drw->fonts->h + 2;
#endif
	updategeom();
#if BAR_PADDING
  lsp = left_sidepad;
  rsp = right_sidepad;
  tvp = top_vertpad;
  bvp = -bottom_vertpad;
#endif
	/* init atoms */
	utf8string = XInternAtom(dpy, "UTF8_STRING", False);
	wmatom[WMProtocols] = XInternAtom(dpy, "WM_PROTOCOLS", False);
	wmatom[WMDelete] = XInternAtom(dpy, "WM_DELETE_WINDOW", False);
	wmatom[WMState] = XInternAtom(dpy, "WM_STATE", False);
	wmatom[WMTakeFocus] = XInternAtom(dpy, "WM_TAKE_FOCUS", False);
	netatom[NetActiveWindow] = XInternAtom(dpy, "_NET_ACTIVE_WINDOW", False);
	netatom[NetSupported] = XInternAtom(dpy, "_NET_SUPPORTED", False);
	netatom[NetWMName] = XInternAtom(dpy, "_NET_WM_NAME", False);
	netatom[NetWMState] = XInternAtom(dpy, "_NET_WM_STATE", False);
	netatom[NetWMCheck] = XInternAtom(dpy, "_NET_SUPPORTING_WM_CHECK", False);
	netatom[NetWMFullscreen] = XInternAtom(dpy, "_NET_WM_STATE_FULLSCREEN", False);
	netatom[NetWMWindowType] = XInternAtom(dpy, "_NET_WM_WINDOW_TYPE", False);
	netatom[NetWMWindowTypeDialog] = XInternAtom(dpy, "_NET_WM_WINDOW_TYPE_DIALOG", False);
	netatom[NetClientList] = XInternAtom(dpy, "_NET_CLIENT_LIST", False);
#if EWMH_TAGS
  netatom[NetDesktopViewport] = XInternAtom(dpy, "_NET_DESKTOP_VIEWPORT", False);
	netatom[NetNumberOfDesktops] = XInternAtom(dpy, "_NET_NUMBER_OF_DESKTOPS", False);
	netatom[NetCurrentDesktop] = XInternAtom(dpy, "_NET_CURRENT_DESKTOP", False);
	netatom[NetDesktopNames] = XInternAtom(dpy, "_NET_DESKTOP_NAMES", False);
	netatom[NetDesktopNum] = XInternAtom(dpy, "_NET_WM_DESKTOP", False);
#if OPACITY
	netatom[NetWMWindowOpacity] = XInternAtom(dpy, "_NET_WM_WINDOW_OPACITY", False);
#endif
#endif
	/* init cursors */
	cursor[CurNormal] = drw_cur_create(drw, XC_left_ptr);
	cursor[CurResize] = drw_cur_create(drw, XC_sizing);
	cursor[CurMove] = drw_cur_create(drw, XC_fleur);
#if BETTER_RESIZE && BR_CHANGE_CURSOR
  cursor[CurNW] = drw_cur_create(drw, XC_top_left_corner);
  cursor[CurNE] = drw_cur_create(drw, XC_top_right_corner);
  cursor[CurSW] = drw_cur_create(drw, XC_bottom_left_corner);
  cursor[CurSE] = drw_cur_create(drw, XC_bottom_right_corner);
  cursor[CurN]  = drw_cur_create(drw, XC_top_side);
  cursor[CurS]  = drw_cur_create(drw, XC_bottom_side);
  cursor[CurE]  = drw_cur_create(drw, XC_right_side);
  cursor[CurW]  = drw_cur_create(drw, XC_left_side);
#endif
	/* init appearance */
	scheme = ecalloc(LENGTH(colors), sizeof(Clr *));
	for (i = 0; i < LENGTH(colors); i++)
		scheme[i] = drw_scm_create(drw, colors[i], 3);
	/* init bars */
	updatebars();
	updatestatus();
#if BAR_PADDING
  updatebarpos(selmon);
#endif
	/* supporting window for NetWMCheck */
	wmcheckwin = XCreateSimpleWindow(dpy, root, 0, 0, 1, 1, 0, 0, 0);
	XChangeProperty(dpy, wmcheckwin, netatom[NetWMCheck], XA_WINDOW, 32,
		PropModeReplace, (unsigned char *) &wmcheckwin, 1);
	XChangeProperty(dpy, wmcheckwin, netatom[NetWMName], utf8string, 8,
		PropModeReplace, (unsigned char *) "vxwm", 4);
	XChangeProperty(dpy, root, netatom[NetWMCheck], XA_WINDOW, 32,
		PropModeReplace, (unsigned char *) &wmcheckwin, 1);
	/* EWMH support per view */
	XChangeProperty(dpy, root, netatom[NetSupported], XA_ATOM, 32,
		PropModeReplace, (unsigned char *) netatom, NetLast);
#if EWMH_TAGS
	setnumdesktops();
	setcurrentdesktop();
	setdesktopnames();
	setviewport();
#endif
	XDeleteProperty(dpy, root, netatom[NetClientList]);
	/* select events */
	wa.cursor = cursor[CurNormal]->cursor;
	wa.event_mask = SubstructureRedirectMask|SubstructureNotifyMask
		|ButtonPressMask|PointerMotionMask|EnterWindowMask
		|LeaveWindowMask|StructureNotifyMask|PropertyChangeMask;
	XChangeWindowAttributes(dpy, root, CWEventMask|CWCursor, &wa);
	XSelectInput(dpy, root, wa.event_mask);
	grabkeys();
	focus(NULL);
}

void
seturgent(Client *c, int urg)
{
	XWMHints *wmh;

	c->isurgent = urg;
	if (!(wmh = XGetWMHints(dpy, c->win)))
		return;
	wmh->flags = urg ? (wmh->flags | XUrgencyHint) : (wmh->flags & ~XUrgencyHint);
	XSetWMHints(dpy, c->win, wmh);
	XFree(wmh);
}

void
showhide(Client *c)
{
	if (!c)
		return;
	
	if (ISVISIBLE(c)) {
		/* show clients top down */
#if !WINDOWMAP
		XMoveWindow(dpy, c->win, c->x, c->y);
		if ((!c->mon->lt[c->mon->sellt]->arrange || c->isfloating) && !c->isfullscreen)
			resize(c, c->x, c->y, c->w, c->h, 0);
#else
		if (!c->ismapped) {
			window_map(dpy, c, 1);
			c->ismapped = 1;
		}
#endif
		showhide(c->snext);
	} else {
		/* hide clients bottom up */
		showhide(c->snext);
		SHOWHIDEPROFILE
	}
}

void
spawn(const Arg *arg)
{
	struct sigaction sa;

	if (arg->v == dmenucmd)
		dmenumon[0] = '0' + selmon->num;
	if (fork() == 0) {
		if (dpy)
			close(ConnectionNumber(dpy));
		setsid();

		sigemptyset(&sa.sa_mask);
		sa.sa_flags = 0;
		sa.sa_handler = SIG_DFL;
		sigaction(SIGCHLD, &sa, NULL);

		execvp(((char **)arg->v)[0], (char **)arg->v);
		die("vxwm: execvp '%s' failed:", ((char **)arg->v)[0]);
	}
}

void
tag(const Arg *arg)
{
    if (selmon->sel && arg->ui & TAGMASK) {
#if INFINITE_TAGS
        Client *c = selmon->sel;
        unsigned int target_tag_mask = arg->ui & TAGMASK;
        int i;

        for (i = 0; i < LENGTH(tags); i++) {
            if (target_tag_mask & (1 << i)) {
                
                c->saved_cx = selmon->canvas[i].cx + (selmon->ww - WIDTH(c)) / 2;
                c->saved_cy = selmon->canvas[i].cy + (selmon->wh - HEIGHT(c)) / 2;
                c->saved_cw = c->w;
                c->saved_ch = c->h;
                c->was_on_canvas = 1;
                
                break;
            }
        }
#endif

        selmon->sel->tags = arg->ui & TAGMASK;
		#if EWMH_TAGS
		updatewmdesktop(selmon->sel);
		#endif
        focus(NULL);
        arrange(selmon);
    }
}

void
tagmon(const Arg *arg)
{
	if (!selmon->sel || !mons->next)
		return;
	sendmon(selmon->sel, dirtomon(arg->i));
}

void
tile(Monitor *m)
{
	unsigned int i, n, g = 0;
	int x, y, w, h, cw, ch;
	float f;
	Client *c;

	for (n = 0, c = nexttiled(m->clients); c; c = nexttiled(c->next), n++);
	if (n == 0)
		return;

#if GAPS
	g = m->gappx;
#endif
	/* remaining free area, inset by the outer gap */
	x = m->wx + g;
	y = m->wy + g;
	w = m->ww - 2 * g;
	h = m->wh - 2 * g;

	for (i = 0, c = nexttiled(m->clients); c; c = nexttiled(c->next), i++) {
		if (i < n - 1) {
			/* first split follows mfact, the rest are half/half */
			f = (i == 0) ? m->mfact : 0.5;
			if (i % 2 == 0) {           /* vertical split: client takes left part */
				cw = (w - g) * f;
				resize(c, x, y, cw - 2 * c->bw, h - 2 * c->bw, 0);
				x += cw + g;
				w -= cw + g;
			} else {                    /* horizontal split: client takes top part */
				ch = (h - g) * f;
				resize(c, x, y, w - 2 * c->bw, ch - 2 * c->bw, 0);
				y += ch + g;
				h -= ch + g;
			}
		} else {
			/* last client gets whatever is left */
			resize(c, x, y, w - 2 * c->bw, h - 2 * c->bw, 0);
		}
	}
}
void
grid(Monitor *m)
{
	unsigned int i, n, cols, rows, col, row, incol, cw, ch;
	unsigned int g = 0;
	Client *c;

	for (n = 0, c = nexttiled(m->clients); c; c = nexttiled(c->next))
		n++;
	if (n == 0)
		return;

#if GAPS
	g = m->gappx;
#endif
	for (rows = 0; rows <= n / 2; rows++)
		if (rows * rows >= n)
			break;
	cols = (rows && (rows - 1) * rows >= n) ? rows - 1 : rows;
	/* cell size leaves room for the gap on the right/below of each cell */
	cw = (m->ww - g * (cols + 1)) / cols;

	for (i = 0, c = nexttiled(m->clients); c; c = nexttiled(c->next), i++) {
		col = i / rows;
		row = i % rows;
		/* the last column may hold fewer windows: stretch them to fill */
		incol = (col == cols - 1) ? n - rows * (cols - 1) : rows;
		ch = (m->wh - g * (incol + 1)) / incol;
		resize(c, m->wx + g + col * (cw + g), m->wy + g + row * (ch + g),
		       cw - 2 * c->bw + (col == cols - 1 ? m->ww - g * (cols + 1) - cw * cols : 0),
		       ch - 2 * c->bw + (row == incol - 1 ? m->wh - g * (incol + 1) - ch * incol : 0), 0);
	}
}

/* Floating canvas: windows never overlap. A new window goes to the free spot
 * nearest to the middle of the screen (so the set grows outward in whatever
 * direction there is room), all windows are big enough to use. Resizing a window
 * reflows the windows stuck to the edges that moved: they shrink or grow to make
 * room or to take the empty space, staying glued at the gap, so nothing slides
 * away and a hole never opens next to a neighbour. Moving a window by hand keeps
 * it where you put it and the windows it covers find a free spot; Mod+f packs
 * everything again. c->fslot is just a "managed by this layout" flag. */
#define FLOAT_W 0.75f  /* default window size as share of the work area */
#define FLOAT_H 0.78f

static int
floatgap(Monitor *m)
{
	int g = 24; /* space between floating windows */
#if GAPS
	g = MAX((int)m->gappx * 2, g);
#endif
	return g;
}

static int
floateligible(Client *o, Monitor *m)
{
	return o->mon == m && ISVISIBLE(o) && !o->is_pinned && !o->isfullscreen;
}

/* does a w x h rectangle at (x, y) clear every obstacle by the gap? */
static int
floatfree(Client **obs, int n, int x, int y, int w, int h, int g)
{
	int i;

	for (i = 0; i < n; i++)
		if (x < obs[i]->x + WIDTH(obs[i]) + g && x + w + g > obs[i]->x &&
		    y < obs[i]->y + HEIGHT(obs[i]) + g && y + h + g > obs[i]->y)
			return 0;
	return 1;
}

/* Choose a spot for c with no overlap, as close as possible to the wanted top-left
 * corner (tx, ty). Candidate spots touch the edges of other windows (or sit on the
 * wanted spot). Only sets c->x / c->y. The obstacles are the eligible windows of m
 * except c and the ones flagged in skip-array (see floatresolve). */
static void
floatplacein(Client *c, int tx, int ty, Client **obs, int n, Monitor *m)
{
	int xs[3 * 256 + 1], ys[3 * 256 + 1], nx = 0, ny = 0, i, j;
	int w = WIDTH(c), h = HEIGHT(c), g = floatgap(m);
	long bd = -1, d;
	int bx = tx, by = ty;

	xs[nx++] = tx;
	ys[ny++] = ty;
	for (i = 0; i < n && i < 256; i++) {
		xs[nx++] = obs[i]->x + WIDTH(obs[i]) + g;
		xs[nx++] = obs[i]->x - w - g;
		xs[nx++] = obs[i]->x;
		ys[ny++] = obs[i]->y + HEIGHT(obs[i]) + g;
		ys[ny++] = obs[i]->y - h - g;
		ys[ny++] = obs[i]->y;
	}
	for (i = 0; i < nx; i++)
		for (j = 0; j < ny; j++) {
			/* distances in thousandths of the screen, so sideways and up/down are
			 * equally cheap on a wide screen */
			d = (long)((xs[i] - tx) * 1000 / MAX(m->ww, 1)) * ((xs[i] - tx) * 1000 / MAX(m->ww, 1)) +
			    (long)((ys[j] - ty) * 1000 / MAX(m->wh, 1)) * ((ys[j] - ty) * 1000 / MAX(m->wh, 1));
			if (bd >= 0 && d >= bd)
				continue;
			if (floatfree(obs, n, xs[i], ys[j], w, h, g)) {
				bd = d; bx = xs[i]; by = ys[j];
			}
		}
	c->x = bx;
	c->y = by;
}

/* top-left that would put a w x h window in the middle of the existing windows
 * (their bounding box); the middle of the screen when there are none */
static void
floatcenter(Client **obs, int n, Monitor *m, int w, int h, int *tx, int *ty)
{
	int i, x0 = 0, y0 = 0, x1 = 0, y1 = 0;

	if (n <= 0) {
		*tx = m->wx + (m->ww - w) / 2;
		*ty = m->wy + (m->wh - h) / 2;
		return;
	}
	x0 = obs[0]->x; x1 = obs[0]->x + WIDTH(obs[0]);
	y0 = obs[0]->y; y1 = obs[0]->y + HEIGHT(obs[0]);
	for (i = 1; i < n; i++) {
		x0 = MIN(x0, obs[i]->x); x1 = MAX(x1, obs[i]->x + WIDTH(obs[i]));
		y0 = MIN(y0, obs[i]->y); y1 = MAX(y1, obs[i]->y + HEIGHT(obs[i]));
	}
	*tx = (x0 + x1 - w) / 2;
	*ty = (y0 + y1 - h) / 2;
}

/* for manage(): c is not in m->clients yet */
static void
floatplace(Client *c, int tx, int ty, Monitor *m, Client *skip)
{
	Client *obs[256], *o;
	int n = 0;

	(void)skip; (void)tx; (void)ty;
	for (o = m->clients; o && n < 256; o = o->next)
		if (o != c && floateligible(o, m) && (o->tags & c->tags))
			obs[n++] = o;
	floatcenter(obs, n, m, WIDTH(c), HEIGHT(c), &tx, &ty);
	floatplacein(c, tx, ty, obs, n, m);
}

/* Mod+f: every visible window of the workspace goes back to the default size and
 * is packed around the middle of the screen, oldest first, spreading outward. */
static void
floatspread(Monitor *m)
{
	Client *list[256], *placed[256], *c;
	unsigned int n = 0, i, np = 0;

	for (c = m->clients; c && n < 256; c = c->next)
		if (floateligible(c, m))
			list[n++] = c; /* newest first */
	floatbusy = 1;
	for (i = n; i-- > 0; ) { /* oldest first */
		int w = (int)(m->ww * FLOAT_W), h = (int)(m->wh * FLOAT_H), tx, ty;
		c = list[i];
		c->fslot = 1;
		c->w = MAX(w - 2 * c->bw, 1);
		c->h = MAX(h - 2 * c->bw, 1);
		floatcenter(placed, np, m, w, h, &tx, &ty);
		floatplacein(c, tx, ty, placed, np, m);
		resizeclient(c, c->x, c->y, c->w, c->h);
		placed[np++] = c;
	}
	floatbusy = 0;
}

/* Safety net: while two windows overlap (by more than `margin`), move one of
 * them (never `keep`) to the nearest free spot. Every move removes at least one
 * overlapping pair, so this ends. `margin` is the gap while settling, 0 while a
 * live resize reflow already kept the windows spaced. */
static void
floatfix(Monitor *m, Client *keep, int margin)
{
	Client *list[256], *obs[256], *o, *mv;
	int n = 0, i, j, k, no, iter, found, moved = 0;

	for (o = m->clients; o && n < 256; o = o->next)
		if (floateligible(o, m))
			list[n++] = o;
	for (iter = 0; iter < 2 * n + 2; iter++) {
		found = 0;
		for (i = 0; i < n && !found; i++)
			for (j = i + 1; j < n && !found; j++) {
				if (list[i]->x < list[j]->x + WIDTH(list[j]) + margin && list[i]->x + WIDTH(list[i]) + margin > list[j]->x &&
				    list[i]->y < list[j]->y + HEIGHT(list[j]) + margin && list[i]->y + HEIGHT(list[i]) + margin > list[j]->y) {
					mv = (list[j] == keep) ? list[i] : list[j];
					for (no = 0, k = 0; k < n; k++)
						if (list[k] != mv)
							obs[no++] = list[k];
					floatplacein(mv, mv->x, mv->y, obs, no, m);
					XMoveWindow(dpy, mv->win, mv->x, mv->y);
					found = moved = 1;
				}
			}
		if (!found)
			break;
	}
	if (moved) {
		XSync(dpy, False);
		{
			XEvent ev;
			while (XCheckMaskEvent(dpy, EnterWindowMask, &ev));
		}
	}
}

/* shift of the windows beyond one edge of the old rectangle: the closure of
 * "touching in that direction" starting from the windows next to the old rect */


/* One side of a just-resized window (dir: 0 left, 1 right, 2 up, 3 down) moved by
 * `press` px into (+) or out of (-) the windows on that side of the old rectangle.
 * The windows touching that old edge (or the ones c grew into) reflow like a
 * stuck partition: each absorbs the movement at its own far edge, which stays
 * anchored, so shrinking a window hands the empty space to its neighbours and
 * growing one makes them thinner. When a window hits its minimum it is pushed
 * out, and everything behind it in that direction moves with it. Windows
 * separated by a real hole are left alone.
 *
 * All the math is done in "outward" coordinates (negated for left / up), so the
 * four sides share one model with the outward axis pointing away from c. */


/* c was resized (old rectangle in c->oldx/y/w/h): the windows stuck to every
 * edge that moved are re-flowed so nothing overlaps and no empty hole opens
 * next to a neighbour; whatever still overlaps after that is moved to a free
 * spot. */
static void
floatresolve(Client *c)
{
	(void)c;
	floatbusy = 0;
}



/* Directional focus on the floating canvas (0 left, 1 right, 2 up, 3 down): the
 * nearest window that lines up with the current one (overlaps it on the other
 * axis); if none does, the closest window in that direction. Ties go to the
 * upper / left one. The key is always handled. */
static int
floatfocus(int dir)
{
	Client *s = selmon->sel, *c, *best = NULL;
	long bs = 0, sc;
	int dx, dy, pass, ov, bt = 0, tie;

	for (pass = 0; pass < 2 && !best; pass++)
		for (c = selmon->clients; c; c = c->next) {
			if (c == s || !ISVISIBLE(c) || !c->fslot)
				continue;
			dx = c->x + WIDTH(c) / 2 - (s->x + WIDTH(s) / 2);
			dy = c->y + HEIGHT(c) / 2 - (s->y + HEIGHT(s) / 2);
			if ((dir == 0 && dx >= -8) || (dir == 1 && dx <= 8) ||
			    (dir == 2 && dy >= -8) || (dir == 3 && dy <= 8))
				continue;
			ov = dir < 2
			    ? (c->y < s->y + HEIGHT(s) && c->y + HEIGHT(c) > s->y)
			    : (c->x < s->x + WIDTH(s) && c->x + WIDTH(c) > s->x);
			if (pass == 0 && !ov)
				continue;
			sc = pass == 0 ? (long)abs(dir < 2 ? dx : dy)
			               : (long)dx * dx + (long)dy * dy;
			tie = dir < 2 ? dy : dx;
			if (!best || sc < bs || (sc == bs && tie < bt)) {
				best = c; bs = sc; bt = tie;
			}
		}
	if (best)
		focus(best);
	return 1;
}

/* Pan the canvas so a slot window that is not fully on screen gets centered. */
static void
floatreveal(Client *c)
{
	Monitor *m = c->mon;
	Arg a;

	if (!c->fslot || c->is_pinned || c->isfullscreen || m != selmon || curlayout(m)->arrange)
		return;
	if (c->x >= m->wx && c->y >= m->wy &&
	    c->x + WIDTH(c) <= m->wx + m->ww && c->y + HEIGHT(c) <= m->wy + m->wh)
		return;
	a.v = c;
	centerwindow(&a);
	/* the pan moved windows under the pointer: those enter events would steal the focus back */
	XSync(dpy, False);
	{
		XEvent ev;
		while (XCheckMaskEvent(dpy, EnterWindowMask, &ev));
	}
}

/* Scrolling strips: an endless row ([H], horizontal) or column ([V], vertical) of
 * windows, no overlap. Every window has its own size along the strip (see
 * stripresize(), Mod+Ctrl+h/l); a window never resized uses the default of mfact
 * (from config.h) of the screen. The size lives in the Client, so it is forgotten
 * when the window closes. The oldest window is first (left / top), a new window opens at the
 * end (right / bottom). The strip scrolls so the focused window is centered,
 * clamped so there is no empty space before the first or after the last window.
 * Windows outside the screen stay mapped, parked just past the screen edge. */
static int
stripsize(Client *c, int vert, int avail, int def, unsigned int n)
{
	int s;

	if (n == 1)
		return avail;
	s = c->stripsz[vert] ? avail * c->stripsz[vert] / 1000 : def;
	return MAX(s, 1);
}

static void
stripl(Monitor *m, int vert)
{
	unsigned int n;
	int g = 0, avail, cross, def, total, maxscroll, scroll;
	int selstart = 0, selsize = 0, have = 0;
	int lo, hi, end, start, size, p, x, y, cw, ch;
	Client *c;
	XWindowChanges wc;
	static int lastscroll[2] = { 0, 0 };

	for (n = 0, c = nexttiled(m->clients); c; c = nexttiled(c->next))
		n++;
	if (n == 0)
		return;

#if GAPS
	g = m->gappx;
#endif
	avail = (vert ? m->wh : m->ww) - 2 * g;
	cross = (vert ? m->ww : m->wh) - 2 * g;
	if (avail < 1 || cross < 1)
		return;
	/* default size comes from config.h's mfact, never from the live m->mfact that
	 * tiling layouts change, so a fresh window always starts at the default */
	def = MAX((int)(avail * mfact), 1);

	/* total length of the strip */
	total = ((int)n - 1) * g;
	for (c = nexttiled(m->clients); c; c = nexttiled(c->next))
		total += stripsize(c, vert, avail, def, n);
	maxscroll = MAX(total - avail, 0);

	/* the list is newest first and the strip is oldest first, so walk it from
	 * the far end: the newest window ends at `total`, each older one before it */
	end = total;
	for (c = nexttiled(m->clients); c; c = nexttiled(c->next)) {
		size = stripsize(c, vert, avail, def, n);
		start = end - size;
		if (c == m->sel) {
			selstart = start;
			selsize = size;
			have = 1;
		}
		end = start - g;
	}

	if (have)
		scroll = selstart - (avail - selsize) / 2;
	else
		scroll = lastscroll[vert]; /* focused window is floating: keep still */
	scroll = MAX(0, MIN(scroll, maxscroll));
	lastscroll[vert] = scroll;

	lo = vert ? m->wy : m->wx;
	hi = lo + (vert ? m->wh : m->ww);

	end = total;
	for (c = nexttiled(m->clients); c; c = nexttiled(c->next)) {
		size = stripsize(c, vert, avail, def, n);
		start = end - size;
		end = start - g;
		p = lo + g + start - scroll;
		/* keep parked windows near the edge (X coordinates are 16 bit) */
		if (p + size + 2 * c->bw <= lo)
			p = lo - size - 2 * c->bw;
		else if (p >= hi)
			p = hi;
		if (vert) {
			x = m->wx + g; y = p;
			cw = cross - 2 * c->bw; ch = size - 2 * c->bw;
		} else {
			x = p; y = m->wy + g;
			cw = size - 2 * c->bw; ch = cross - 2 * c->bw;
		}
		cw = MAX(cw, 1);
		ch = MAX(ch, 1);
		if (x == c->x && y == c->y && cw == c->w && ch == c->h)
			continue;
		/* not resize(): applysizehints() would clamp us back on-screen.
		 * Not resizeclient() either: it syncs per window, we sync once. */
		c->oldx = c->x; c->x = wc.x = x;
		c->oldy = c->y; c->y = wc.y = y;
		c->oldw = c->w; c->w = wc.width = cw;
		c->oldh = c->h; c->h = wc.height = ch;
		wc.border_width = c->bw;
		XConfigureWindow(dpy, c->win, CWX|CWY|CWWidth|CWHeight|CWBorderWidth, &wc);
		configure(c);
	}
	XSync(dpy, False);
}

void
strip(Monitor *m)
{
	stripl(m, 0);
}

void
vstrip(Monitor *m)
{
	stripl(m, 1);
}

/* Focus keys. In a strip layout the keys along the strip's axis walk the
 * strip (h/l = older/newer window in the horizontal one, k/j = older/newer in
 * the vertical one). Everything else falls back to directional focus.
 * arg->i uses focusdir's numbering: 0 left, 1 right, 2 up, 3 down. */
void
focusstrip(const Arg *arg)
{
	const Layout *l = curlayout(selmon);
	int vert = (l->arrange == vstrip);
	Client *c = NULL, *i, *sel = selmon->sel;

	if (!l->arrange && sel && sel->fslot && floatfocus(arg->i))
		return;
	if (!(l->arrange == strip || l->arrange == vstrip)
	|| (vert ? arg->i < 2 : arg->i >= 2)) {
#if DIRECTIONAL_FOCUS
		focusdir(arg);
#endif
		return;
	}
	if (!sel || sel->isfloating)
		return;
	if (arg->i == 0 || arg->i == 2) {  /* left / up = older = next in list */
		c = nexttiled(sel->next);
	} else {                           /* right / down = newer = previous in list */
		for (i = nexttiled(selmon->clients); i && i != sel; i = nexttiled(i->next))
			c = i;
		if (i != sel)
			c = NULL;
	}
	if (c)
		focus(c); /* focus() re-arranges, which scrolls the strip */
}

/* Mod+Ctrl+h / Mod+Ctrl+l. In [H] / [V] this resizes ONLY the focused window along
 * the strip (arg->f in fractions of the screen, like setmfact); every other window
 * keeps its size and the strip re-centers on the focused one. In every other
 * layout it is the normal setmfact. */
void
stripresize(const Arg *arg)
{
	const Layout *l = curlayout(selmon);
	Client *c = selmon->sel;
	int vert, cur;

	if (arg && !l->arrange && c && c->fslot) {
		/* floating canvas: Mod+Ctrl+h/l change the width, neighbours make room */
		int nw = c->w + (int)(arg->f * selmon->ww);
		resizeclient(c, c->x, c->y, MAX(nw, 100), c->h);
		return;
	}
	if (!arg || !(l->arrange == strip || l->arrange == vstrip)) {
		setmfact(arg);
		return;
	}
	if (!c || c->isfloating)
		return;
	vert = (l->arrange == vstrip);
	cur = c->stripsz[vert] ? c->stripsz[vert] : (int)(mfact * 1000);
	cur += (int)(arg->f * 1000 + (arg->f < 0 ? -0.5 : 0.5));
	c->stripsz[vert] = MAX(100, MIN(cur, 1000)); /* 10% .. 100% of the screen */
	arrange(selmon);
}

void
togglebar(const Arg *arg)
{
    selmon->showbar = !selmon->showbar;
    updatebarpos(selmon);

    int bar_y;
    if (selmon->showbar) {
        bar_y = selmon->by;
    } else {
        if (topbar) {
            bar_y = -bh;
        } else {
            bar_y = selmon->mh + bh;
        }
    }

#if !BAR_PADDING
    XMoveResizeWindow(dpy, selmon->barwin, selmon->wx, bar_y, selmon->ww, bh);
#else
    int final_y = (selmon->showbar) ? (bar_y + (selmon->topbar ? tvp : bvp)) : bar_y;
    XMoveResizeWindow(dpy, selmon->barwin, selmon->wx + lsp, final_y, selmon->ww - lsp - rsp, bh);
#endif

    arrange(selmon);
}

void
togglefloating(const Arg *arg)
{
	if (!selmon->sel)
		return;
	if (selmon->sel->isfullscreen) /* no support for fullscreen windows */
		return;
	selmon->sel->isfloating = !selmon->sel->isfloating || selmon->sel->isfixed;
	if (selmon->sel->isfloating)
		resize(selmon->sel, selmon->sel->x, selmon->sel->y,
			selmon->sel->w, selmon->sel->h, 0);
	arrange(selmon);
}

void
toggletag(const Arg *arg)
{
	unsigned int newtags;

	if (!selmon->sel)
		return;
	newtags = selmon->sel->tags ^ (arg->ui & TAGMASK);
	if (newtags) {
		selmon->sel->tags = newtags;
		#if EWMH_TAGS
		updatewmdesktop(selmon->sel);
		#endif
		focus(NULL);
		arrange(selmon);
	}
#if EWMH_TAGS
  updatecurrentdesktop();
#endif
}

void
toggleview(const Arg *arg)
{
	unsigned int newtagset = selmon->tagset[selmon->seltags] ^ (arg->ui & TAGMASK);

	if (newtagset) {
		selmon->tagset[selmon->seltags] = newtagset;
		focus(NULL);
		arrange(selmon);
	}
#if EWMH_TAGS
  updatecurrentdesktop();
#endif
}

void
unfocus(Client *c, int setfocus)
{
	if (!c)
		return;
	grabbuttons(c, 0);
	XSetWindowBorder(dpy, c->win, scheme[SchemeNorm][ColBorder].pixel);
#if OPACITY
	if (opacity_enabled)
		opacity_apply(c, opacity_for(c, 0));
#endif
	if (setfocus) {
		XSetInputFocus(dpy, root, RevertToPointerRoot, CurrentTime);
		XDeleteProperty(dpy, root, netatom[NetActiveWindow]);
	}
}

void
unmanage(Client *c, int destroyed)
{
	Monitor *m = c->mon;
	XWindowChanges wc;
	unsigned int ctags = c->tags;

	detach(c);
	detachstack(c);
	if (!destroyed) {
		wc.border_width = c->oldbw;
		XGrabServer(dpy); /* avoid race conditions */
		XSetErrorHandler(xerrordummy);
		XSelectInput(dpy, c->win, NoEventMask);
		XConfigureWindow(dpy, c->win, CWBorderWidth, &wc); /* restore border */
		XUngrabButton(dpy, AnyButton, AnyModifier, c->win);
		setclientstate(c, WithdrawnState);
		XSync(dpy, False);
		XSetErrorHandler(xerror);
		XUngrabServer(dpy);
	}
	free(c);
	/* last tiled window of a tag is gone: forget that tag's master-size (mfact)
	 * adjustment and its layout, so the next windows there start at the config.h
	 * defaults again. Only the floating layout stays remembered. */
#if PER_TAG_LAYOUT
	{
		unsigned int i;
		Client *o;

		for (i = 0; i < LENGTH(tags); i++) {
			if (!(ctags & (1 << i)))
				continue;
			for (o = m->clients; o && (o->isfloating || !(o->tags & (1 << i))); o = o->next);
			if (o)
				continue;
			if (!m->pertaglt[i]->arrange) /* floating layout: keep it */
				continue;
			m->pertagmfact[i] = mfact;
			m->pertaglt[i] = &layouts[0];
			m->pertagsellt[i] = 0;
			if (currenttagidx(m) == (int)i) {
				m->mfact = mfact;
				m->lt[0] = &layouts[0];
				m->sellt = 0;
			}
		}
	}
#else
	(void)ctags;
	if (!nexttiled(m->clients))
		m->mfact = mfact;
#endif
	focus(NULL);
	updateclientlist();
	arrange(m);
#if WARP_TO_CLIENT && WARP_TO_CENTER_OF_PREVIOUS_WINDOW
  if (m == selmon && m->sel)
    warptoclient(m->sel);
#endif
}

void
unmapnotify(XEvent *e)
{
	Client *c;
	XUnmapEvent *ev = &e->xunmap;

	if ((c = wintoclient(ev->window))) {
		if (ev->send_event)
			setclientstate(c, WithdrawnState);
		else
			unmanage(c, 0);
	}
#if EXTERNAL_BARS
  externalbars_unregister(ev->window);
#endif
}

void
updatebars(void)
{
	Monitor *m;
	XSetWindowAttributes wa = {
		.override_redirect = True,
		.background_pixmap = ParentRelative,
		.event_mask = ButtonPressMask|ExposureMask
	};
	XClassHint ch = {"vxwm", "vxwm"};
	for (m = mons; m; m = m->next) {
		if (m->barwin)
			continue;
#if !BAR_PADDING
		m->barwin = XCreateWindow(dpy, root, m->wx, m->by, m->ww, bh, 0, DefaultDepth(dpy, screen),
#else
    m->barwin = XCreateWindow(dpy, root, m->wx + lsp, m->by + (m->topbar ? tvp : bvp), m->ww - lsp - rsp, bh, 0, DefaultDepth(dpy, screen),
#endif
				CopyFromParent, DefaultVisual(dpy, screen),
				CWOverrideRedirect|CWBackPixmap|CWEventMask, &wa);
		XDefineCursor(dpy, m->barwin, cursor[CurNormal]->cursor);
		XMapRaised(dpy, m->barwin);
		XSetClassHint(dpy, m->barwin, &ch);
	}
}

void
updatebarpos(Monitor *m)
{
	m->wy = m->my;
	m->wh = m->mh;
	if (m->showbar) {
#if !BAR_PADDING
		m->wh -= bh;
		m->by = m->topbar ? m->wy : m->wy + m->wh;
		m->wy = m->topbar ? m->wy + bh : m->wy;
#else
    m->wh = m->wh - top_vertpad - bottom_vertpad - bh;
		m->by = m->topbar ? m->wy : m->wy + m->wh + top_vertpad + bottom_vertpad;
		m->wy = m->topbar ? m->wy + bh + tvp : m->wy;
#endif
	} else
#if !BAR_PADDING
		m->by = -bh;
#else
    m->by = -bh - bvp;
#endif
#if EXTERNAL_BARS
    m->wx += m->strut_left;
    m->ww -= m->strut_left + m->strut_right;
    m->wy += m->strut_top;
    m->wh -= m->strut_top + m->strut_bottom;
    if (m->ww < 1) m->ww = 1;
    if (m->wh < 1) m->wh = 1;
 #endif
}

void
updateclientlist(void)
{
	Client *c;
	Monitor *m;

	XDeleteProperty(dpy, root, netatom[NetClientList]);
	for (m = mons; m; m = m->next)
		for (c = m->clients; c; c = c->next)
			XChangeProperty(dpy, root, netatom[NetClientList],
				XA_WINDOW, 32, PropModeAppend,
				(unsigned char *) &(c->win), 1);
}

int
updategeom(void)
{
	int dirty = 0;

#ifdef XINERAMA
	if (XineramaIsActive(dpy)) {
		int i, j, n, nn;
		Client *c;
		Monitor *m;
		XineramaScreenInfo *info = XineramaQueryScreens(dpy, &nn);
		XineramaScreenInfo *unique = NULL;

		for (n = 0, m = mons; m; m = m->next, n++);
		/* only consider unique geometries as separate screens */
		unique = ecalloc(nn, sizeof(XineramaScreenInfo));
		for (i = 0, j = 0; i < nn; i++)
			if (isuniquegeom(unique, j, &info[i]))
				memcpy(&unique[j++], &info[i], sizeof(XineramaScreenInfo));
		XFree(info);
		nn = j;

		/* new monitors if nn > n */
		for (i = n; i < nn; i++) {
			for (m = mons; m && m->next; m = m->next);
			if (m)
				m->next = createmon();
			else
				mons = createmon();
		}
		for (i = 0, m = mons; i < nn && m; m = m->next, i++)
			if (i >= n
			|| unique[i].x_org != m->mx || unique[i].y_org != m->my
			|| unique[i].width != m->mw || unique[i].height != m->mh)
			{
				dirty = 1;
				m->num = i;
				m->mx = m->wx = unique[i].x_org;
				m->my = m->wy = unique[i].y_org;
				m->mw = m->ww = unique[i].width;
				m->mh = m->wh = unique[i].height;
				updatebarpos(m);
			}
		/* removed monitors if n > nn */
		for (i = nn; i < n; i++) {
			for (m = mons; m && m->next; m = m->next);
			while ((c = m->clients)) {
				dirty = 1;
				m->clients = c->next;
				detachstack(c);
				c->mon = mons;
				attach(c);
				attachstack(c);
			}
			if (m == selmon)
				selmon = mons;
			cleanupmon(m);
		}
		free(unique);
	} else
#endif /* XINERAMA */
	{ /* default monitor setup */
		if (!mons)
			mons = createmon();
		if (mons->mw != sw || mons->mh != sh) {
			dirty = 1;
			mons->mw = mons->ww = sw;
			mons->mh = mons->wh = sh;
			updatebarpos(mons);
		}
	}
	if (dirty) {
		selmon = mons;
		selmon = wintomon(root);
	}
	return dirty;
}

void
updatenumlockmask(void)
{
	unsigned int i, j;
	XModifierKeymap *modmap;

	numlockmask = 0;
	modmap = XGetModifierMapping(dpy);
	for (i = 0; i < 8; i++)
		for (j = 0; j < modmap->max_keypermod; j++)
			if (modmap->modifiermap[i * modmap->max_keypermod + j]
				== XKeysymToKeycode(dpy, XK_Num_Lock))
				numlockmask = (1 << i);
	XFreeModifiermap(modmap);
}

void
updatesizehints(Client *c)
{
	long msize;
	XSizeHints size;

	if (!XGetWMNormalHints(dpy, c->win, &size, &msize))
		/* size is uninitialized, ensure that size.flags aren't used */
		size.flags = PSize;
	if (size.flags & PBaseSize) {
		c->basew = size.base_width;
		c->baseh = size.base_height;
	} else if (size.flags & PMinSize) {
		c->basew = size.min_width;
		c->baseh = size.min_height;
	} else
		c->basew = c->baseh = 0;
	if (size.flags & PResizeInc) {
		c->incw = size.width_inc;
		c->inch = size.height_inc;
	} else
		c->incw = c->inch = 0;
	if (size.flags & PMaxSize) {
		c->maxw = size.max_width;
		c->maxh = size.max_height;
	} else
		c->maxw = c->maxh = 0;
	if (size.flags & PMinSize) {
		c->minw = size.min_width;
		c->minh = size.min_height;
	} else if (size.flags & PBaseSize) {
		c->minw = size.base_width;
		c->minh = size.base_height;
	} else
		c->minw = c->minh = 0;
	if (size.flags & PAspect) {
		c->mina = (float)size.min_aspect.y / size.min_aspect.x;
		c->maxa = (float)size.max_aspect.x / size.max_aspect.y;
	} else
		c->maxa = c->mina = 0.0;
	c->isfixed = (c->maxw && c->maxh && c->maxw == c->minw && c->maxh == c->minh);
	c->hintsvalid = 1;
}

void
updatestatus(void)
{
	if (!gettextprop(root, XA_WM_NAME, stext, sizeof(stext)))
		strcpy(stext, "vxwm-"VERSION);
	drawbar(selmon);
}

void
updatetitle(Client *c)
{
	if (!gettextprop(c->win, netatom[NetWMName], c->name, sizeof c->name))
		gettextprop(c->win, XA_WM_NAME, c->name, sizeof c->name);
	if (c->name[0] == '\0') /* hack to mark broken clients */
		strcpy(c->name, broken);
}

void
updatewindowtype(Client *c)
{
	Atom state = getatomprop(c, netatom[NetWMState]);
	Atom wtype = getatomprop(c, netatom[NetWMWindowType]);

	if (state == netatom[NetWMFullscreen])
		setfullscreen(c, 1);
	if (wtype == netatom[NetWMWindowTypeDialog])
		c->isfloating = 1;
}

void
updatewmhints(Client *c)
{
	XWMHints *wmh;

	if ((wmh = XGetWMHints(dpy, c->win))) {
		if (c == selmon->sel && wmh->flags & XUrgencyHint) {
			wmh->flags &= ~XUrgencyHint;
			XSetWMHints(dpy, c->win, wmh);
		} else
			c->isurgent = (wmh->flags & XUrgencyHint) ? 1 : 0;
		if (wmh->flags & InputHint)
			c->neverfocus = !wmh->input;
		else
			c->neverfocus = 0;
		XFree(wmh);
	}
}

#if TAG_TO_TAG

void
view(const Arg *arg)
{
#if INFINITE_TAGS
    if (selmon->lt[selmon->sellt]->arrange == NULL) {
        save_canvas_positions(selmon);
    }
#endif

    if ((arg->ui & TAGMASK) == selmon->tagset[selmon->seltags])
        selmon->seltags ^= 1;
    else {
        selmon->seltags ^= 1;
        if (arg->ui & TAGMASK)
            selmon->tagset[selmon->seltags] = arg->ui & TAGMASK;
    }

#if PER_TAG_LAYOUT
    /* Each tag carries its own layout, so pull in the one belonging to the
       tag we just switched to. */
    loadtaglayout(selmon);
#endif

#if INFINITE_TAGS
    int newtag = getcurrenttag(selmon);

    if (selmon->lt[selmon->sellt]->arrange == NULL) {
        restore_canvas_positions(selmon);

        Client *c;
        for (c = selmon->clients; c; c = c->next)
            if (c->tags & (1 << newtag))
                c->isfloating = 1;
    } else {
        selmon->canvas[newtag].cx = 0;
        selmon->canvas[newtag].cy = 0;
    }
#endif

    focus(NULL);
    arrange(selmon);
#if EWMH_TAGS
    updatecurrentdesktop();
#endif
}

#else

void
view(const Arg *arg)
{
#if INFINITE_TAGS
    if (selmon->lt[selmon->sellt]->arrange == NULL)
        save_canvas_positions(selmon);
#endif

    if ((arg->ui & TAGMASK) == selmon->tagset[selmon->seltags])
        return;
    selmon->seltags ^= 1;
    if (arg->ui & TAGMASK)
        selmon->tagset[selmon->seltags] = arg->ui & TAGMASK;

#if INFINITE_TAGS
    int newtag = getcurrenttag(selmon);

    if (selmon->lt[selmon->sellt]->arrange != NULL) {
        selmon->canvas[newtag].cx = 0;
        selmon->canvas[newtag].cy = 0;
    } else {
        restore_canvas_positions(selmon);

        Client *c;
        for (c = selmon->clients; c; c = c->next)
            if (ISVISIBLE(c))
                c->isfloating = 1;
    }
#endif

    focus(NULL);
    arrange(selmon);
#if EWMH_TAGS
    updatecurrentdesktop();
#endif
}

#endif

Client *
wintoclient(Window w)
{
	Client *c;
	Monitor *m;

	for (m = mons; m; m = m->next)
		for (c = m->clients; c; c = c->next)
			if (c->win == w)
				return c;
	return NULL;
}

Monitor *
wintomon(Window w)
{
	int x, y;
	Client *c;
	Monitor *m;

	if (w == root && getrootptr(&x, &y))
		return recttomon(x, y, 1, 1);
	for (m = mons; m; m = m->next)
		if (w == m->barwin)
			return m;
	if ((c = wintoclient(w)))
		return c->mon;
	return selmon;
}

/* There's no way to check accesses to destroyed windows, thus those cases are
 * ignored (especially on UnmapNotify's). Other types of errors call Xlibs
 * default error handler, which may call exit. */
int
xerror(Display *dpy, XErrorEvent *ee)
{
	if (ee->error_code == BadWindow
	|| (ee->request_code == X_SetInputFocus && ee->error_code == BadMatch)
	|| (ee->request_code == X_PolyText8 && ee->error_code == BadDrawable)
	|| (ee->request_code == X_PolyFillRectangle && ee->error_code == BadDrawable)
	|| (ee->request_code == X_PolySegment && ee->error_code == BadDrawable)
	|| (ee->request_code == X_ConfigureWindow && ee->error_code == BadMatch)
	|| (ee->request_code == X_GrabButton && ee->error_code == BadAccess)
	|| (ee->request_code == X_GrabKey && ee->error_code == BadAccess)
	|| (ee->request_code == X_CopyArea && ee->error_code == BadDrawable))
		return 0;
	fprintf(stderr, "vxwm: fatal error: request code=%d, error code=%d\n",
		ee->request_code, ee->error_code);
	return xerrorxlib(dpy, ee); /* may call exit */
}

int
xerrordummy(Display *dpy, XErrorEvent *ee)
{
	return 0;
}

/* Startup Error handler to check if another window manager
 * is already running. */
int
xerrorstart(Display *dpy, XErrorEvent *ee)
{
	die("vxwm: another window manager is already running");
	return -1;
}

void
swapmaster(const Arg *arg)
{
	Client *c = selmon->sel;
#if WARP_TO_CLIENT && WARP_TO_CENTER_OF_SWAPMASTERED_WINDOW
  Client *target = c;
#endif

	if (!selmon->lt[selmon->sellt]->arrange || !c || c->isfloating)
		return;
	if (c == nexttiled(selmon->clients) && !(c = nexttiled(c->next)))
		return;
	pop(c);
#if WARP_TO_CLIENT && WARP_TO_CENTER_OF_SWAPMASTERED_WINDOW
  warptoclient(target);
#endif
}

int
main(int argc, char *argv[])
{
	if (argc == 2 && !strcmp("-v", argv[1]))
		die("vxwm "VERSION);
  if (argc == 2 && !strcmp("-srcdir", argv[1]))
    die(SRCDIR);
  if (argc == 2 && !strcmp("-ignoreautostart", argv[1]))
    printf("Ignoring autostart");
	else if (argc != 1)
		die("usage: vxwm [-v] [-srcdir]"
#if AUTOSTART
         " [-ignoreautostart]"
#endif
       );
	if (!setlocale(LC_CTYPE, "") || !XSupportsLocale())
		fputs("warning: no locale support\n", stderr);
	if (!(dpy = XOpenDisplay(NULL)))
		die("vxwm: cannot open display");
	checkotherwm();
#if XRDB
  XrmInitialize();
  loadxrdb();
#endif
	setup();
#ifdef __OpenBSD__
	if (pledge("stdio rpath proc exec", NULL) == -1)
		die("pledge");
#endif /* __OpenBSD__ */
	scan();
#if AUTOSTART
  if (!(argc == 2 && !strcmp("-ignoreautostart", argv[1])))
    runautostart();
#endif
	run();
	cleanup();
	XCloseDisplay(dpy);
	return EXIT_SUCCESS;
}
