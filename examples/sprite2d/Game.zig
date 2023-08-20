const std = @import("std");
const zigimg = @import("zigimg");
const assets = @import("assets");
const mach = @import("mach");
const core = mach.core;
const gpu = mach.gpu;
const ecs = mach.ecs;
const Sprite2D = mach.gfx2d.Sprite2D;
const math = mach.math;
const vec = math.vec;
const mat = math.mat;
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Mat3x3 = math.Mat3x3;
const Mat4x4 = math.Mat4x4;

timer: mach.Timer,
player: mach.ecs.EntityID,
direction: Vec2 = .{ 0, 0 },
spawning: bool = false,
spawn_timer: mach.Timer,
fps_timer: mach.Timer,
frame_count: usize,
sprites: usize,
rand: std.rand.DefaultPrng,
time: f32,

const d0 = 0.000001;

// Each module must have a globally unique name declared, it is impossible to use two modules with
// the same name in a program. To avoid name conflicts, we follow naming conventions:
//
// 1. `.mach` and the `.mach_foobar` namespace is reserved for Mach itself and the modules it
//    provides.
// 2. Single-word names like `.game` are reserved for the application itself.
// 3. Libraries which provide modules MUST be prefixed with an "owner" name, e.g. `.ziglibs_imgui`
//    instead of `.imgui`. We encourage using e.g. your GitHub name, as these must be globally
//    unique.
//
pub const name = .game;

pub fn init(adapter: *mach.Engine) !void {
    // The adapter lets us get a type-safe interface to interact with any module in our program.
    var sprite2d = adapter.mod(.mach_sprite2d);
    var game = adapter.mod(.game);

    // The Mach .core is where we set window options, etc.
    core.setTitle("gfx.Sprite2D example");

    // We can create entities, and set components on them. Note that components live in a module
    // namespace, e.g. the `.mach_sprite2d` module could have a 3D `.location` component with a different
    // type than the `.physics2d` module's `.location` component if you desire.

    const player = try adapter.newEntity();
    try sprite2d.set(player, .transform, mat.translate3d(.{ -0.02, 0, 0 }));
    try sprite2d.set(player, .size, Vec2{ 32, 32 });
    try sprite2d.set(player, .uv_transform, mat.translate2d(.{ 0, 0 }));

    try loadTexture(adapter);
    try adapter.send(.machSprite2DInit);

    game.initState(.{
        .timer = try mach.Timer.start(),
        .spawn_timer = try mach.Timer.start(),
        .player = player,
        .fps_timer = try mach.Timer.start(),
        .frame_count = 0,
        .sprites = 0,
        .rand = std.rand.DefaultPrng.init(1337),
        .time = 0,
    });
}

