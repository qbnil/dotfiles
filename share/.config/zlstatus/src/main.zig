const std = @import("std");
const c = @cImport({
    @cInclude("locale.h");
    @cInclude("unistd.h");
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
    @cInclude("time.h");
    @cInclude("alsa/asoundlib.h");
    @cInclude("sys/timerfd.h");
    @cInclude("sys/epoll.h");
    @cInclude("sys/socket.h");
    @cInclude("sys/un.h");
    @cInclude("sys/time.h");
    @cInclude("errno.h");
    @cInclude("fcntl.h");
    @cInclude("poll.h");
    @cInclude("netinet/in.h");
    @cInclude("arpa/inet.h");
    // Network status: raw rtnetlink socket (event-driven, no polling) +
    // getifaddrs() to resolve the active interface. NOTE: we deliberately
    // do NOT include linux/rtnetlink.h here — it drags in linux/if.h,
    // which redefines macros already provided by net/if.h below and fails
    // to compile. We only need sockaddr_nl/AF_NETLINK/NETLINK_ROUTE from
    // linux/netlink.h; the RTMGRP_* group numbers are hardcoded as Zig
    // constants instead (they're stable ABI, see rtnetlink(7)).
    @cInclude("linux/netlink.h");
    @cInclude("ifaddrs.h");
    @cInclude("net/if.h");
});

const config = @import("config");
const OutMode: type = config.@"build.OutMode";
const out_mode: OutMode = config.out_mode;

const Out: type = switch (out_mode) {
    .X11 => struct {
        const x = @cImport(@cInclude("X11/Xlib.h"));
        var display: ?*x.Display = null;

        fn init() void {
            display = x.XOpenDisplay(null);
            if (display == null) @panic("XOpenDisplay");
        }
        fn deinit() void {
            _ = x.XStoreName(display, x.DefaultRootWindow(display), null);
            _ = x.XCloseDisplay(display);
            display = null;
        }
        fn write() void {
            if (x.XStoreName(display, x.DefaultRootWindow(display), fStatus.ptr) < 0) @panic("XStoreName");
            _ = x.XFlush(display);
        }
    },
    .Wayland => struct {
        fn write() void {
            _ = c.write(1, fStatus.ptr, fStatus.len);
        }
    },
};

fn writeStatus() void {
    setStatus();
    Out.write();
}

const FMT_BATVOL = "B:%d V:%d%s";
const FMT_DATE = "%a %d %b %H:%M ";
// BUF_LEN grew to fit "<net><now playing><batt/vol><date>"
const BUF_LEN = 224;
var status_buf: [BUF_LEN]u8 = undefined;
var fStatus: [:0]u8 = undefined;

// Inserts a single-space separator before the next segment, but only if
// something has already been written (so the bar never starts with a
// leading space). Keeps spacing uniform between every segment, matching
// the single space already used between "B:%d" and "V:%d".
fn appendSep(n: *usize) void {
    if (n.* > 0) {
        status_buf[n.*] = ' ';
        n.* += 1;
    }
}

fn setStatus() void {
    var n: usize = 0;

    // Now playing (mpd), if any
    if (mpd_np_len > 0) {
        appendSep(&n);
        @memcpy(status_buf[n .. n + mpd_np_len], mpd_np[0..mpd_np_len]);
        n += mpd_np_len;
    }

    // Network status, if any (right of mpd)
    if (net_len > 0) {
        appendSep(&n);
        @memcpy(status_buf[n .. n + net_len], net_buf[0..net_len]);
        n += net_len;
    }

    appendSep(&n);
    const buf1: []u8 = status_buf[n..];
    const n1: usize = @intCast(c.snprintf(
        buf1.ptr,
        buf1.len,
        FMT_BATVOL,
        fBatCapacity,
        fVolume,
        if (fIsOn) @as([*:0]const u8, "") else "M",
    ));
    if (n1 >= buf1.len) @panic("snprintf");
    n += n1;

    appendSep(&n);
    const buf2: []u8 = status_buf[n..];
    const tm_ptr = c.localtime(&fTime.tv_sec);
    const n2: usize = c.strftime(buf2.ptr, buf2.len, FMT_DATE, tm_ptr);
    if (n2 >= buf2.len) @panic("strftime");
    n += n2;

    return switch (comptime out_mode) {
        .X11 => {
            fStatus = status_buf[0..n :0];
        },
        .Wayland => {
            status_buf[n] = '\n';
            status_buf[n + 1] = 0;
            fStatus = status_buf[0 .. n + 1 :0];
        },
    };
}

var bcfd: c_int = -1;
var fBatCapacity: u8 = 0;
fn readBatCapacity() void {
    // No battery (desktop / VM): leave fBatCapacity at 0 and skip I/O.
    if (bcfd < 0) return;
    var buf: [8]u8 = undefined;
    _ = c.lseek(bcfd, 0, c.SEEK_SET);
    const n: isize = c.read(bcfd, &buf, 8);
    if (n < 1) return; // transient read error — keep last known value
    const un: usize = @intCast(n);
    if (buf[un - 1] == '\n')
        buf[un - 1] = 0
    else
        buf[un] = 0;
    var endptr: [*c]u8 = undefined;
    const value: c_long = c.strtol(&buf, &endptr, 10);
    if (endptr == @as([*c]u8, @ptrCast(&buf))) return;
    fBatCapacity = @intCast(value);
}

