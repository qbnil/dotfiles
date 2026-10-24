const std = @import("std");

const OutMode = enum { X11, Wayland };

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    // Zig 0.17 removed @cImport. Translate the C headers once in the build and
    // expose them to main.zig as the ordinary `c` module.
    const translate_c = b.addTranslateC(.{
        .root_source_file = b.path("src/c.h"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    mod.addImport("c", translate_c.createModule());

    const out_mode: OutMode = b.option(OutMode, "mode", "X11 or Wayland") orelse .X11;

    const options = b.addOptions();
    options.addOption(OutMode, "out_mode", out_mode);
    mod.addOptions("config", options);

    if (out_mode == .X11) mod.linkSystemLibrary("X11", .{});
    mod.linkSystemLibrary("asound", .{});

    const exe = b.addExecutable(.{
        .name = "zlstatus",
        .root_module = mod,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    // Zig 0.17 removed Build.args; `zig build run` no longer forwards extra
    // arguments. zlstatus takes none — it is configured at compile time — so
    // dropping the forwarding loses nothing.

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
