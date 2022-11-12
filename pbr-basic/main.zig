const std = @import("std");
const mach = @import("mach");
const gpu = @import("gpu");
const zm = @import("zmath");
const m3d = @import("model3d");
const c = @cImport({
    @cInclude("stdlib.h");
});

pub const App = @This();

const Vertex = extern struct {
    position: Vec3,
    normal: Vec3,
};

const Model = struct {
    vertices: []Vertex,
    indices: []u32,
    vertex_buffer: *gpu.Buffer,
    index_buffer: *gpu.Buffer,
};

var models: [4]Model = undefined;

const model_paths = [_][]const u8{
    projectRootPath() ++ "/assets/sphere_ascii.m3d",
    projectRootPath() ++ "/assets/sphere.m3d",
    projectRootPath() ++ "/assets/teapot.m3d",
    projectRootPath() ++ "/assets/torusknot.m3d",
    projectRootPath() ++ "/assets/venus.m3d",
};

fn projectRootPath() []const u8 {
    comptime {
        return std.fs.path.dirname(@src().file).?;
    }
}

const grid_dimensions = 7;

// var camera: Camera = undefined;

var current_material_index: usize = 0;
var current_object_index: usize = 0;

// const Vec4 = @Vector(4, f32);
// const Vec3 = @Vector(3, f32);
// const Vec2 = @Vector(2, f32);

// const Vec4 = packed struct {
//     x: f32,
//     y: f32,
//     z: f32,
//     w: f32,
// };

// const Vec3 = packed struct {
//     x: f32,
//     y: f32,
//     z: f32,
// };

// const Vec2 = packed struct {
//     x: f32,
//     y: f32,
// };

const Vec4 = [4]f32;
const Vec3 = [3]f32;
const Vec2 = [2]f32;

const Mat4 = [4]Vec4;

const UniformBufferObject = struct {
    mat: zm.Mat,
};

// const Camera = struct {
//     const Mode = enum(u32) {
//         look_at = 1,
//         first_person = 2,
//     };

//     const Matrices = struct {
//         perspective: Mat4 = .{
//             .{ 0.0, 0.0, 0.0, 0.0 },
//             .{ 0.0, 0.0, 0.0, 0.0 },
//             .{ 0.0, 0.0, 0.0, 0.0 },
//             .{ 0.0, 0.0, 0.0, 0.0 },
//         },
//         view: Mat4 = .{
//             .{ 0.0, 0.0, 0.0, 0.0 },
//             .{ 0.0, 0.0, 0.0, 0.0 },
//             .{ 0.0, 0.0, 0.0, 0.0 },
//             .{ 0.0, 0.0, 0.0, 0.0 },
//         },
//     };

//     const Keys = struct {
//         left: bool = false,
//         right: bool = false,
//         up: bool = false,
//         down: bool = false,
//     };

//     rotation: Vec3 = .{ 0.0, 0.0, 0.0 },
//     position: Vec3 = .{ 0.0, 0.0, 0.0 },
//     view_position: Vec4 = .{ 0.0, 0.0, 0.0, 0.0 },
//     mode: Mode,
//     fov: f32 = 0.0,
//     znear: f32 = 0.0,
//     zfar: f32 = 0.0,
//     rotation_speed: f32 = 0.0,
//     movement_speed: f32 = 0.0,
//     updated: bool = false,
//     flip_y: bool = false,
//     matrices: Matrices = .{},
//     keys: Keys = .{},

//     pub fn updateViewMatrix(self: *@This()) void {
//         const rot_x_degrees = self.rotation[0] * (if (self.flip_y) -1.0 else 1.0);
//         const rotation_matrix = Mat4{
//             zm.rotationX(rot_x_degrees),
//             zm.rotationY(self.rotation[1]),
//             zm.rotationZ(self.rotation[2]),
//             .{ 0.0, 0.0, 0.0, 1.0 },
//         };
//         const translation_vec = blk: {
//             break :blk Vec3{
//                 self.position[0],
//                 if (self.flip_y) -self.position[1] else self.position[1],
//                 self.position[2],
//             };
//         };
//         const translation_matrix = zm.translation(translation_vec.x, translation_vec.y, translation_vec.z);

