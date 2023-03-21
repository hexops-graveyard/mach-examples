const std = @import("std");
const zmath = @import("zmath");

const PI = 3.1415927410125732421875;

pub const F32x3 = @Vector(3, f32);
pub const F32x4 = @Vector(4, f32);
pub const VertexData = struct {
    position: F32x3,
    normal: F32x3,
};

pub const PrimitiveType = enum(u4) { none, triangle, quad, plane, circle, uv_sphere, ico_sphere, cylinder, cone, torus };

pub const Primitive = struct {
    vertex_data: std.ArrayList(VertexData),
    vertex_count: u32,
    index_data: std.ArrayList(u32),
    index_count: u32,
    type: PrimitiveType = .none,
};

// 2D Primitives
pub fn createTrianglePrimitive(allocator: std.mem.Allocator, size: f32) !Primitive {
    const vertex_count = 3;
    const index_count = 3;
    var vertex_data = try std.ArrayList(VertexData).initCapacity(allocator, vertex_count);

    const edge = size / 2.0;

    vertex_data.appendSliceAssumeCapacity(&[vertex_count]VertexData{
        VertexData{ .position = F32x3{ -edge, -edge, 0.0 }, .normal = F32x3{ -edge, -edge, 0.0 } },
        VertexData{ .position = F32x3{ edge, -edge, 0.0 }, .normal = F32x3{ edge, -edge, 0.0 } },
        VertexData{ .position = F32x3{ 0.0, edge, 0.0 }, .normal = F32x3{ 0.0, edge, 0.0 } },
    });

    var index_data = try std.ArrayList(u32).initCapacity(allocator, index_count);
    index_data.appendSliceAssumeCapacity(&[index_count]u32{ 0, 1, 2 });

    return Primitive{ .vertex_data = vertex_data, .vertex_count = 3, .index_data = index_data, .index_count = 3, .type = .triangle };
}

pub fn createQuadPrimitive(allocator: std.mem.Allocator, size: f32) !Primitive {
    const vertex_count = 4;
    const index_count = 6;
    var vertex_data = try std.ArrayList(VertexData).initCapacity(allocator, vertex_count);

    const edge = size / 2.0;

    vertex_data.appendSliceAssumeCapacity(&[vertex_count]VertexData{
        VertexData{ .position = F32x3{ -edge, -edge, 0.0 }, .normal = F32x3{ -edge, -edge, 0.0 } },
        VertexData{ .position = F32x3{ edge, -edge, 0.0 }, .normal = F32x3{ edge, -edge, 0.0 } },
        VertexData{ .position = F32x3{ -edge, edge, 0.0 }, .normal = F32x3{ -edge, edge, 0.0 } },
        VertexData{ .position = F32x3{ edge, edge, 0.0 }, .normal = F32x3{ edge, edge, 0.0 } },
    });

    var index_data = try std.ArrayList(u32).initCapacity(allocator, index_count);
    index_data.appendSliceAssumeCapacity(&[index_count]u32{
        0, 1, 2,
        1, 3, 2,
    });

    return Primitive{ .vertex_data = vertex_data, .vertex_count = 4, .index_data = index_data, .index_count = 6, .type = .quad };
}

pub fn createPlanePrimitive(allocator: std.mem.Allocator, x_subdivision: u32, y_subdivision: u32, size: f32) !Primitive {
    const x_num_vertices = x_subdivision + 1;
    const y_num_vertices = y_subdivision + 1;
    const vertex_count = x_num_vertices * y_num_vertices;
    var vertex_data = try std.ArrayList(VertexData).initCapacity(allocator, vertex_count);

    const vertices_distance_y = (size / @intToFloat(f32, y_subdivision));
    const vertices_distance_x = (size / @intToFloat(f32, x_subdivision));
    var y: u32 = 0;
    while (y < y_num_vertices) : (y += 1) {
        var x: u32 = 0;
        const pos_y = (-size / 2.0) + @intToFloat(f32, y) * vertices_distance_y;
        while (x < x_num_vertices) : (x += 1) {
            const pos_x = (-size / 2.0) + @intToFloat(f32, x) * vertices_distance_x;
            vertex_data.appendAssumeCapacity(VertexData{ .position = F32x3{ pos_x, pos_y, 0.0 }, .normal = F32x3{ pos_x, pos_y, 0.0 } });
        }
    }

    const index_count = x_subdivision * y_subdivision * 2 * 3;
    var index_data = try std.ArrayList(u32).initCapacity(allocator, index_count);

    y = 0;
    while (y < y_subdivision) : (y += 1) {
        var x: u32 = 0;
        while (x < x_subdivision) : (x += 1) {
            // First Triangle of Quad
            index_data.appendAssumeCapacity(x + y * y_num_vertices);
            index_data.appendAssumeCapacity(x + 1 + y * y_num_vertices);
            index_data.appendAssumeCapacity(x + (y + 1) * y_num_vertices);

            // Second Triangle of Quad
            index_data.appendAssumeCapacity(x + 1 + y * y_num_vertices);
            index_data.appendAssumeCapacity(x + (y + 1) * y_num_vertices + 1);
            index_data.appendAssumeCapacity(x + (y + 1) * y_num_vertices);
        }
    }

    return Primitive{ .vertex_data = vertex_data, .vertex_count = vertex_count, .index_data = index_data, .index_count = index_count, .type = .plane };
}

