const std = @import("std");
const mach = @import("mach");
const gpu = mach.gpu;
const zm = @import("zmath");
const zigimg = @import("zigimg");
const assets = @import("assets");
const imgui = @import("imgui").MachImgui(mach);
const json = std.json;

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
const SpriteFrames = extern struct {
    up: Vec2,
    down: Vec2,
    left: Vec2,
    right: Vec2,
};
const JSONFrames = struct {
    up: []f32,
    down: []f32,
    left: []f32,
    right: []f32,
};
const JSONSprite = struct {
    pos: []f32,
    size: []f32,
    world_pos: []f32,
    is_player: bool = false,
    frames: JSONFrames,
};
const SpriteSheet = struct {
    width: f32,
    height: f32,
};
const JSONData = struct {
    sheet: SpriteSheet,
    sprites: []JSONSprite,
};
const SpriteRenderer = struct {
    const Self = @This();

    pipeline: *gpu.RenderPipeline,
    texture: *gpu.Texture,
    sprites_buffer: ?*gpu.Buffer,
    sprites: std.ArrayList(Sprite),
    bind_group: ?*gpu.BindGroup,
    uniform_buffer: ?*gpu.Buffer,

    fn init(core: *mach.Core, allocator: std.mem.Allocator, queue: *gpu.Queue) !Self {
        const device = core.device();

        var img = try zigimg.Image.fromMemory(allocator, assets.example_spritesheet_image);
        defer img.deinit();

        const img_size = gpu.Extent3D{ .width = @intCast(u32, img.width), .height = @intCast(u32, img.height) };
        std.log.info("Image Dimensions: {} {}", .{ img.width, img.height });

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

        return Self{
            .texture = texture,
            .pipeline = Self.pipeline(core),
            .sprites = std.ArrayList(Sprite).init(allocator),
            .sprites_buffer = null,
            .bind_group = null,
            .uniform_buffer = null,
        };
    }

    fn pipeline(core: *mach.Core) *gpu.RenderPipeline {
        const device = core.device();

        const shader_module = device.createShaderModuleWGSL("sprite-shader.wgsl", @embedFile("sprite-shader.wgsl"));
        // TODO: At the end of the app init, shader_module is being released via shader_module.release() and we need to do that again in this struct

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
            .format = core.descriptor().format,
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
            .depth_stencil = &.{
                .format = .depth24_plus_stencil8,
                .depth_write_enabled = true,
                .depth_compare = .less,
            },
            .vertex = gpu.VertexState.init(.{
                .module = shader_module,
                .entry_point = "vertex_main",
            }),
        };
        return device.createRenderPipeline(&pipeline_descriptor);
    }

    fn addSpriteFromJSON(self: *Self, sprite: JSONSprite, sheet: SpriteSheet) !void {
        try self.sprites.append(.{
            .pos = Vec2{ sprite.pos[0], sprite.pos[1] },
            .size = Vec2{ sprite.size[0], sprite.size[1] },
            .world_pos = Vec2{ sprite.world_pos[0], sprite.world_pos[1] },
            .sheet_size = Vec2{ sheet.width, sheet.height },
        });
    }

    fn initSpritesBuffer(self: *Self, core: *mach.Core) void {
        const sprites_buffer = core.device().createBuffer(&.{
            .usage = .{ .storage = true, .copy_dst = true },
            .size = @sizeOf(Sprite) * self.sprites.items.len,
            .mapped_at_creation = true,
        });
        var sprites_mapped = sprites_buffer.getMappedRange(Sprite, 0, self.sprites.items.len);
        std.mem.copy(Sprite, sprites_mapped.?, self.sprites.items[0..]);
        sprites_buffer.unmap();

        self.sprites_buffer = sprites_buffer;
    }

    fn initBindGroup(self: *Self, core: *mach.Core) void {
        const uniform_buffer = core.device().createBuffer(&.{
            .usage = .{ .copy_dst = true, .uniform = true },
            .size = @sizeOf(UniformBufferObject),
            .mapped_at_creation = false,
        });

        self.uniform_buffer = uniform_buffer;

        // Create a sampler with linear filtering for smooth interpolation.
        const sampler = core.device().createSampler(&.{
            .mag_filter = .linear,
            .min_filter = .linear,
        });

        const bind_group = core.device().createBindGroup(
            &gpu.BindGroup.Descriptor.init(.{
                .layout = self.pipeline.getBindGroupLayout(0),
                .entries = &.{
                    gpu.BindGroup.Entry.buffer(0, self.uniform_buffer.?, 0, @sizeOf(UniformBufferObject)),
                    gpu.BindGroup.Entry.sampler(1, sampler),
                    gpu.BindGroup.Entry.textureView(2, self.texture.createView(&gpu.TextureView.Descriptor{})),
                    gpu.BindGroup.Entry.buffer(3, self.sprites_buffer.?, 0, @sizeOf(Sprite) * self.sprites.items.len),
                },
            }),
        );

        self.bind_group = bind_group;
    }

    fn getSprite(self: *Self, index: usize) *Sprite {
        return &self.sprites.items[index];
    }

    fn deinit(self: *Self) void {
        self.sprites.deinit();
        // if (self.sprites_buffer != null) {
        //     self.sprites_buffer.deinit();
        // }
        // if (self.uniform_buffer != null) {
        //     self.uniform_buffer.deinit();
        // }
        // if (self.bind_group != null) {
        //     self.bind_group.deinit();
        // }
    }

    fn getTotalVertices(self: *Self) u32 {
        return @intCast(u32, self.sprites.items.len * 6);
    }
};
const SpriteRendererRed = struct {
    const Self = @This();

    pipeline: *gpu.RenderPipeline,
    texture: *gpu.Texture,
    sprites_buffer: ?*gpu.Buffer,
    sprites: std.ArrayList(Sprite),
    bind_group: ?*gpu.BindGroup,
    uniform_buffer: ?*gpu.Buffer,

    fn init(core: *mach.Core, allocator: std.mem.Allocator, queue: *gpu.Queue) !Self {
        const device = core.device();

        var img = try zigimg.Image.fromMemory(allocator, assets.example_spritesheet_red_image);
        defer img.deinit();

        const img_size = gpu.Extent3D{ .width = @intCast(u32, img.width), .height = @intCast(u32, img.height) };
        std.log.info("Image Dimensions: {} {}", .{ img.width, img.height });

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

        return Self{
            .texture = texture,
            .pipeline = Self.pipeline(core),
            .sprites = std.ArrayList(Sprite).init(allocator),
            .sprites_buffer = null,
            .bind_group = null,
            .uniform_buffer = null,
        };
    }

    fn pipeline(core: *mach.Core) *gpu.RenderPipeline {
        const device = core.device();

        const shader_module = device.createShaderModuleWGSL("world-shader.wgsl", @embedFile("world-shader.wgsl"));
        // TODO: At the end of the app init, shader_module is being released via shader_module.release() and we need to do that again in this struct

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
            .format = core.descriptor().format,
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
            .depth_stencil = &.{
                .format = .depth24_plus_stencil8,
                .depth_write_enabled = true,
                .depth_compare = .less,
            },
            .vertex = gpu.VertexState.init(.{
                .module = shader_module,
                .entry_point = "vertex_main",
            }),
        };
        return device.createRenderPipeline(&pipeline_descriptor);
    }

    fn addSpriteFromJSON(self: *Self, sprite: JSONSprite, sheet: SpriteSheet) !void {
        try self.sprites.append(.{
            .pos = Vec2{ sprite.pos[0], sprite.pos[1] },
            .size = Vec2{ sprite.size[0], sprite.size[1] },
            .world_pos = Vec2{ sprite.world_pos[0], sprite.world_pos[1] },
            .sheet_size = Vec2{ sheet.width, sheet.height },
        });
    }

    fn initSpritesBuffer(self: *Self, core: *mach.Core) void {
        const sprites_buffer = core.device().createBuffer(&.{
            .usage = .{ .storage = true, .copy_dst = true },
            .size = @sizeOf(Sprite) * self.sprites.items.len,
            .mapped_at_creation = true,
        });
        var sprites_mapped = sprites_buffer.getMappedRange(Sprite, 0, self.sprites.items.len);
        std.mem.copy(Sprite, sprites_mapped.?, self.sprites.items[0..]);
        sprites_buffer.unmap();

        self.sprites_buffer = sprites_buffer;
    }

    fn initBindGroup(self: *Self, core: *mach.Core) void {
        const uniform_buffer = core.device().createBuffer(&.{
            .usage = .{ .copy_dst = true, .uniform = true },
            .size = @sizeOf(UniformBufferObject),
            .mapped_at_creation = false,
        });

        self.uniform_buffer = uniform_buffer;

        // Create a sampler with linear filtering for smooth interpolation.
        const sampler = core.device().createSampler(&.{
            .mag_filter = .linear,
            .min_filter = .linear,
        });

        const bind_group = core.device().createBindGroup(
            &gpu.BindGroup.Descriptor.init(.{
                .layout = self.pipeline.getBindGroupLayout(0),
                .entries = &.{
                    gpu.BindGroup.Entry.buffer(0, self.uniform_buffer.?, 0, @sizeOf(UniformBufferObject)),
                    gpu.BindGroup.Entry.sampler(1, sampler),
                    gpu.BindGroup.Entry.textureView(2, self.texture.createView(&gpu.TextureView.Descriptor{})),
                    gpu.BindGroup.Entry.buffer(3, self.sprites_buffer.?, 0, @sizeOf(Sprite) * self.sprites.items.len),
                },
            }),
        );

        self.bind_group = bind_group;
    }

    fn getSprite(self: *Self, index: usize) *Sprite {
        return &self.sprites.items[index];
    }

    fn deinit(self: *Self) void {
        self.sprites.deinit();
        // if (self.sprites_buffer != null) {
        //     self.sprites_buffer.deinit();
        // }
        // if (self.uniform_buffer != null) {
        //     self.uniform_buffer.deinit();
        // }
        // if (self.bind_group != null) {
        //     self.bind_group.deinit();
        // }
    }

    fn getTotalVertices(self: *Self) u32 {
        return @intCast(u32, self.sprites.items.len * 6);
    }
};
// const Player = struct {
//     pos: vec2,
//     direction: f32,
// };
var gpa = std.heap.GeneralPurposeAllocator(.{}){};