//         if (self.mode == .first_person) {
//             self.matrices.view = zm.mul(rotation_matrix, translation_matrix);
//         } else {
//             self.matrices.view = zm.mul(translation_matrix, rotation_matrix);
//         }
//         self.view_position = zm.mul(
//             Vec4{ self.position[0], self.position[1], self.position[2], 0.0 },
//             Vec4{ -1.0, 1.0, -1.0, 1.0 },
//         );
//         self.updated = true;
//     }

//     pub fn setMovementSpeed(self: *@This(), speed: f32) void {
//         self.movement_speed = speed;
//     }

//     pub fn setPerspective(self: *@This(), fov: f32, aspect: f32, znear: f32, zfar: f32) void {
//         self.fov = fov;
//         self.znear = znear;
//         self.zfar = zfar;
//         self.matrices.perspective = zm.perspectiveFovLh(fov, aspect, znear, zfar);
//         if (self.flip_y) {
//             self.matrices.perspective[1][1] *= -1.0;
//         }
//     }

//     pub fn setRotationSpeed(self: *@This(), speed: f32) void {
//         self.rotation_speed = speed;
//     }

//     pub fn setRotation(self: *@This(), rotation: Vec3) void {
//         self.rotation = rotation;
//         self.updateViewMatrix();
//     }

//     pub fn setPosition(self: *@This(), position: Vec3) void {
//         self.position = .{
//             position[0],
//             -position[1],
//             position[2],
//         };
//         self.updateViewMatrix();
//     }
// };

const UniformBuffers = struct {
    const Params = struct {
        buffer: *gpu.Buffer,
        buffer_size: u64,
        model_size: u64,
    };
    const Buffer = struct {
        buffer: *gpu.Buffer,
        size: u32,
    };
    ubo_matrices: Buffer,
    ubo_params: Buffer,
    material_params: Params,
    object_params: Params,
};

const UboParams = struct {
    lights: [4]Vec4,
};
var ubo_params: UboParams = undefined;

const UboMatrices = extern struct {
    projection: Mat4,
    model: Mat4,
    view: Mat4,
    camera_position: Vec3,
};
var ubo_matrices: UboMatrices = undefined;

var uniform_buffers: UniformBuffers = undefined;
const grid_element_count = grid_dimensions * grid_dimensions;

const MaterialParamsDynamic = extern struct {
    roughness: f32 = 0,
    metallic: f32 = 0,
    color: Vec3 = .{ 0, 0, 0 },
    padding: [236]u8 = [1]u8{0} ** 236,
};
const MaterialParamsDynamicGrid = [grid_element_count]MaterialParamsDynamic;
var material_params_dynamic: MaterialParamsDynamicGrid = [1]MaterialParamsDynamic{.{}} ** grid_element_count;

const ObjectParamsDynamic = extern struct {
    position: Vec3 = .{ 0, 0, 0 },
    padding: [244]u8 = [1]u8{0} ** 244,
};
const ObjectParamsDynamicGrid = [grid_element_count]ObjectParamsDynamic;
var object_params_dynamic: ObjectParamsDynamicGrid = [1]ObjectParamsDynamic{.{}} ** grid_element_count;

// TODO: Make generic?
inline fn roundToMultipleOf4(comptime T: type, value: T) T {
    return (value + 3) & ~@as(T, 3);
}