pub fn createCirclePrimitive(allocator: std.mem.Allocator, vertices: u32, radius: f32) !Primitive {
    const vertex_count = vertices + 1;
    var vertex_data = try std.ArrayList(VertexData).initCapacity(allocator, vertex_count);

    // Mid point of circle
    vertex_data.appendAssumeCapacity(VertexData{ .position = F32x3{ 0, 0, 0.0 }, .normal = F32x3{ 0, 0, 0.0 } });

    var x: u32 = 0;
    var angle = 2 * PI / @intToFloat(f32, vertices);
    while (x < vertices) : (x += 1) {
        const x_f = @intToFloat(f32, x);
        const pos_x = radius * zmath.cos(angle * x_f);
        const pos_y = radius * zmath.sin(angle * x_f);

        vertex_data.appendAssumeCapacity(VertexData{ .position = F32x3{ pos_x, pos_y, 0.0 }, .normal = F32x3{ pos_x, pos_y, 0.0 } });
    }

    const index_count = (vertices + 1) * 3;
    var index_data = try std.ArrayList(u32).initCapacity(allocator, index_count);

    x = 1;
    while (x <= vertices) : (x += 1) {
        index_data.appendAssumeCapacity(0);
        index_data.appendAssumeCapacity(x);
        index_data.appendAssumeCapacity(x + 1);
    }

    index_data.appendAssumeCapacity(0);
    index_data.appendAssumeCapacity(vertices);
    index_data.appendAssumeCapacity(1);

    return Primitive{ .vertex_data = vertex_data, .vertex_count = vertex_count, .index_data = index_data, .index_count = index_count, .type = .plane };
}

// 3D Primitives
pub fn createCubePrimitive(allocator: std.mem.Allocator, size: f32) !Primitive {
    const vertex_count = 8;
    const index_count = 36;
    var vertex_data = try std.ArrayList(VertexData).initCapacity(allocator, vertex_count);

    const edge = size / 2.0;

    vertex_data.appendSliceAssumeCapacity(&[vertex_count]VertexData{
        // Front positions
        VertexData{ .position = F32x3{ -edge, -edge, edge }, .normal = F32x3{ -edge, -edge, edge } },
        VertexData{ .position = F32x3{ edge, -edge, edge }, .normal = F32x3{ edge, -edge, edge } },
        VertexData{ .position = F32x3{ edge, edge, edge }, .normal = F32x3{ edge, edge, edge } },
        VertexData{ .position = F32x3{ -edge, edge, edge }, .normal = F32x3{ -edge, edge, edge } },
        // Back positions
        VertexData{ .position = F32x3{ -edge, -edge, -edge }, .normal = F32x3{ -edge, -edge, -edge } },
        VertexData{ .position = F32x3{ edge, -edge, -edge }, .normal = F32x3{ edge, -edge, -edge } },
        VertexData{ .position = F32x3{ edge, edge, -edge }, .normal = F32x3{ edge, edge, -edge } },
        VertexData{ .position = F32x3{ -edge, edge, -edge }, .normal = F32x3{ -edge, edge, -edge } },
    });

    var index_data = try std.ArrayList(u32).initCapacity(allocator, index_count);

    index_data.appendSliceAssumeCapacity(&[index_count]u32{
        // front quad
        0, 1, 2,
        2, 3, 0,
        // right quad
        1, 5, 6,
        6, 2, 1,
        // back quad
        7, 6, 5,
        5, 4, 7,
        // left quad
        4, 0, 3,
        3, 7, 4,
        // bottom quad
        4, 5, 1,
        1, 0, 4,
        // top quad
        3, 2, 6,
        6, 7, 3,
    });

    return Primitive{ .vertex_data = vertex_data, .vertex_count = vertex_count, .index_data = index_data, .index_count = index_count, .type = .quad };
}