var mixer: ?*c.snd_mixer_t = null;
var vol_min: f32 = 0;
var vol_max: f32 = 0;
var fVolume: u8 = 0;
var fIsOn: bool = true;
fn readMasterVolume(elem: ?*c.snd_mixer_elem_t, _: c_uint) callconv(.c) c_int {
    var is_on: c_int = 1;
    var vol_int: c_long = undefined;
    _ = c.snd_mixer_selem_get_playback_volume(elem, c.SND_MIXER_SCHN_FRONT_LEFT, &vol_int);
    const vol: f32 = @floatFromInt(vol_int);
    fVolume = @intFromFloat(@round(100 * (vol - vol_min) / (vol_max - vol_min)));
    _ = c.snd_mixer_selem_get_playback_switch(elem, c.SND_MIXER_SCHN_FRONT_LEFT, &is_on);
    fIsOn = is_on != 0;
    return 0;
}

var fTime: c.timespec = undefined;
fn readTime() void {
    if (c.clock_gettime(c.CLOCK_REALTIME, &fTime) != 0)
        @panic("clock_gettime");
}

var timerfd: c_int = -1;
var g_epollfd: c_int = -1;
const BAT = "/sys/class/power_supply/BAT0/";
const MAX_EVENTS = 8;
var last_monotonic: i64 = 0;

// ---------------------------------------------------------------------------
// Network status, via rtnetlink group socket (no polling, no subprocess)
//
// Deliberately cheap: everything here runs synchronously on the epoll thread,
// but only when something can actually have changed — a netlink event or the
// existing 60s clock tick. There is no background thread and no timerfd, so an
// idle zlstatus does no periodic work of its own.
//
// Each layer's health is inferred from CONFIGURATION (is there a default route,
// does resolv.conf list nameservers, is tailscaled Running) rather than by
// actively probing the network. That is a deliberate trade: an earlier version
// sent ICMP/TCP/DNS probes from a polling thread and reported `!dns` on a
// perfectly healthy network, because with a Tailscale exit node the RTT to
// 1.1.1.1 alone (~476ms measured here) overran the 800ms probe deadline. A
// config check cannot produce that false alarm, opens no sockets, and keeps the
// process down to a single thread.
//
// The one thing config genuinely cannot answer is "is there internet at all":
// every one of those signals stays green while the link is up and no packet
// leaves the machine (dead exit node, captive portal, upstream outage). That
// case is covered by probeStart/probeFinish below, which is non-blocking and so
// carries none of the stall that got the earlier probe version removed.
// ---------------------------------------------------------------------------
var netfd: c_int = -1;
var net_buf: [48]u8 = undefined;
var net_len: usize = 0;

// Last interface that held a default route. Used to avoid showing a VPN/tunnel
// interface with !route during resume, when the physical interface's default
// route hasn't been restored yet — a race where activeIfaceInto picks the
// first UP interface (tailscale0) instead of the one that will own the route
// once the system finishes resuming (wlan0).
var last_routed_iface: [16]u8 = undefined;
var last_routed_iface_len: usize = 0;
var cached_route: RouteInfo = .{};
var cached_dns: DnsInfo = .{};
var cached_dns_valid: bool = false;

// rtnetlink(7) multicast group bitmask values (stable ABI). Hardcoded to
// avoid pulling in linux/rtnetlink.h, see comment on the cImport above.
const RTMGRP_LINK: u32 = 0x1;
const RTMGRP_IPV4_IFADDR: u32 = 0x10;
const RTMGRP_IPV4_ROUTE: u32 = 0x40;

fn netSetDown() void {
    const down = "down";
    @memcpy(net_buf[0..down.len], down);
    net_len = down.len;
}

/// Append `s` to net_buf at `len`, silently truncating if it would not fit.
fn netAppend(len: *usize, s: []const u8) void {
    if (len.* + s.len > net_buf.len) return;
    @memcpy(net_buf[len.*..][0..s.len], s);
    len.* += s.len;
}

/// What one pass over /proc/net/route tells us: whether we are routed at all,
/// and which interface owns the default route. Reading this once answers three
/// questions that used to need three separate scans.
const RouteInfo = struct {
    has_default: bool = false,
    iface: [16]u8 = undefined,
    iface_len: usize = 0,
};

/// The default route, lowest metric winning.
///
/// Parsed as text rather than via netlink, matching the file's existing style
/// and avoiding a second socket. When several default routes exist (a wired and
/// a wireless NIC, or a Tailscale exit node) the lowest metric is the one the
/// kernel actually prefers, so that is the interface the bar should name.
fn readRouteInfo() RouteInfo {
    var info: RouteInfo = .{};
    var best_metric: u32 = std.math.maxInt(u32);

    const f = c.fopen("/proc/net/route", "rb") orelse return info;
    defer _ = c.fclose(f);

    var line: [512]u8 = undefined;
    while (c.fgets(&line, line.len, f)) |_| {
        const s = std.mem.sliceTo(line[0..], 0);
        if (s.len == 0 or s[0] == 'I') continue;
        var it = std.mem.tokenizeAny(u8, s, " \t\r\n");
        const iface = it.next() orelse continue;
        const dest = it.next() orelse continue;
        if (!std.mem.eql(u8, dest, "00000000")) continue;
        if (iface.len == 0 or iface.len > info.iface.len) continue;
        _ = it.next() orelse continue;
        _ = it.next() orelse continue;
        _ = it.next() orelse continue;
        _ = it.next() orelse continue;
        const metric = std.fmt.parseInt(u32, it.next() orelse continue, 10) catch best_metric;
        if (info.has_default and metric >= best_metric) continue;

        @memcpy(info.iface[0..iface.len], iface);
        info.iface_len = iface.len;
        best_metric = metric;
        info.has_default = true;
    }
    return info;
}

