const std = @import("std");
const ft = @import("freetype");
const mach = @import("mach");
const math = mach.math;
const vec2 = math.vec2;
const FontRenderer = mach.gfx.FontRenderer;
const RGBA32 = mach.gfx.RGBA32;
const Glyph = mach.gfx.Glyph;
const GlyphMetrics = mach.gfx.GlyphMetrics;

freetype: ft.Library,
faces: FaceMap = .{},

const FTFontManager = @This();

const FaceMap = std.ArrayHashMapUnmanaged(Identifier, Face, Identifier.Context, true);

const Identifier = struct {
    name: []const u8,
    face_index: u8,

    pub const Context = struct {
        pub fn hash(ctx: @This(), v: Identifier) u32 {
            _ = ctx;
            var hasher = std.hash.Wyhash.init(0);
            std.hash.autoHashStrat(&hasher, v.name, .Deep);
            std.hash.autoHash(&hasher, v.face_index);
            return @as(u32, @truncate(hasher.final()));
        }

        pub fn eql(ctx: @This(), a: Identifier, b: Identifier, b_index: usize) bool {
            _ = ctx;
            _ = b_index;
            return a.face_index == b.face_index and std.mem.eql(u8, a.name, b.name);
        }
    };
};

const Face = struct {
    face: ft.Face,
    renderer: FTFontRenderer,
};

pub const FTFontRenderer = struct {
    face: *ft.Face,
    bitmap: std.ArrayList(RGBA32),

    pub fn render(r: *FTFontRenderer, codepoint: u21, size: f32) !Glyph {
        r.face.setCharSize(@intFromFloat(size * 64.0), 0, 0, 0) catch return error.RenderError;
        r.face.loadChar(codepoint, .{ .render = true }) catch return error.RenderError;
        const glyph = r.face.glyph();
        const glyph_bitmap = glyph.bitmap();
        const buffer = glyph_bitmap.buffer();
        const width = glyph_bitmap.width();
        const height = glyph_bitmap.rows();
        const margin = 1;

        if (buffer == null) return .{
            .bitmap = null,
            .width = width + (margin * 2),
            .height = height + (margin * 2),
        };

        // Add 1 pixel padding to texture to avoid bleeding over other textures. This is part of the
        // render() API contract.
        r.bitmap.clearRetainingCapacity();
        const num_pixels = (width + (margin * 2)) * (height + (margin * 2));
        // TODO: handle OOM here
        r.bitmap.ensureTotalCapacity(num_pixels) catch return error.RenderError;
        r.bitmap.resize(num_pixels) catch return error.RenderError;
        for (r.bitmap.items, 0..) |*data, i| {
            const x = i % (width + (margin * 2));
            const y = i / (width + (margin * 2));
            if (x < margin or x > (width + margin) or y < margin or y > (height + margin)) {
                data.* = RGBA32{ .r = 0, .g = 0, .b = 0, .a = 0 };
            } else {
                const alpha = buffer.?[((y - margin) * width + (x - margin)) % buffer.?.len];
                data.* = RGBA32{ .r = 0, .g = 0, .b = 0, .a = alpha };
            }
        }

        return .{
            .bitmap = r.bitmap.items,
            .width = width + (margin * 2),
            .height = height + (margin * 2),
        };
    }

    pub fn measure(r: *const FTFontRenderer, codepoint: u21, size: f32) !GlyphMetrics {
        r.face.setCharSize(@intFromFloat(size * 64.0), 0, 0, 0) catch return error.MeasureError;
        r.face.loadChar(codepoint, .{ .render = false }) catch return error.MeasureError;
        const glyph = r.face.glyph();
        const metrics = glyph.metrics();
        return .{
            .size = vec2(toPixels(metrics.width), toPixels(metrics.height)),
            .advance = vec2(toPixels(metrics.horiAdvance), toPixels(metrics.vertAdvance)),
            .bearing_horizontal = vec2(toPixels(metrics.horiBearingX), toPixels(metrics.horiBearingY)),
            .bearing_vertical = vec2(toPixels(metrics.vertBearingX), toPixels(metrics.vertBearingY)),
        };
    }

    fn toPixels(v: anytype) f32 {
        return @as(f32, @floatFromInt(v)) / 64.0;
    }
};

pub fn init() !FTFontManager {
    return .{
        .freetype = try ft.Library.init(),
    };
}

pub fn deinit(p: *FTFontManager, allocator: std.mem.Allocator) void {
    p.freetype.deinit();
    for (p.faces.entries.items(.value)) |r| r.renderer.bitmap.deinit();
    p.faces.deinit(allocator);
}

/// If true is returned, existing renderers may have been invalidated.
pub fn ensureFontFaceBytes(
    p: *FTFontManager,
    allocator: std.mem.Allocator,
    name: []const u8,
    face_index: u8,
    bytes: []const u8,
) !bool {
    const identifier = Identifier{ .name = name, .face_index = face_index };
    const face = try p.faces.getOrPut(allocator, identifier);
    if (face.found_existing) return false;
    errdefer _ = p.faces.swapRemove(identifier);

    face.value_ptr.* = .{
        .face = try p.freetype.createFaceMemory(bytes, face_index),
        .renderer = FTFontRenderer{
            .face = &face.value_ptr.face,
            .bitmap = std.ArrayList(RGBA32).init(allocator),
        },
    };
    return true;
}

pub fn renderer(
    p: *FTFontManager,
    name: []const u8,
    face_index: u8,
) !FontRenderer {
    const identifier = Identifier{ .name = name, .face_index = face_index };
    const face = p.faces.getPtr(identifier) orelse return error.NoSuchFont;
    return FontRenderer{
        .ptr = &face.renderer,
        .vtable = &FontRenderer.VTable{
            .render = render,
            .measure = measure,
        },
    };
}

fn render(ctx: *anyopaque, codepoint: u21, size: f32) error{RenderError}!Glyph {
    return @as(*FTFontRenderer, @ptrCast(@alignCast(ctx))).render(codepoint, size);
}

fn measure(ctx: *anyopaque, codepoint: u21, size: f32) error{MeasureError}!GlyphMetrics {
    return @as(*FTFontRenderer, @ptrCast(@alignCast(ctx))).measure(codepoint, size);
}
