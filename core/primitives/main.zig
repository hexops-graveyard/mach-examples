const std = @import("std");
const gpu = @import("gpu");
const mach = @import("mach");
const renderer = @import("renderer.zig");

pub const App = @This();
core: mach.Core,

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub fn init(app: *App) !void {
    try app.core.init(gpa.allocator(), .{.required_limits = gpu.Limits 
    { .max_vertex_buffers = 1,
      .max_vertex_attributes = 1
    }});

    renderer.rendererInit(&app.core);
}

pub fn deinit(app: *App) void {
    defer _ = gpa.deinit();
    defer app.core.deinit();

}

pub fn update(app: *App) !bool {
    while (app.core.pollEvents()) |event| {
        switch (event) {
            .key_press => |ev| {
                if (ev.key == .space) return true;
            },
            .close => return true,
            else => {},
        }
    }

    renderer.renderUpdate(&app.core);
    
    return false;
}