/// Name of the first usable non-loopback interface, as a slice into `buf`.
///
/// Only used as a fallback when there is no default route, so the bar can still
/// say `wlan0!route` rather than a bare `down`.
fn activeIfaceInto(buf: []u8) ?[]const u8 {
    var ifaddr: ?*c.ifaddrs = null;
    if (c.getifaddrs(&ifaddr) != 0) return null;
    defer _ = c.freeifaddrs(ifaddr);
    var cur: ?*c.ifaddrs = ifaddr;
    while (cur) |ifa| : (cur = ifa.*.ifa_next) {
        const flags = ifa.*.ifa_flags;
        if (flags & c.IFF_LOOPBACK != 0) continue;
        if (flags & c.IFF_UP == 0 or flags & c.IFF_RUNNING == 0) continue;
        const sa: ?*c.sockaddr = ifa.*.ifa_addr;
        if (sa == null) continue;
        if (sa.?.*.sa_family != c.AF_INET) continue;
        const n = c.snprintf(buf.ptr, buf.len, "%s", ifa.*.ifa_name);
        if (n <= 0 or n >= buf.len) return null;
        return buf[0..@intCast(n)];
    }
    return null;
}

const DnsInfo = struct {
    count: usize = 0,
    // True while every nameserver seen so far sits in Tailscale's 100.64.0.0/10.
    all_cgnat: bool = true,
};

/// Count the usable IPv4 nameservers in /etc/resolv.conf.
///
/// Config, not a query: we care whether nameservers are CONFIGURED, and this can
/// never block the bar the way a real lookup would. IPv6 literals are skipped —
/// this is an IPv4-only bar.
fn readDnsInfo() DnsInfo {
    var info: DnsInfo = .{};

    const f = c.fopen("/etc/resolv.conf", "rb") orelse return info;
    defer _ = c.fclose(f);

    var line: [512]u8 = undefined;
    while (c.fgets(&line, line.len, f)) |_| {
        // `line` is uninitialised, so it holds garbage past the NUL that fgets
        // wrote. Bound the line by its terminator, then copy the address out
        // before parsing it: the trimmed token is still a view into that
        // uninitialised buffer, and handing it straight to inet_pton makes the
        // parse fail. (Measured — the identical string from a literal parses
        // fine, the same bytes read out of `line` do not.)
        const s = std.mem.trim(u8, std.mem.sliceTo(line[0..], 0), " \t\r\n");
        if (!std.mem.startsWith(u8, s, "nameserver")) continue;
        const addr = std.mem.trim(u8, s["nameserver".len..], " \t");
        if (addr.len == 0 or addr.len >= 64) continue;

        var host: [64]u8 = undefined;
        @memcpy(host[0..addr.len], addr[0..addr.len]);
        host[addr.len] = 0;

        var v4: [4]u8 = undefined;
        if (c.inet_pton(c.AF_INET, host[0..addr.len :0], &v4) != 1) continue;
        info.count += 1;
        // 100.64.0.0/10 covers 100.64.x.x - 100.127.x.x: first octet 100, and
        // second octet 64-127, whose top two bits are 01.
        if (!(v4[0] == 100 and (v4[1] & 0xc0) == 0x40)) info.all_cgnat = false;
    }
    return info;
}

// --- Tailscale -------------------------------------------------------------
// Read from tailscaled's LocalAPI socket rather than by exec'ing `tailscale`:
// the socket is world-writable (srw-rw-rw-), so this needs no root and no
// subprocess, which keeps zlstatus fork-free like the rest of it.
const TS_SOCK = "/run/tailscale/tailscaled.sock";
const TS_REQ = "GET /localapi/v0/status HTTP/1.1\r\nHost: local-tailscaled.sock\r\n\r\n";
const TS_KEY = "\"BackendState\"";

/// Is tailscaled up and logged in?
///
/// BackendState is a short enum ("Running", "Stopped", "NeedsLogin", "NoState").
/// Anything other than Running means traffic is not going through Tailscale,
/// which is what the bar reports.
fn tailscaleRunning() bool {
    const fd = c.socket(c.AF_UNIX, c.SOCK_STREAM, 0);
    if (fd < 0) return false; // no tailscaled at all
    defer _ = c.close(fd);

    var addr: c.sockaddr_un = std.mem.zeroes(c.sockaddr_un);
    addr.sun_family = c.AF_UNIX;
    if (TS_SOCK.len >= addr.sun_path.len) return false;
    @memcpy(addr.sun_path[0..TS_SOCK.len], TS_SOCK);
    addr.sun_path[TS_SOCK.len] = 0;

    // Bounded connect: tailscaled can be mid-restart and leave the socket
    // present but unaccepting, and the bar must never stall on that.
    if (!connectWithTimeout(fd, @ptrCast(&addr), @sizeOf(c.sockaddr_un))) return false;
    setSocketTimeout(fd, 100);

    if (c.write(fd, TS_REQ, TS_REQ.len) < 0) return false;

    // BackendState is the third key of the JSON body, which follows ~194 bytes
    // of HTTP headers, so the key lands around byte 254. One read() is
    // comfortably enough: asking for a full 512-byte buffer would be a trap,
    // since the body itself is ~5.5KB and the read would block waiting for a
    // header's worth of JSON that never arrives. Read once, then check.
    var buf: [512]u8 = undefined;
    const n = c.read(fd, &buf, buf.len);
    if (n <= 0) return false;
    const body = buf[0..@intCast(n)];

    const at = std.mem.indexOf(u8, body, TS_KEY) orelse return false;
    var i = at + TS_KEY.len;
    while (i < body.len and body[i] != ':') i += 1;
    i += 1; // step past the colon itself
    while (i < body.len and (body[i] == ' ' or body[i] == '\t')) i += 1;
    if (i >= body.len or body[i] != '"') return false;
    i += 1;
    return std.mem.startsWith(u8, body[i..], "Running\"");
}

