const std = @import("std");
const mach = @import("mach");
const core = mach.core;
const gpu = mach.gpu;
const ecs = mach.ecs;
const Sprite2D = mach.gfx2d.Sprite2D;
const math = mach.math;
const vec2 = math.vec2;
const vec3 = math.vec3;
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Mat3x3 = math.Mat3x3;
const Mat4x4 = math.Mat4x4;

timer: mach.Timer,
player: mach.ecs.EntityID,
direction: Vec2 = vec2(0, 0),
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

pub const Pipeline = enum(u32) {
    default,
    text,
};

pub fn init(
    engine: *mach.Mod(.engine),
    sprite2d: *mach.Mod(.engine_sprite2d),
    text2d: *mach.Mod(.engine_text2d),
    game: *mach.Mod(.game),
) !void {
    // The Mach .core is where we set window options, etc.
    core.setTitle("gfx.Sprite2D example");

    // Initialize text2D texture
    try text2d.send(.init, .{});

    // Tell sprite2d to use the texture
    try sprite2d.send(.init, .{});
    try sprite2d.send(.initPipeline, .{Sprite2D.PipelineOptions{
        .pipeline = @intFromEnum(Pipeline.text),
        .texture = text2d.state.texture,
    }});

    // We can create entities, and set components on them. Note that components live in a module
    // namespace, e.g. the `.engine_sprite2d` module could have a 3D `.location` component with a different
    // type than the `.physics2d` module's `.location` component if you desire.

    const r = text2d.state.regions.get('?').?;
    const player = try engine.newEntity();
    try sprite2d.set(player, .transform, Mat4x4.translate(vec3(-0.02, 0, 0)));
    try sprite2d.set(player, .size, vec2(@floatFromInt(r.width), @floatFromInt(r.height)));
    try sprite2d.set(player, .uv_transform, Mat3x3.translate(vec2(@floatFromInt(r.x), @floatFromInt(r.y))));
    try sprite2d.set(player, .pipeline, @intFromEnum(Pipeline.text));
    try sprite2d.send(.updated, .{@intFromEnum(Pipeline.text)});

    game.state = .{
        .timer = try mach.Timer.start(),
        .spawn_timer = try mach.Timer.start(),
        .player = player,
        .fps_timer = try mach.Timer.start(),
        .frame_count = 0,
        .sprites = 0,
        .rand = std.rand.DefaultPrng.init(1337),
        .time = 0,
    };
}

