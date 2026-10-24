// C headers used by zlstatus, translated by the build system (Zig 0.17 removed
// @cImport). build.zig turns this into the `c` module; main.zig imports it.
//
// Network status: raw rtnetlink socket (event-driven, no polling) +
// getifaddrs() to resolve the active interface. NOTE: we deliberately do NOT
// include linux/rtnetlink.h here — it drags in linux/if.h, which redefines
// macros already provided by net/if.h and fails to compile. We only need
// sockaddr_nl/AF_NETLINK/NETLINK_ROUTE from linux/netlink.h; the RTMGRP_*
// group numbers are hardcoded as Zig constants instead (they're stable ABI,
// see rtnetlink(7)).
#include <locale.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <alsa/asoundlib.h>
#include <sys/timerfd.h>
#include <sys/epoll.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/time.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/file.h>
#include <signal.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <sys/inotify.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <linux/netlink.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <X11/Xlib.h>