/// Rebuild the net segment: the interface name, then any fault tags.
///
/// Healthy output is just `wlan0 ts`. Faults are appended in a fixed order so the
/// string stays stable between refreshes — a bar whose text jitters is worse than
/// one that is merely terse.
fn netRefresh() void {
    const route = readRouteInfo();
    cached_route = route;
    cached_dns_valid = false;
    netRender(route);

    probeStart(route.has_default);
}

/// Rebuild net_buf from current state. Split out from netRefresh because a probe
/// verdict must repaint the bar WITHOUT re-arming: re-arming here would make
/// every verdict kick off another probe, and a probe that resolves instantly
/// (refused, or unroutable) would spin at whatever rate it completes.
fn netRender(route: RouteInfo) void {
    // Prefer the interface that owns the default route. When there's no default
    // route, prefer the last interface that HAD one (handles resume race where
    // the route temporarily disappears) over activeIfaceInto, which picks the
    // first UP interface and can return a VPN/tunnel (tailscale0) instead of the
    // physical interface (wlan0) that will own the route once resume finishes.
    var ifbuf: [16]u8 = undefined;
    const name: []const u8 = if (route.has_default) blk: {
        // Remember this interface for the next time route.has_default is false
        @memcpy(last_routed_iface[0..route.iface_len], route.iface[0..route.iface_len]);
        last_routed_iface_len = route.iface_len;
        break :blk route.iface[0..route.iface_len];
    } else if (last_routed_iface_len > 0) blk: {
        // No default route right now, but we remember which interface had it last
        @memcpy(ifbuf[0..last_routed_iface_len], last_routed_iface[0..last_routed_iface_len]);
        break :blk ifbuf[0..last_routed_iface_len];
    } else blk: {
        // No default route and no memory of one: fall back to first UP interface
        break :blk activeIfaceInto(&ifbuf) orelse {
            netSetDown();
            return;
        };
    };

    var len: usize = 0;
    netAppend(&len, name);

    if (!route.has_default) netAppend(&len, "!route");

    const ts_ok = tailscaleRunning();
    if (!cached_dns_valid) {
        cached_dns = readDnsInfo();
        cached_dns_valid = true;
    }
    if (cached_dns.count == 0 or (cached_dns.all_cgnat and !ts_ok)) netAppend(&len, "!dns");

    netAppend(&len, if (ts_ok) " ts" else "!ts");

    if (net_ok) |ok| {
        if (!ok) netAppend(&len, " !net");
    }

    net_len = len;
}

fn netInit() void {
    netfd = c.socket(c.AF_NETLINK, c.SOCK_RAW | c.SOCK_NONBLOCK, c.NETLINK_ROUTE);

    netRefresh();

    if (netfd < 0) {
        _ = c.fprintf(c.stderr, "net: socket() failed, link-only status\n");
        return;
    }
    var addr: c.sockaddr_nl = std.mem.zeroes(c.sockaddr_nl);
    addr.nl_family = c.AF_NETLINK;
    // RTMGRP_IPV4_ROUTE is what makes `!route` appear the moment a default route
    // comes or goes, rather than up to a minute later.
    addr.nl_groups = RTMGRP_LINK | RTMGRP_IPV4_IFADDR | RTMGRP_IPV4_ROUTE;
    if (c.bind(netfd, @ptrCast(&addr), @sizeOf(c.sockaddr_nl)) < 0) {
        _ = c.fprintf(c.stderr, "net: bind() failed, link-only status\n");
        _ = c.close(netfd);
        netfd = -1;
        return;
    }
    var event = c.epoll_event{
        .events = @as(u32, c.EPOLLIN) | c.EPOLLET,
        .data = .{ .u64 = @intFromEnum(Event.NetChange) },
    };
    // Non-fatal: if this fails we still refresh once a minute from the clock.
    _ = c.epoll_ctl(g_epollfd, c.EPOLL_CTL_ADD, netfd, &event);
}

fn netHandleEvent() void {
    if (netfd >= 0) {
        // Edge-triggered: drain the socket fully before re-scanning.
        var buf: [4096]u8 = undefined;
        while (c.recv(netfd, &buf, buf.len, 0) > 0) {}
    }
    netRefresh();
}

