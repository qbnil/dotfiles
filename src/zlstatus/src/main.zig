const std = @import("std");
// C declarations are translated from src/c.h by build.zig (Zig 0.17 removed
// the @cImport builtin).
const c = @import("c");

const config = @import("config");
const OutMode: type = config.@"build.OutMode";
const out_mode: OutMode = config.out_mode;

const Out: type = switch (out_mode) {
    .X11 => struct {
        var display: ?*c.Display = null;

        fn init() void {
            display = c.XOpenDisplay(null);
            if (display == null) @panic("XOpenDisplay");
        }
        fn deinit() void {
            _ = c.XStoreName(display, c.DefaultRootWindow(display), null);
            _ = c.XCloseDisplay(display);
            display = null;
        }
        fn write() void {
            if (c.XStoreName(display, c.DefaultRootWindow(display), fStatus.ptr) < 0) @panic("XStoreName");
            _ = c.XFlush(display);
        }
    },
    .Wayland => struct {
        fn init() void {}
        fn deinit() void {}
        fn write() void {
            _ = c.write(1, fStatus.ptr, fStatus.len);
        }
    },
};

fn writeStatus() void {
    setStatus();
    Out.write();
}

// Charger marker sits right after the capacity: `B:99+` actively charging,
// `B:99F` attached but holding (charge limit / full), `B:99` discharging. It
// mirrors the existing ASCII style (`+ts`, `M` for muted) and needs no font.
const FMT_BATVOL = "B:%d%s V:%d%s";
// Desktop / VM fallback: with no battery present, only the volume segment.
const FMT_VOL = "V:%d%s";
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
    // Keep the clock independent from which event caused the repaint. This is
    // important after NTP corrections, resume, and network-only updates: the
    // previous implementation only refreshed fTime on the minute timer tick.
    readTime();
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

    // Battery + volume. The battery portion is omitted entirely when no
    // battery was found at startup (desktop / VM), leaving just the volume.
    appendSep(&n);
    const buf1: []u8 = status_buf[n..];
    const vol_mark: [*:0]const u8 = if (fIsOn) "" else "M";
    const n1: usize = @intCast(if (bcfd >= 0)
        c.snprintf(
            buf1.ptr,
            buf1.len,
            FMT_BATVOL,
            fBatCapacity,
            batMark(),
            fVolume,
            vol_mark,
        )
    else
        c.snprintf(
            buf1.ptr,
            buf1.len,
            FMT_VOL,
            fVolume,
            vol_mark,
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

var bsfd: c_int = -1;
// Charger state from BAT0/status. `.charging` is real current flow; `.plugged`
// covers "Full" and "Not charging" — charger attached but the pack holding
// (e.g. at the charge limit) — shown as `F` after the capacity.
const BatState = enum { none, plugged, charging };
var fBatState: BatState = .none;

fn batMark() [*:0]const u8 {
    return switch (fBatState) {
        .charging => "+",
        .plugged => "F",
        .none => "",
    };
}

fn readBatStatus() void {
    if (bsfd < 0) return;
    var buf: [32]u8 = undefined;
    _ = c.lseek(bsfd, 0, c.SEEK_SET);
    const n: usize = @intCast(c.read(bsfd, &buf, buf.len - 1));
    if (n < 1) {
        fBatState = .none;
        return;
    }
    buf[n] = 0;
    const s = std.mem.trim(u8, std.mem.sliceTo(buf[0..], 0), " \t\r\n");
    fBatState = if (std.mem.eql(u8, s, "Charging"))
        .charging
    else if (std.mem.eql(u8, s, "Full") or std.mem.eql(u8, s, "Not charging"))
        .plugged
    else
        .none;
}

var mixer: ?*c.snd_mixer_t = null;
var master_elem: ?*c.snd_mixer_elem_t = null;
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
const MAX_EVENTS = 8;
/// Monotonic seconds including suspend (CLOCK_BOOTTIME), only used to notice a
/// resume on the existing 60s tick. It is not a network poll.
var last_monotonic: i64 = 0;

fn bootSec() i64 {
    var ts: c.timespec = undefined;
    if (c.clock_gettime(c.CLOCK_BOOTTIME, &ts) != 0) return 0;
    return ts.tv_sec;
}

fn monoMs() i64 {
    var ts: c.timespec = undefined;
    if (c.clock_gettime(c.CLOCK_MONOTONIC, &ts) != 0) return 0;
    return ts.tv_sec * 1000 + @divTrunc(ts.tv_nsec, 1_000_000);
}

// ---------------------------------------------------------------------------
// Network status is event-driven. rtnetlink reports link/address/route changes
// and inotify reports resolver changes. The bar intentionally reports only
// local facts: interface, IPv4, route, DNS configuration, and Tailscale state.
// A conservative non-blocking heartbeat detects silent WAN/exit-node failure;
// local status remains entirely event-driven and the heartbeat uses one socket,
// one rotating target, and two failures before it reports `no-inet`.
//
//   wlan0 192.168.8.162 +ts       local path configured, Tailscale Running
//   wlan0 192.168.8.162 no-net    no usable local route/IP
//   wlan0 192.168.8.162 no-dns    no usable resolver configuration
//   ... ts-                       Tailscale is not Running
//   ... ts!                       Tailscale reports a health warning
//
// Every verdict change is appended to ~/.local/state/zlstatus/net.log.
// ---------------------------------------------------------------------------
var netfd: c_int = -1;
var net_buf: [96]u8 = undefined;
var net_len: usize = 0;

// inotify fd watching the two places resolv.conf actually lives (see dnsInit).
var dnsfd: c_int = -1;
var dns_wd_etc: c_int = -1;
var dns_wd_resolve: c_int = -1;

// Last interface that held a default route. Used to avoid showing a VPN/tunnel
// interface with no-net during resume, when the physical interface's default
// route hasn't been restored yet — a race where activeIfaceInto picks the
// first UP interface (tailscale0) instead of the one that will own the route
// once the system finishes resuming (wlan0).
var last_routed_iface: [16]u8 = undefined;
var last_routed_iface_len: usize = 0;
var cached_dns: DnsInfo = .{};
var cached_dns_valid: bool = false;

// rtnetlink(7) multicast group bitmask values (stable ABI). Hardcoded to
// avoid pulling in linux/rtnetlink.h, see comment on the cImport above.
const RTMGRP_LINK: u32 = 0x1;
const RTMGRP_IPV4_IFADDR: u32 = 0x10;
const RTMGRP_IPV4_ROUTE: u32 = 0x40;

fn netSetDown() void {
    const down = "net down";
    @memcpy(net_buf[0..down.len], down);
    net_len = down.len;
}

/// Append `s` to net_buf at `len`, silently truncating if it would not fit.
fn netAppend(len: *usize, s: []const u8) void {
    if (len.* + s.len > net_buf.len) return;
    @memcpy(net_buf[len.*..][0..s.len], s);
    len.* += s.len;
}

// --- Network log -----------------------------------------------------------
// zlstatus runs from xinitrc, where stderr usually disappears into the display
// manager's journal or nowhere at all. Keep a small explicit log so a failed
// connection leaves evidence instead of a silent `no-net`: every verdict change
// and every init failure is appended with a timestamp and the inputs that
// produced it. This is the only file zlstatus writes.
var net_log_fd: c_int = -1;
var net_log_path: [256]u8 = undefined;

fn logTimestamp(buf: []u8) []const u8 {
    var t: c.time_t = c.time(null);
    const tm = c.localtime(&t);
    if (tm == null) return "?";
    const n = c.strftime(buf.ptr, buf.len, "%Y-%m-%d %H:%M:%S", tm);
    return buf[0..n];
}

/// mkdir(2) that tolerates an existing directory. Used to create the log's
/// parents on a fresh account where ~/.local/state does not exist yet; without
/// them the log silently falls back to stderr (which xinitrc usually discards).
fn mkdirp(path: []const u8) void {
    var buf: [256]u8 = undefined;
    if (path.len >= buf.len) return;
    @memcpy(buf[0..path.len], path);
    buf[path.len] = 0;
    _ = c.mkdir(@ptrCast(&buf), @as(c.mode_t, 0o755));
}

fn netLogInit() void {
    const home_z = c.getenv("HOME") orelse return;
    const home = std.mem.span(home_z);

    var dirbuf: [256]u8 = undefined;
    const local = std.fmt.bufPrint(&dirbuf, "{s}/.local", .{home}) catch return;
    mkdirp(local);
    const state = std.fmt.bufPrint(&dirbuf, "{s}/.local/state", .{home}) catch return;
    mkdirp(state);
    const dir = std.fmt.bufPrint(&dirbuf, "{s}/.local/state/zlstatus", .{home}) catch return;
    mkdirp(dir);

    const p = std.fmt.bufPrint(&net_log_path, "{s}/net.log", .{dir}) catch return;
    net_log_path[p.len] = 0;

    // Keep the file small: one previous generation is enough to see what
    // happened before the last restart.
    var st: c.struct_stat = undefined;
    if (c.stat(@ptrCast(&net_log_path), &st) == 0 and st.st_size > 128 * 1024) {
        var oldbuf: [260]u8 = undefined;
        const old = std.fmt.bufPrint(&oldbuf, "{s}.1", .{p}) catch return;
        oldbuf[old.len] = 0;
        _ = c.rename(@ptrCast(&net_log_path), @ptrCast(&oldbuf));
    }

    net_log_fd = c.open(@ptrCast(&net_log_path), c.O_WRONLY | c.O_CREAT | c.O_APPEND, @as(c.mode_t, 0o644));
}

fn netLog(comptime fmt: []const u8, args: anytype) void {
    var body: [512]u8 = undefined;
    const msg = std.fmt.bufPrint(&body, fmt, args) catch return;

    var tsbuf: [32]u8 = undefined;
    const ts = logTimestamp(&tsbuf);

    var line: [640]u8 = undefined;
    const full = std.fmt.bufPrint(&line, "{s} zlstatus: net: {s}\n", .{ ts, msg }) catch return;
    line[full.len] = 0;

    if (net_log_fd >= 0) {
        _ = c.write(net_log_fd, full.ptr, full.len);
    } else {
        _ = c.fprintf(c.stderr, "%s", full.ptr);
    }
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

/// Is `ifname` actually up and running right now? /proc/net/route can keep a
/// stale default route for an interface that has already gone down; without
/// this check the bar would call that state healthy just because an address is
/// still bound.
fn ifaceIsUp(ifname: []const u8) bool {
    var ifaddr: ?*c.ifaddrs = null;
    if (c.getifaddrs(&ifaddr) != 0) return false;
    defer _ = c.freeifaddrs(ifaddr);
    var cur: ?*c.ifaddrs = ifaddr;
    while (cur) |ifa| : (cur = ifa.*.ifa_next) {
        if (!std.mem.eql(u8, std.mem.span(ifa.*.ifa_name), ifname)) continue;
        const flags = ifa.*.ifa_flags;
        return flags & c.IFF_UP != 0 and flags & c.IFF_RUNNING != 0;
    }
    return false;
}

/// True when the interface is still administratively present. During Wi-Fi
/// reassociation IFF_RUNNING can briefly clear, but the status should continue
/// to identify wlan0 instead of switching to tailscale0 or another tunnel.
fn ifaceExists(ifname: []const u8) bool {
    var ifaddr: ?*c.ifaddrs = null;
    if (c.getifaddrs(&ifaddr) != 0) return false;
    defer _ = c.freeifaddrs(ifaddr);
    var cur: ?*c.ifaddrs = ifaddr;
    while (cur) |ifa| : (cur = ifa.*.ifa_next) {
        if (!std.mem.eql(u8, std.mem.span(ifa.*.ifa_name), ifname)) continue;
        return ifa.*.ifa_flags & c.IFF_UP != 0;
    }
    return false;
}

const DnsInfo = struct {
    count: usize = 0,
    // True while every nameserver seen so far sits in Tailscale's 100.64.0.0/10.
    all_cgnat: bool = true,
};

/// IPv4 address of `ifname`, as a slice into `buf`, or null when the interface
/// has no IPv4 address bound right now.
///
/// getifaddrs() is cheap and this only ever runs in response to a netlink or
/// inotify event — a changed address already woke us up, so showing stale text
/// would be the only way to be slow here.
fn ifaceAddrInto(buf: []u8, ifname: []const u8) ?[]const u8 {
    var ifaddr: ?*c.ifaddrs = null;
    if (c.getifaddrs(&ifaddr) != 0) return null;
    defer _ = c.freeifaddrs(ifaddr);
    var cur: ?*c.ifaddrs = ifaddr;
    while (cur) |ifa| : (cur = ifa.*.ifa_next) {
        const sa: ?*c.sockaddr = ifa.*.ifa_addr;
        if (sa == null) continue;
        if (sa.?.*.sa_family != c.AF_INET) continue;
        if (c.snprintf(buf.ptr, buf.len, "%s", ifa.*.ifa_name) <= 0) continue;
        const nlen = std.mem.indexOfScalar(u8, buf[0..buf.len], 0) orelse continue;
        if (!std.mem.eql(u8, buf[0..nlen], ifname)) continue;
        const addr: *const c.sockaddr_in = @ptrCast(@alignCast(&sa.?.*));
        if (c.inet_ntop(c.AF_INET, &addr.sin_addr, buf.ptr, @intCast(buf.len)) == null) return null;
        const alen = std.mem.indexOfScalar(u8, buf[0..buf.len], 0) orelse return null;
        return buf[0..alen];
    }
    return null;
}

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

const TsBackend = enum { absent, stopped, starting, running, needs_login, other };

const TsInfo = struct {
    /// The LocalAPI socket answered, i.e. tailscaled is installed and running
    /// as a service. `backend` then says whether the node itself is up.
    present: bool = false,
    backend: TsBackend = .absent,
    online: bool = false,
    /// Tailscale published at least one health warning (dead relay, no DERP,
    /// exit node trouble, ...). Shown as `ts!`; details live in vxpanel.
    health: bool = false,
};

fn jsonStringAfter(body: []const u8, key: []const u8) ?[]const u8 {
    const at = std.mem.indexOf(u8, body, key) orelse return null;
    var i = at + key.len;
    while (i < body.len and body[i] != ':') i += 1;
    i += 1; // step past the colon itself
    while (i < body.len and (body[i] == ' ' or body[i] == '\t')) i += 1;
    if (i >= body.len or body[i] != '"') return null;
    i += 1;
    const start = i;
    while (i < body.len and body[i] != '"') i += 1;
    if (i >= body.len) return null;
    return body[start..i];
}

fn jsonBoolAfter(body: []const u8, key: []const u8) ?bool {
    const at = std.mem.indexOf(u8, body, key) orelse return null;
    var i = at + key.len;
    while (i < body.len and body[i] != ':') i += 1;
    i += 1;
    while (i < body.len and (body[i] == ' ' or body[i] == '\t')) i += 1;
    if (std.mem.startsWith(u8, body[i..], "true")) return true;
    if (std.mem.startsWith(u8, body[i..], "false")) return false;
    return null;
}

/// True when key names a non-empty JSON array; false for [], null, or a
/// non-array. Only the first element is inspected, which is enough for
/// Tailscale's `Health` list.
fn jsonArrayNonEmptyAfter(body: []const u8, key: []const u8) ?bool {
    const at = std.mem.indexOf(u8, body, key) orelse return null;
    var i = at + key.len;
    while (i < body.len and body[i] != ':') i += 1;
    if (i >= body.len) return null;
    i += 1;
    while (i < body.len and (body[i] == ' ' or body[i] == '\t' or
        body[i] == '\r' or body[i] == '\n')) i += 1;
    if (i >= body.len) return null;
    if (body[i] != '[') return false; // null / absent
    i += 1;
    while (i < body.len and (body[i] == ' ' or body[i] == '\t' or
        body[i] == '\r' or body[i] == '\n')) i += 1;
    return i < body.len and body[i] != ']';
}

/// What tailscaled reports right now. BackendState is the authority for on/off:
/// `Self.Online` alone is false in several healthy states (starting, a quiet
/// tailnet) and was the reason the old Super+Shift+\ toggle could see "off"
/// while Tailscale was up and then report "Connected" on `tailscale up`.
///
/// The read is bounded and non-blocking-ish: tailscaled can be mid-restart and
/// leave the socket present but unaccepting, and the bar must never stall on
/// that.
fn tailscaleInfo() TsInfo {
    var info: TsInfo = .{};

    const fd = c.socket(c.AF_UNIX, c.SOCK_STREAM, 0);
    if (fd < 0) return info; // no tailscaled at all
    defer _ = c.close(fd);

    var addr: c.sockaddr_un = std.mem.zeroes(c.sockaddr_un);
    addr.sun_family = c.AF_UNIX;
    if (TS_SOCK.len >= addr.sun_path.len) return info;
    @memcpy(addr.sun_path[0..TS_SOCK.len], TS_SOCK);
    addr.sun_path[TS_SOCK.len] = 0;

    if (!connectWithTimeout(fd, @ptrCast(&addr), @sizeOf(c.sockaddr_un))) return info;
    info.present = true;
    setSocketTimeout(fd, 100);

    if (c.write(fd, TS_REQ, TS_REQ.len) < 0) return info;

    // BackendState lands around byte 40, Self.Online around byte 980 and the
    // Health array around byte 3 KiB once peers exist. 4 KiB covers all three
    // with room to spare; read() returns what is available rather than waiting
    // to fill the buffer, and the 100 ms socket timeout bounds tailscaled.
    var buf: [4096]u8 = undefined;
    const n = c.read(fd, &buf, buf.len);
    if (n <= 0) return info;
    const body = buf[0..@intCast(n)];

    if (jsonStringAfter(body, TS_KEY)) |state| {
        info.backend = if (std.mem.eql(u8, state, "Running"))
            .running
        else if (std.mem.eql(u8, state, "Stopped"))
            .stopped
        else if (std.mem.eql(u8, state, "Starting"))
            .starting
        else if (std.mem.eql(u8, state, "NeedsLogin"))
            .needs_login
        else
            .other;
    }

    // Self.Online is the first `"Online"` after `"Self"`; only look inside the
    // Self object so a peer's Online flag can never be mistaken for ours.
    if (std.mem.indexOf(u8, body, "\"Self\"")) |sp| {
        if (jsonBoolAfter(body[sp..], "\"Online\"")) |b| info.online = b;
    }

    // Health is a top-level array of warning strings. An empty array (or null)
    // means tailscaled has nothing to report. This is Tailscale's own verdict,
    // not a reachability probe, so it is safe to show even when the generic
    // internet probe is green.
    if (jsonArrayNonEmptyAfter(body, "\"Health\"")) |bad| info.health = bad;

    return info;
}

// --- Internet reachability -------------------------------------------------
// A route and an IP cannot detect a silent WAN/exit-node failure. One very
// small non-blocking TCP connect is therefore used as a heartbeat. This is
// intentionally conservative: one rotating target at a time, a 4s deadline,
// and two consecutive failed rounds before `no-inet`. A successful check
// clears the fault immediately. This avoids the old false alarms caused by a
// single slow public destination while still exposing a real outage without
// threads or blocking the bar's epoll loop.
const ProbeState = enum { unknown, online, offline };
const ProbeTarget = struct { addr: [:0]const u8, port: u16 };
const PROBE_TARGETS = [_]ProbeTarget{
    .{ .addr = "1.1.1.1", .port = 443 },
    .{ .addr = "8.8.8.8", .port = 443 },
    .{ .addr = "9.9.9.9", .port = 443 },
};
const PROBE_TIMEOUT_MS: u64 = 2500;
const PROBE_HEALTHY_MS: u64 = 5000;
const PROBE_RETRY_MS: u64 = 1000;
const PROBE_SETTLE_MS: u64 = 100;
// Public TCP services can briefly drop or filter a SYN. Two failures were
// enough to make a healthy connection flash `no-inet` (especially while a
// route or Tailscale was settling). Require a complete extra failure before
// changing the visible verdict; successful checks still clear it immediately.
const PROBE_FAIL_LIMIT: u8 = 3;

var probe_state: ProbeState = .unknown;
var probe_timerfd: c_int = -1;
var probe_fd: c_int = -1;
var probe_active: bool = false;
var probe_again: bool = false;
var probe_target: usize = 0;
var probe_failures: u8 = 0;

fn probeArm(ms: u64) void {
    if (probe_timerfd < 0) return;
    var its: c.itimerspec = std.mem.zeroes(c.itimerspec);
    its.it_value.tv_sec = @intCast(ms / 1000);
    its.it_value.tv_nsec = @intCast((ms % 1000) * 1_000_000);
    _ = c.timerfd_settime(probe_timerfd, 0, &its, null);
}

fn probeClose() void {
    if (probe_fd >= 0) {
        _ = c.epoll_ctl(g_epollfd, c.EPOLL_CTL_DEL, probe_fd, null);
        _ = c.close(probe_fd);
        probe_fd = -1;
    }
    probe_active = false;
}

fn probeKick() void {
    if (probe_timerfd < 0) return;
    if (probe_active) {
        probe_again = true;
        return;
    }
    probeArm(PROBE_SETTLE_MS);
}

fn probeFinish(ok: bool) void {
    probeClose();
    if (ok) {
        const changed = probe_state != .online;
        probe_state = .online;
        probe_failures = 0;
        if (changed) netLog("internet check: reachable", .{});
    } else {
        if (probe_failures < 255) probe_failures += 1;
        if (probe_failures >= PROBE_FAIL_LIMIT) {
            const changed = probe_state != .offline;
            probe_state = .offline;
            if (changed) netLog("internet check: no response after {d} checks", .{probe_failures});
        }
    }
    netRefresh();
    const next = if (probe_again) blk: {
        probe_again = false;
        break :blk PROBE_SETTLE_MS;
    } else if (probe_state == .offline or probe_failures > 0)
        PROBE_RETRY_MS
    else
        PROBE_HEALTHY_MS;
    probeArm(next);
}

fn probeStart() void {
    if (probe_timerfd < 0 or probe_active) return;
    if (!udpRouteOk()) {
        probe_state = .unknown;
        probe_failures = 0;
        probeArm(PROBE_RETRY_MS);
        return;
    }

    const t = PROBE_TARGETS[probe_target];
    probe_target = (probe_target + 1) % PROBE_TARGETS.len;
    var sa: c.sockaddr_in = std.mem.zeroes(c.sockaddr_in);
    sa.sin_family = c.AF_INET;
    sa.sin_port = c.htons(t.port);
    if (c.inet_pton(c.AF_INET, t.addr, &sa.sin_addr) != 1) {
        probeFinish(false);
        return;
    }
    const fd = c.socket(c.AF_INET, c.SOCK_STREAM | c.SOCK_NONBLOCK, 0);
    if (fd < 0) {
        probeFinish(false);
        return;
    }
    probe_fd = fd;
    probe_active = true;
    if (c.connect(fd, @ptrCast(&sa), @sizeOf(c.sockaddr_in)) == 0) {
        probeFinish(true);
        return;
    }
    const err = c.__errno_location().*;
    if (err != c.EINPROGRESS and err != c.EAGAIN) {
        probeFinish(false);
        return;
    }
    var ev = c.epoll_event{
        .events = @as(u32, c.EPOLLOUT) | c.EPOLLERR | c.EPOLLHUP | c.EPOLLET,
        .data = .{ .u64 = @intFromEnum(Event.ProbeSocket) },
    };
    if (c.epoll_ctl(g_epollfd, c.EPOLL_CTL_ADD, fd, &ev) < 0) {
        probeFinish(false);
        return;
    }
    probeArm(PROBE_TIMEOUT_MS);
}

fn probeSocketHandle() void {
    if (!probe_active or probe_fd < 0) return;
    var err: c_int = 0;
    var len: c.socklen_t = @sizeOf(c_int);
    if (c.getsockopt(probe_fd, c.SOL_SOCKET, c.SO_ERROR, @ptrCast(&err), &len) != 0)
        err = 1;
    probeFinish(err == 0);
}

fn probeTimerHandle() void {
    if (probe_timerfd < 0) return;
    var expirations: u64 = undefined;
    _ = c.read(probe_timerfd, &expirations, @sizeOf(u64));
    if (probe_active) probeFinish(false) else probeStart();
}

fn probeInit() void {
    probe_timerfd = c.timerfd_create(c.CLOCK_BOOTTIME, c.TFD_NONBLOCK);
    if (probe_timerfd < 0) {
        netLog("internet check timer unavailable: errno {d}", .{c.__errno_location().*});
        return;
    }
    var ev = c.epoll_event{
        .events = @as(u32, c.EPOLLIN) | c.EPOLLET,
        .data = .{ .u64 = @intFromEnum(Event.ProbeTimer) },
    };
    if (c.epoll_ctl(g_epollfd, c.EPOLL_CTL_ADD, probe_timerfd, &ev) < 0) {
        netLog("internet check epoll registration failed: errno {d}", .{c.__errno_location().*});
        _ = c.close(probe_timerfd);
        probe_timerfd = -1;
        return;
    }
    probeKick();
}

/// Does the kernel currently have a route for an arbitrary IPv4 destination?
///
/// A UDP `connect()` is a local route lookup: it sends no packets (a datagram
/// is only transmitted on send(2)), but it makes the kernel pick a source
/// address and fail with ENETUNREACH when no route exists. Unlike parsing
/// /proc/net/route, this sees policy routing and VPN/exit-node tables, so a
/// working Tailscale route can never be misreported as `no-net`.
fn udpRouteOk() bool {
    const fd = c.socket(c.AF_INET, c.SOCK_DGRAM, 0);
    if (fd < 0) return false;
    defer _ = c.close(fd);

    var sa: c.sockaddr_in = std.mem.zeroes(c.sockaddr_in);
    sa.sin_family = c.AF_INET;
    sa.sin_port = c.htons(443);
    if (c.inet_pton(c.AF_INET, "1.1.1.1", &sa.sin_addr) != 1) return false;
    return c.connect(fd, @ptrCast(&sa), @sizeOf(c.sockaddr_in)) == 0;
}


/// Re-read current route / DNS / interface state and repaint the bar. Called
/// from every network wakeup: netlink events, resolv.conf changes via inotify,
/// and resume detection.
fn netRefresh() void {
    const route = readRouteInfo();
    cached_dns_valid = false;
    netRender(route);
}

var net_last_log: [96]u8 = undefined;
var net_last_log_len: usize = 0;
var net_logged: bool = false;

/// Log only when the visible verdict changes, so a busy link does not fill the
/// log with identical lines. The caller's format includes the raw inputs.
fn netLogIfChanged(comptime fmt: []const u8, args: anytype) void {
    if (net_logged and std.mem.eql(u8, net_last_log[0..net_last_log_len], net_buf[0..net_len])) return;
    net_last_log_len = @min(net_len, net_last_log.len);
    @memcpy(net_last_log[0..net_last_log_len], net_buf[0..net_last_log_len]);
    net_logged = true;
    netLog(fmt, args);
}

/// Rebuild net_buf from current state.
///
/// Plain text, faults in a fixed order so the string stays stable between
/// refreshes — a bar whose text jitters is worse than one that is merely terse.
/// Examples:
///   `wlan0 192.168.1.42`          healthy
///   `wlan0 192.168.1.42 +ts`      healthy, Tailscale Running
///   `wlan0 192.168.1.42 ts-`      tailscaled running, node not connected
///   `wlan0 192.168.1.42 +ts!`     Tailscale Running with a health warning
///   `wlan0 192.168.1.42 no-net`   no usable local route/IP
///   `wlan0 no-ip no-net`          link up, DHCP supplied no IPv4 address
///   `net down`                    nothing usable is up
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
    } else if (last_routed_iface_len > 0 and blk: {
        var remembered: [16]u8 = undefined;
        @memcpy(remembered[0..last_routed_iface_len], last_routed_iface[0..last_routed_iface_len]);
        break :blk ifaceExists(remembered[0..last_routed_iface_len]);
    }) blk: {
        // No default route right now, but we remember which interface had it last
        @memcpy(ifbuf[0..last_routed_iface_len], last_routed_iface[0..last_routed_iface_len]);
        break :blk ifbuf[0..last_routed_iface_len];
    } else blk: {
        // No default route and no memory of one: fall back to first UP interface
        break :blk activeIfaceInto(&ifbuf) orelse {
            netSetDown();
            const dns = readDnsInfo();
            const ts = tailscaleInfo();
            netLogIfChanged(
                "verdict \"{s}\" iface=- ip=- up=false route={} dns={d} ts={s} online={} reason=no-usable-interface",
                .{ net_buf[0..net_len], route.has_default, dns.count, @tagName(ts.backend), ts.online },
            );
            return;
        };
    };

    var len: usize = 0;
    netAppend(&len, name);

    // IPv4 of the active interface, when it has one.
    var ipbuf: [16]u8 = undefined;
    const ip = ifaceAddrInto(&ipbuf, name);
    if (ip) |addr| {
        netAppend(&len, " ");
        netAppend(&len, addr);
    }

    // A route can outlive the interface it points at, so "up" and "routed" are
    // checked separately. `up` is diagnostic: a Wi-Fi driver can drop
    // IFF_RUNNING for a moment while the address and route stay usable, and
    // that must not paint `no-net`. The verdict itself comes from the kernel
    // route lookup, not from /proc/net/route: the file only shows the main
    // table, while a VPN/exit node can carry traffic through a policy table.
    const up = ifaceIsUp(name);
    const routed = udpRouteOk();
    const reason: []const u8 = if (!routed and ip == null)
        "no-ipv4-no-route"
    else if (!routed)
        "no-route"
    else if (ip == null)
        "no-ipv4"
    else
        "ok";

    if (!std.mem.eql(u8, reason, "ok"))
        netAppend(&len, " no-net")
    else if (probe_state == .offline)
        netAppend(&len, " no-inet");

    const ts = tailscaleInfo();
    if (!cached_dns_valid) {
        cached_dns = readDnsInfo();
        cached_dns_valid = true;
    }
    const dns_bad = cached_dns.count == 0 or
        (cached_dns.all_cgnat and ts.backend != .running and ts.backend != .starting);
    if (dns_bad) netAppend(&len, " no-dns");

    switch (ts.backend) {
        // Show on/off plus Tailscale's own health warning. Self.Online can lag
        // behind BackendState and is logged but not used for the bar; vxpanel
        // shows the full Online/Health view.
        .running => netAppend(&len, if (ts.health) " +ts!" else " +ts"),
        .absent => {},
        else => netAppend(&len, " ts-"),
    }

    net_len = len;
    netLogIfChanged(
        "verdict \"{s}\" iface={s} ip={s} up={} routed={} dns={d} dns_src={s} ts={s} online={} health={} reason={s}",
        .{
            net_buf[0..net_len],
            name,
            ip orelse "-",
            up,
            routed,
            cached_dns.count,
            if (cached_dns.all_cgnat) "tailnet" else "public",
            @tagName(ts.backend),
            ts.online,
            ts.health,
            reason,
        },
    );
}

fn netInit() void {
    netLogInit();
    netLog("start: event-driven local status (rtnetlink + inotify)", .{});

    netfd = c.socket(c.AF_NETLINK, c.SOCK_RAW | c.SOCK_NONBLOCK, c.NETLINK_ROUTE);

    netRefresh();

    if (netfd < 0) {
        netLog("netlink socket() failed: errno {d}; status will only change on resume", .{c.__errno_location().*});
        return;
    }
    var addr: c.sockaddr_nl = std.mem.zeroes(c.sockaddr_nl);
    addr.nl_family = c.AF_NETLINK;
    // RTMGRP_IPV4_ROUTE is what makes `no-net` appear the moment a default route
    // comes or goes, rather than waiting for something else to wake the bar.
    addr.nl_groups = RTMGRP_LINK | RTMGRP_IPV4_IFADDR | RTMGRP_IPV4_ROUTE;
    if (c.bind(netfd, @ptrCast(&addr), @sizeOf(c.sockaddr_nl)) < 0) {
        netLog("netlink bind() failed: errno {d}; status will only change on resume", .{c.__errno_location().*});
        _ = c.close(netfd);
        netfd = -1;
        return;
    }
    var event = c.epoll_event{
        .events = @as(u32, c.EPOLLIN) | c.EPOLLET,
        .data = .{ .u64 = @intFromEnum(Event.NetChange) },
    };
    // Non-fatal: without this the bar still repaints on inotify and resume.
    if (c.epoll_ctl(g_epollfd, c.EPOLL_CTL_ADD, netfd, &event) < 0)
        netLog("netlink epoll_ctl failed: errno {d}", .{c.__errno_location().*});
}

/// Watch the two places resolv.conf actually lives so nameserver changes repaint
/// the bar instantly instead of waiting for a netlink event that may never come
/// (e.g. tailscaled rewriting resolv.conf while routes stay put). systemd-resolved
/// writes /run/systemd/resolve/stub-resolv.conf in place; other resolvers rewrite
/// /etc/resolv.conf directly, sometimes via rename. Both are watched at the
/// directory level so a rename that REPLACES the file is still seen (IN_MOVED_TO),
/// which watching the file itself would miss.
fn dnsInit() void {
    dnsfd = c.inotify_init1(c.IN_NONBLOCK);
    if (dnsfd < 0) {
        netLog("inotify_init1() failed: errno {d}; DNS changes only on netlink events", .{c.__errno_location().*});
        return;
    }
    const dir_mask: u32 = @intCast(c.IN_MODIFY | c.IN_CREATE | c.IN_MOVED_TO | c.IN_DELETE | c.IN_ATTRIB);
    dns_wd_etc = c.inotify_add_watch(dnsfd, "/etc", dir_mask);
    dns_wd_resolve = c.inotify_add_watch(dnsfd, "/run/systemd/resolve", dir_mask);
    if (dns_wd_etc < 0 and dns_wd_resolve < 0) {
        netLog("no resolv.conf path watchable: errno {d}; DNS changes only on netlink events", .{c.__errno_location().*});
        _ = c.close(dnsfd);
        dnsfd = -1;
        return;
    }
    var event = c.epoll_event{
        .events = @as(u32, c.EPOLLIN),
        .data = .{ .u64 = @intFromEnum(Event.DnsChange) },
    };
    // Non-fatal: without this we still repaint on every netlink event.
    if (c.epoll_ctl(g_epollfd, c.EPOLL_CTL_ADD, dnsfd, &event) < 0)
        netLog("inotify epoll_ctl failed: errno {d}", .{c.__errno_location().*});
}

/// Drain the inotify buffer; refresh only if a watched resolv.conf actually
/// changed — other /etc activity must never touch the bar.
fn dnsHandleEvent() void {
    if (dnsfd < 0) return;
    var buf: [4096]u8 = undefined;
    const n = c.read(dnsfd, &buf, buf.len);
    if (n < 0) return;
    const hdr = @sizeOf(c.inotify_event);
    const total: usize = @intCast(n);
    var off: usize = 0;
    var relevant: bool = false;
    while (off + hdr <= total) {
        const ev: *c.inotify_event = @ptrCast(@alignCast(&buf[off]));
        const namelen: usize = @intCast(ev.*.len);
        if (namelen > 1) {
            const name: [*]const u8 = @ptrCast(@alignCast(&buf[off + hdr]));
            if (ev.*.wd == dns_wd_etc and std.mem.eql(u8, name[0 .. namelen - 1], "resolv.conf"))
                relevant = true;
            if (ev.*.wd == dns_wd_resolve and std.mem.eql(u8, name[0 .. namelen - 1], "stub-resolv.conf"))
                relevant = true;
        }
        off += hdr + namelen;
    }
    if (!relevant) return;
    netRefresh();
}

fn netHandleEvent() void {
    if (netfd >= 0) {
        // Edge-triggered: drain the socket fully before re-scanning.
        var buf: [4096]u8 = undefined;
        while (c.recv(netfd, &buf, buf.len, 0) > 0) {}
    }
    // A route change is a new connection attempt. Do not carry an old WAN
    // failure across DHCP/reassociation; the probe will verify the new route.
    probeClose();
    probe_state = .unknown;
    probe_failures = 0;
    netRefresh();
    probeKick();
}

// --- Battery charger uevents -----------------------------------------------
// Plugging/unplugging the charger is a kernel KOBJ_CHANGE uevent on the
// power_supply class. Subscribing to the kernel's uevent netlink group makes the
// charging indicator instant with no polling at all (the bind needs no
// privileges here — verified as this user). Every uevent is drained; only
// power_supply changes are acted on.
var ueventfd: c_int = -1;

fn ueventInit() void {
    ueventfd = c.socket(c.AF_NETLINK, c.SOCK_DGRAM | c.SOCK_NONBLOCK, c.NETLINK_KOBJECT_UEVENT);
    if (ueventfd < 0) {
        _ = c.fprintf(c.stderr, "batt: uevent socket() failed, charging updates only on the minute tick\n");
        return;
    }
    var addr: c.sockaddr_nl = std.mem.zeroes(c.sockaddr_nl);
    addr.nl_family = c.AF_NETLINK;
    addr.nl_groups = 1; // kernel-originated uevents
    if (c.bind(ueventfd, @ptrCast(&addr), @sizeOf(c.sockaddr_nl)) < 0) {
        _ = c.fprintf(c.stderr, "batt: uevent bind() failed, charging updates only on the minute tick\n");
        _ = c.close(ueventfd);
        ueventfd = -1;
        return;
    }
    var event = c.epoll_event{
        .events = @as(u32, c.EPOLLIN) | c.EPOLLET,
        .data = .{ .u64 = @intFromEnum(Event.Uevent) },
    };
    // Non-fatal: without this the minute tick still refreshes the indicator.
    _ = c.epoll_ctl(g_epollfd, c.EPOLL_CTL_ADD, ueventfd, &event);
}

fn ueventHandle() void {
    if (ueventfd < 0) return;
    // Edge-triggered: drain every queued uevent so the fd goes quiet again.
    var buf: [8192]u8 = undefined;
    var power_changed = false;
    while (true) {
        const n = c.recv(ueventfd, &buf, buf.len, 0);
        if (n <= 0) break;
        const msg = buf[0..@intCast(n)];
        if (std.mem.indexOf(u8, msg, "SUBSYSTEM=power_supply") != null)
            power_changed = true;
    }
    if (!power_changed) return;
    readBatCapacity();
    readBatStatus();
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

/// One bar per display. Without this a second start (WM restart, manual launch,
/// or a leftover instance) races the first one's XStoreName calls, so the root
/// name can flip between two different verdicts — and one of them can be stale.
/// The lock is per $DISPLAY and lives in the state dir; its fd stays open for
/// the process lifetime and the kernel releases it on exit/panic.
var instance_lock_fd: c_int = -1;

fn readLockPid(fd: c_int) c.pid_t {
    var buf: [32]u8 = undefined;
    _ = c.lseek(fd, 0, c.SEEK_SET);
    const n = c.read(fd, &buf, buf.len);
    if (n <= 0) return 0;
    const s = std.mem.trim(u8, buf[0..@intCast(n)], " \t\r\n");
    return std.fmt.parseInt(c.pid_t, s, 10) catch 0;
}

/// Confirm the PID in the lock file is really a zlstatus before signalling it;
/// PIDs are reused and `kill` must never hit an unrelated process.
fn pidLooksLikeZlstatus(pid: c.pid_t) bool {
    var pathbuf: [64]u8 = undefined;
    const path = std.fmt.bufPrint(&pathbuf, "/proc/{d}/comm", .{pid}) catch return false;
    if (path.len >= pathbuf.len) return false;
    pathbuf[path.len] = 0;
    const fd = c.open(@ptrCast(&pathbuf), c.O_RDONLY);
    if (fd < 0) return false;
    defer _ = c.close(fd);
    var buf: [32]u8 = undefined;
    const n = c.read(fd, &buf, buf.len);
    if (n <= 0) return false;
    return std.mem.startsWith(u8, buf[0..@intCast(n)], "zlstatus");
}

fn singleInstanceInit() bool {
    const home_z = c.getenv("HOME") orelse return true;
    const home = std.mem.span(home_z);

    var dirbuf: [256]u8 = undefined;
    const local = std.fmt.bufPrint(&dirbuf, "{s}/.local", .{home}) catch return true;
    mkdirp(local);
    const state = std.fmt.bufPrint(&dirbuf, "{s}/.local/state", .{home}) catch return true;
    mkdirp(state);
    const dir = std.fmt.bufPrint(&dirbuf, "{s}/.local/state/zlstatus", .{home}) catch return true;
    mkdirp(dir);

    const display_z = c.getenv("DISPLAY");
    const raw_display: []const u8 = if (display_z != null) std.mem.span(display_z) else "wayland";
    // :0 and :0.0 are the same root window; normalise the screen suffix so they
    // cannot each start a bar.
    const display = if (std.mem.indexOfScalar(u8, raw_display, '.')) |dot|
        raw_display[0..dot]
    else
        raw_display;
    var namebuf: [64]u8 = undefined;
    var n: usize = 0;
    for (display) |ch| {
        if (n >= namebuf.len) break;
        namebuf[n] = if (std.ascii.isAlphanumeric(ch)) ch else '_';
        n += 1;
    }
    if (n == 0) {
        @memcpy(namebuf[0..7], "default");
        n = 7;
    }

    var pathbuf: [320]u8 = undefined;
    const path = std.fmt.bufPrint(&pathbuf, "{s}/instance-{s}.lock", .{ dir, namebuf[0..n] }) catch return true;
    if (path.len >= pathbuf.len) return true;
    pathbuf[path.len] = 0;

    instance_lock_fd = c.open(@ptrCast(&pathbuf), c.O_RDWR | c.O_CREAT, @as(c.mode_t, 0o644));
    if (instance_lock_fd < 0) return true; // never make a bad lock path fatal

    var locked = c.flock(instance_lock_fd, c.LOCK_EX | c.LOCK_NB) == 0;
    if (!locked) {
        // Last start wins: a WM restart or a leftover bar from an earlier
        // session must not race this one on the same root window. Terminate
        // the verified holder, then wait briefly for it to release the lock.
        const old = readLockPid(instance_lock_fd);
        if (old > 1 and old != c.getpid() and pidLooksLikeZlstatus(old))
            _ = c.kill(old, c.SIGTERM);
        var tries: usize = 0;
        while (tries < 40) : (tries += 1) {
            if (c.flock(instance_lock_fd, c.LOCK_EX | c.LOCK_NB) == 0) {
                locked = true;
                break;
            }
            _ = c.usleep(10_000);
        }
    }
    if (!locked) {
        _ = c.close(instance_lock_fd);
        instance_lock_fd = -1;
        return false;
    }

    // Publish our PID so the next start can replace us cleanly.
    _ = c.ftruncate(instance_lock_fd, 0);
    _ = c.lseek(instance_lock_fd, 0, c.SEEK_SET);
    var pidbuf: [32]u8 = undefined;
    const pid = std.fmt.bufPrint(&pidbuf, "{d}\n", .{c.getpid()}) catch "";
    if (pid.len > 0) _ = c.write(instance_lock_fd, pid.ptr, pid.len);
    return true;
}

pub fn main() u8 {
    if (!singleInstanceInit()) {
        _ = c.fprintf(c.stderr, "zlstatus: another instance already owns this display\n");
        return 1;
    }

    Out.init();
    defer Out.deinit();

    const epollfd: c_int = c.epoll_create1(0);
    if (epollfd < 0) @panic("epoll_create1");
    defer _ = c.close(epollfd);
    g_epollfd = epollfd;

    // Date and time
    if (c.setlocale(c.LC_TIME, "") == null)
        @panic("setlocale");

    // BOOTTIME so the date/battery tick and the suspend/resume check run
    // immediately on wake, not one paused interval later.
    timerfd = c.timerfd_create(c.CLOCK_BOOTTIME, 0);
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

    // Battery (optional — desktops and VMs often have no BAT*). Try BAT0 then
    // BAT1; when neither exists the bar simply omits the battery segment and
    // every battery read below and in the event loop is skipped (bcfd stays
    // -1) instead of crashing the whole bar at startup.
    const BAT_CAP = [_][:0]const u8{
        "/sys/class/power_supply/BAT0/capacity",
        "/sys/class/power_supply/BAT1/capacity",
    };
    const BAT_STATUS = [_][:0]const u8{
        "/sys/class/power_supply/BAT0/status",
        "/sys/class/power_supply/BAT1/status",
    };
    for (BAT_CAP, 0..) |path, i| {
        bcfd = c.open(path, c.O_RDONLY);
        if (bcfd < 0) continue;
        readBatCapacity();
        // Charging marker (`+`/`F`) is non-fatal: a missing status file just
        // means no charging indicator, not a dead bar.
        bsfd = c.open(BAT_STATUS[i], c.O_RDONLY);
        if (bsfd >= 0) readBatStatus();
        break;
    }
    defer {
        if (bcfd >= 0) _ = c.close(bcfd);
        if (bsfd >= 0) _ = c.close(bsfd);
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
            master_elem = elem;
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

    // Network status (rtnetlink group socket, event-driven) + resolv.conf
    // watcher (inotify) plus the adaptive, non-blocking internet check.
    netInit();
    dnsInit();
    probeInit();

    // Charger plug/unplug uevents (power_supply class) - non-fatal
    ueventInit();

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
            if (ev.data.u64 > @intFromEnum(Event.ProbeTimer)) continue;
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
    DnsChange,
    Uevent,
    ProbeSocket,
    ProbeTimer,

    fn handleTimeout1m() void {
        readTime();
        // Consume amount of expirations from fd
        var exp_count: u64 = undefined;
        _ = c.read(timerfd, &exp_count, @sizeOf(u64));
        readBatCapacity();
        readBatStatus();

        // The network block itself is event-driven and never polled. The one
        // exception is suspend/resume: CLOCK_BOOTTIME keeps counting through
        // sleep, so a gap much larger than this 60s tick proves the machine
        // was suspended and kernel route events may have been missed. Refresh
        // once here; that is a recovery step on an existing wakeup, not a
        // periodic network poll.
        const now = bootSec();
        if (last_monotonic > 0 and now - last_monotonic > 120) {
            netLog("resume detected (gap {d}s), refreshing network status", .{now - last_monotonic});
            netRefresh();
            probeKick();
            if (master_elem) |elem| _ = readMasterVolume(elem, 0);
        }
        last_monotonic = now;

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

    fn handleDnsChange() void {
        dnsHandleEvent();
    }

    fn handleUevent() void {
        ueventHandle();
    }

    fn handleEvent(self: Event) void {
        switch (self) {
            .TimeOut1m => handleTimeout1m(),
            .VolChange => handleVolChange(),
            .MpdEvent => handleMpdEvent(),
            .NetChange => handleNetChange(),
            .DnsChange => handleDnsChange(),
            .Uevent => handleUevent(),
            .ProbeSocket => probeSocketHandle(),
            .ProbeTimer => probeTimerHandle(),
        }
    }
};