core: mach.Core,
timer: mach.Timer,
fps_timer: mach.Timer,
window_title_timer: mach.Timer,
queue: *gpu.Queue,
sheet: SpriteSheet,
player_pos: Vec2,
direction: Vec2,
player_sprite_index: usize,
sprite_renderer: SpriteRenderer,
sprite_renderer_red: SpriteRendererRed,
sprites_frames: std.ArrayList(SpriteFrames),
allocator: std.mem.Allocator,
imgui_render_pipeline: *gpu.RenderPipeline,
color_attachment: gpu.RenderPassColorAttachment,
depth_stencil_attachment_description: gpu.RenderPassDepthStencilAttachment,
depth_texture: *gpu.Texture,
depth_texture_view: *gpu.TextureView,

pub fn init(app: *App) !void {
    app.allocator = gpa.allocator();
    try app.core.init(app.allocator, .{});

    const queue = app.core.device().getQueue();
    app.queue = queue;

    app.sprite_renderer = try SpriteRenderer.init(&app.core, app.allocator, app.queue);
    app.sprite_renderer_red = try SpriteRendererRed.init(&app.core, app.allocator, app.queue);

    const sprites_file = try std.fs.cwd().openFile(assets.example_spritesheet_json_path, .{ .mode = .read_only });
    defer sprites_file.close();
    const file_size = (try sprites_file.stat()).size;
    var buffer = try app.allocator.alloc(u8, file_size);
    defer app.allocator.free(buffer);
    try sprites_file.reader().readNoEof(buffer);
    var stream = std.json.TokenStream.init(buffer);
    const root = try std.json.parse(JSONData, &stream, .{ .allocator = app.allocator });
    defer std.json.parseFree(JSONData, root, .{ .allocator = app.allocator });

    app.player_pos = Vec2{ 0, 0 };
    app.direction = Vec2{ 0, 0 };
    app.sheet = root.sheet;
    std.log.info("Sheet Dimensions: {} {}", .{ app.sheet.width, app.sheet.height });
    app.sprites_frames = std.ArrayList(SpriteFrames).init(app.allocator);
    for (root.sprites) |sprite| {
        std.log.info("Typeof Sprite {}", .{@TypeOf(sprite)});
        std.log.info("Sprite World Position: {} {}", .{ sprite.world_pos[0], sprite.world_pos[1] });
        std.log.info("Sprite Texture Position: {} {}", .{ sprite.pos[0], sprite.pos[1] });
        std.log.info("Sprite Dimensions: {} {}", .{ sprite.size[0], sprite.size[1] });
        if (sprite.is_player) {
            app.player_sprite_index = app.sprite_renderer.sprites.items.len;
        }
        try app.sprite_renderer.addSpriteFromJSON(sprite, app.sheet);
        try app.sprite_renderer_red.addSpriteFromJSON(sprite, app.sheet);
        try app.sprites_frames.append(.{ .up = Vec2{ sprite.frames.up[0], sprite.frames.up[1] }, .down = Vec2{ sprite.frames.down[0], sprite.frames.down[1] }, .left = Vec2{ sprite.frames.left[0], sprite.frames.left[1] }, .right = Vec2{ sprite.frames.right[0], sprite.frames.right[1] } });
    }
    std.log.info("Number of sprites: {}", .{app.sprite_renderer.sprites.items.len});

    app.sprite_renderer.initSpritesBuffer(&app.core);
    app.sprite_renderer_red.initSpritesBuffer(&app.core);

    app.sprite_renderer.initBindGroup(&app.core);
    app.sprite_renderer_red.initBindGroup(&app.core);

    imgui.init(gpa.allocator());
    const font_normal = imgui.io.addFontFromFile(assets.fonts.roboto_medium.path, 18.0);
    const blend_component_descriptor = gpu.BlendComponent{
        .operation = .add,
        .src_factor = .one,
        .dst_factor = .zero,
    };
    const color_target_state = gpu.ColorTargetState{
        .format = app.core.descriptor().format,
        .blend = &.{
            .color = blend_component_descriptor,
            .alpha = blend_component_descriptor,
        },
    };
    const shader_module = app.core.device().createShaderModuleWGSL("imgui", assets.shaders.imgui.bytes);
    const imgui_pipeline_descriptor = gpu.RenderPipeline.Descriptor{
        .depth_stencil = &.{
            .format = .depth24_plus_stencil8,
            .depth_write_enabled = true,
        },
        .fragment = &gpu.FragmentState.init(.{
            .module = shader_module,
            .entry_point = "frag_main",
            .targets = &.{color_target_state},
        }),
        .vertex = gpu.VertexState.init(.{
            .module = shader_module,
            .entry_point = "vert_main",
        }),
    };
    app.imgui_render_pipeline = app.core.device().createRenderPipeline(&imgui_pipeline_descriptor);
    shader_module.release();
    imgui.io.setDefaultFont(font_normal);
    imgui.mach_backend.init(app.core.device(), app.core.descriptor().format, .{
        .depth_stencil_format = @enumToInt(gpu.Texture.Format.depth24_plus_stencil8),
    });

    setupRenderPass(app);

    app.timer = try mach.Timer.start();
    app.fps_timer = try mach.Timer.start();
    app.window_title_timer = try mach.Timer.start();
    app.queue = queue;
}

