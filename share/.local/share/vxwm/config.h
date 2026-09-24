#pragma once

/* See LICENSE file for copyright and license details. */

/* appearance */
static const unsigned int borderpx  = 2;        /* border pixel of windows */
static const unsigned int snap      = 0;       /* snap pixel */
static const int showbar            = 1;        /* 0 means no bar */
static const int topbar             = 1;        /* 0 means bottom bar */
static const char *fonts[] = {
      "JetBrainsMono Nerd Font:size=11",
//    "Symbols Nerd Font:size=10",
//    "Noto Color Emoji:size=10"
};
static const char dmenufont[]       = "JetBrainsMono Nerd Font:size=10";
static const char *up_vol[]   = { "wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "5%+"};
static const char *down_vol[] = { "wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "5%-"};
static const char *mute_vol[] = { "wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"};
static const char *screenshotcmd[] = { "flameshot", "gui", NULL };
static const char *next_song[] = { "mpc", "next", NULL };
static const char *prev_song[] = { "mpc", "prev", NULL };
static const char *stop_song[] = { "mpc", "stop", NULL };
static const char *toggle_play[] = { "mpc", "toggle", NULL };
static const char *cliphistadd[] = { "cliphist", "add", NULL };
static const char *cliphistsel[] = { "cliphist", "sel", NULL };
#define COORDINATES_STYLE "[x%d y%d]" /* The style of coordinates displayed in bar, do not remove %d. */

#include "/home/kent/.cache/wal/colors-wal-dwm.h"

// static MAYBE_CONST char normbgcolor[]           = "#000000";
// static MAYBE_CONST char normbordercolor[]       = "#000000";
// static MAYBE_CONST char normfgcolor[]           = "#ffffff";
// static MAYBE_CONST char selfgcolor[]            = "#000000";
// static MAYBE_CONST char selbordercolor[]        = "#7d7c7c";
// static MAYBE_CONST char selbgcolor[]            = "#a780a8";
// static MAYBE_CONST char *colors[][3] = {
       /*               fg           bg           border   */
//       [SchemeNorm] = { normfgcolor, normbgcolor, normbordercolor },
//       [SchemeSel]  = { selfgcolor,  selbgcolor,  selbordercolor  },
//};

#define CENTER_NEW_FLOATING_WINDOWS 0 // so, basically, it does what it says. (make 0 to turn off)
#define NEW_FLOATING_WINDOWS_APPEAR_UNDER_CURSOR 0 // so, basically, it does what it says. (make 0 to turn off) 

#if GAPS
static const unsigned int gappx = 3;
#endif

#if BAR_HEIGHT
static const int user_bh = 34;
#endif

#if BAR_PADDING
static const int top_vertpad = 3;          /* top vertical padding of bar */ 
// static const int bottom_vertpad = 8;       /* bottom vertical padding of bar */
static const int bottom_vertpad = 0;       /* bottom vertical padding of bar */
// static const int left_sidepad = 10;         /* left horizontal padding of bar */
// static const int right_sidepad = 10;        /* right horizontal padding of bar */
static const int left_sidepad = 3;         /* left horizontal padding of bar */
static const int right_sidepad = 3;        /* right horizontal padding of bar */
#endif

#define BAR_ALWAYS_ON_TOP 1 /* Makes internal bar on top of other windows. */

#if EXTERNAL_BARS
#define EXTERNAL_BARS_ALWAYS_ON_TOP 1 /* Makes external bars on top of other windows. */
#endif

#if INFINITE_TAGS
#define PINNED_WINDOWS_ALWAYS_ON_TOP 1 /* Makes pinned windows on top of other windows */
#endif

/* tagging */
static const char *tags[] = { "1", "2", "3", "4", "5", "6", "7", "8", "9" };

#if OCCUPIED_TAGS_DECORATION
static const char *occupiedtags[] = { "1+", "2+", "3+", "4+", "5+", "6+", "7+", "8+", "9+" };
#endif

#if INFINITE_TAGS
#define MOVE_CANVAS_STEP 120 /* Defines how many pixel will be jumped when using movecanvas function */
#endif

#if INFINITE_TAGS && IT_SHOW_COORDINATES_IN_BAR
#define COORDINATES_DIVISOR 10 /* Defines by what number coordinates on the bar will be divided, can be used for making numbers smaller which makes navigation easier */
#endif

#if MOVE_RESIZE_WITH_KEYBOARD
#define MOVE_WITH_KEYBOARD_STEP 50 /* Defines by how many pixels windows will be resized with keyboard */
#define RESIZE_WITH_KEYBOARD_STEP 50 /* Defines by how many pixels windows will be resized with keyboard */
#endif

#if AUTOSTART
/* vxwm will execute this on startup (can be skipped with -ignoreautostart vxwm flag). */

static const char *const autostart[] = {
	"st",
	NULL /* must end with NULL */
};
#endif

static const Rule rules[] = {
	/* xprop(1):
	 *	WM_CLASS(STRING) = instance, class
	 *	WM_NAME(STRING) = title
	 */
	/* class      instance    title       tags mask     isfloating   monitor */
	{ "Gimp",     NULL,       NULL,       0,            1,           -1 },
//	{ "vivaldi",  NULL,       NULL,       1 << 8,       0,           -1 },
};

/* layout(s) */
static const float mfact     = 0.55; /* factor of master area size [0.05..0.95] */
static const int nmaster     = 1;    /* number of clients in master area */
static const int resizehints = 1;    /* 1 means respect size hints in tiled resizals */
static const int lockfullscreen = 1; /* 1 will force focus on the fullscreen window */
#if LOCK_MOVE_RESIZE_REFRESH_RATE
static const int refreshrate = 240;  /* refresh rate (per second) for client move/resize, set it to your monitor refresh rate or double of that*/
#endif //LOCK_MOVE_RESIZE_REFRESH_RATE
static const Layout layouts[] = {
	{ "[]=",      tile },    /* first entry is default */
	/* symbol     arrange function */
	{ "><>",      NULL },    /* no layout function means floating behavior */
	{ "[M]",      monocle },
};

/* key definitions */
#define MODKEY Mod4Mask
#define ALTERNATE_MODKEY Mod1Mask

#define SCROLL_UP Button4
#define SCROLL_DOWN Button5

#define TAGKEYS(KEY,TAG) \
	{ MODKEY,                       KEY,      view,           {.ui = 1 << TAG} }, \
	{ MODKEY|ControlMask,           KEY,      toggleview,     {.ui = 1 << TAG} }, \
	{ MODKEY|ShiftMask,                     KEY,      tag,            {.ui = 1 << TAG} }, \
	{ MODKEY|ControlMask|ShiftMask, KEY,      toggletag,      {.ui = 1 << TAG} },

/* helper for spawning shell commands in the pre dwm-5.0 fashion */
#define SHCMD(cmd) { .v = (const char*[]){ "/bin/sh", "-c", cmd, NULL } }

/* commands */
static char dmenumon[2] = "0"; /* component of dmenucmd, manipulated in spawn() */
static const char *dmenucmd[] = { "dmenu_run", "-fn", dmenufont, NULL };

static const char *termcmd[]  = { "st", NULL };
static const char *powermenu[] = { "sys", NULL };
static const char *wallpapermenu[] = { "wallpapermenu", NULL };
static const char *cheatsheet[] = { "cheatsheet", NULL };

#if ZOOM
static const char *zoomin[] = { "vcompmgr", "-Z", "+0.15", NULL }; // zoom in
static const char *zoomout[] = { "vcompmgr", "-Z", "-0.15", NULL }; // zoom out
static const char *zoomreset[] = { "vcompmgr", "-Z", "1", NULL }; // set zoom to 1
#endif

static const Key keys[] = {
	/* modifier                     key        function        argument */
	{ MODKEY,                       XK_d,      spawn,          {.v = dmenucmd } },
  	{ MODKEY,     		        XK_Return, spawn,          {.v = termcmd } },
	{ MODKEY,                       XK_w,      spawn,      {.v = wallpapermenu} },
	{ MODKEY,                       XK_slash,  spawn,      {.v = cheatsheet} },
	{ MODKEY,                       XK_p,      spawn,      {.v = powermenu} },
	{ MODKEY,                       XK_b,      togglebar,      {0} },
//	{ 0,				XKB_KEY_XF86AudioRaiseVolume, spawn, {.v = up_vol} },
//	{ 0,				XKB_KEY_XF86AudioLowerVolume, spawn, {.v = down_vol} },
//	{ 0,				XKB_KEY_XF86AudioMute, spawn, {.v = mute_vol} },
	{ 0, 				XF86XK_AudioRaiseVolume, spawn, {.v = up_vol} },
	{ 0, 				XF86XK_AudioLowerVolume, spawn, {.v = down_vol} },
	{ 0, 				XF86XK_AudioMute,        spawn, {.v = mute_vol} },
	{ MODKEY, 			XK_c, spawn, {.v = cliphistadd } },
	{ MODKEY, 			XK_v, spawn, {.v = cliphistsel } },
	{ MODKEY,			XK_bracketleft, spawn, {.v = prev_song} },
	{ MODKEY,			XK_bracketright, spawn, {.v = next_song} },
	{ MODKEY,			XK_s, spawn, {.v = stop_song} },
//	{ MODKEY|ShiftMask,		XK_p, spawn, {.v = toggle_play} },
//	{ MODKEY|ShiftMask,             XK_j,      focusstack,     {.i = +1 } },
//	{ MODKEY|ShiftMask,             XK_k,      focusstack,     {.i = -1 } },
	{ MODKEY,                       XK_i,      incnmaster,     {.i = +1 } },
	{ MODKEY,                       XK_o,      incnmaster,     {.i = -1 } },
	{ MODKEY|ControlMask,           XK_h,      setmfact,       {.f = -0.05} },
	{ MODKEY|ControlMask,           XK_l,      setmfact,       {.f = +0.05} },
	{ MODKEY|ShiftMask,             XK_Return, swapmaster,     {0} },
	{ MODKEY,                       XK_0,      view,           {0} },
	{ MODKEY,	                XK_q,      killclient,     {0} },
	{ MODKEY,                       XK_t,      setlayout,      {.v = &layouts[1]} },
	{ MODKEY,                       XK_f,      setlayout,      {.v = &layouts[0]} },
	{ MODKEY,                       XK_m,      setlayout,      {.v = &layouts[2]} },
//	{ MODKEY|ControlMask,           XK_space,  setlayout,      {0} },
//	{ MODKEY|ShiftMask,             XK_space,  togglefloating, {0} }, //default toggle floating bind.
	{ MODKEY,                       XK_Tab,    view,           {.ui = ~0 } },
	{ MODKEY|ShiftMask,             XK_0,      tag,            {.ui = ~0 } },
	{ MODKEY,                       XK_comma,  focusmon,       {.i = -1 } },
	{ MODKEY,                       XK_period, focusmon,       {.i = +1 } },
	{ MODKEY|ShiftMask,             XK_comma,  tagmon,         {.i = -1 } },
	{ MODKEY|ShiftMask,             XK_period, tagmon,         {.i = +1 } },
	{ MODKEY|ShiftMask,             XK_s,      spawn,          {.v = screenshotcmd } },
	TAGKEYS(                        XK_1,                      0)
	TAGKEYS(                        XK_2,                      1)
	TAGKEYS(                        XK_3,                      2)
	TAGKEYS(                        XK_4,                      3)
	TAGKEYS(                        XK_5,                      4)
	TAGKEYS(                        XK_6,                      5)
	TAGKEYS(                        XK_7,                      6)
	TAGKEYS(                        XK_8,                      7)
	TAGKEYS(                        XK_9,                      8)
	{ MODKEY|ShiftMask,             XK_q,      quit,           {0} },
#if XRDB
  { MODKEY,                       XK_F5,     xrdb,           {.v = NULL } },
#endif
#if FULLSCREEN
  { MODKEY|ShiftMask,             XK_f,      togglefullscr,  {0} },
#endif
#if ENHANCED_TOGGLE_FLOATING
  { MODKEY,                       XK_e,      enhancedtogglefloating, {0} }, //enhanced toggle floating bind.
#endif
#if GAPS
  { MODKEY,                       XK_minus,  setgaps,        {.i = -1 } },
  { MODKEY,                       XK_equal,  setgaps,        {.i = +1 } },
  { MODKEY|ShiftMask,             XK_equal,  setgaps,        {.i = 0  } },
#endif
#if MOVE_RESIZE_WITH_KEYBOARD
  { MODKEY|ShiftMask,		 	      XK_j,	moveresize,		{.v = (int []){ 0, MOVE_WITH_KEYBOARD_STEP, 0, 0 }}}, // Move window to down
  { MODKEY|ShiftMask,			      XK_k,	moveresize,		{.v = (int []){ 0, -MOVE_WITH_KEYBOARD_STEP, 0, 0 }}}, // Move window to up
  { MODKEY|ShiftMask,			      XK_l,	moveresize,		{.v = (int []){ MOVE_WITH_KEYBOARD_STEP, 0, 0, 0 }}}, // Move window to right
  { MODKEY|ShiftMask,			      XK_h,	moveresize,		{.v = (int []){ -MOVE_WITH_KEYBOARD_STEP, 0, 0, 0 }}}, // Move window to left
#endif
#if INFINITE_TAGS
  { ALTERNATE_MODKEY,             XK_r,      homecanvas,       {0} }, // Return to x:0, y:0 position
  { ALTERNATE_MODKEY,             XK_l,   movecanvas,       {.i = 0} }, // Move your position to left
  { ALTERNATE_MODKEY,             XK_h,  movecanvas,       {.i = 1} }, // Move your position to right
  { ALTERNATE_MODKEY,             XK_j,     movecanvas,       {.i = 2} }, // Move your position up
  { ALTERNATE_MODKEY,             XK_k,   movecanvas,       {.i = 3} }, // Move your position down
//  { ALTERNATE_MODKEY,             XK_d,      centerwindow,     {0} },
  { ALTERNATE_MODKEY,             XK_z,      pinwindow,        {0} },
#endif
#if DIRECTIONAL_FOCUS
	{ MODKEY, XK_h,   focusdir,       {.i = 0 } }, // left
	{ MODKEY, XK_l,   focusdir,       {.i = 1 } }, // right
	{ MODKEY, XK_k,   focusdir,       {.i = 2 } }, // up
	{ MODKEY, XK_j,   focusdir,       {.i = 3 } }, // down
#endif
#if ZOOM
 { ALTERNATE_MODKEY|ShiftMask,    XK_r,      spawn,          {.v = zoomreset } },
 { ALTERNATE_MODKEY,              XK_equal,  spawn,          {.v = zoomin } },
 { ALTERNATE_MODKEY,              XK_minus,  spawn,          {.v = zoomout } },
#endif
};

/* button definitions */
/* click can be ClkTagBar, ClkLtSymbol, ClkStatusText, ClkWinTitle, ClkClientWin, or ClkRootWin */
static const Button buttons[] = {
	/* click                event mask      button          function        argument */
#if INFINITE_TAGS
  { ClkRootWin,           MODKEY|ShiftMask,         Button1,        movecanvasmouse,     {.f = 1.5 } }, 
  { ClkClientWin,         MODKEY|ShiftMask,         Button1,        movecanvasmouse,     {.f = 1.5 } },
  { ClkRootWin,           0,                        Button1,        movecanvasmouse,     {.f = 1.5 } },
  /* .f = 1 is moving multiplier, for example if set to 0.5, canvas will move 2 times slower, if set to 2, canvas will move 2 times faster. 
     If you want inverted canvas move then set the value to a negative value. */
#endif
#if ZOOM
  { ClkRootWin,           MODKEY,         SCROLL_UP,      spawn,          {.v = zoomin } },
  { ClkRootWin,           MODKEY,         SCROLL_DOWN,    spawn,          {.v = zoomout } },

  { ClkClientWin,         MODKEY,         SCROLL_UP,      spawn,          {.v = zoomin } },
  { ClkClientWin,         MODKEY,         SCROLL_DOWN,    spawn,          {.v = zoomout } },
#endif
	{ ClkLtSymbol,          0,              Button1,        setlayout,      {0} },
	{ ClkLtSymbol,          0,              Button3,        setlayout,      {.v = &layouts[2]} },
	{ ClkWinTitle,          0,              Button2,        swapmaster,     {0} },
	{ ClkStatusText,        0,              Button2,        spawn,          {.v = termcmd } },
	{ ClkClientWin,         MODKEY,         Button1,        movemouse,      {0} },
	{ ClkClientWin,         MODKEY,         Button2,        togglefloating, {0} },
	{ ClkClientWin,         MODKEY,         Button3,        resizemouse,    {0} },
	{ ClkTagBar,            0,              Button1,        view,           {0} },
	{ ClkTagBar,            0,              Button3,        toggleview,     {0} },
	{ ClkTagBar,            MODKEY,         Button1,        tag,            {0} },
	{ ClkTagBar,            MODKEY,         Button3,        toggletag,      {0} },
};

