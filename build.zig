const std = @import("std");
const mach = @import("libs/mach/build.zig");
const mach_imgui = @import("libs/imgui/build.zig");
const Pkg = std.build.Pkg;

pub fn build(b: *std.build.Builder) !void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();
    const options = mach.Options{ .gpu_dawn_options = .{
        .from_source = b.option(bool, "dawn-from-source", "Build Dawn from source") orelse false,
        .debug = b.option(bool, "dawn-debug", "Use a debug build of Dawn") orelse false,
    } };

    try ensureDependencies(b.allocator);

    inline for ([_]struct {
        name: []const u8,
        deps: []const Pkg = &.{},
        std_platform_only: bool = false,
        has_assets: bool = false,
        use_freetype: bool = false,
        use_model3d: bool = false,
        use_imgui: bool = false,
    }{
        .{ .name = "triangle" },
        .{ .name = "triangle-msaa" },
        .{ .name = "boids" },
        .{
            .name = "pbr-basic",
            .deps = &.{ Packages.zmath, Packages.model3d, Packages.mach_imgui, Packages.assets },
            .use_model3d = true,
            .use_imgui = true,
        },
        .{ .name = "imgui", .deps = &.{ Packages.mach_imgui, Packages.assets }, .use_imgui = true },
        .{ .name = "rotating-cube", .deps = &.{Packages.zmath} },
        .{ .name = "pixel-post-process", .deps = &.{Packages.zmath} },
        .{ .name = "two-cubes", .deps = &.{Packages.zmath} },
        .{ .name = "instanced-cube", .deps = &.{Packages.zmath} },
        .{ .name = "advanced-gen-texture-light", .deps = &.{Packages.zmath} },
        .{ .name = "fractal-cube", .deps = &.{Packages.zmath} },
        .{ .name = "textured-cube", .deps = &.{ Packages.zmath, Packages.zigimg, Packages.assets } },
        .{ .name = "ecs-app", .deps = &.{} },
        .{ .name = "image-blur", .deps = &.{ Packages.zigimg, Packages.assets } },
        .{ .name = "cubemap", .deps = &.{ Packages.zmath, Packages.zigimg, Packages.assets } },
        .{ .name = "map-async", .deps = &.{} },
        .{ .name = "sysaudio", .deps = &.{} },
        .{
            .name = "gkurve",
            .deps = &.{ Packages.zmath, Packages.zigimg, Packages.assets },
            .std_platform_only = true,
            .use_freetype = true,
        },
    }) |example| {
        // FIXME: this is workaround for a problem that some examples
        // (having the std_platform_only=true field) as well as zigimg
        // uses IO which is not supported in freestanding environments.
        // So break out of this loop as soon as any such examples is found.
        // This does means that any example which works on wasm should be
        // placed before those who dont.
        if (example.std_platform_only)
            if (target.getCpuArch() == .wasm32)
                break;

        const app = try mach.App.init(
            b,
            .{
                .name = example.name,
                .src = example.name ++ "/main.zig",
                .target = target,
                .deps = example.deps,
                .res_dirs = if (example.has_assets) &.{example.name ++ "/assets"} else null,
                .watch_paths = &.{example.name},
                .use_freetype = if (example.use_freetype) "freetype" else null,
                .use_model3d = example.use_model3d,
            },
        );

        if (example.use_imgui) {
            mach_imgui.link(app.step);
        }

        app.setBuildMode(mode);
        try app.link(options);
        app.install();

        const compile_step = b.step(example.name, "Compile " ++ example.name);
        compile_step.dependOn(&app.getInstallStep().?.step);

        const run_cmd = try app.run();
        run_cmd.dependOn(compile_step);
        const run_step = b.step("run-" ++ example.name, "Run " ++ example.name);
        run_step.dependOn(run_cmd);
    }

    // @embedFile can't embed files outside the source file's directory, so copy our assets into
    // those directories.
    copyFile("libs/mach/libs/freetype/upstream/assets/FiraSans-Regular.ttf", "gkurve/FiraSans-Regular.ttf");

    const compile_all = b.step("compile-all", "Compile all examples and applications");
    compile_all.dependOn(b.getInstallStep());
}

const Packages = struct {
    // Declared here because submodule may not be cloned at the time build.zig runs.
    const zmath = Pkg{
        .name = "zmath",
        .source = .{ .path = "libs/zmath/src/zmath.zig" },
    };
    const zigimg = Pkg{
        .name = "zigimg",
        .source = .{ .path = "libs/zigimg/zigimg.zig" },
    };
    const model3d = Pkg{
        .name = "model3d",
        .source = .{ .path = "libs/mach/libs/model3d/src/main.zig" },
    };
    const mach_imgui = Pkg{
        .name = "mach-imgui",
        .source = .{ .path = "libs/imgui/src/main.zig" },
    };
    const assets = Pkg{
        .name = "assets",
        .source = .{ .path = "assets/assets.zig" },
    };
};

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
    try ensureSubmodule(allocator, "libs/zmath");
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
