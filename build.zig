const std = @import("std");
const mach = @import("mach");

pub fn build(b: *std.Build) !void {
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
                .assets => "assets/assets.zig",
                .model3d => return std.Build.ModuleDependency{
                    .name = "model3d",
                    .module = b2.dependency("mach_model3d", .{
                        .target = target2,
                        .optimize = optimize2,
                    }).module("mach-model3d"),
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
        mach.mach_glfw_import_path = "mach.mach_core.mach_gpu.mach_gpu_dawn.mach_glfw";
        mach.harfbuzz_import_path = "mach.mach_freetype.harfbuzz";
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
