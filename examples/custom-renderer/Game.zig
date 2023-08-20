const std = @import("std");
const mach = @import("mach");
const ecs = mach.ecs;
const core = mach.core;
const Renderer = @import("Renderer.zig");

timer: mach.Timer,
player: mach.ecs.EntityID,
direction: Vec2 = .{ 0, 0 },
spawning: bool = false,
spawn_timer: mach.Timer,

pub const components = struct {
    pub const follower = void;
};

// Each module must have a globally unique name declared, it is impossible to use two modules with
// the same name in a program. To avoid name conflicts, we follow naming conventions:
//
// 1. `.mach` and the `.mach_foobar` namespace is reserved for Mach itself and the modules it
//    provides.
// 2. Single-word names like `.renderer`, `.game`, etc. are reserved for the application itself.
// 3. Libraries which provide modules MUST be prefixed with an "owner" name, e.g. `.ziglibs_imgui`
//    instead of `.imgui`. We encourage using e.g. your GitHub name, as these must be globally
//    unique.
//
pub const name = .game;

const Vec2 = @Vector(2, f32);

pub fn init(eng: *mach.Engine) !void {
    // The eng lets us get a type-safe interface to interact with any module in our program.
    var renderer = eng.mod(.renderer);
    var game = eng.mod(.game);

    // The Mach .core is where we set window options, etc.
    core.setTitle("Hello, ECS!");

    // We can create entities, and set components on them. Note that components live in a module
    // namespace, e.g. the `.renderer` module could have a 3D `.location` component with a different
    // type than the `.physics2d` module's `.location` component if you desire.

    const player = try eng.newEntity();
    try renderer.set(player, .location, .{ 0, 0, 0 });
    try renderer.set(player, .scale, 1.0);

    game.initState(.{
        .timer = try mach.Timer.start(),
        .spawn_timer = try mach.Timer.start(),
        .player = player,
    });
}

pub fn tick(eng: *mach.Engine) !void {
    var game = eng.mod(.game);
    var renderer = eng.mod(.renderer); // TODO: why can't this be const?

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
            .close => try eng.send(.machExit),
            else => {},
        }
    }
    game.state().direction = direction;
    game.state().spawning = spawning;

    var player_pos = renderer.get(game.state().player, .location).?;
    if (spawning and game.state().spawn_timer.read() > 1.0 / 60.0) {
        for (0..10) |_| {
            // Spawn a new follower entity
            _ = game.state().spawn_timer.lap();
            const new_entity = try eng.newEntity();
            try game.set(new_entity, .follower, {});
            try renderer.set(new_entity, .location, player_pos);
            try renderer.set(new_entity, .scale, 1.0 / 6.0);
        }
    }

    // Multiply by delta_time to ensure that movement is the same speed regardless of the frame rate.
    const delta_time = game.state().timer.lap();

    // Move following entities closer to us.
    var archetypes_iter = eng.entities.query(.{ .all = &.{
        .{ .game = &.{.follower} },
    } });
    while (archetypes_iter.next()) |archetype| {
        var ids = archetype.slice(.entity, .id);
        var locations = archetype.slice(.renderer, .location);
        for (ids, locations) |id, location| {
            // Avoid other follower entities by moving away from them if they are close to us.
            const close_dist = 1.0 / 15.0;
            var avoidance: Renderer.Vec3 = splat(0);
            var avoidance_div: f32 = 1.0;
            var archetypes_iter_2 = eng.entities.query(.{ .all = &.{
                .{ .game = &.{.follower} },
            } });
            while (archetypes_iter_2.next()) |archetype_2| {
                var other_ids = archetype_2.slice(.entity, .id);
                var other_locations = archetype_2.slice(.renderer, .location);
                for (other_ids, other_locations) |other_id, other_location| {
                    if (id == other_id) continue;
                    if (dist(location, other_location) < close_dist) {
                        avoidance -= dir(location, other_location);
                        avoidance_div += 1.0;
                    }
                }
            }
            // Avoid the player
            var avoid_player_multiplier: f32 = 1.0;
            if (dist(location, player_pos) < close_dist * 6.0) {
                avoidance -= dir(location, player_pos);
                avoidance_div += 1.0;
                avoid_player_multiplier = 4.0;
            }

            // Move away from things we want to avoid
            var move_speed = 1.0 * delta_time;
            var new_location = location + ((avoidance / splat(avoidance_div)) * splat(move_speed * avoid_player_multiplier));

            // Move towards the center
            new_location = moveTowards(new_location, .{ 0, 0, 0 }, move_speed / avoidance_div);
            try renderer.set(id, .location, new_location);
        }
    }

    // Calculate the player position, by moving in the direction the player wants to go
    // by the speed amount.
    const speed = 1.0;
    player_pos[0] += direction[0] * speed * delta_time;
    player_pos[1] += direction[1] * speed * delta_time;
    try renderer.set(game.state().player, .location, player_pos);
}

fn dist(a: Renderer.Vec3, b: Renderer.Vec3) f32 {
    var d = b - a;
    return std.math.sqrt((d[0] * d[0]) + (d[1] * d[1]) + (d[2] * d[2]));
}

/// Moves a towards b by some amount (0.0, 1.0)
fn moveTowards(a: Renderer.Vec3, b: Renderer.Vec3, amount: f32) Renderer.Vec3 {
    return .{
        (a[0] * (1.0 - amount)) + (b[0] * amount),
        (a[1] * (1.0 - amount)) + (b[1] * amount),
        (a[2] * (1.0 - amount)) + (b[2] * amount),
    };
}

fn dir(a: Renderer.Vec3, b: Renderer.Vec3) Renderer.Vec3 {
    return normalize(b - a);
}

fn normalize(a: Renderer.Vec3) Renderer.Vec3 {
    return a / splat(length(a) + 0.0000001);
}

fn length(a: Renderer.Vec3) f32 {
    return std.math.sqrt((a[0] * a[0]) + (a[1] * a[1]) + (a[2] * a[2]));
}

fn splat(a: f32) Renderer.Vec3 {
    return .{ a, a, a };
}

fn eql(a: Renderer.Vec3, b: Renderer.Vec3) bool {
    return a[0] == b[0] and a[1] == b[1] and a[2] == b[2];
}
