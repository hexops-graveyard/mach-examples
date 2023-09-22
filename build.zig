const std = @import("std");
const builtin = @import("builtin");
const mach = @import("mach");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const Dependency = enum {
        assets,
        model3d,
        freetype,
        zigimg,

        pub fn moduleDependency(
            dep: @This(),
            b2: *std.Build,
            target2: std.zig.CrossTarget,
            optimize2: std.builtin.OptimizeMode,
        ) std.Build.ModuleDependency {
            const path = switch (dep) {
                .assets => "assets/assets.zig",
                .model3d => return std.Build.ModuleDependency{
                    .name = "model3d",
                    .module = b2.dependency("mach_model3d", .{
                        .target = target2,
                        .optimize = optimize2,
                    }).module("mach-model3d"),
                },
                .freetype => return std.Build.ModuleDependency{
                    .name = "freetype",
                    .module = b2.dependency("mach_freetype", .{
                        .target = target2,
                        .optimize = optimize2,
                    }).module("mach-freetype"),
                },
                .zigimg => return std.Build.ModuleDependency{
                    .name = "zigimg",
                    .module = b2.dependency("zigimg", .{
                        .target = target2,
                        .optimize = optimize2,
                    }).module("zigimg"),
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
    }{
        .{ .name = "sysaudio", .deps = &.{} },
        .{
            .name = "gkurve",
            .deps = &.{ .zigimg, .freetype, .assets },
            .std_platform_only = true,
        },
        .{ .name = "custom-renderer", .deps = &.{} },
        .{
            .name = "sprite",
            .deps = &.{ .zigimg, .assets },
        },
        .{
            .name = "text",
            .deps = &.{ .freetype, .assets },
        },
        .{
            .name = "glyphs",
            .deps = &.{ .freetype, .assets },
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
            },
        );

        try app.link();

        for (example.deps) |dep| switch (dep) {
            .model3d => app.compile.linkLibrary(b.dependency("mach_model3d", .{
                .target = target,
                .optimize = optimize,
            }).artifact("mach-model3d")),
            .freetype => @import("mach_freetype").linkFreetype(b.dependency("mach_freetype", .{
                .target = target,
                .optimize = optimize,
            }).builder, app.compile),
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

comptime {
    const min_zig = std.SemanticVersion.parse("0.11.0") catch unreachable;
    if (builtin.zig_version.order(min_zig) == .lt) {
        @compileError(std.fmt.comptimePrint("Your Zig version v{} does not meet the minimum build requirement of v{}", .{ builtin.zig_version, min_zig }));
    }
}