fn prepareUniformBuffers(app: *App, core: *mach.Core, encoder: *gpu.CommandEncoder) void {
    comptime {
        std.debug.assert(@sizeOf(ObjectParamsDynamic) == 256);
        std.debug.assert(@sizeOf(MaterialParamsDynamic) == 256);
    }

    uniform_buffers.ubo_matrices.size = roundToMultipleOf4(u32, @intCast(u32, @sizeOf(UboMatrices)));
    uniform_buffers.ubo_matrices.buffer = core.device.createBuffer(&.{
        .usage = .{ .copy_dst = true, .uniform = true },
        .size = uniform_buffers.ubo_matrices.size,
        .mapped_at_creation = true,
    });

    uniform_buffers.ubo_params.size = roundToMultipleOf4(u32, @intCast(u32, @sizeOf(UboParams)));
    uniform_buffers.ubo_params.buffer = core.device.createBuffer(&.{
        .usage = .{ .copy_dst = true, .uniform = true },
        .size = uniform_buffers.ubo_params.size,
        .mapped_at_creation = true,
    });

    //
    // Material parameter uniform buffer
    //
    uniform_buffers.material_params.model_size = @sizeOf(Vec2) + @sizeOf(Vec3);
    uniform_buffers.material_params.buffer_size = roundToMultipleOf4(u32, @intCast(u32, @sizeOf(MaterialParamsDynamicGrid)));
    std.debug.assert(uniform_buffers.material_params.buffer_size >= uniform_buffers.material_params.model_size);
    uniform_buffers.material_params.buffer = core.device.createBuffer(&.{
        .usage = .{ .copy_dst = true, .uniform = true },
        .size = uniform_buffers.material_params.buffer_size,
        .mapped_at_creation = true,
    });

    //
    // Object parameter uniform buffer
    //
    uniform_buffers.object_params.model_size = @sizeOf(Vec3);
    uniform_buffers.object_params.buffer_size = roundToMultipleOf4(u32, @intCast(u32, @sizeOf(MaterialParamsDynamicGrid)));
    std.debug.assert(uniform_buffers.object_params.buffer_size >= uniform_buffers.object_params.model_size);
    uniform_buffers.object_params.buffer = core.device.createBuffer(&.{
        .usage = .{ .copy_dst = true, .uniform = true },
        .size = uniform_buffers.object_params.buffer_size,
        .mapped_at_creation = true,
    });

    app.updateUniformBuffers(core, encoder);
    updateDynamicUniformBuffer(encoder);
    app.updateLights(encoder);
}

fn updateDynamicUniformBuffer(encoder: *gpu.CommandEncoder) void {
    var index: u32 = 0;
    var y: usize = 0;
    while (y < grid_dimensions) : (y += 1) {
        var x: usize = 0;
        while (x < grid_dimensions) : (x += 1) {
            const grid_dimensions_float = @intToFloat(f32, grid_dimensions);
            object_params_dynamic[index].position[0] = (@intToFloat(f32, x) - (grid_dimensions_float / 2)) * 2.5;
            object_params_dynamic[index].position[1] = 0;
            object_params_dynamic[index].position[2] = (@intToFloat(f32, y) - (grid_dimensions_float / 2)) * 2.5;
            material_params_dynamic[index].metallic = zm.clamp(@intToFloat(f32, x) / (grid_dimensions_float - 1), 0.1, 1.0);
            material_params_dynamic[index].roughness = zm.clamp(@intToFloat(f32, y) / (grid_dimensions_float - 1), 0.05, 1.0);
            material_params_dynamic[index].color = material_params_dynamic[current_material_index].color;
            index += 1;
        }
    }
    encoder.writeBuffer(
        uniform_buffers.object_params.buffer,
        0,
        &object_params_dynamic,
    );
    encoder.writeBuffer(
        uniform_buffers.material_params.buffer,
        0,
        &material_params_dynamic,
    );
    uniform_buffers.object_params.buffer.unmap();
    uniform_buffers.material_params.buffer.unmap();
}

fn updateUniformBuffers(app: *App, core: *mach.Core, encoder: *gpu.CommandEncoder) void {
    const time = app.timer.read();
    const model_vec = zm.mul(zm.rotationX(time * (std.math.pi / 2.0)), zm.rotationZ(time * (std.math.pi / 2.0)));
    ubo_matrices.model[0] = model_vec[0];
    ubo_matrices.model[1] = model_vec[1];
    ubo_matrices.model[2] = model_vec[2];
    ubo_matrices.model[3] = model_vec[3];
    const view = zm.lookAtRh(
        zm.f32x4(0, 4, 2, 1),
        zm.f32x4(0, 0, 0, 1),
        zm.f32x4(0, 0, 1, 0),
    );
    ubo_matrices.view[0] = view[0];
    ubo_matrices.view[1] = view[1];
    ubo_matrices.view[2] = view[2];
    ubo_matrices.view[3] = view[3];
    const projection = zm.perspectiveFovRh(
        (std.math.pi / 4.0),
        @intToFloat(f32, core.current_desc.width) / @intToFloat(f32, core.current_desc.height),
        0.1,
        10,
    );
    ubo_matrices.projection[0] = projection[0];
    ubo_matrices.projection[1] = projection[1];
    ubo_matrices.projection[2] = projection[2];
    ubo_matrices.projection[3] = projection[3];
    encoder.writeBuffer(uniform_buffers.ubo_matrices.buffer, 0, &[_]UboMatrices{ubo_matrices});
    uniform_buffers.ubo_matrices.buffer.unmap();
}

