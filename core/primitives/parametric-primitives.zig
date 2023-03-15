const std = @import("std");

pub const F32x3 = @Vector(3, f32);
pub const VertexData = struct {
    position : F32x3,
    normal : F32x3,
};

pub const PrimitiveType = enum(u4) {
    none,
    triangle,
    quad,
    plane,
    circle,
    uv_sphere,
    ico_sphere,
    cylinder,
    cone,
    torus
};

pub const Primitive = struct {
    vertex_data : std.ArrayList(VertexData),
    vertex_count : u32,
    index_data : std.ArrayList(u32),
    index_count : u32,
    type : PrimitiveType = .none,
};


pub fn createTrianglePrimitive(allocator : std.mem.Allocator) Primitive {
    var vertex_data : std.ArrayList(VertexData) = undefined;
    if (std.ArrayList(VertexData).initCapacity(allocator, 3)) |array_list| {
        vertex_data = array_list;
    } else |err| {
        std.log.err("mach-examples: error: primitive triangle vertex memory wasn't allocated. Full message {}", .{err});
    }

    vertex_data.appendSliceAssumeCapacity(&[3]VertexData {
        VertexData{.position = F32x3{ -0.5, -0.5, 0.0 }, .normal = F32x3{-0.5, -0.5, 0.0 }},
        VertexData{.position = F32x3{ 0.5, -0.5, 0.0 }, .normal = F32x3{ 0.5, -0.5, 0.0}},
        VertexData{.position = F32x3{ 0.0, 0.5, 0.0 }, .normal = F32x3{ 0.0, 0.5, 0.0}},
    });

    var index_data : std.ArrayList(u32) = undefined;
    if (std.ArrayList(u32).initCapacity(allocator, 3)) |array_list| {
        index_data = array_list;
    } else |err| {
        std.log.err("mach-examples: error: primitive triangle index memory wasn't allocated. Full message {}", .{err});
    }

    index_data.appendSliceAssumeCapacity(&[3]u32 { 0,1,2 });

    return Primitive {
        .vertex_data = vertex_data,
        .vertex_count = 3,
        .index_data = index_data,
        .index_count = 3,
        .type = .triangle
    };
}