// --- Internet reachability probe -------------------------------------------
// The one thing the config checks above cannot answer: with the link up, the
// route installed, nameservers listed and tailscaled Running, every signal is
// green while nothing actually leaves the machine — a dead exit node, a
// captive portal, an upstream outage. That is exactly the state this reports.
//
// A TCP connect to a public IP:443. Never a DNS lookup (that would fold the
// nameserver check into this and double-count one failure) and never ICMP
// (commonly rate-limited or dropped outright, so it false-alarms).
//
// The connect is issued non-blocking and the verdict is collected later from
// SO_ERROR when the fd reports writable, so a black-holed destination costs the
// bar nothing: no sleep, no stall, no thread. This is the difference from the
// probe version the header comment describes — that one blocked, and a ~476ms
// RTT through a Tailscale exit node overran its deadline on a perfectly healthy
// network. Here the only deadline is the kernel's own, and exceeding it just
// means the next refresh re-probes.
//
// Two independent signals, deliberately not collapsed into one: reachability
// and name resolution. `!net` alone means the WAN is gone; `!net` plus `!dns`
// means the nameserver check failed too, the more actionable pair when
// Tailscale is involved.
const PROBE_ADDR = "1.1.1.1";
const PROBE_PORT: u16 = 443;
// A real connect through a Tailscale exit node measured ~476ms here, so this is
// generous on purpose: it only exists to stop a silently-dropped SYN from
// pinning the probe in flight until the kernel's own ~127s connect timeout,
// which would freeze the verdict at whatever the last refresh saw. Checked from
// the once-a-minute tick, so the real resolution is one tick.
const PROBE_STUCK_SEC: i64 = 8;

var probe_fd: c_int = -1;
// null until a probe has produced a verdict. Null is NOT "unreachable": at
// startup the bar shows the clean `wlan0 ts` until the first result lands, rather
// than alarming about a link it has not measured yet.
var net_ok: ?bool = null;
var probe_started: i64 = 0;

fn probeElapsedSec() i64 {
    var ts: c.timespec = undefined;
    if (c.clock_gettime(c.CLOCK_MONOTONIC, &ts) != 0) return 0;
    const elapsed = ts.tv_sec;

    // Detect suspend/resume: if monotonic clock jumped backward or by more than
    // a minute, the system was suspended. Force a network refresh to catch any
    // configuration changes that happened during sleep.
    if (last_monotonic > 0) {
        const delta = elapsed - last_monotonic;
        if (delta < 0 or delta > 120) {
            _ = c.fprintf(c.stderr, "net: detected suspend/resume, refreshing\n");
            netRefresh();
        }
    }
    last_monotonic = elapsed;

    return elapsed;
}

/// Begin a probe, if one is not already in flight. `have_route` is the caller's
/// freshly-read default-route state: with no route the destination is
/// unroutable, so connecting would only hang until the kernel gives up, and
/// `!route` already says what is wrong.
fn probeStart(have_route: bool) void {
    if (probe_fd >= 0) return;
    if (!have_route) return;

    const fd = c.socket(c.AF_INET, c.SOCK_STREAM, 0);
    if (fd < 0) return;

    var addr: c.sockaddr_in = std.mem.zeroes(c.sockaddr_in);
    addr.sin_family = c.AF_INET;
    addr.sin_port = c.htons(PROBE_PORT);
    if (c.inet_pton(c.AF_INET, PROBE_ADDR, &addr.sin_addr) != 1) {
        _ = c.close(fd);
        return;
    }

    const flags = c.fcntl(fd, c.F_GETFL, @as(c_int, 0));
    _ = c.fcntl(fd, c.F_SETFL, flags | c.O_NONBLOCK);

    var event = c.epoll_event{
        .events = @as(u32, c.EPOLLOUT) | c.EPOLLERR,
        .data = .{ .u64 = @intFromEnum(Event.ProbeDone) },
    };
    if (c.epoll_ctl(g_epollfd, c.EPOLL_CTL_ADD, fd, &event) < 0) {
        _ = c.close(fd);
        return;
    }

    probe_fd = fd;
    probe_started = probeElapsedSec();

    if (c.connect(fd, @ptrCast(&addr), @sizeOf(c.sockaddr_in)) == 0) {
        probeFinish(false);
    }
}

/// Collect the verdict for an in-flight probe. `stuck` forces a failure verdict
/// for a connect that has outrun PROBE_STUCK_SEC — SO_ERROR is still EINPROGRESS
/// there, so it would otherwise read as success.
fn probeFinish(stuck: bool) void {
    const fd = probe_fd;
    if (fd < 0) return;
    probe_fd = -1;
    defer {
        _ = c.epoll_ctl(g_epollfd, c.EPOLL_CTL_DEL, fd, null);
        _ = c.close(fd);
    }

    if (stuck) {
        net_ok = false;
    } else {
        var err: c_int = 0;
        var errlen: c.socklen_t = @sizeOf(c_int);
        if (c.getsockopt(fd, c.SOL_SOCKET, c.SO_ERROR, &err, &errlen) < 0) return;
        net_ok = (err == 0);
    }
    netRender(cached_route);
}

/// Is a probe still outstanding, and has it outrun its deadline? Called from the
/// once-a-minute tick, which is the only place with a clock to judge it by.
fn probeTick() void {
    if (probe_fd < 0) return;
    if (probeElapsedSec() - probe_started < PROBE_STUCK_SEC) return;
    probeFinish(true);
}

// ---------------------------------------------------------------------------
// MPD now-playing, via direct socket + idle protocol (no mpc/fork+exec)
// ---------------------------------------------------------------------------
var mpdfd: c_int = -1;
var mpd_np: [64]u8 = undefined;
var mpd_np_len: usize = 0;