fn updateLights(app: *App, encoder: *gpu.CommandEncoder) void {
    const p: f32 = 15.0;
    // TODO: Assigning directly triggers a compilation error
    //       with no message
    const vec0 = Vec4{ -p, -p * 0.5, -p, 1.0 };
    const vec1 = Vec4{ -p, -p * 0.5, p, 1.0 };
    const vec2 = Vec4{ p, -p * 0.5, p, 1.0 };
    const vec3 = Vec4{ p, -p * 0.5, -p, 1.0 };
    ubo_params.lights[0] = vec0;
    ubo_params.lights[1] = vec1;
    ubo_params.lights[2] = vec2;
    ubo_params.lights[3] = vec3;
    // ubo_params.lights[0] = Vec4{ -p, -p * 0.5, -p, 1.0 };
    // ubo_params.lights[1] = Vec4{ -p, -p * 0.5, p, 1.0 };
    // ubo_params.lights[2] = Vec4{ p, -p * 0.5, p, 1.0 };
    // ubo_params.lights[3] = Vec4{ p, -p * 0.5, -p, 1.0 };
    const time = app.timer.read();
    ubo_params.lights[0][0] = @sin(time * 360.0) * 20.0;
    ubo_params.lights[0][2] = @cos(time * 360.0) * 20.0;
    ubo_params.lights[1][0] = @cos(time * 360.0) * 20.0;
    ubo_params.lights[1][1] = @sin(time * 360.0) * 20.0;
    encoder.writeBuffer(
        uniform_buffers.ubo_params.buffer,
        0,
        &[_]UboParams{ubo_params},
    );
    uniform_buffers.ubo_params.buffer.unmap();
}

