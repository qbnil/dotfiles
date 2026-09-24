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
    @cInclude("netinet/in.h");
    @cInclude("arpa/inet.h");
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

const FMT_BATVOL = " B:%d V:%d%s ";
const FMT_DATE = "%a %d %b %H:%M ";

// BUF_LEN grew to fit "<now playing><batt/vol><date>"
const BUF_LEN = 192;
var status_buf: [BUF_LEN]u8 = undefined;
var fStatus: [:0]u8 = undefined;

fn setStatus() void {
    var n: usize = 0;

    // Now playing (mpd), if any
    if (mpd_np_len > 0) {
        @memcpy(status_buf[0..mpd_np_len], mpd_np[0..mpd_np_len]);
        n = mpd_np_len;
    }

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
    var buf: [8]u8 = undefined;
    _ = c.lseek(bcfd, 0, c.SEEK_SET);
    const n: usize = @intCast(c.read(bcfd, &buf, 8));
    if (n < 1) @panic("read bcfd");

    if (buf[n - 1] == '\n')
        buf[n - 1] = 0
    else
        buf[n] = 0;

    var endptr: [*c]u8 = undefined;
    const value: c_long = c.strtol(&buf, &endptr, 10);
    if (endptr == @as([*c]u8, @ptrCast(&buf))) @panic("strtol");

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
    _ = c.fprintf(c.stderr, "mpd: currentsong reply: %.*s\n", @as(c_int, @intCast(resp.len)), resp.ptr);

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
            break :blk std.fmt.bufPrint(&tmp, "{s} - {s} ", .{ artist, title }) catch tmp[0..0]
        else if (title.len > 0)
            break :blk std.fmt.bufPrint(&tmp, "{s} ", .{title}) catch tmp[0..0]
        else
            break :blk tmp[0..0];
    };

    const copy_len = @min(combined.len, mpd_np.len);
    @memcpy(mpd_np[0..copy_len], combined[0..copy_len]);
    mpd_np_len = copy_len;
    _ = c.fprintf(c.stderr, "mpd: now-playing text: \"%.*s\" (%zu bytes)\n", @as(c_int, @intCast(mpd_np_len)), &mpd_np, mpd_np_len);
}

fn mpdSendIdle() void {
    if (mpdfd < 0) return;
    const cmd = "idle player\n";
    if (c.write(mpdfd, cmd.ptr, cmd.len) < 0) mpdDisconnect();
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

    if (c.connect(fd, @ptrCast(&addr), @sizeOf(c.sockaddr_un)) < 0) {
        _ = c.fprintf(c.stderr, "mpd: unix connect() failed (errno %d)\n", c.__errno_location().*);
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

    if (c.connect(fd, @ptrCast(&addr), @sizeOf(c.sockaddr_in)) < 0) {
        _ = c.fprintf(c.stderr, "mpd: tcp connect() failed (errno %d)\n", c.__errno_location().*);
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

    // Battery capacity
    bcfd = c.open(BAT ++ "capacity", c.O_RDONLY);
    if (bcfd < 0) @panic("open BAT capacity");
    defer _ = c.close(bcfd);

    readBatCapacity();

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

    // MPD (now playing) - non-fatal if mpd isn't running
    mpdConnect();
    defer mpdDisconnect();

    writeStatus();

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

    fn handleTimeout1m() void {
        readTime();
        // Consume amount of expirations from fd
        var exp_count: u64 = undefined;
        _ = c.read(timerfd, &exp_count, @sizeOf(u64));
        readBatCapacity();

        // Retry MPD connection if it dropped (e.g. mpd wasn't running at startup)
        if (mpdfd < 0) mpdConnect();
    }

    fn handleVolChange() void {
        _ = c.snd_mixer_handle_events(mixer);
    }

    fn handleMpdEvent() void {
        mpdHandleEvent();
    }

    fn handleEvent(self: Event) void {
        switch (self) {
            .TimeOut1m => handleTimeout1m(),
            .VolChange => handleVolChange(),
            .MpdEvent => handleMpdEvent(),
        }
    }
};
