const std = @import("std");
const gpu = @import("gpu");
const mach = @import("mach");
const renderer = @import("renderer.zig");

pub const App = @This();
core: mach.Core,

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub fn init(app: *App) !void {
    var allocator = gpa.allocator();
    try app.core.init(allocator, .{.required_limits = gpu.Limits 
    { .max_vertex_buffers = 1,
      .max_vertex_attributes = 2
    }});

    renderer.init(&app.core, allocator);
}

pub fn deinit(app: *App) void {
    defer _ = gpa.deinit();
    defer app.core.deinit();
    defer renderer.deinit();

}

pub fn update(app: *App) !bool {
    while (app.core.pollEvents()) |event| {
        switch (event) {
            .key_press => |ev| {
                if (ev.key == .space) return true;
                // TODO(Rok Kos): Improve this, maybe even make ImGui for this
                if (ev.key == .right) {
                    renderer.curr_primitive_index += 1;
                    renderer.curr_primitive_index %= 4;
                }
            },
            .close => return true,
            else => {},
        }
    }

    renderer.update(&app.core);
    
    return false;
}