pub fn tick(
    engine: *mach.Mod(.engine),
    sprite2d: *mach.Mod(.engine_sprite2d),
    text2d: *mach.Mod(.engine_text2d),
    game: *mach.Mod(.game),
) !void {
    // TODO(engine): event polling should occur in mach.Engine module and get fired as ECS events.
    var iter = core.pollEvents();
    var direction = game.state.direction;
    var spawning = game.state.spawning;
    while (iter.next()) |event| {
        switch (event) {
            .key_press => |ev| {
                switch (ev.key) {
                    .left => direction.v[0] -= 1,
                    .right => direction.v[0] += 1,
                    .up => direction.v[1] += 1,
                    .down => direction.v[1] -= 1,
                    .space => spawning = true,
                    else => {},
                }
            },
            .key_release => |ev| {
                switch (ev.key) {
                    .left => direction.v[0] += 1,
                    .right => direction.v[0] -= 1,
                    .up => direction.v[1] -= 1,
                    .down => direction.v[1] += 1,
                    .space => spawning = false,
                    else => {},
                }
            },
            .close => try engine.send(.exit, .{}),
            else => {},
        }
    }
    game.state.direction = direction;
    game.state.spawning = spawning;

    var player_transform = sprite2d.get(game.state.player, .transform).?;
    var player_pos = player_transform.translation();
    if (!spawning and game.state.spawn_timer.read() > 1.0 / 60.0) {
        // Spawn new entities
        _ = game.state.spawn_timer.lap();
        for (0..50) |_| {
            var new_pos = player_pos;
            new_pos.v[0] += game.state.rand.random().floatNorm(f32) * 25;
            new_pos.v[1] += game.state.rand.random().floatNorm(f32) * 25;

            const rand_index = game.state.rand.random().intRangeAtMost(usize, 0, text2d.state.regions.count() - 1);
            const r = text2d.state.regions.entries.get(rand_index).value;

            const new_entity = try engine.newEntity();
            try sprite2d.set(new_entity, .transform, Mat4x4.translate(new_pos).mul(&Mat4x4.scaleScalar(0.3)));
            try sprite2d.set(new_entity, .size, vec2(@floatFromInt(r.width), @floatFromInt(r.height)));
            try sprite2d.set(new_entity, .uv_transform, Mat3x3.translate(vec2(@floatFromInt(r.x), @floatFromInt(r.y))));
            try sprite2d.set(new_entity, .pipeline, @intFromEnum(Pipeline.text));
            game.state.sprites += 1;
        }
    }

    // Multiply by delta_time to ensure that movement is the same speed regardless of the frame rate.
    const delta_time = game.state.timer.lap();

    // Animate entities
    var archetypes_iter = engine.entities.query(.{ .all = &.{
        .{ .engine_sprite2d = &.{.transform} },
    } });
    while (archetypes_iter.next()) |archetype| {
        var ids = archetype.slice(.entity, .id);
        var transforms = archetype.slice(.engine_sprite2d, .transform);
        for (ids, transforms) |id, *old_transform| {
            var location = old_transform.translation();
            if (location.x() < -@as(f32, @floatFromInt(core.size().width)) / 1.5 or location.x() > @as(f32, @floatFromInt(core.size().width)) / 1.5 or location.y() < -@as(f32, @floatFromInt(core.size().height)) / 1.5 or location.y() > @as(f32, @floatFromInt(core.size().height)) / 1.5) {
                try engine.entities.remove(id);
                game.state.sprites -= 1;
                continue;
            }

            var transform = Mat4x4.ident;
            transform = transform.mul(&Mat4x4.scale(Vec3.splat(1.0 + (0.2 * delta_time))));
            transform = transform.mul(&Mat4x4.translate(location));
            transform = transform.mul(&Mat4x4.rotateZ(2 * math.pi * game.state.time));
            transform = transform.mul(&Mat4x4.scale(Vec3.splat(@max(math.cos(game.state.time / 2.0), 0.2))));

            // TODO: .set() API is substantially slower due to internals
            // try sprite2d.set(id, .transform, transform);
            old_transform.* = transform;
        }
    }

    // Calculate the player position, by moving in the direction the player wants to go
    // by the speed amount.
    const speed = 200.0;
    player_pos.v[0] += direction.x() * speed * delta_time;
    player_pos.v[1] += direction.y() * speed * delta_time;
    player_transform = Mat4x4.translate(player_pos).mul(
        &Mat4x4.scale(Vec3.splat(1.0)),
    );
    try sprite2d.set(game.state.player, .transform, player_transform);

    try sprite2d.send(.updated, .{@intFromEnum(Pipeline.text)});

    // Perform pre-render work
    try sprite2d.send(.preRender, .{@intFromEnum(Pipeline.text)});

    // Render a frame
    try engine.send(.beginPass, .{gpu.Color{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 }});
    try sprite2d.send(.render, .{@intFromEnum(Pipeline.text)});
    try engine.send(.endPass, .{});
    try engine.send(.present, .{}); // Present the frame

    // Every second, update the window title with the FPS
    if (game.state.fps_timer.read() >= 1.0) {
        try core.printTitle("gfx.Sprite2D example [ FPS: {d} ] [ Sprites: {d} ]", .{ game.state.frame_count, game.state.sprites });
        game.state.fps_timer.reset();
        game.state.frame_count = 0;
    }
    game.state.frame_count += 1;
    game.state.time += delta_time;
}
