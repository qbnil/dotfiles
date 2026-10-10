/* Swap the focused window with the closest visible window in the given
 * direction (0 = left, 1 = right, 2 = up, 3 = down).
 *
 * Unlike the old movedir(), this works in every layout and handles both
 * kinds of window:
 *   - tiled windows are exchanged in the client list, so whichever tiling
 *     layout is active simply re-arranges them in their new order;
 *   - floating windows exchange their on-screen geometry (position + size).
 */
void
swapdir(const Arg *arg)
{
        Client *s = selmon->sel, *f = NULL, *c, *next, *p;
        unsigned int score = -1;
        unsigned int client_score;
        int dist;
        int dirweight = 20;
        int isfloating;

        if (!s)
                return;

        isfloating = s->isfloating || curlayout(selmon)->arrange == NULL;

        next = s->next;
        if (!next)
                next = s->mon->clients;
        for (c = next; c != s; c = next) {
                next = c->next;
                if (!next)
                        next = s->mon->clients;
                if (!ISVISIBLE(c) || c->isfloating != isfloating)
                        continue;
                switch (arg->i) {
                case 0: // left
                        dist = s->x - c->x - c->w;
                        client_score =
                                dirweight * MIN(abs(dist), abs(dist + s->mon->ww)) +
                                abs(s->y - c->y);
                        break;
                case 1: // right
                        dist = c->x - s->x - s->w;
                        client_score =
                                dirweight * MIN(abs(dist), abs(dist + s->mon->ww)) +
                                abs(c->y - s->y);
                        break;
                case 2: // up
                        dist = s->y - c->y - c->h;
                        client_score =
                                dirweight * MIN(abs(dist), abs(dist + s->mon->wh)) +
                                abs(s->x - c->x);
                        break;
                default:
                case 3: // down
                        dist = c->y - s->y - s->h;
                        client_score =
                                dirweight * MIN(abs(dist), abs(dist + s->mon->wh)) +
                                abs(c->x - s->x);
                        break;
                }
                if (((arg->i == 0 || arg->i == 2) && client_score <= score) || client_score < score) {
                        score = client_score;
                        f = c;
                }
        }
        if (!f || f == s)
                return;

        if (isfloating) {
                /* exchange geometry so each window takes the other's place */
                int tx = s->x, ty = s->y, tw = s->w, th = s->h;
                s->x = f->x; s->y = f->y; s->w = f->w; s->h = f->h;
                f->x = tx;   f->y = ty;   f->w = tw;   f->h = th;
                XMoveResizeWindow(dpy, s->win, s->x, s->y, s->w, s->h);
                XMoveResizeWindow(dpy, f->win, f->x, f->y, f->w, f->h);
                configure(s);
                configure(f);
                focus(s);
                restack(s->mon);
                return;
        }

        /* tiled windows: swap the two entries in the client list */
        Client *ps = NULL, *pf = NULL;
        for (p = s->mon->clients; p; p = p->next) {
                if (p->next == s) ps = p;
                if (p->next == f) pf = p;
        }

        if (s->next == f) {
                if (ps) ps->next = f; else s->mon->clients = f;
                s->next = f->next;
                f->next = s;
        } else if (f->next == s) {
                if (pf) pf->next = s; else s->mon->clients = s;
                f->next = s->next;
                s->next = f;
        } else {
                if (ps) ps->next = f; else s->mon->clients = f;
                if (pf) pf->next = s; else s->mon->clients = s;
                Client *tmp = s->next;
                s->next = f->next;
                f->next = tmp;
        }

        focus(s);
        arrange(s->mon);
}
