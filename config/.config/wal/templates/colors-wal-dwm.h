static char normfgcolor[]     = "{foreground}";
static char normbgcolor[]     = "{background}";
static char normbordercolor[] = "{color8}";
static char selfgcolor[]      = "{background}";
static char selbgcolor[]      = "{color6}";
static char selbordercolor[]  = "{color6}";

static char *colors[][3] = {{
    [SchemeNorm] = {{ normfgcolor,   normbgcolor,   normbordercolor }},
    [SchemeSel]  = {{ selfgcolor,    selbgcolor,    selbordercolor }}
}};
