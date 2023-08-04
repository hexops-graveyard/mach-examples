const std = @import("std");
const mach = @import("libs/mach/build.zig");

pub fn build(b: *std.Build) !void {
    try ensureDependencies(b.allocator);

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const Dependency = enum {
        zigimg,
        model3d,
        assets,

        pub fn moduleDependency(
            dep: @This(),
            b2: *std.Build,
            target2: std.zig.CrossTarget,
            optimize2: std.builtin.OptimizeMode,
        ) std.Build.ModuleDependency {
            const path = switch (dep) {
                .zigimg => "libs/zigimg/zigimg.zig",
                .assets => "assets/assets.zig",
                .model3d => return std.Build.ModuleDependency{
                    .name = "model3d",
                    .module = b2.dependency("mach_model3d", .{
                        .target = target2,
                        .optimize = optimize2,
                    }).module("mach-model3d"),
                },
            };
            return std.Build.ModuleDependency{
                .name = @tagName(dep),
                .module = b2.createModule(.{ .source_file = .{ .path = path } }),
            };
        }
    };

    inline for ([_]struct {
        name: []const u8,
        deps: []const Dependency = &.{},
        std_platform_only: bool = false,
        has_assets: bool = false,
        use_freetype: bool = false,
    }{
        .{ .name = "sysaudio", .deps = &.{} },
        .{
            .name = "gkurve",
            .deps = &.{ .zigimg, .assets },
            .std_platform_only = true,
            .use_freetype = true,
        },
        .{ .name = "custom-renderer", .deps = &.{} },
        .{
            .name = "sprite2d",
            .deps = &.{ .zigimg, .assets },
        },
        .{
            .name = "text2d",
            .deps = &.{ .zigimg, .assets },
            .use_freetype = true,
        },
    }) |example| {
        // FIXME: this is workaround for a problem that some examples
        // (having the std_platform_only=true field) as well as zigimg
        // uses IO and depends on gpu-dawn which is not supported
        // in freestanding environments. So break out of this loop
        // as soon as any such examples is found. This does means that any
        // example which works on wasm should be placed before those who dont.
        if (example.std_platform_only)
            if (target.getCpuArch() == .wasm32)
                break;

        var deps = std.ArrayList(std.Build.ModuleDependency).init(b.allocator);
        for (example.deps) |d| try deps.append(d.moduleDependency(b, target, optimize));
        const app = try mach.App.init(
            b,
            .{
                .name = example.name,
                .src = "examples/" ++ example.name ++ "/main.zig",
                .target = target,
                .optimize = optimize,
                .deps = deps.items,
                .res_dirs = if (example.has_assets) &.{example.name ++ "/assets"} else null,
                .watch_paths = &.{"examples/" ++ example.name},
                .use_freetype = if (example.use_freetype) "freetype" else null,
            },
        );

        try app.link(.{});
        for (example.deps) |dep| switch (dep) {
            .model3d => app.compile.linkLibrary(b.dependency("mach_model3d", .{
                .target = target,
                .optimize = optimize,
            }).artifact("mach-model3d")),
            else => {},
        };

        const compile_step = b.step(example.name, "Compile " ++ example.name);
        compile_step.dependOn(&app.install.step);

        const run_step = b.step("run-" ++ example.name, "Run " ++ example.name);
        run_step.dependOn(&app.run.step);
    }

    const compile_all = b.step("compile-all", "Compile all examples and applications");
    compile_all.dependOn(b.getInstallStep());
}

pub fn copyFile(src_path: []const u8, dst_path: []const u8) void {
    std.fs.cwd().makePath(std.fs.path.dirname(dst_path).?) catch unreachable;
    std.fs.cwd().copyFile(src_path, std.fs.cwd(), dst_path, .{}) catch unreachable;
}

fn sdkPath(comptime suffix: []const u8) []const u8 {
    if (suffix[0] != '/') @compileError("suffix must be an absolute path");
    return comptime blk: {
        const root_dir = std.fs.path.dirname(@src().file) orelse ".";
        break :blk root_dir ++ suffix;
    };
}

fn ensureDependencies(allocator: std.mem.Allocator) !void {
    ensureGit(allocator);
    try ensureSubmodule(allocator, "libs/mach");
    try ensureSubmodule(allocator, "libs/zigimg");
}

fn ensureSubmodule(allocator: std.mem.Allocator, path: []const u8) !void {
    if (std.process.getEnvVarOwned(allocator, "NO_ENSURE_SUBMODULES")) |no_ensure_submodules| {
        defer allocator.free(no_ensure_submodules);
        if (std.mem.eql(u8, no_ensure_submodules, "true")) return;
    } else |_| {}
    var child = std.ChildProcess.init(&.{ "git", "submodule", "update", "--init", path }, allocator);
    child.cwd = sdkPath("/");
    child.stderr = std.io.getStdErr();
    child.stdout = std.io.getStdOut();

    _ = try child.spawnAndWait();
}

fn ensureGit(allocator: std.mem.Allocator) void {
    const result = std.ChildProcess.exec(.{
        .allocator = allocator,
        .argv = &.{ "git", "--version" },
    }) catch { // e.g. FileNotFound
        std.log.err("mach: error: 'git --version' failed. Is git not installed?", .{});
        std.process.exit(1);
    };
    defer {
        allocator.free(result.stderr);
        allocator.free(result.stdout);
    }
    if (result.term.Exited != 0) {
        std.log.err("mach: error: 'git --version' failed. Is git not installed?", .{});
        std.process.exit(1);
    }
}
