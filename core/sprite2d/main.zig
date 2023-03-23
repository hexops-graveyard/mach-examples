const std = @import("std");
const mach = @import("mach");
const gpu = mach.gpu;
const zm = @import("zmath");
const zigimg = @import("zigimg");
const assets = @import("assets");

pub const App = @This();

const speed = 2.0 * 100.0; // pixels per second

const Vec2 = @Vector(2, f32);

const UniformBufferObject = struct {
    mat: zm.Mat,
};
const Sprite = extern struct {
    pos: Vec2,
    size: Vec2,
    world_pos: Vec2,
    sheet_size: Vec2,
};
const SpriteSheet = struct {
    width: f32,
    height: f32,
};
var gpa = std.heap.GeneralPurposeAllocator(.{}){};

core: mach.Core,
timer: mach.Timer,
fps_timer: mach.Timer,
window_title_timer: mach.Timer,
pipeline: *gpu.RenderPipeline,
queue: *gpu.Queue,
uniform_buffer: *gpu.Buffer,
bind_group: *gpu.BindGroup,
sprite1: usize,
sprite2: usize,
sheet: SpriteSheet,
sprites_buffer: *gpu.Buffer,
sprites: std.ArrayList(Sprite),
player_pos: Vec2,
direction: Vec2,

pub fn init(app: *App) !void {
    const allocator = gpa.allocator();
    try app.core.init(allocator, .{});

    app.player_pos = Vec2{ 0, 0 };
    app.direction = Vec2{ 0, 0 };
    app.sheet = SpriteSheet{ .width = 384.0, .height = 96.0 };
    app.sprites = std.ArrayList(Sprite).init(allocator);

    app.sprite1 = app.sprites.items.len;
    try app.sprites.append(.{
        .pos = Vec2{ 0, 0 },
        .size = Vec2{ 64, 96 },
        .world_pos = Vec2{ 0, 0 },
        .sheet_size = Vec2{ app.sheet.width, app.sheet.height },
    });

    app.sprite2 = app.sprites.items.len;
    try app.sprites.append(.{
        .pos = Vec2{ 64, 0 },
        .size = Vec2{ 64, 96 },
        .world_pos = Vec2{ 128, 128 },
        .sheet_size = Vec2{ app.sheet.width, app.sheet.height },
    });

    const shader_module = app.core.device().createShaderModuleWGSL("sprite-shader.wgsl", @embedFile("sprite-shader.wgsl"));

    const blend = gpu.BlendState{
        .color = .{
            .operation = .add,
            .src_factor = .src_alpha,
            .dst_factor = .one_minus_src_alpha,
        },
        .alpha = .{
            .operation = .add,
            .src_factor = .one,
            .dst_factor = .zero,
        },
    };
    const color_target = gpu.ColorTargetState{
        .format = app.core.descriptor().format,
        .blend = &blend,
        .write_mask = gpu.ColorWriteMaskFlags.all,
    };
    const fragment = gpu.FragmentState.init(.{
        .module = shader_module,
        .entry_point = "frag_main",
        .targets = &.{color_target},
    });

    const pipeline_descriptor = gpu.RenderPipeline.Descriptor{
        .fragment = &fragment,
        .vertex = gpu.VertexState.init(.{
            .module = shader_module,
            .entry_point = "vertex_main",
        }),
    };
    const pipeline = app.core.device().createRenderPipeline(&pipeline_descriptor);

    const sprites_buffer = app.core.device().createBuffer(&.{
        .usage = .{ .storage = true, .copy_dst = true },
        .size = @sizeOf(Sprite) * app.sprites.items.len,
        .mapped_at_creation = true,
    });
    var sprites_mapped = sprites_buffer.getMappedRange(Sprite, 0, app.sprites.items.len);
    std.mem.copy(Sprite, sprites_mapped.?, app.sprites.items[0..]);
    sprites_buffer.unmap();

    // Create a sampler with linear filtering for smooth interpolation.
    const sampler = app.core.device().createSampler(&.{
        .mag_filter = .linear,
        .min_filter = .linear,
    });
    const queue = app.core.device().getQueue();
    var img = try zigimg.Image.fromMemory(allocator, assets.example_spritesheet_image);
    defer img.deinit();
    const img_size = gpu.Extent3D{ .width = @intCast(u32, img.width), .height = @intCast(u32, img.height) };
    const texture = app.core.device().createTexture(&.{
        .size = img_size,
        .format = .rgba8_unorm,
        .usage = .{
            .texture_binding = true,
            .copy_dst = true,
            .render_attachment = true,
        },
    });
    const data_layout = gpu.Texture.DataLayout{
        .bytes_per_row = @intCast(u32, img.width * 4),
        .rows_per_image = @intCast(u32, img.height),
    };
    switch (img.pixels) {
        .rgba32 => |pixels| queue.writeTexture(&.{ .texture = texture }, &data_layout, &img_size, pixels),
        .rgb24 => |pixels| {
            const data = try rgb24ToRgba32(allocator, pixels);
            defer data.deinit(allocator);
            queue.writeTexture(&.{ .texture = texture }, &data_layout, &img_size, data.rgba32);
        },
        else => @panic("unsupported image color format"),
    }

    const uniform_buffer = app.core.device().createBuffer(&.{
        .usage = .{ .copy_dst = true, .uniform = true },
        .size = @sizeOf(UniformBufferObject),
        .mapped_at_creation = false,
    });

    const bind_group = app.core.device().createBindGroup(
        &gpu.BindGroup.Descriptor.init(.{
            .layout = pipeline.getBindGroupLayout(0),
            .entries = &.{
                gpu.BindGroup.Entry.buffer(0, uniform_buffer, 0, @sizeOf(UniformBufferObject)),
                gpu.BindGroup.Entry.sampler(1, sampler),
                gpu.BindGroup.Entry.textureView(2, texture.createView(&gpu.TextureView.Descriptor{})),
                gpu.BindGroup.Entry.buffer(3, sprites_buffer, 0, @sizeOf(Sprite) * app.sprites.items.len),
            },
        }),
    );

    app.timer = try mach.Timer.start();
    app.fps_timer = try mach.Timer.start();
    app.window_title_timer = try mach.Timer.start();
    app.pipeline = pipeline;
    app.queue = queue;
    app.uniform_buffer = uniform_buffer;
    app.bind_group = bind_group;
    app.sprites_buffer = sprites_buffer;

    shader_module.release();
}