fn mpdHost() []const u8 {
    if (c.getenv("MPD_HOST")) |h| {
        const s = std.mem.span(h);
        if (s.len > 0 and s[0] != '/') return s;
    }
    return "127.0.0.1";
}

fn mpdPort() u16 {
    if (c.getenv("MPD_PORT")) |p| {
        const s = std.mem.span(p);
        return std.fmt.parseInt(u16, s, 10) catch 6600;
    }
    return 6600;
}

fn mpdUnixPath(buf: []u8) ?[]const u8 {
    if (c.getenv("MPD_HOST")) |h| {
        const s = std.mem.span(h);
        if (s.len > 0 and s[0] == '/') return s;
    }
    if (c.getenv("XDG_RUNTIME_DIR")) |d| {
        const s = std.mem.span(d);
        if (std.fmt.bufPrint(buf, "{s}/mpd/socket", .{s})) |p| return p else |_| {}
    }
    return null;
}

fn mpdDisconnect() void {
    if (mpdfd >= 0) _ = c.close(mpdfd);
    mpdfd = -1;
    mpd_np_len = 0;
}

fn mpdRegisterEpoll() void {
    if (mpdfd < 0) return;
    var event = c.epoll_event{
        .events = @as(u32, c.EPOLLIN) | c.EPOLLET,
        .data = .{ .u64 = @intFromEnum(Event.MpdEvent) },
    };
    // Non-fatal: if this fails we just won't get async updates until next retry.
    _ = c.epoll_ctl(g_epollfd, c.EPOLL_CTL_ADD, mpdfd, &event);
}

fn mpdRefreshSong() void {
    if (mpdfd < 0) return;
    const cmd = "currentsong\n";
    if (c.write(mpdfd, cmd.ptr, cmd.len) < 0) {
        mpdDisconnect();
        return;
    }
    var buf: [1024]u8 = undefined;
    const n = c.read(mpdfd, &buf, buf.len);
    if (n <= 0) {
        mpdDisconnect();
        return;
    }
    const resp = buf[0..@intCast(n)];

    var artist: []const u8 = "";
    var title: []const u8 = "";
    var lines = std.mem.splitScalar(u8, resp, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "Artist: ")) artist = line[8..];
        if (std.mem.startsWith(u8, line, "Title: ")) title = line[7..];
    }

    var tmp: [256]u8 = undefined;
    const combined: []const u8 = blk: {
        if (title.len > 0 and artist.len > 0)
            break :blk std.fmt.bufPrint(&tmp, "{s} - {s}", .{ artist, title }) catch tmp[0..0]
        else if (title.len > 0)
            break :blk std.fmt.bufPrint(&tmp, "{s}", .{title}) catch tmp[0..0]
        else
            break :blk tmp[0..0];
    };

    const copy_len = @min(combined.len, mpd_np.len);
    @memcpy(mpd_np[0..copy_len], combined[0..copy_len]);
    mpd_np_len = copy_len;
}

fn mpdSendIdle() void {
    if (mpdfd < 0) return;
    const cmd = "idle player\n";
    if (c.write(mpdfd, cmd.ptr, cmd.len) < 0) mpdDisconnect();
}

// SO_RCVTIMEO/SO_SNDTIMEO (set after connecting, see setSocketTimeout) do
// NOT bound connect() itself on Linux. If MPD isn't reachable yet (daemon
// still starting at boot, wrong host, firewall dropping the SYN, ...) a
// plain blocking connect() can stall for the OS's default timeout, which
// is many seconds — freezing the whole bar (and, since this also runs from
// the once-a-minute retry timer, freezing it again every minute). This
// makes the socket non-blocking for the connect attempt only, and bounds
// it with poll() instead.
const MPD_CONNECT_TIMEOUT_MS: c_int = 200;

fn connectWithTimeout(fd: c_int, addr: [*c]const c.sockaddr, addrlen: c.socklen_t) bool {
    const flags = c.fcntl(fd, c.F_GETFL, @as(c_int, 0));
    _ = c.fcntl(fd, c.F_SETFL, flags | c.O_NONBLOCK);

    if (c.connect(fd, addr, addrlen) == 0) {
        _ = c.fcntl(fd, c.F_SETFL, flags); // back to blocking for reads/writes
        return true;
    }
    if (c.__errno_location().* != c.EINPROGRESS) return false;

    var pfd = c.pollfd{ .fd = fd, .events = c.POLLOUT, .revents = 0 };
    if (c.poll(&pfd, 1, MPD_CONNECT_TIMEOUT_MS) <= 0) return false; // timeout or error

    var err: c_int = 0;
    var errlen: c.socklen_t = @sizeOf(c_int);
    if (c.getsockopt(fd, c.SOL_SOCKET, c.SO_ERROR, &err, &errlen) < 0 or err != 0) return false;

    _ = c.fcntl(fd, c.F_SETFL, flags); // back to blocking for reads/writes
    return true;
}

fn setSocketTimeout(fd: c_int, ms: i64) void {
    const tv = c.timeval{
        .tv_sec = @intCast(@divTrunc(ms, 1000)),
        .tv_usec = @intCast(@mod(ms, 1000) * 1000),
    };
    _ = c.setsockopt(fd, c.SOL_SOCKET, c.SO_RCVTIMEO, &tv, @sizeOf(c.timeval));
    _ = c.setsockopt(fd, c.SOL_SOCKET, c.SO_SNDTIMEO, &tv, @sizeOf(c.timeval));
}