fn setupPipeline(app: *App, core: *mach.Core) void {
    comptime {
        std.debug.assert(@sizeOf(Vertex) == @sizeOf(f32) * 6);
    }

    const bind_group_layout_entries = [_]gpu.BindGroupLayout.Entry{
        .{
            .binding = 0,
            .visibility = .{ .vertex = true, .fragment = true },
            .buffer = .{
                .@"type" = .uniform,
                .has_dynamic_offset = false,
                .min_binding_size = uniform_buffers.ubo_matrices.size,
            },
        },
        .{
            .binding = 1,
            .visibility = .{ .fragment = true },
            .buffer = .{
                .@"type" = .uniform,
                .has_dynamic_offset = false,
                .min_binding_size = uniform_buffers.ubo_params.size,
            },
        },
        .{
            .binding = 2,
            .visibility = .{ .fragment = true },
            .buffer = .{
                .@"type" = .uniform,
                .has_dynamic_offset = true,
                .min_binding_size = uniform_buffers.material_params.model_size,
            },
        },
        .{
            .binding = 3,
            .visibility = .{ .vertex = true },
            .buffer = .{
                .@"type" = .uniform,
                .has_dynamic_offset = true,
                .min_binding_size = uniform_buffers.object_params.model_size,
            },
        },
    };

    const bind_group_layout = core.device.createBindGroupLayout(
        &gpu.BindGroupLayout.Descriptor.init(.{
            .entries = bind_group_layout_entries[0..],
        }),
    );

    const bind_group_layouts = [_]*gpu.BindGroupLayout{bind_group_layout};
    const pipeline_layout = core.device.createPipelineLayout(&gpu.PipelineLayout.Descriptor.init(.{
        .bind_group_layouts = &bind_group_layouts,
    }));

    const vertex_buffer_layout = gpu.VertexBufferLayout.init(.{
        .array_stride = @sizeOf(Vertex),
        .step_mode = .vertex,
        .attributes = &.{
            .{ .format = .float32x3, .offset = @offsetOf(Vertex, "position"), .shader_location = 0 },
            .{ .format = .float32x3, .offset = @offsetOf(Vertex, "normal"), .shader_location = 1 },
        },
    });

    const vertex_shader_code = @embedFile("pbr.vert.spv");
    const vertex_shader_module = core.device.createShaderModule(&.{
        .next_in_chain = .{ .spirv_descriptor = &.{
            .code = @ptrCast([*]const u32, @alignCast(4, vertex_shader_code)),
            .code_size = vertex_shader_code.len / 4,
        } },
    });

    const fragment_shader_code = @embedFile("pbr.frag.spv");
    const fragment_shader_module = core.device.createShaderModule(&.{
        .next_in_chain = .{ .spirv_descriptor = &.{
            .code = @ptrCast([*]const u32, @alignCast(4, fragment_shader_code)),
            .code_size = fragment_shader_code.len / 4,
        } },
    });

    const blend_component_descriptor = gpu.BlendComponent{
        .operation = .add,
        .src_factor = .one,
        .dst_factor = .zero,
    };

    const color_target_state = gpu.ColorTargetState{
        .format = core.swap_chain_format,
        .blend = &.{
            .color = blend_component_descriptor,
            .alpha = blend_component_descriptor,
        },
    };

    const pipeline_descriptor = gpu.RenderPipeline.Descriptor{
        .layout = pipeline_layout,
        .primitive = .{
            .cull_mode = .back,
        },
        .depth_stencil = &.{
            .format = .depth24_plus_stencil8,
            .depth_write_enabled = true,
        },
        .fragment = &gpu.FragmentState.init(.{
            .module = fragment_shader_module,
            .entry_point = "main",
            .targets = &.{color_target_state},
        }),
        .vertex = gpu.VertexState.init(.{
            .module = vertex_shader_module,
            .entry_point = "main",
            .buffers = &.{vertex_buffer_layout},
        }),
    };

    app.render_pipeline = core.device.createRenderPipeline(&pipeline_descriptor);

    vertex_shader_module.release();
    fragment_shader_module.release();

    {
        const bind_group_entries = [_]gpu.BindGroup.Entry{
            .{
                .binding = 0,
                .buffer = uniform_buffers.ubo_matrices.buffer,
                .size = uniform_buffers.ubo_matrices.size,
            },
            .{
                .binding = 1,
                .buffer = uniform_buffers.ubo_params.buffer,
                .size = uniform_buffers.ubo_params.size,
            },
            .{
                .binding = 2,
                .buffer = uniform_buffers.material_params.buffer,
                .size = uniform_buffers.material_params.model_size,
            },
            .{
                .binding = 3,
                .buffer = uniform_buffers.object_params.buffer,
                .size = uniform_buffers.object_params.model_size,
            },
        };
        app.bind_group = core.device.createBindGroup(
            &gpu.BindGroup.Descriptor.init(.{
                .layout = bind_group_layout,
                .entries = &bind_group_entries,
            }),
        );
    }
}

fn setupRenderPass(app: *App, core: *mach.Core) void {
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

    app.depth_texture = core.device.createTexture(&.{
        .usage = .{ .render_attachment = true, .copy_src = true },
        .format = .depth24_plus_stencil8,
        .sample_count = 1,
        .size = .{
            .width = core.current_desc.width,
            .height = core.current_desc.height,
            .depth_or_array_layers = 1,
        },
    });

    const depth_texture_view = app.depth_texture.createView(&.{
        .format = .depth24_plus_stencil8,
        .dimension = .dimension_2d,
        .array_layer_count = 1,
        .aspect = .all,
    });

    app.depth_stencil_attachment_description = gpu.RenderPassDepthStencilAttachment{
        .view = depth_texture_view,
        .depth_load_op = .clear,
        .depth_store_op = .store,
        .depth_clear_value = 1.0,
        .clear_depth = 1.0,
        .clear_stencil = 0,
        .stencil_load_op = .clear,
        .stencil_store_op = .store,
    };
}