pub fn deinit(app: *App) void {
    defer _ = gpa.deinit();
    defer app.core.deinit();

    app.sprites.deinit();
    app.uniform_buffer.release();
    app.bind_group.release();
    app.sprites_buffer.release();
}

pub fn update(app: *App) !bool {
    // Handle input by determining the direction the player wants to go.
    var iter = app.core.pollEvents();
    while (iter.next()) |event| {
        switch (event) {
            .key_press => |ev| {
                switch (ev.key) {
                    .space => return true,
                    .left => app.direction[0] += 1,
                    .right => app.direction[0] -= 1,
                    .up => app.direction[1] += 1,
                    .down => app.direction[1] -= 1,
                    else => {},
                }
            },
            .key_release => |ev| {
                switch (ev.key) {
                    .left => app.direction[0] -= 1,
                    .right => app.direction[0] += 1,
                    .up => app.direction[1] -= 1,
                    .down => app.direction[1] += 1,
                    else => {},
                }
            },
            .close => return true,
            else => {},
        }
    }

    // Calculate the player position, by moving in the direction the player wants to go
    // by the speed amount. Multiply by delta_time to ensure that movement is the same speed
    // regardless of the frame rate.
    const delta_time = app.fps_timer.lap();
    app.player_pos += app.direction * Vec2{ speed, speed } * Vec2{ delta_time, delta_time };

    // Render the frame
    try app.render();

    // Every second, update the window title with the FPS
    if (app.window_title_timer.read() >= 1.0) {
        app.window_title_timer.reset();
        var buf: [32]u8 = undefined;
        const title = try std.fmt.bufPrintZ(&buf, "Sprite2D [ FPS: {d} ]", .{@floor(1 / delta_time)});
        app.core.setTitle(title);
    }
    return false;
}

fn render(app: *App) !void {
    const back_buffer_view = app.core.swapChain().getCurrentTextureView();
    const color_attachment = gpu.RenderPassColorAttachment{
        .view = back_buffer_view,
        // sky blue background color:
        .clear_value = .{ .r = 0.52, .g = 0.8, .b = 0.92, .a = 1.0 },
        .load_op = .clear,
        .store_op = .store,
    };

    const encoder = app.core.device().createCommandEncoder(null);
    const render_pass_info = gpu.RenderPassDescriptor.init(.{
        .color_attachments = &.{color_attachment},
    });

    const sprite2 = &app.sprites.items[app.sprite2];
    sprite2.world_pos = app.player_pos;

    // One pixel in our scene will equal one window pixel (i.e. be roughly the same size
    // irrespective of whether the user has a Retina/HDPI display.)
    const proj = zm.orthographicRh(
        @intToFloat(f32, app.core.size().width),
        @intToFloat(f32, app.core.size().height),
        0.1,
        1000,
    );
    const view = zm.lookAtRh(
        zm.f32x4(0, 1000, 0, 1),
        zm.f32x4(0, 0, 0, 1),
        zm.f32x4(0, 0, 1, 0),
    );
    const mvp = zm.mul(view, proj);
    const ubo = UniformBufferObject{
        .mat = zm.transpose(mvp),
    };

    // Pass the latest uniform values & sprite values to the shader program.
    encoder.writeBuffer(app.uniform_buffer, 0, &[_]UniformBufferObject{ubo});
    encoder.writeBuffer(app.sprites_buffer, 0, app.sprites.items);

    // Draw the sprite batch
    const total_vertices = @intCast(u32, app.sprites.items.len * 6);
    const pass = encoder.beginRenderPass(&render_pass_info);
    pass.setPipeline(app.pipeline);
    pass.setBindGroup(0, app.bind_group, &.{});
    pass.draw(total_vertices, 1, 0, 0);
    pass.end();
    pass.release();

    // Submit the frame.
    var command = encoder.finish(null);
    encoder.release();
    app.queue.submit(&[_]*gpu.CommandBuffer{command});
    command.release();
    app.core.swapChain().present();
    back_buffer_view.release();
}

fn rgb24ToRgba32(allocator: std.mem.Allocator, in: []zigimg.color.Rgb24) !zigimg.color.PixelStorage {
    const out = try zigimg.color.PixelStorage.init(allocator, .rgba32, in.len);
    var i: usize = 0;
    while (i < in.len) : (i += 1) {
        out.rgba32[i] = zigimg.color.Rgba32{ .r = in[i].r, .g = in[i].g, .b = in[i].b, .a = 255 };
    }
    return out;
}
