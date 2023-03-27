const std = @import("std");
const mach = @import("mach");
const ecs = mach.ecs;

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

pub const Message = ecs.Messages(.{
    .init = void,
});

pub fn update(adapter: anytype, msg: Message) !void {
    switch (msg) {
        .init => {
            std.debug.print("game init!", .{});
            // The Mach .core is where we set window options, etc.
            const core = adapter.get(.mach, .core);
            core.setTitle("Hello, ECS!");

            // We can get the GPU device:
            const device = adapter.get(.mach, .device);
            _ = device; // TODO: actually show off using the GPU device

            // We can create entities, and set components on them. Note that components live in a module
            // namespace, so we set the `.renderer, .location` component which is different than the
            // `.physics2d, .location` component.

            // TODO: cut out the `.entities.` in this API to make it more brief
            const player = try adapter.entities.new();
            try adapter.entities.setComponent(player, .renderer, .location, .{ .x = 0, .y = 0, .z = 0 });
            try adapter.entities.setComponent(player, .physics2d, .location, .{ .x = 0, .y = 0 });

            // TODO: there could be an entities wrapper to interact with a single namespace so you don't
            // have to pass it in as a parameter always?

            adapter.set(.mach, .exit, true);
        },
    }
}