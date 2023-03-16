const std = @import("std");
const zmath = @import("zmath");

const PI = 3.1415927410125732421875;

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


pub fn createQuadPrimitive(allocator : std.mem.Allocator) Primitive {
    var vertex_data : std.ArrayList(VertexData) = undefined;
    if (std.ArrayList(VertexData).initCapacity(allocator, 4)) |array_list| {
        vertex_data = array_list;
    } else |err| {
        std.log.err("mach-examples: error: primitive triangle vertex memory wasn't allocated. Full message {}", .{err});
    }

    vertex_data.appendSliceAssumeCapacity(&[4]VertexData {
        VertexData{.position = F32x3{ -0.5, -0.5, 0.0 }, .normal = F32x3{-0.5, -0.5, 0.0 }},
        VertexData{.position = F32x3{ 0.5, -0.5, 0.0 }, .normal = F32x3{ 0.5, -0.5, 0.0}},
        VertexData{.position = F32x3{ -0.5, 0.5, 0.0 }, .normal = F32x3{ -0.5, 0.5, 0.0}},
        VertexData{.position = F32x3{ 0.5, 0.5, 0.0 }, .normal = F32x3{ 0.5, 0.5, 0.0}},
    });

    var index_data : std.ArrayList(u32) = undefined;
    if (std.ArrayList(u32).initCapacity(allocator, 6)) |array_list| {
        index_data = array_list;
    } else |err| {
        std.log.err("mach-examples: error: primitive triangle index memory wasn't allocated. Full message {}", .{err});
    }

    index_data.appendSliceAssumeCapacity(&[6]u32 { 
        0,1,2,
        1,3,2,
     });

    return Primitive {
        .vertex_data = vertex_data,
        .vertex_count = 4,
        .index_data = index_data,
        .index_count = 6,
        .type = .quad
    };
}

pub fn createPlanePrimitive(allocator : std.mem.Allocator, x_subdivision : u32, y_subdivision : u32, size : f32) Primitive {
    const x_num_vertices = x_subdivision + 1;
    const y_num_vertices = y_subdivision + 1;
    const vertex_count = x_num_vertices * y_num_vertices;

    var vertex_data : std.ArrayList(VertexData) = undefined;
    if (std.ArrayList(VertexData).initCapacity(allocator, vertex_count)) |array_list| {
        vertex_data = array_list;
    } else |err| {
        std.log.err("mach-examples: error: primitive triangle vertex memory wasn't allocated. Full message {}", .{err});
    }


    const vertices_distance_y = (size / @intToFloat(f32, y_subdivision));
    const vertices_distance_x = (size / @intToFloat(f32, x_subdivision));
    var y: u32 = 0;
    while (y < y_num_vertices) : (y += 1) {
        var x: u32 = 0;
        const pos_y = (-size / 2.0) + @intToFloat(f32, y)  * vertices_distance_y;
        while (x < x_num_vertices) : (x += 1) {
            const pos_x = (-size / 2.0) + @intToFloat(f32, x)  * vertices_distance_x;
            vertex_data.appendAssumeCapacity(VertexData{
                .position = F32x3{ pos_x, pos_y, 0.0 },
                .normal = F32x3{ pos_x, pos_y, 0.0 }
            });    
        }
    }

    const index_count = x_subdivision * y_subdivision * 2 * 3;
    var index_data : std.ArrayList(u32) = undefined;
    if (std.ArrayList(u32).initCapacity(allocator, index_count)) |array_list| {
        index_data = array_list;
    } else |err| {
        std.log.err("mach-examples: error: primitive triangle index memory wasn't allocated. Full message {}", .{err});
    }

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

    return Primitive {
        .vertex_data = vertex_data,
        .vertex_count = vertex_count,
        .index_data = index_data,
        .index_count = index_count,
        .type = .plane
    };
}

pub fn createCirclePrimitive(allocator : std.mem.Allocator, vertices : u32, radius : f32) Primitive {
    const vertex_count = vertices + 1;
    var vertex_data : std.ArrayList(VertexData) = undefined;
    if (std.ArrayList(VertexData).initCapacity(allocator, vertex_count)) |array_list| {
        vertex_data = array_list;
    } else |err| {
        std.log.err("mach-examples: error: primitive triangle vertex memory wasn't allocated. Full message {}", .{err});
    }

    // Mid point of circle
    vertex_data.appendAssumeCapacity(VertexData{
        .position = F32x3{ 0, 0, 0.0 },
        .normal = F32x3{ 0, 0, 0.0 }
    });   

    var x: u32 = 0;
    var angle = 2 * PI / @intToFloat(f32, vertices);
    while (x < vertices) : (x += 1) {

        const x_f = @intToFloat(f32,x);
        const pos_x = radius * zmath.cos(angle * x_f);
        const pos_y = radius * zmath.sin(angle * x_f);

        vertex_data.appendAssumeCapacity(VertexData{
            .position = F32x3{ pos_x, pos_y, 0.0 },
            .normal = F32x3{ pos_x, pos_y, 0.0 }
        });    
    }
    


    const index_count = (vertices + 1) * 3;
    var index_data : std.ArrayList(u32) = undefined;
    if (std.ArrayList(u32).initCapacity(allocator, index_count)) |array_list| {
        index_data = array_list;
    } else |err| {
        std.log.err("mach-examples: error: primitive triangle index memory wasn't allocated. Full message {}", .{err});
    }

    x = 1;
    while (x <= vertices) : (x += 1) {
        index_data.appendAssumeCapacity(0);
        index_data.appendAssumeCapacity(x);
        index_data.appendAssumeCapacity(x + 1);
    }

    index_data.appendAssumeCapacity(0);
    index_data.appendAssumeCapacity(vertices);
    index_data.appendAssumeCapacity(1);

    return Primitive {
        .vertex_data = vertex_data,
        .vertex_count = vertex_count,
        .index_data = index_data,
        .index_count = index_count,
        .type = .plane
    };
}

