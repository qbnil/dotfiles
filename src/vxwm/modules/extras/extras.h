#pragma once

/* Ideas ported from chadwm (siduck/chadwm), rewritten for vxwm's gaps/bar model. */

#if EXTRA_LAYOUTS
static void bstack(Monitor *m);          /* master row on top, stack row below */
static void centeredmaster(Monitor *m);  /* master in the middle, stack left+right */
#endif

#if LAYOUT_CYCLE
static void cyclelayout(const Arg *arg); /* arg->i: +1 next, -1 previous tiled layout */
#endif

#if SHIFTVIEW
static void shiftview(const Arg *arg);   /* arg->i: +1 next tag, -1 previous tag (wraps) */
#endif

#if MOVESTACK
static void movestack(const Arg *arg);   /* arg->i: +1 / -1 swap with next/previous tiled client */
#endif
