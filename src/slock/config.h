/* user and group to drop privileges to */
static const char *user  = "nobody";
static const char *group = "nobody"; // use "nobody" for arch

static const char *colorname[NUMCOLS] = {
	#if DWM_LOGO_PATCH && !BLUR_PIXELATED_SCREEN_PATCH
	[BACKGROUND] =  "#2d2d2d", /* after initialization */
	#endif // DWM_LOGO_PATCH
	[INIT] =   "black",     /* after initialization */
	[INPUT] =  "#005577",   /* during input */
	[FAILED] = "#CC3333",   /* wrong password */
	#if CAPSCOLOR_PATCH
	[CAPS] =   "red",       /* CapsLock on */
	#endif // CAPSCOLOR_PATCH
	#if PAMAUTH_PATCH
	[PAM] =    "#9400D3",   /* waiting for PAM */
	#endif // PAMAUTH_PATCH
	#if KEYPRESS_FEEDBACK_PATCH
	[BLOCKS] = "#ffffff",   /* key feedback block */
	#endif // KEYPRESS_FEEDBACK_PATCH
};

#if MESSAGE_PATCH || COLOR_MESSAGE_PATCH
/* default message */
static const char * message = "Suckless: Software that sucks less.";

/* text color */
static const char * text_color = "#ffffff";

/* text size (must be a valid size) */
static const char * font_name = "6x10";
#endif // MESSAGE_PATCH | COLOR_MESSAGE_PATCH

#if BACKGROUND_IMAGE_PATCH
/* Background image path, should be available to the user above */
static const char * background_image = "";
#endif // BACKGROUND_IMAGE_PATCH

#if DWM_LOGO_PATCH
/* VXWM wordmark, drawn as a grid of rectangle "pixels".
 * The grid is logow x logoh cells and every cell is logosize pixels wide.
 * The logo is centred on every monitor (see drawlogo in patch/dwmlogo.c). */
static const int logosize = 32;
static const int logow = 23;   /* grid width and height */
static const int logoh = 7;

static XRectangle rectangles[] = {
   /* x    y   w   h */
   {  0,  0,  1,  1 }, {  4,  0,  1,  1 }, {  6,  0,  1,  1 }, { 10,  0,  1,  1 },
   { 12,  0,  1,  1 }, { 16,  0,  1,  1 }, { 18,  0,  1,  1 }, { 22,  0,  1,  1 },
   {  0,  1,  1,  1 }, {  4,  1,  1,  1 }, {  6,  1,  1,  1 }, { 10,  1,  1,  1 },
   { 12,  1,  1,  1 }, { 16,  1,  1,  1 }, { 18,  1,  2,  1 }, { 21,  1,  2,  1 },
   {  0,  2,  1,  1 }, {  4,  2,  1,  1 }, {  7,  2,  1,  1 }, {  9,  2,  1,  1 },
   { 12,  2,  1,  1 }, { 16,  2,  1,  1 }, { 18,  2,  1,  1 }, { 20,  2,  1,  1 },
   { 22,  2,  1,  1 }, {  0,  3,  1,  1 }, {  4,  3,  1,  1 }, {  8,  3,  1,  1 },
   { 12,  3,  1,  1 }, { 14,  3,  1,  1 }, { 16,  3,  1,  1 }, { 18,  3,  1,  1 },
   { 22,  3,  1,  1 }, {  0,  4,  1,  1 }, {  4,  4,  1,  1 }, {  7,  4,  1,  1 },
   {  9,  4,  1,  1 }, { 12,  4,  1,  1 }, { 14,  4,  1,  1 }, { 16,  4,  1,  1 },
   { 18,  4,  1,  1 }, { 22,  4,  1,  1 }, {  1,  5,  1,  1 }, {  3,  5,  1,  1 },
   {  6,  5,  1,  1 }, { 10,  5,  1,  1 }, { 12,  5,  2,  1 }, { 15,  5,  2,  1 },
   { 18,  5,  1,  1 }, { 22,  5,  1,  1 }, {  2,  6,  1,  1 }, {  6,  6,  1,  1 },
   { 10,  6,  1,  1 }, { 12,  6,  1,  1 }, { 16,  6,  1,  1 }, { 18,  6,  1,  1 },
   { 22,  6,  1,  1 },
};
#endif // DWM_LOGO_PATCH

#if XRESOURCES_PATCH
/*
 * Xresources preferences to load at startup.
 *
 * The bare names below are read from the wal/pywal palette already loaded
 * into the X server (*background, *color1, *color3, *color4, *foreground,
 * ...). Any explicit slock.<name> resource is applied on top, so individual
 * colors can still be overridden, e.g.:
 *     slock.input:  #005577
 *     slock.failed: #cc3333
 */
