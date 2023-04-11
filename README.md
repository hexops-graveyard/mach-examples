# Mach engine & core examples

<a href="https://user-images.githubusercontent.com/3173176/173177664-2ac9e90b-9429-4b09-aaf9-b80b53fee49f.gif"><img align="left" src="https://user-images.githubusercontent.com/3173176/173177664-2ac9e90b-9429-4b09-aaf9-b80b53fee49f.gif" alt="example-advanced-gen-texture-light" height="190px"></img></a>
<a href="https://user-images.githubusercontent.com/3173176/163936001-fd9eb918-7c29-4dcc-bfcb-5586f2ea1f9a.gif"><img align="left" src="https://user-images.githubusercontent.com/3173176/163936001-fd9eb918-7c29-4dcc-bfcb-5586f2ea1f9a.gif" alt="example-boids" height="190px"></img></a>
<a href="https://user-images.githubusercontent.com/3173176/173177646-a3f0982c-f07b-496f-947b-265bdc71ece9.gif"><img src="https://user-images.githubusercontent.com/3173176/173177646-a3f0982c-f07b-496f-947b-265bdc71ece9.gif" alt="example-textured-cube" height="190px"></img></a>

More screenshots / example showcase: https://machengine.org/gpu

## Run examples

```sh
git clone --recursive https://github.com/hexops/mach-examples
cd mach-examples/
zig build run-textured-cube
```

## Use Mach engine in your own project

First run `zig init-exe` to create your project, then add Mach as a Git submodule:

```
git submodule add https://github.com/hexops/mach libs/mach
```

In your `build.zig`, use `mach.App`:

```zig
const std = @import("std");
const mach = @import("libs/mach/build.zig");

// Needs to be able to return an error with mach so, void -> !void
pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    //from:
    //const exe = b.addExecutable(.{
    //    .name = "myapp",
    //    .root_source_file = .{ .path = "src/main.zig" },
    //    .target = target,
    //    .optimize = optimize,
    //});
    //
    // to:
    const exe = try mach.App.init(b, .{
        .name = "myapp",
        .src = "src/main.zig",
        .target = target,
        .deps = &[_]std.build.ModuleDependency{},
        .optimize = optimize,
    });
    //used to link options if needed
    try exe.link(.{});

    //rest can stay the same
    exe.install();

    const run_cmd = exe.run();

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}
```

Your `src/main.zig` file can now `const mach = @import("mach");` and you can run your code using `zig build run`.

For an example of how to further setup your main.zig to have an update loop etc. look at [Triangle demo's main.zig](https://github.com/hexops/mach-examples/blob/main/core/triangle/main.zig)

## Cross-compilation

You can cross-compile to every OS using:

```sh
zig build -Dtarget=x86_64-windows
zig build -Dtarget=x86_64-linux
zig build -Dtarget=x86_64-macos.12
zig build -Dtarget=aarch64-macos.12
```

## WebAssembly examples

We don't yet support graphics in the browser ([hexops/mach#90](https://github.com/hexops/mach/issues/90)) but you can run the virtual piano example in the browser:

```sh
zig build run-sysaudio -Dtarget=wasm32-freestanding
```

Then navigate to http://localhost:8080/sysaudio.html and click inside the border area + type on your keyboard to play notes.

## Join the community

Join the Mach community [on Discord](https://discord.gg/XNG3NZgCqp) to discuss this project, ask questions, get help, etc.

## Issues

Issues are tracked in the [main Mach repository](https://github.com/hexops/mach/issues?q=is%3Aissue+is%3Aopen+label%3Aexamples).

## Contributing

We're actively looking for contributors to [port WebGPU examples to Zig](https://github.com/hexops/mach/issues/230), and are always looking for useful small examples we can include. If you think you might have one, definitely share it with us so we can consider including it!