pub fn createCylinderPrimitive(allocator: std.mem.Allocator, radius: f32, height: f32, num_sides: u32) !Primitive {
    var vertex_data = try std.ArrayList(VertexData).initCapacity(allocator, 500);
    var index_data = try std.ArrayList(u32).initCapacity(allocator, 500);
    var indexes: u32 = 0;

    var temp_normal: [500 * 3]f32 = undefined;
    var temp_vertices: [(500 * 3) + 3]f32 = undefined;

    std.mem.set(f32, &temp_normal, 0.0);
    std.mem.set(f32, &temp_vertices, 0.0);

    temp_vertices[0] = 0.0;
    temp_vertices[1] = (height / 2.0);
    temp_vertices[2] = 0.0;

    temp_vertices[3] = 0.0;
    temp_vertices[4] = -((height / 2.0));
    temp_vertices[5] = 0.0;

    const angle = 2.0 * PI / @intToFloat(f32, num_sides);

    for (0..num_sides + 1) |i| {
        var float_i = @intToFloat(f32, i);

        var x: f32 = radius * @sin(angle * float_i);
        var y: f32 = radius * @cos(angle * float_i);

        temp_vertices[i * 6] = x;
        temp_vertices[i * 6 + 1] = (height / 2.0);
        temp_vertices[i * 6 + 2] = y;

        temp_vertices[i * 6 + 3] = x;
        temp_vertices[i * 6 + 4] = -(height / 2.0);
        temp_vertices[i * 6 + 5] = y;
    }

    var group1: u32 = 1;
    var group2: u32 = 3;
    indexes = 0;

    for (0..num_sides + 1) |_| {
        if (group2 >= num_sides * 2) group2 = 1;
        index_data.appendSliceAssumeCapacity(&[_]u32{
            0,          group1 + 1, group2 + 1,
            group1 + 2, group2 + 1, group1 + 1,
            group1 + 2, group2 + 2, group2 + 1,
            1,          group2 + 2, group1 + 2,
        });
        indexes += 12;
        group1 += 2;
        group2 += 2;
    }

    {
        var i: u32 = 0;
        while (i < indexes) : (i += 3) {
            var indexA: u32 = index_data.items[i];
            var indexB: u32 = index_data.items[i + 1];
            var indexC: u32 = index_data.items[i + 2];

            var vert1: F32x4 = F32x4{ temp_vertices[indexA * 3], temp_vertices[indexA * 3 + 1], temp_vertices[indexA * 3 + 2], 1.0 };
            var vert2: F32x4 = F32x4{ temp_vertices[indexB * 3], temp_vertices[indexB * 3 + 1], temp_vertices[indexB * 3 + 2], 1.0 };
            var vert3: F32x4 = F32x4{ temp_vertices[indexC * 3], temp_vertices[indexC * 3 + 1], temp_vertices[indexC * 3 + 2], 1.0 };

            var edgeAB: F32x4 = vert2 - vert1;
            var edgeAC: F32x4 = vert3 - vert1;

            var cross = zmath.cross3(edgeAB, edgeAC);

            temp_normal[indexA * 3] += cross[0];
            temp_normal[indexA * 3 + 1] += cross[1];
            temp_normal[indexA * 3 + 2] += cross[2];
            temp_normal[indexB * 3] += cross[0];
            temp_normal[indexB * 3 + 1] += cross[1];
            temp_normal[indexB * 3 + 2] += cross[2];
            temp_normal[indexC * 3] += cross[0];
            temp_normal[indexC * 3 + 1] += cross[1];
            temp_normal[indexC * 3 + 2] += cross[2];
        }
    }

    for (0..(indexes / 3)) |i| {
        vertex_data.appendAssumeCapacity(VertexData{ .position = F32x3{ temp_vertices[i * 3], temp_vertices[i * 3 + 1], temp_vertices[i * 3 + 2] }, .normal = F32x3{ temp_normal[i * 3], temp_normal[i * 3 + 1], temp_normal[i * 3 + 2] } });
    }

    return Primitive{ .vertex_data = vertex_data, .vertex_count = indexes / 3, .index_data = index_data, .index_count = indexes, .type = .cylinder };
}
