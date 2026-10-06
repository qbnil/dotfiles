/* Alt-tab cycling. Two modes:
 *
 *   alttab()    - floating clients only
 *   alttaball() - every visible client, tiled ones included
 *
 * The candidate order is deliberately stable while cycling. focus() moves
 * the focused client to the head of m->stack, so deriving the order from
 * m->stack on every keypress would make the selection oscillate between two
 * windows instead of walking all of them. Instead this module keeps its own
 * list: clients are appended as they appear and dropped when they go away,
 * and cycling just steps through it without reordering. */

static Client **alttablist = NULL;
static int alttabn = 0, alttabcap = 0;

static int
clientalive(Client *c)
{
	Monitor *m;
	Client *i;

	for (m = mons; m; m = m->next)
		for (i = m->clients; i; i = i->next)
			if (i == c)
				return 1;
	return 0;
}

/* Drop clients that are gone, then append ones we have not seen yet. */
static void
alttabsync(void)
{
	Client *c, **fresh = NULL;
	int nfresh = 0, cap = 0, i, j = 0;

	for (i = 0; i < alttabn; i++)
		if (clientalive(alttablist[i]))
			alttablist[j++] = alttablist[i];
	alttabn = j;

	for (c = selmon->stack; c; c = c->snext) {
		if (!ISVISIBLE(c))
			continue;
		for (i = 0; i < alttabn; i++)
			if (alttablist[i] == c)
				break;
		if (i < alttabn)
			continue;
		if (nfresh == cap) {
			Client **tmp;
			cap = cap ? cap * 2 : 8;
			if (!(tmp = realloc(fresh, cap * sizeof(Client *)))) {
				free(fresh);
				return;
			}
			fresh = tmp;
		}
		fresh[nfresh++] = c;
	}

	/* m->stack is most-recent-first; append back-to-front so the newest
	   client lands last and alt+shift+tab reaches it first. */
	for (i = nfresh - 1; i >= 0; i--) {
		if (alttabn == alttabcap) {
			Client **tmp;
			int ncap = alttabcap ? alttabcap * 2 : 8;
			if (!(tmp = realloc(alttablist, ncap * sizeof(Client *)))) {
				free(fresh);
				return;
			}
			alttablist = tmp;
			alttabcap = ncap;
		}
		alttablist[alttabn++] = fresh[i];
	}
	free(fresh);
}

/* floatsonly != 0 restricts cycling to floating clients. */
static void
alttabcycle(const Arg *arg, int floatsonly)
{
	Client *c, **cands, *t;
	int n = 0, i, sel = -1, target;

	if (!selmon->sel || (selmon->sel->isfullscreen && lockfullscreen))
		return;

	alttabsync();

	if (alttabn > 0 && (cands = calloc(alttabn, sizeof(Client *)))) {
		for (i = 0; i < alttabn; i++) {
			c = alttablist[i];
			if (c->mon != selmon || !ISVISIBLE(c))
				continue;
			if (floatsonly && !c->isfloating)
				continue;
			if (c == selmon->sel)
				sel = n;
			cands[n++] = c;
		}

		/* sel is -1 when focus sits on a client outside this mode's
		   candidate set; either way the candidate becomes focused. */
		if (n > 1) {
			if (sel < 0) {
				target = arg->i > 0 ? 0 : n - 1;
			} else {
				target = (sel + arg->i) % n;
				if (target < 0)
					target += n;
			}

			t = cands[target];
			focus(t);
#if INFINITE_TAGS
			centerwindow(NULL);
#endif
#if WARP_TO_CLIENT && WARP_TO_CENTER_OF_WINDOW_AFFECTED_BY_ALTTAB
			warptoclient(t);
#endif
			restack(t->mon);
		}
		free(cands);
	}
}

void
alttab(const Arg *arg)
{
	alttabcycle(arg, 1);
}

void
alttaball(const Arg *arg)
{
	alttabcycle(arg, 0);
}