// Shared post-connect steps: read greeting, fetch current song, register
// with epoll, and start the idle wait. Takes ownership of fd on failure too
// (closes it), so callers just return afterwards either way.
fn mpdFinishConnect(fd: c_int) void {
    setSocketTimeout(fd, 500);
    mpdfd = fd;

    var greet: [128]u8 = undefined;
    const gn = c.read(mpdfd, &greet, greet.len - 1); // discard "OK MPD x.y.z\n"
    if (gn <= 0) {
        _ = c.fprintf(c.stderr, "mpd: no greeting received, giving up\n");
        mpdDisconnect();
        return;
    }
    greet[@intCast(gn)] = 0;
    _ = c.fprintf(c.stderr, "mpd: connected (%s)\n", &greet);

    mpdRefreshSong();
    mpdRegisterEpoll();
    mpdSendIdle();
}

fn mpdConnectUnix(path: []const u8) void {
    var addr: c.sockaddr_un = std.mem.zeroes(c.sockaddr_un);
    addr.sun_family = c.AF_UNIX;
    if (path.len >= addr.sun_path.len) {
        _ = c.fprintf(c.stderr, "mpd: socket path too long\n");
        return;
    }
    @memcpy(addr.sun_path[0..path.len], path);
    addr.sun_path[path.len] = 0;

    const fd = c.socket(c.AF_UNIX, c.SOCK_STREAM, 0);
    if (fd < 0) {
        _ = c.fprintf(c.stderr, "mpd: socket() failed\n");
        return;
    }
    if (!connectWithTimeout(fd, @ptrCast(&addr), @sizeOf(c.sockaddr_un))) {
        _ = c.fprintf(c.stderr, "mpd: unix connect() failed/timed out (errno %d)\n", c.__errno_location().*);
        _ = c.close(fd);
        return;
    }
    mpdFinishConnect(fd);
}

fn mpdConnectTcp(host: []const u8, port: u16) void {
    var hostbuf: [64]u8 = undefined;
    if (host.len >= hostbuf.len) {
        _ = c.fprintf(c.stderr, "mpd: host too long\n");
        return;
    }
    @memcpy(hostbuf[0..host.len], host);
    hostbuf[host.len] = 0;

    var addr: c.sockaddr_in = std.mem.zeroes(c.sockaddr_in);
    addr.sin_family = c.AF_INET;
    addr.sin_port = c.htons(port);
    if (c.inet_pton(c.AF_INET, &hostbuf, &addr.sin_addr) != 1) {
        _ = c.fprintf(c.stderr, "mpd: inet_pton failed for %s (only dotted IPs supported, not hostnames)\n", &hostbuf);
        return;
    }

    const fd = c.socket(c.AF_INET, c.SOCK_STREAM, 0);
    if (fd < 0) {
        _ = c.fprintf(c.stderr, "mpd: socket() failed\n");
        return;
    }
    if (!connectWithTimeout(fd, @ptrCast(&addr), @sizeOf(c.sockaddr_in))) {
        _ = c.fprintf(c.stderr, "mpd: tcp connect() failed/timed out (errno %d)\n", c.__errno_location().*);
        _ = c.close(fd);
        return;
    }
    mpdFinishConnect(fd);
}

fn mpdConnect() void {
    var pathbuf: [128]u8 = undefined;
    if (mpdUnixPath(&pathbuf)) |path| {
        _ = c.fprintf(c.stderr, "mpd: trying unix socket %.*s\n", @as(c_int, @intCast(path.len)), path.ptr);
        mpdConnectUnix(path);
        if (mpdfd >= 0) return;
    }
    const host = mpdHost();
    const port = mpdPort();
    _ = c.fprintf(c.stderr, "mpd: trying tcp %.*s:%d\n", @as(c_int, @intCast(host.len)), host.ptr, @as(c_int, port));
    mpdConnectTcp(host, port);
}

fn mpdHandleEvent() void {
    if (mpdfd < 0) {
        mpdConnect();
        return;
    }
    var buf: [256]u8 = undefined;
    const n = c.read(mpdfd, &buf, buf.len);
    if (n <= 0) {
        // server closed the connection (or error)
        mpdDisconnect();
        return;
    }
    mpdRefreshSong();
    mpdSendIdle();
}