pub fn tick(adapter: *mach.Engine) !void {
    var game = adapter.mod(.game);
    var sprite2d = adapter.mod(.mach_sprite2d); // TODO: why can't this be const?

    // TODO(engine): event polling should occur in mach.Module and get fired as ECS events.
    var iter = core.pollEvents();
    var direction = game.state().direction;
    var spawning = game.state().spawning;
    while (iter.next()) |event| {
        switch (event) {
            .key_press => |ev| {
                switch (ev.key) {
                    .left => direction[0] -= 1,
                    .right => direction[0] += 1,
                    .up => direction[1] += 1,
                    .down => direction[1] -= 1,
                    .space => spawning = true,
                    else => {},
                }
            },
            .key_release => |ev| {
                switch (ev.key) {
                    .left => direction[0] += 1,
                    .right => direction[0] -= 1,
                    .up => direction[1] -= 1,
                    .down => direction[1] += 1,
                    .space => spawning = false,
                    else => {},
                }
            },
            .close => try adapter.send(.machExit),
            else => {},
        }
    }
    game.state().direction = direction;
    game.state().spawning = spawning;

    var player_transform = sprite2d.get(game.state().player, .transform).?;
    var player_pos = mat.translation3d(player_transform);
    if (spawning and game.state().spawn_timer.read() > 1.0 / 60.0) {
        // Spawn new entities
        _ = game.state().spawn_timer.lap();
        for (0..100) |_| {
            var new_pos = player_pos;
            new_pos[0] += game.state().rand.random().floatNorm(f32) * 25;
            new_pos[1] += game.state().rand.random().floatNorm(f32) * 25;

            const new_entity = try adapter.newEntity();
            try sprite2d.set(new_entity, .transform, mat.mul(mat.translate3d(new_pos), mat.scale3d(vec.splat(Vec3, 0.3))));
            try sprite2d.set(new_entity, .size, Vec2{ 32, 32 });
            try sprite2d.set(new_entity, .uv_transform, mat.translate2d(.{ 0, 0 }));
            game.state().sprites += 1;
        }
    }

    // Multiply by delta_time to ensure that movement is the same speed regardless of the frame rate.
    const delta_time = game.state().timer.lap();

    // Rotate entities
    var archetypes_iter = adapter.entities.query(.{ .all = &.{
        .{ .mach_sprite2d = &.{.transform} },
    } });
    while (archetypes_iter.next()) |archetype| {
        var ids = archetype.slice(.entity, .id);
        var transforms = archetype.slice(.mach_sprite2d, .transform);
        for (ids, transforms) |id, *old_transform| {
            _ = id;
            var location = mat.translation3d(old_transform.*);
            // var transform = mat.mul(old_transform, mat.translate3d(-location));
            // transform = mat.mul(mat.rotateZ(0.3 * delta_time), transform);
            // transform = mat.mul(transform, mat.translate3d(location));
            var transform = mat.identity(Mat4x4);
            transform = mat.mul(transform, mat.translate3d(location));
            transform = mat.mul(transform, mat.rotateZ(2 * std.math.pi * game.state().time));
            transform = mat.mul(transform, mat.scale3d(vec.splat(Vec3, @min(std.math.cos(game.state().time / 2.0), 0.5))));

            // TODO: .set() API is substantially slower due to internals
            // try sprite2d.set(id, .transform, transform);
            old_transform.* = transform;
        }
    }

    // Calculate the player position, by moving in the direction the player wants to go
    // by the speed amount.
    const speed = 200.0;
    player_pos[0] += direction[0] * speed * delta_time;
    player_pos[1] += direction[1] * speed * delta_time;
    try sprite2d.set(game.state().player, .transform, mat.translate3d(player_pos));

    // Every second, update the window title with the FPS
    if (game.state().fps_timer.read() >= 1.0) {
        try core.printTitle("gfx.Sprite2D example [ FPS: {d} ] [ Sprites: {d} ]", .{ game.state().frame_count, game.state().sprites });
        game.state().fps_timer.reset();
        game.state().frame_count = 0;
    }
    game.state().frame_count += 1;
    game.state().time += delta_time;
}

// TODO: move this helper into gfx2d module
fn loadTexture(adapter: *mach.Engine) !void {
    var mach_mod = adapter.mod(.mach);
    var sprite2d = adapter.mod(.mach_sprite2d);
    const device = mach_mod.state().device;
    const queue = device.getQueue();

    // Load the image from memory
    var img = try zigimg.Image.fromMemory(adapter.allocator, assets.example_spritesheet_image);
    defer img.deinit();
    const img_size = gpu.Extent3D{ .width = @as(u32, @intCast(img.width)), .height = @as(u32, @intCast(img.height)) };

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
        .bytes_per_row = @as(u32, @intCast(img.width * 4)),
        .rows_per_image = @as(u32, @intCast(img.height)),
    };
    switch (img.pixels) {
        .rgba32 => |pixels| queue.writeTexture(&.{ .texture = texture }, &data_layout, &img_size, pixels),
        .rgb24 => |pixels| {
            const data = try rgb24ToRgba32(adapter.allocator, pixels);
            defer data.deinit(adapter.allocator);
            queue.writeTexture(&.{ .texture = texture }, &data_layout, &img_size, data.rgba32);
        },
        else => @panic("unsupported image color format"),
    }

    // Tell sprite2d to use the texture
    sprite2d.state().texture = texture;
}

fn rgb24ToRgba32(allocator: std.mem.Allocator, in: []zigimg.color.Rgb24) !zigimg.color.PixelStorage {
    const out = try zigimg.color.PixelStorage.init(allocator, .rgba32, in.len);
    var i: usize = 0;
    while (i < in.len) : (i += 1) {
        out.rgba32[i] = zigimg.color.Rgba32{ .r = in[i].r, .g = in[i].g, .b = in[i].b, .a = 255 };
    }
    return out;
}
