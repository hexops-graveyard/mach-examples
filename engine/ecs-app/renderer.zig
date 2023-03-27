const mach = @import("mach");
const ecs = mach.ecs;

pub const name = .renderer;

pub const components = .{
    .location = Vec3,
    .rotation = Vec3,
};

pub const Vec3 = extern struct { x: f32, y: f32, z: f32 };