pub fn update(app: *App, core: *mach.Core) !void {
    const back_buffer_view = core.swap_chain.?.getCurrentTextureView();
    app.color_attachment.view = back_buffer_view;
    app.render_pass_descriptor = gpu.RenderPassDescriptor{
        .color_attachment_count = 1,
        .color_attachments = &[_]gpu.RenderPassColorAttachment{app.color_attachment},
        .depth_stencil_attachment = &app.depth_stencil_attachment_description,
    };
    const encoder = core.device.createCommandEncoder(null);
    const current_model = models[current_object_index];

    const pass = encoder.beginRenderPass(&app.render_pass_descriptor);
    pass.setPipeline(app.render_pipeline);

    var i: usize = 0;
    while (i < (grid_dimensions * grid_dimensions)) : (i += 1) {
        const alignment = 256;
        const dynamic_offset: u32 = @intCast(u32, i) * alignment;
        const dynamic_offsets = [2]u32{ dynamic_offset, dynamic_offset };
        pass.setBindGroup(0, app.bind_group, &dynamic_offsets);
        if (!app.buffers_bound) {
            pass.setVertexBuffer(0, current_model.vertex_buffer, 0, @sizeOf(Vertex) * current_model.vertices.len);
            pass.setIndexBuffer(current_model.index_buffer, .uint32, 0, gpu.whole_size);
            app.buffers_bound = true;
        }
        pass.drawIndexed(
            @intCast(u32, current_model.indices.len), // index_count
            1, // instance_count
            0, // first_index
            0, // base_vertex
            0, // first_instance
        );
    }

    pass.end();
    pass.release();

    var command = encoder.finish(null);
    encoder.release();

    app.queue.submit(&[_]*gpu.CommandBuffer{command});
    command.release();
    core.swap_chain.?.present();
    back_buffer_view.release();

    app.buffers_bound = false;
}

pub fn resize(app: *App, core: *mach.Core, width: u32, height: u32) !void {
    app.depth_texture = core.device.createTexture(&gpu.Texture.Descriptor{
        .usage = .{ .render_attachment = true },
        .format = .depth24_plus_stencil8,
        .sample_count = 1,
        .size = .{
            .width = width,
            .height = height,
            .depth_or_array_layers = 1,
        },
    });
    app.depth_view = app.depth_texture.createView(&gpu.TextureView.Descriptor{
        .format = .depth24_plus_stencil8,
        .dimension = .dimension_2d,
        .array_layer_count = 1,
        .aspect = .all,
    });
    app.depth_stencil_attachment_description = gpu.RenderPassDepthStencilAttachment{
        .view = app.depth_view,
        .depth_load_op = .clear,
        .depth_store_op = .store,
        .depth_clear_value = 1.0,
        .clear_depth = 1.0,
        .clear_stencil = 0,
        .stencil_load_op = .clear,
        .stencil_store_op = .store,
    };
}

render_pipeline: *gpu.RenderPipeline,
render_pass_descriptor: gpu.RenderPassDescriptor,
bind_group: *gpu.BindGroup,
frame_counter: usize,
queue: *gpu.Queue,
color_attachment: gpu.RenderPassColorAttachment,
depth_stencil_attachment_description: gpu.RenderPassDepthStencilAttachment,
depth_texture: *gpu.Texture,
depth_view: *gpu.TextureView,
timer: mach.Timer,
prepared: bool = false,
buffers_bound: bool = false,

pub fn deinit(_: *App, _: *mach.Core) void {}