pub fn deinit(app: *App) void {
    defer _ = gpa.deinit();
    defer app.core.deinit();

    app.sprite_renderer.deinit();
    app.sprite_renderer_red.deinit();
    app.sprites_frames.deinit();
}

fn drawUI() void {
    imgui.setNextWindowPos(.{ .x = 0, .y = 0 });
    if (!imgui.begin("Settings", .{})) {
        imgui.end();
        return;
    }

    imgui.text("Text render!", .{});

    imgui.end();
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

fn setupRenderPass(app: *App) void {
    app.color_attachment = gpu.RenderPassColorAttachment{
        .clear_value = .{
            .r = 0.0,
            .g = 0.0,
            .b = 0.0,
            .a = 0.0,
        },
        .load_op = .clear,
        .store_op = .store,
    };

    app.depth_texture = app.core.device().createTexture(&.{
        .usage = .{ .render_attachment = true, .copy_src = true },
        .format = .depth24_plus_stencil8,
        .sample_count = 1,
        .size = .{
            .width = app.core.descriptor().width,
            .height = app.core.descriptor().height,
            .depth_or_array_layers = 1,
        },
    });

    app.depth_texture_view = app.depth_texture.createView(&.{
        .format = .depth24_plus_stencil8,
        .dimension = .dimension_2d,
        .array_layer_count = 1,
        .aspect = .all,
    });

    app.depth_stencil_attachment_description = gpu.RenderPassDepthStencilAttachment{
        .view = app.depth_texture_view,
        .depth_load_op = .clear,
        .depth_store_op = .store,
        .depth_clear_value = 1.0,
        .stencil_clear_value = 0,
        .stencil_load_op = .clear,
        .stencil_store_op = .store,
    };
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
        .depth_stencil_attachment = &app.depth_stencil_attachment_description,
    });

    const player_sprite = &app.sprite_renderer.sprites.items[app.player_sprite_index];
    const player_sprite_frame = &app.sprites_frames.items[app.player_sprite_index];
    if (app.direction[0] == -1.0) {
        player_sprite.pos = player_sprite_frame.up;
    } else if (app.direction[0] == 1.0) {
        player_sprite.pos = player_sprite_frame.down;
    } else if (app.direction[1] == -1.0) {
        player_sprite.pos = player_sprite_frame.left;
    } else if (app.direction[1] == 1.0) {
        player_sprite.pos = player_sprite_frame.right;
    }
    player_sprite.world_pos = app.player_pos;

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
    encoder.writeBuffer(app.sprite_renderer.uniform_buffer.?, 0, &[_]UniformBufferObject{ubo});
    encoder.writeBuffer(app.sprite_renderer.sprites_buffer.?, 0, app.sprite_renderer.sprites.items);
    encoder.writeBuffer(app.sprite_renderer_red.uniform_buffer.?, 0, &[_]UniformBufferObject{ubo});
    encoder.writeBuffer(app.sprite_renderer_red.sprites_buffer.?, 0, app.sprite_renderer_red.sprites.items);
    // TODO: Maybe we need something like the update function in structs in advanced-gen-texture-light where the queue is written into?

    // Draw the sprite batch
    const pass = encoder.beginRenderPass(&render_pass_info);
    defer pass.release();

    pass.setPipeline(app.sprite_renderer.pipeline);
    pass.setBindGroup(0, app.sprite_renderer.bind_group.?, &.{});
    pass.draw(app.sprite_renderer.getTotalVertices(), 1, 0, 0);

    pass.setPipeline(app.sprite_renderer_red.pipeline);
    pass.setBindGroup(0, app.sprite_renderer_red.bind_group.?, &.{});
    pass.draw(app.sprite_renderer_red.getTotalVertices(), 1, 0, 0);

    pass.setPipeline(app.imgui_render_pipeline);
    const window_size = app.core.size();
    imgui.mach_backend.newFrame(
        &app.core,
        window_size.width,
        window_size.height,
    );
    drawUI();
    imgui.mach_backend.draw(pass);

    pass.end();

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
