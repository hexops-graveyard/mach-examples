const std = @import("std");
const mach = @import("libs/mach/build.zig");
// const imgui = @import("libs/imgui/build.zig");
const zmath = @import("libs/zmath/build.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const options = mach.Options{ .core = .{
        .gpu_dawn_options = .{
            .from_source = b.option(bool, "dawn-from-source", "Build Dawn from source") orelse false,
            .debug = b.option(bool, "dawn-debug", "Use a debug build of Dawn") orelse false,
        },
    } };

    try ensureDependencies(b.allocator);

    const Dependency = enum {
        zmath,
        zigimg,
        model3d,
        imgui,
        assets,

        pub fn moduleDependency(dep: @This(), b2: *std.Build) std.Build.ModuleDependency {
            if (dep == .zmath) return std.Build.ModuleDependency{
                .name = @tagName(dep),
                .module = zmath.Package.build(b2, .{
                    .options = .{ .enable_cross_platform_determinism = true },
                }).zmath,
            };
            const path = switch (dep) {
                .zmath => unreachable,
                .zigimg => "libs/zigimg/zigimg.zig",
                .model3d => "libs/mach/libs/model3d/src/main.zig",
                .imgui => "libs/imgui/src/main.zig",
                .assets => "assets/assets.zig",
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
        use_model3d: bool = false,
        use_imgui: bool = false,
        mach_engine_example: bool = false,
    }{
        .{ .name = "triangle" },
        .{ .name = "triangle-msaa" },
        .{ .name = "boids" },
        // TODO: imgui examples are broken
        // .{
        //     .name = "pbr-basic",
        //     .deps = &.{ .zmath, .model3d, .imgui, .assets },
        //     .use_model3d = true,
        //     .use_imgui = true,
        // },
        // .{
        //     .name = "deferred-rendering",
        //     .deps = &.{ .zmath, .model3d, .imgui, .assets },
        //     .use_model3d = true,
        //     .use_imgui = true,
        // },
        // .{ .name = "imgui", .deps = &.{ .imgui, .assets }, .use_imgui = true },
        .{ .name = "rotating-cube", .deps = &.{.zmath} },
        .{ .name = "pixel-post-process", .deps = &.{.zmath} },
        .{ .name = "two-cubes", .deps = &.{.zmath} },
        .{ .name = "instanced-cube", .deps = &.{.zmath} },
        .{ .name = "advanced-gen-texture-light", .deps = &.{.zmath} },
        .{ .name = "fractal-cube", .deps = &.{.zmath} },
        .{ .name = "textured-cube", .deps = &.{ .zmath, .zigimg, .assets } },
        .{ .name = "ecs-app", .deps = &.{}, .mach_engine_example = true },
        .{ .name = "image-blur", .deps = &.{ .zigimg, .assets } },
        .{ .name = "cubemap", .deps = &.{ .zmath, .zigimg, .assets } },
        .{ .name = "map-async", .deps = &.{} },
        .{ .name = "sysaudio", .deps = &.{}, .mach_engine_example = true },
        .{
            .name = "gkurve",
            .deps = &.{ .zmath, .zigimg, .assets },
            .std_platform_only = true,
            .use_freetype = true,
            .mach_engine_example = true,
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

        const path_suffix = if (example.mach_engine_example) "engine/" else "core/";
        var deps = std.ArrayList(std.Build.ModuleDependency).init(b.allocator);
        for (example.deps) |d| try deps.append(d.moduleDependency(b));
        const app = try mach.App.init(
            b,
            .{
                .name = example.name,
                .src = path_suffix ++ example.name ++ "/main.zig",
                .target = target,
                .optimize = optimize,
                .deps = deps.items,
                .res_dirs = if (example.has_assets) &.{example.name ++ "/assets"} else null,
                .watch_paths = &.{path_suffix ++ example.name},
                .use_freetype = if (example.use_freetype) "freetype" else null,
                .use_model3d = example.use_model3d,
            },
        );

        // if (example.use_imgui) {
        //     imgui.link(app.step);
        // }

        try app.link(options);
        app.install();

        const compile_step = b.step(example.name, "Compile " ++ example.name);
        compile_step.dependOn(&app.getInstallStep().?.step);

        const run_cmd = try app.run();
        run_cmd.dependOn(compile_step);
        const run_step = b.step("run-" ++ example.name, "Run " ++ example.name);
        run_step.dependOn(run_cmd);
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
