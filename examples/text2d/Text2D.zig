const mach_mod = @import("mach");
const gpu = mach_mod.gpu;
const ft = @import("freetype");
const std = @import("std");

pub const name = .mach_text2d;

// pub const components = .{};

texture_atlas: mach_mod.Atlas,
texture: *gpu.Texture,
ft: ft.Library,
face: ft.Face,
question_region: mach_mod.Atlas.Region,

pub fn machText2DInit(adapter: anytype) !void {
    var mach = adapter.mod(.mach);
    const device = mach.state().device;
    const queue = device.getQueue();

    // rgba32_pixels
    const img_size = gpu.Extent3D{ .width = 1024, .height = 1024 };

    // Create a GPU texture
    const texture = device.createTexture(&.{
        .size = img_size,
        .format = .rgba8_unorm,
        .usage = .{
            .texture_binding = true,
            .copy_dst = true,
            .render_attachment = true,
        },
    });
    const data_layout = gpu.Texture.DataLayout{
        .bytes_per_row = @as(u32, @intCast(img_size.width * 4)),
        .rows_per_image = @as(u32, @intCast(img_size.height)),
    };

    var text2d = adapter.mod(.mach_text2d);
    const s = text2d.state();

    s.texture = texture;
    s.texture_atlas = try mach_mod.Atlas.init(
        adapter.allocator,
        img_size.width,
        .rgba,
    );

    s.ft = try ft.Library.init();
    s.face = try s.ft.createFace("assets/fonts/Roboto-Medium.ttf", 0);

    const font_size = 48 * 1;
    try s.face.setCharSize(font_size * 64, 0, 50, 0);
    try s.face.loadChar('?', .{ .render = true });
    const glyph = s.face.glyph();
    const metrics = glyph.metrics();

    const glyph_bitmap = glyph.bitmap();
    const glyph_width = glyph_bitmap.width();
    const glyph_height = glyph_bitmap.rows();

    // Add 1 pixel padding to texture to avoid bleeding over other textures
    const margin = 1;
    var glyph_data = try adapter.allocator.alloc([4]u8, (glyph_width + (margin * 2)) * (glyph_height + (margin * 2)));
    defer adapter.allocator.free(glyph_data);
    const glyph_buffer = glyph_bitmap.buffer().?;
    for (glyph_data, 0..) |*data, i| {
        const x = i % (glyph_width + (margin * 2));
        const y = i / (glyph_width + (margin * 2));
        if (x < margin or x > (glyph_width + margin) or y < margin or y > (glyph_height + margin)) {
            data.* = [4]u8{ 0, 0, 0, 0 };
        } else {
            const col = 255 - glyph_buffer[((y - margin) * glyph_width + (x - margin)) % glyph_buffer.len];
            data.* = [4]u8{ col, col, col, std.math.maxInt(u8) };
        }
    }
    var glyph_atlas_region = try s.texture_atlas.reserve(adapter.allocator, glyph_width + (margin * 2), glyph_height + (margin * 2));
    s.texture_atlas.set(glyph_atlas_region, @as([*]const u8, @ptrCast(glyph_data.ptr))[0 .. glyph_data.len * 4]);

    glyph_atlas_region.x += margin;
    glyph_atlas_region.y += margin;
    glyph_atlas_region.width -= margin * 2;
    glyph_atlas_region.height -= margin * 2;
    s.question_region = glyph_atlas_region;

    queue.writeTexture(&.{ .texture = s.texture }, &data_layout, &img_size, s.texture_atlas.data);

    _ = metrics;
}

pub fn deinit(adapter: anytype) !void {
    var text2d = adapter.mod(.mach_text2d);
    const s = text2d.state();

    s.texture_atlas.deinit(adapter.allocator);
    s.texture.release();
    s.face.deinit();
    s.ft.deinit();
}
