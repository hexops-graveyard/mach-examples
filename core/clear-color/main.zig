const std = @import("std");
const mach = @import("mach");
const renderer = @import("renderer.zig");

pub const App = @This();
core: mach.Core,

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub fn init(app: *App) !void {
    try app.core.init(gpa.allocator(), .{});
    renderer.RendererInit(&app.core);
}

pub fn deinit(app: *App) void {
    defer _ = gpa.deinit();
    defer app.core.deinit();
}

pub fn update(app: *App) !bool {
    var iter = app.core.pollEvents();
    while (iter.next()) |event| {
        switch (event) {
            .key_press => |ev| {
                if (ev.key == .space) return true;
            },
            .close => return true,
            else => {},
        }
    }

    renderer.RenderUpdate(&app.core);
    return false;
}