pub fn main() u8 {
    if (comptime @hasDecl(Out, "init")) Out.init();
    defer if (comptime @hasDecl(Out, "deinit")) Out.deinit();

    const epollfd: c_int = c.epoll_create1(0);
    if (epollfd < 0) @panic("epoll_create1");
    defer _ = c.close(epollfd);
    g_epollfd = epollfd;

    // Date and time
    if (c.setlocale(c.LC_TIME, "") == null)
        @panic("setlocale");

    timerfd = c.timerfd_create(c.CLOCK_MONOTONIC, 0);
    if (timerfd < 0) @panic("timerfd_create");
    defer _ = c.close(timerfd);

    readTime();

    const itval = c.itimerspec{ .it_value = .{
        .tv_sec = 60 - @rem(fTime.tv_sec, 60) - 1,
        .tv_nsec = @as(c_long, 1e9) - fTime.tv_nsec,
    }, .it_interval = .{
        .tv_sec = 60,
        .tv_nsec = 0,
    } };
    if (c.timerfd_settime(timerfd, 0, &itval, null) < 0)
        @panic("timerfd_settime");

    var event = c.epoll_event{
        .events = @as(u32, c.EPOLLIN) | c.EPOLLET,
        .data = .{ .u64 = @intFromEnum(Event.TimeOut1m) },
    };
    if (c.epoll_ctl(epollfd, c.EPOLL_CTL_ADD, timerfd, &event) < 0)
        @panic("epoll_ctl");

    // Battery capacity — optional (desktops / VMs often have no BAT*).
    // Try BAT0 then BAT1; if neither exists, status shows B:0 and we skip updates.
    bcfd = c.open(BAT ++ "capacity", c.O_RDONLY);
    if (bcfd < 0) bcfd = c.open("/sys/class/power_supply/BAT1/capacity", c.O_RDONLY);
    if (bcfd >= 0) {
        // closed at process exit; no defer so the fd stays valid for the event loop
        readBatCapacity();
    } else {
        fBatCapacity = 0;
    }

    // ALSA
    if (c.snd_mixer_open(&mixer, 0) < 0 or
        c.snd_mixer_attach(mixer, "default") < 0 or
        c.snd_mixer_selem_register(mixer, null, null) < 0 or
        c.snd_mixer_load(mixer) < 0)
        @panic("Failed to setup ALSA mixer");
    defer _ = c.snd_mixer_close(mixer);

    var elem: ?*c.snd_mixer_elem_t = c.snd_mixer_first_elem(mixer);
    while (elem) |_| : (elem = c.snd_mixer_elem_next(elem)) {
        if (c.strcmp("Master", c.snd_mixer_selem_get_name(elem)) == 0) {
            var min: c_long = undefined;
            var max: c_long = undefined;
            _ = c.snd_mixer_selem_get_playback_volume_range(elem, &min, &max);
            vol_min = @floatFromInt(min);
            vol_max = @floatFromInt(max);
            c.snd_mixer_elem_set_callback(elem, readMasterVolume);
            _ = readMasterVolume(elem, 0);
            break;
        }
    } else @panic("Master channel not found");

    var alsafd: c.pollfd = undefined;
    if (c.snd_mixer_poll_descriptors(mixer, &alsafd, 1) != 1)
        @panic("snd_mixer_poll_descriptors");
    event = c.epoll_event{
        .events = @as(u32, c.EPOLLIN) | c.EPOLLET,
        .data = .{ .u64 = @intFromEnum(Event.VolChange) },
    };
    if (c.epoll_ctl(epollfd, c.EPOLL_CTL_ADD, alsafd.fd, &event) < 0)
        @panic("epoll_ctl");

    // Network status (rtnetlink group socket, event-driven) - non-fatal
    netInit();

    // Everything fast (time, battery, volume, network) is known by now —
    // paint it. This is the FIRST paint, so the bar never appears with
    // placeholder B:0 V:0 values. MPD is the only remaining piece, it's
    // bounded to ~200ms if unreachable (see connectWithTimeout), so
    // delaying the first paint until after it would just add a visible
    // blank/partial bar on boot for no benefit.
    writeStatus();

    // MPD (now playing) - non-fatal if mpd isn't running
    mpdConnect();
    defer mpdDisconnect();

    // Repaint once more only if MPD actually produced a now-playing entry,
    // otherwise the bar is already correct and we'd be writing to the X root
    // window (and waking the compositor) for nothing.
    if (mpd_np_len > 0) writeStatus();

    // Main epoll loop
    var events: [MAX_EVENTS]c.epoll_event = undefined;
    while (true) {
        for (0..@intCast(c.epoll_wait(epollfd, &events, MAX_EVENTS, -1))) |i| {
            const ev: c.epoll_event = events[i];
            @as(Event, @enumFromInt(ev.data.u64)).handleEvent();
        }
        writeStatus();
    }

    return 0;
}

const Event = enum(u8) {
    TimeOut1m,
    VolChange,
    MpdEvent,
    NetChange,
    ProbeDone,

    fn handleTimeout1m() void {
        readTime();
        // Consume amount of expirations from fd
        var exp_count: u64 = undefined;
        _ = c.read(timerfd, &exp_count, @sizeOf(u64));
        readBatCapacity();
        // Re-read the network too. Tailscale can come and go (and with it
        // rewrite resolv.conf) without any link or route change, so the
        // netlink socket alone would not wake us for that; once a minute is
        // cheap enough and keeps the bar self-correcting.
        netRefresh();
        // Retire a probe that has outrun its deadline, and re-arm the next one.
        // Together with netRefresh's own re-arm this is the only thing that
        // keeps the verdict fresh while the network is down and silent.
        probeTick();
        // Retry MPD connection if it dropped (e.g. mpd wasn't running at startup)
        if (mpdfd < 0) mpdConnect();
    }

    fn handleVolChange() void {
        _ = c.snd_mixer_handle_events(mixer);
    }

    fn handleMpdEvent() void {
        mpdHandleEvent();
    }

    fn handleNetChange() void {
        netHandleEvent();
    }

    fn handleProbeDone() void {
        probeFinish(false);
    }

    fn handleEvent(self: Event) void {
        switch (self) {
            .TimeOut1m => handleTimeout1m(),
            .VolChange => handleVolChange(),
            .MpdEvent => handleMpdEvent(),
            .NetChange => handleNetChange(),
            .ProbeDone => handleProbeDone(),
        }
    }
};
