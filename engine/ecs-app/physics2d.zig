const mach = @import("mach");
const ecs = mach.ecs;
const std = @import("std");

pub const name = .physics2d;

pub const components = .{
    .location = Vec2,
    .rotation = Vec2,
    .velocity = Vec2,
};

pub const Vec2 = extern struct { x: f32, y: f32 };

pub fn tick(adapter: anytype) !void {
    _ = adapter;
    std.log.debug("physics tick!", .{});
}