ResourcePref resources[] = {
		#if DWM_LOGO_PATCH && !BLUR_PIXELATED_SCREEN_PATCH
		{ "background",   STRING,  &colorname[BACKGROUND] },
		#endif //DWM_LOGO_PATCH
		#if BACKGROUND_IMAGE_PATCH
		{ "bg_image",     STRING,  &background_image },
		#endif // BACKGROUND_IMAGE_PATCH
		/* pywal palette */
		{ "foreground",   STRING,  &colorname[INIT] },
		{ "color4",       STRING,  &colorname[INPUT] },
		{ "color1",       STRING,  &colorname[FAILED] },
		#if CAPSCOLOR_PATCH
		{ "color3",       STRING,  &colorname[CAPS] },
		#endif // CAPSCOLOR_PATCH
		#if PAMAUTH_PATCH
		{ "color5",       STRING,  &colorname[PAM] },
		#endif // PAMAUTH_PATCH
		#if KEYPRESS_FEEDBACK_PATCH
		{ "foreground",   STRING,  &colorname[BLOCKS] },
		#endif // KEYPRESS_FEEDBACK_PATCH
		/* explicit slock.<name> overrides */
		{ "locked",       STRING,  &colorname[INIT] },
		{ "input",        STRING,  &colorname[INPUT] },
		{ "failed",       STRING,  &colorname[FAILED] },
		#if CAPSCOLOR_PATCH
		{ "capslock",     STRING,  &colorname[CAPS] },
		#endif // CAPSCOLOR_PATCH
		#if PAMAUTH_PATCH
		{ "pamauth",      STRING,  &colorname[PAM] },
		#endif // PAMAUTH_PATCH
		#if KEYPRESS_FEEDBACK_PATCH
		{ "blocks",       STRING,  &colorname[BLOCKS] },
		#endif // KEYPRESS_FEEDBACK_PATCH
		#if MESSAGE_PATCH || COLOR_MESSAGE_PATCH
		{ "message",      STRING,  &message },
		{ "text_color",   STRING,  &text_color },
		{ "font_name",    STRING,  &font_name },
		#endif // MESSAGE_PATCH | COLOR_MESSAGE_PATCH
};
#endif // XRESOURCES_PATCH

#if ALPHA_PATCH
/* lock screen opacity */
static const float alpha = 0.9;
#endif // ALPHA_PATCH

/* treat a cleared input like a wrong password (color) */
static const int failonclear = 1;

#if AUTO_TIMEOUT_PATCH
/* length of time (seconds) until */
static const int timeoffset = 60;

/* should [command] be run only once? */
static const int runonce = 0;

/* command to be run after [time] has passed */
static const char *command = "doas poweroff";
#endif // AUTO_TIMEOUT_PATCH

#if FAILURE_COMMAND_PATCH
/* number of failed password attempts until failcommand is executed.
   Set to 0 to disable */
static const int failcount = 0;

/* command to be executed after [failcount] failed password attempts */
static const char *failcommand = "shutdown";
#endif // FAILURE_COMMAND_PATCH

#if SECRET_PASSWORD_PATCH
static const secretpass scom[] = {
	/* Password             command */
	{ "shutdown",           "doas poweroff"},
};
#endif // SECRET_PASSWORD_PATCH

#if BLUR_PIXELATED_SCREEN_PATCH
/* Enable blur */
//#define BLUR
/* Set blur radius */
static const int blurRadius = 5;
/* Enable Pixelation */
#define PIXELATION
/* Set pixelation radius (size of one pixel block) */
static const int pixelSize = 12;
#endif // BLUR_PIXELATED_SCREEN_PATCH

#if CONTROLCLEAR_PATCH
/* allow control key to trigger fail on clear */
static const int controlkeyclear = 0;
#endif // CONTROLCLEAR_PATCH

#if DPMS_PATCH
/* time in seconds before the monitor shuts down */
static int monitortime = 5;

#if VISUAL_UNLOCK_PATCH
/* time in seconds before the monitor shuts down, if visual_unlock is enabled */
static const int monitortime_vu = 0;
#endif // VISUAL_UNLOCK_PATCH
#endif // DPMS_PATCH

#if KEYPRESS_FEEDBACK_PATCH
static short int blocks_enabled = 1; // 0 = don't show blocks
static const int blocks_width = 0; // 0 = square blocks (uses blocks_height)
static const int blocks_height = 18; // block size in pixels

// reserved (kept for compatibility)
static const int blocks_x = 0;
static const int blocks_y = 0;

// Number of blocks drawn per key press, per monitor
static const int blocks_count = 10;
#endif // KEYPRESS_FEEDBACK_PATCH

#if PAMAUTH_PATCH
/* PAM service that's used for authentication */
static const char* pam_service = "login";
#endif // PAMAUTH_PATCH

#if QUICKCANCEL_PATCH
/* time in seconds to cancel lock with mouse movement */
static const int timetocancel = 4;
#endif // QUICKCANCEL_PATCH
