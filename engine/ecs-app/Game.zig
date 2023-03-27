const std = @import("std");

// Each module must have a globally unique name declared, it is impossible to use two modules with
// the same name in a program. To avoid name conflicts, we follow naming conventions:
//
// 1. `.mach` and the `.mach_foobar` namespace is reserved for Mach itself and the modules it
//    provides.
// 2. Single-word names like `.renderer`, `.game`, etc. are reserved for the application itself.
// 3. Libraries which provide modules MUST be prefixed with an "owner" name, e.g. `.ziglibs_imgui`
//    instead of `.imgui`. We encourage using e.g. your GitHub name, as these must be globally
//    unique.
//
pub const name = .game;

pub fn init(adapter: anytype) !void {
    std.debug.print("Game.init!\n", .{});

    // The adapter lets us get a type-safe interface to interact with any module in our program.
    var mach = adapter.mod(.mach);
    var renderer = adapter.mod(.renderer);
    var physics2d = adapter.mod(.physics2d);

    // The Mach .core is where we set window options, etc.
    const core = mach.getState(.core);
    core.setTitle("Hello, ECS!");

    // We can get the GPU device:
    const device = mach.getState(.device);
    _ = device; // TODO: actually show off using the GPU device

    // We can create entities, and set components on them. Note that components live in a module
    // namespace, the `.renderer` module `.location` component is a different type than the
    // `.physics2d` module `.location` component.

    const player = try adapter.newEntity();
    try renderer.set(player, .location, .{ .x = 0, .y = 0, .z = 0 });
    try physics2d.set(player, .location, .{ .x = 0, .y = 0 });

    mach.setState(.exit, true);
}