pub fn init(app: *App, core: *mach.Core) !void {
    app.timer = try mach.Timer.start();
    app.queue = core.device.getQueue();

    //
    // Setup Camera
    //

    // const aspect_ratio: f32 = @intToFloat(f32, core.current_desc.width) / @intToFloat(f32, core.current_desc.height);

    // camera = Camera{
    //     .rotation_speed = 1.0,
    //     .movement_speed = 1.0,
    //     .mode = .first_person,
    // };
    // camera.setPosition(.{ 10.0, 13.0, 1.8 });
    // camera.setRotation(.{ 62.5, 90.0, 0.0 });
    // camera.setMovementSpeed(4.0);
    // camera.setPerspective(60.0, aspect_ratio, 0.1, 256.0);
    // camera.setRotationSpeed(0.25);

    //
    // Load Assets
    //

    const encoder = core.device.createCommandEncoder(null);

    var allocator = std.heap.c_allocator;
    for (model_paths) |model_path, model_path_i| {
        var model_file = std.fs.openFileAbsolute(model_path, .{}) catch |err| {
            std.log.err("Failed to load model: '{s}' Error: {}", .{ model_path, err });
            return error.LoadModelFileFailed;
        };
        defer model_file.close();

        var model_data = try model_file.readToEndAllocOptions(allocator, 600 * 1024, 600 * 1024, @alignOf(u8), 0);
        defer allocator.free(model_data);

        const m3d_model = m3d.load(model_data, null, null, null) orelse return error.LoadModelFailed;

        const vertex_count = m3d_model.handle.numvertex;
        const face_count = m3d_model.handle.numface;
        const index_count = face_count * 3;

        var model: *Model = &models[model_path_i];

        model.vertices = try allocator.alloc(Vertex, vertex_count);
        model.indices = try allocator.alloc(u32, index_count);

        var i: usize = 0;
        while (i < face_count) : (i += 1) {
            std.debug.assert(i < vertex_count);

            const vertices = m3d_model.handle.vertex[0..vertex_count];
            const face = m3d_model.handle.face;

            model.indices[i + 0] = face.*.vertex[0];
            model.indices[i + 1] = face.*.vertex[1];
            model.indices[i + 2] = face.*.vertex[2];
            // TODO: memcpy ?

            const normal0 = face.*.normal[0];
            const normal1 = face.*.normal[1];
            const normal2 = face.*.normal[2];

            if (normal0 == std.math.maxInt(u32)) {
                std.log.warn("No normals", .{});
                continue;
            }

            std.debug.assert(normal0 < vertices.len);
            std.debug.assert(normal1 < vertices.len);
            std.debug.assert(normal2 < vertices.len);

            model.vertices[i].normal[0] = vertices[normal0].x;
            model.vertices[i].normal[1] = vertices[normal0].y;
            model.vertices[i].normal[2] = vertices[normal0].z;
            model.vertices[i].normal[0] = vertices[normal1].x;
            model.vertices[i].normal[1] = vertices[normal1].y;
            model.vertices[i].normal[2] = vertices[normal1].z;
            model.vertices[i].normal[0] = vertices[normal2].x;
            model.vertices[i].normal[1] = vertices[normal2].y;
            model.vertices[i].normal[2] = vertices[normal2].z;
        }
        i = 0;
        while (i < vertex_count) : (i += 1) {
            const vertex = m3d_model.handle.vertex[i];
            model.vertices[i].position[0] = vertex.x;
            model.vertices[i].position[1] = vertex.y;
            model.vertices[i].position[2] = vertex.z;
        }
        //
        // Load vertex and index data into webgpu buffers
        //
        model.vertex_buffer = core.device.createBuffer(&.{
            .usage = .{ .copy_dst = true, .vertex = true },
            .size = @sizeOf(Vertex) * model.vertices.len,
            .mapped_at_creation = true,
        });
        encoder.writeBuffer(
            model.vertex_buffer,
            0,
            model.vertices,
        );
        model.vertex_buffer.unmap();

        model.index_buffer = core.device.createBuffer(&.{
            .usage = .{ .copy_dst = true, .index = true },
            .size = @sizeOf(u32) * model.indices.len,
            .mapped_at_creation = true,
        });
        encoder.writeBuffer(
            model.index_buffer,
            0,
            model.indices,
        );
        model.index_buffer.unmap();
    }

    prepareUniformBuffers(app, core, encoder);
    var command = encoder.finish(null);
    encoder.release();
    app.queue.submit(&[_]*gpu.CommandBuffer{command});
    command.release();

    setupPipeline(app, core);
    setupRenderPass(app, core);

    app.prepared = true;
}
