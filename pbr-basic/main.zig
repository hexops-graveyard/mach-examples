const std = @import("std");
const mach = @import("mach");
const gpu = @import("gpu");
const zm = @import("zmath");
const m3d = @import("model3d");
const assets = @import("assets");

pub const App = @This();

const Vec4 = [4]f32;
const Vec3 = [3]f32;
const Vec2 = [2]f32;
const Mat4 = [4]Vec4;

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

const Material = struct {
    const Params = extern struct {
        roughness: f32,
        metallic: f32,
        color: Vec3,
    };

    name: []const u8,
    params: Params,
};

const PressedKeys = packed struct(u16) {
    right: bool = false,
    left: bool = false,
    up: bool = false,
    down: bool = false,
    padding: u12 = undefined,

    pub inline fn areKeysPressed(self: @This()) bool {
        return (self.up or self.down or self.left or self.right);
    }

    pub inline fn clear(self: *@This()) void {
        self.right = false;
        self.left = false;
        self.up = false;
        self.down = false;
    }
};

const Camera = struct {
    const Matrices = struct {
        perspective: zm.Mat = .{
            .{ 0.0, 0.0, 0.0, 0.0 },
            .{ 0.0, 0.0, 0.0, 0.0 },
            .{ 0.0, 0.0, 0.0, 0.0 },
            .{ 0.0, 0.0, 0.0, 0.0 },
        },
        view: zm.Mat = .{
            .{ 0.0, 0.0, 0.0, 0.0 },
            .{ 0.0, 0.0, 0.0, 0.0 },
            .{ 0.0, 0.0, 0.0, 0.0 },
            .{ 0.0, 0.0, 0.0, 0.0 },
        },
    };

    rotation: Vec3 = .{ 0.0, 0.0, 0.0 },
    position: Vec3 = .{ 0.0, 0.0, 0.0 },
    view_position: Vec4 = .{ 0.0, 0.0, 0.0, 0.0 },
    fov: f32 = 0.0,
    znear: f32 = 0.0,
    zfar: f32 = 0.0,
    rotation_speed: f32 = 0.0,
    movement_speed: f32 = 0.0,
    updated: bool = false,
    matrices: Matrices = .{},

    pub fn calculateMovement(self: *@This(), pressed_keys: PressedKeys) void {
        std.debug.assert(pressed_keys.areKeysPressed());
        const rotation_radians = Vec3{
            toRadians(self.rotation[0]),
            toRadians(self.rotation[1]),
            toRadians(self.rotation[2]),
        };
        var camera_front = zm.Vec{ -zm.cos(rotation_radians[0]) * zm.sin(rotation_radians[1]), zm.sin(rotation_radians[0]), zm.cos(rotation_radians[0]) * zm.cos(rotation_radians[1]), 0 };
        camera_front = zm.normalize3(camera_front);
        if (pressed_keys.up) {
            camera_front[0] *= self.movement_speed;
            camera_front[1] *= self.movement_speed;
            camera_front[2] *= self.movement_speed;
            self.position = Vec3{
                self.position[0] + camera_front[0],
                self.position[1] + camera_front[1],
                self.position[2] + camera_front[2],
            };
        }
        if (pressed_keys.down) {
            camera_front[0] *= self.movement_speed;
            camera_front[1] *= self.movement_speed;
            camera_front[2] *= self.movement_speed;
            self.position = Vec3{
                self.position[0] - camera_front[0],
                self.position[1] - camera_front[1],
                self.position[2] - camera_front[2],
            };
        }
        if (pressed_keys.right) {
            camera_front = zm.cross3(.{ 0.0, 1.0, 0.0, 0.0 }, camera_front);
            camera_front = zm.normalize3(camera_front);
            camera_front[0] *= self.movement_speed;
            camera_front[1] *= self.movement_speed;
            camera_front[2] *= self.movement_speed;
            self.position = Vec3{
                self.position[0] - camera_front[0],
                self.position[1] - camera_front[1],
                self.position[2] - camera_front[2],
            };
        }
        if (pressed_keys.left) {
            camera_front = zm.cross3(.{ 0.0, 1.0, 0.0, 0.0 }, camera_front);
            camera_front = zm.normalize3(camera_front);
            camera_front[0] *= self.movement_speed;
            camera_front[1] *= self.movement_speed;
            camera_front[2] *= self.movement_speed;
            self.position = Vec3{
                self.position[0] + camera_front[0],
                self.position[1] + camera_front[1],
                self.position[2] + camera_front[2],
            };
        }
        self.updateViewMatrix();
    }

    fn updateViewMatrix(self: *@This()) void {
        const rotation_x = zm.rotationX(toRadians(self.rotation[2]));
        const rotation_y = zm.rotationY(toRadians(self.rotation[1]));
        const rotation_z = zm.rotationZ(toRadians(self.rotation[0]));
        const rotation_matrix = zm.mul(rotation_z, zm.mul(rotation_x, rotation_y));

        const translation_matrix: zm.Mat = zm.translationV(.{
            self.position[0],
            self.position[1],
            self.position[2],
            0,
        });

        self.matrices.view = zm.mul(translation_matrix, rotation_matrix);
        self.view_position = .{
            -self.position[0],
            self.position[1],
            -self.position[2],
            0.0,
        };
        self.updated = true;
    }

    pub fn setMovementSpeed(self: *@This(), speed: f32) void {
        self.movement_speed = speed;
    }

    pub fn setPerspective(self: *@This(), fov: f32, aspect: f32, znear: f32, zfar: f32) void {
        self.fov = fov;
        self.znear = znear;
        self.zfar = zfar;
        const perspective = zm.perspectiveFovRhGl(toRadians(fov), aspect, znear, zfar);
        self.matrices.perspective[0] = perspective[0];
        self.matrices.perspective[1] = perspective[1];
        self.matrices.perspective[2] = perspective[2];
        self.matrices.perspective[3] = perspective[3];
    }

    pub fn setRotationSpeed(self: *@This(), speed: f32) void {
        self.rotation_speed = speed;
    }

    pub fn setRotation(self: *@This(), rotation: Vec3) void {
        self.rotation = rotation;
        self.updateViewMatrix();
    }

    pub fn setPosition(self: *@This(), position: Vec3) void {
        self.position = .{
            position[0],
            -position[1],
            position[2],
        };
        self.updateViewMatrix();
    }
};

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

const UboMatrices = extern struct {
    projection: Mat4,
    model: Mat4,
    view: Mat4,
    camera_position: Vec3,
};

const grid_element_count = grid_dimensions * grid_dimensions;

const MaterialParamsDynamic = extern struct {
    roughness: f32 = 0,
    metallic: f32 = 0,
    color: Vec3 = .{ 0, 0, 0 },
    padding: [236]u8 = [1]u8{0} ** 236,
};
const MaterialParamsDynamicGrid = [grid_element_count]MaterialParamsDynamic;

const ObjectParamsDynamic = extern struct {
    position: Vec3 = .{ 0, 0, 0 },
    padding: [244]u8 = [1]u8{0} ** 244,
};
const ObjectParamsDynamicGrid = [grid_element_count]ObjectParamsDynamic;

//
// Globals
//

const vertex_shader_path = "pbr.vert.spv";
const fragment_shader_path = "pbr.frag.spv";

const materials = [_]Material{
    .{ .name = "Gold", .params = .{ .roughness = 0.1, .metallic = 1.0, .color = .{ 1.0, 0.765557, 0.336057 } } },
    .{ .name = "Copper", .params = .{ .roughness = 0.1, .metallic = 1.0, .color = .{ 0.955008, 0.637427, 0.538163 } } },
    .{ .name = "Chromium", .params = .{ .roughness = 0.1, .metallic = 1.0, .color = .{ 0.549585, 0.556114, 0.554256 } } },
    .{ .name = "Nickel", .params = .{ .roughness = 0.1, .metallic = 1.0, .color = .{ 1.0, 0.608679, 0.525649 } } },
    .{ .name = "Titanium", .params = .{ .roughness = 0.1, .metallic = 1.0, .color = .{ 0.541931, 0.496791, 0.449419 } } },
    .{ .name = "Cobalt", .params = .{ .roughness = 0.1, .metallic = 1.0, .color = .{ 0.662124, 0.654864, 0.633732 } } },
    .{ .name = "Platinum", .params = .{ .roughness = 0.1, .metallic = 1.0, .color = .{ 0.672411, 0.637331, 0.585456 } } },
    // Testing colors
    .{ .name = "White", .params = .{ .roughness = 0.1, .metallic = 1.0, .color = .{ 1.0, 1.0, 1.0 } } },
    .{ .name = "Red", .params = .{ .roughness = 0.1, .metallic = 1.0, .color = .{ 1.0, 0.0, 0.0 } } },
    .{ .name = "Blue", .params = .{ .roughness = 0.1, .metallic = 1.0, .color = .{ 0.0, 0.0, 1.0 } } },
    .{ .name = "Black", .params = .{ .roughness = 0.1, .metallic = 1.0, .color = .{ 0.0, 0.0, 0.0 } } },
};

const grid_dimensions = 7;
const model_paths = [_][]const u8{
    assets.teapot_ascii_path,
    // TODO: Setup Imgui bindings and allow option to switch between models
    //       Currently there is no point loading in the other models
    // assets.sphere_ascii_path,
    // assets.torusknot_ascii_path,
    // assets.venus_ascii_path,
};

//
// Member variables
//

camera: Camera,
render_pipeline: *gpu.RenderPipeline,
render_pass_descriptor: gpu.RenderPassDescriptor,
bind_group: *gpu.BindGroup,
queue: *gpu.Queue,
color_attachment: gpu.RenderPassColorAttachment,
depth_stencil_attachment_description: gpu.RenderPassDepthStencilAttachment,
depth_texture: *gpu.Texture,
depth_view: *gpu.TextureView,
timer: f32,
pressed_keys: PressedKeys,
models: [4]Model,
ubo_params: UboParams,
ubo_matrices: UboMatrices,
uniform_buffers: UniformBuffers,
material_params_dynamic: MaterialParamsDynamicGrid = [1]MaterialParamsDynamic{.{}} ** grid_element_count,
object_params_dynamic: ObjectParamsDynamicGrid = [1]ObjectParamsDynamic{.{}} ** grid_element_count,
buffers_bound: bool,
current_material_index: usize,
current_object_index: usize,

//
// Functions
//

pub fn init(app: *App, core: *mach.Core) !void {
    app.queue = core.device.getQueue();
    app.current_material_index = 0;
    app.buffers_bound = false;
    app.camera = Camera{
        .rotation_speed = 1.0,
        .movement_speed = 1.0,
    };

    //
    // Setup Camera
    //
    const aspect_ratio: f32 = @intToFloat(f32, core.current_desc.width) / @intToFloat(f32, core.current_desc.height);
    app.camera.setPosition(.{ 10.0, 13.0, 1.8 });
    app.camera.setRotation(.{ 62.5, 90.0, 0.0 });
    app.camera.setMovementSpeed(0.5);
    app.camera.setPerspective(60.0, aspect_ratio, 0.1, 256.0);
    app.camera.setRotationSpeed(0.25);

    //
    // Load Assets
    //

    var allocator = std.heap.c_allocator;
    for (model_paths) |model_path, model_path_i| {
        var model_file = std.fs.openFileAbsolute(model_path, .{}) catch |err| {
            std.log.err("Failed to load model: '{s}' Error: {}", .{ model_path, err });
            return error.LoadModelFileFailed;
        };
        defer model_file.close();

        var model_data = try model_file.readToEndAllocOptions(allocator, 4048 * 1024, 4048 * 1024, @alignOf(u8), 0);
        defer allocator.free(model_data);

        const m3d_model = m3d.load(model_data, null, null, null) orelse return error.LoadModelFailed;

        const vertex_count = m3d_model.handle.numvertex;
        const face_count = m3d_model.handle.numface;
        const index_count = face_count * 3;

        var model: *Model = &app.models[model_path_i];

        model.vertices = try allocator.alloc(Vertex, vertex_count);
        model.indices = try allocator.alloc(u32, index_count);

        const scale: f32 = 0.45;
        const vertices = m3d_model.handle.vertex[0..vertex_count];
        var i: usize = 0;
        while (i < face_count) : (i += 1) {
            std.debug.assert(i < vertex_count);

            const face = m3d_model.handle.face[i];
            const src_base_index: usize = (i * 3);
            model.indices[src_base_index + 0] = face.vertex[0];
            model.indices[src_base_index + 1] = face.vertex[1];
            model.indices[src_base_index + 2] = face.vertex[2];

            const normal0 = face.normal[0];
            const normal1 = face.normal[1];
            const normal2 = face.normal[2];

            if (normal0 == std.math.maxInt(u32)) {
                std.log.warn("No normals", .{});
                continue;
            }

            std.debug.assert(normal0 < vertices.len);
            std.debug.assert(normal1 < vertices.len);
            std.debug.assert(normal2 < vertices.len);

            var vertex0 = &model.vertices[face.vertex[0]];
            var vertex1 = &model.vertices[face.vertex[1]];
            var vertex2 = &model.vertices[face.vertex[2]];

            vertex0.normal[0] = vertices[normal0].x;
            vertex0.normal[1] = vertices[normal0].y;
            vertex0.normal[2] = vertices[normal0].z;
            vertex1.normal[0] = vertices[normal1].x;
            vertex1.normal[1] = vertices[normal1].y;
            vertex1.normal[2] = vertices[normal1].z;
            vertex2.normal[0] = vertices[normal2].x;
            vertex2.normal[1] = vertices[normal2].y;
            vertex2.normal[2] = vertices[normal2].z;
        }
        i = 0;
        while (i < vertex_count) : (i += 1) {
            const vertex = m3d_model.handle.vertex[i];
            model.vertices[i].position[0] = vertex.x * scale;
            model.vertices[i].position[1] = vertex.y * scale;
            model.vertices[i].position[2] = vertex.z * scale;
        }
        //
        // Load vertex and index data into webgpu buffers
        //
        model.vertex_buffer = core.device.createBuffer(&.{
            .usage = .{ .copy_dst = true, .vertex = true },
            .size = @sizeOf(Vertex) * model.vertices.len,
            .mapped_at_creation = false,
        });
        app.queue.writeBuffer(
            model.vertex_buffer,
            0,
            model.vertices,
        );

        model.index_buffer = core.device.createBuffer(&.{
            .usage = .{ .copy_dst = true, .index = true },
            .size = @sizeOf(u32) * model.indices.len,
            .mapped_at_creation = false,
        });
        app.queue.writeBuffer(
            model.index_buffer,
            0,
            model.indices,
        );
    }

    prepareUniformBuffers(app, core);
    setupPipeline(app, core);
    setupRenderPass(app, core);
}

pub fn deinit(_: *App, _: *mach.Core) void {}

pub fn update(app: *App, core: *mach.Core) !void {
    const frame_start_sec = std.time.timestamp();
    while (core.pollEvent()) |event| {
        switch (event) {
            .key_press => |ev| {
                const key = ev.key;
                if (key == .up or key == .w) app.pressed_keys.up = true;
                if (key == .down or key == .s) app.pressed_keys.down = true;
                if (key == .left or key == .a) app.pressed_keys.left = true;
                if (key == .right or key == .d) app.pressed_keys.right = true;
            },
            else => {},
        }
    }
    if (app.pressed_keys.areKeysPressed()) {
        app.camera.calculateMovement(app.pressed_keys);
        app.pressed_keys.clear();
        updateUniformBuffers(app);
    }

    const back_buffer_view = core.swap_chain.?.getCurrentTextureView();
    app.color_attachment.view = back_buffer_view;
    app.render_pass_descriptor = gpu.RenderPassDescriptor{
        .color_attachment_count = 1,
        .color_attachments = &[_]gpu.RenderPassColorAttachment{app.color_attachment},
        .depth_stencil_attachment = &app.depth_stencil_attachment_description,
    };
    const encoder = core.device.createCommandEncoder(null);
    const current_model = app.models[app.current_object_index];

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
    const frame_end_sec = std.time.timestamp();
    const frame_duration_sec = @intToFloat(f32, frame_end_sec) - @intToFloat(f32, frame_start_sec);
    app.timer = @mod(frame_duration_sec + app.timer, 1.0);
    std.debug.assert(app.timer >= 0.0);
    std.debug.assert(app.timer < 1.0);
    app.updateLights();
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
        .clear_stencil = 0,
        .stencil_load_op = .clear,
        .stencil_store_op = .store,
    };
}

fn prepareUniformBuffers(app: *App, core: *mach.Core) void {
    comptime {
        std.debug.assert(@sizeOf(ObjectParamsDynamic) == 256);
        std.debug.assert(@sizeOf(MaterialParamsDynamic) == 256);
    }

    app.uniform_buffers.ubo_matrices.size = roundToMultipleOf4(u32, @intCast(u32, @sizeOf(UboMatrices)));
    app.uniform_buffers.ubo_matrices.buffer = core.device.createBuffer(&.{
        .usage = .{ .copy_dst = true, .uniform = true },
        .size = app.uniform_buffers.ubo_matrices.size,
        .mapped_at_creation = false,
    });

    app.uniform_buffers.ubo_params.size = roundToMultipleOf4(u32, @intCast(u32, @sizeOf(UboParams)));
    app.uniform_buffers.ubo_params.buffer = core.device.createBuffer(&.{
        .usage = .{ .copy_dst = true, .uniform = true },
        .size = app.uniform_buffers.ubo_params.size,
        .mapped_at_creation = false,
    });

    //
    // Material parameter uniform buffer
    //
    app.uniform_buffers.material_params.model_size = @sizeOf(Vec2) + @sizeOf(Vec3);
    app.uniform_buffers.material_params.buffer_size = calculateConstantBufferByteSize(@sizeOf(MaterialParamsDynamicGrid));
    std.debug.assert(app.uniform_buffers.material_params.buffer_size >= app.uniform_buffers.material_params.model_size);
    app.uniform_buffers.material_params.buffer = core.device.createBuffer(&.{
        .usage = .{ .copy_dst = true, .uniform = true },
        .size = app.uniform_buffers.material_params.buffer_size,
        .mapped_at_creation = false,
    });

    //
    // Object parameter uniform buffer
    //
    app.uniform_buffers.object_params.model_size = @sizeOf(Vec3);
    app.uniform_buffers.object_params.buffer_size = calculateConstantBufferByteSize(@sizeOf(MaterialParamsDynamicGrid));
    std.debug.assert(app.uniform_buffers.object_params.buffer_size >= app.uniform_buffers.object_params.model_size);
    app.uniform_buffers.object_params.buffer = core.device.createBuffer(&.{
        .usage = .{ .copy_dst = true, .uniform = true },
        .size = app.uniform_buffers.object_params.buffer_size,
        .mapped_at_creation = false,
    });

    app.updateUniformBuffers();
    app.updateDynamicUniformBuffer();
    app.updateLights();
}

fn updateDynamicUniformBuffer(app: *App) void {
    var index: u32 = 0;
    var y: usize = 0;
    while (y < grid_dimensions) : (y += 1) {
        var x: usize = 0;
        while (x < grid_dimensions) : (x += 1) {
            const grid_dimensions_float = @intToFloat(f32, grid_dimensions);
            app.object_params_dynamic[index].position[0] = (@intToFloat(f32, x) - (grid_dimensions_float / 2) * 2.5);
            app.object_params_dynamic[index].position[1] = 0;
            app.object_params_dynamic[index].position[2] = (@intToFloat(f32, y) - (grid_dimensions_float / 2) * 2.5);
            app.material_params_dynamic[index].metallic = zm.clamp(@intToFloat(f32, x) / (grid_dimensions_float - 1), 0.1, 1.0);
            app.material_params_dynamic[index].roughness = zm.clamp(@intToFloat(f32, y) / (grid_dimensions_float - 1), 0.05, 1.0);
            app.material_params_dynamic[index].color = materials[app.current_material_index].params.color;
            index += 1;
        }
    }
    app.queue.writeBuffer(
        app.uniform_buffers.object_params.buffer,
        0,
        &app.object_params_dynamic,
    );
    app.queue.writeBuffer(
        app.uniform_buffers.material_params.buffer,
        0,
        &app.material_params_dynamic,
    );
}

fn updateUniformBuffers(app: *App) void {
    const projection = app.camera.matrices.perspective;
    zm.storeArr4(&app.ubo_matrices.projection[0], projection[0]);
    zm.storeArr4(&app.ubo_matrices.projection[1], projection[1]);
    zm.storeArr4(&app.ubo_matrices.projection[2], projection[2]);
    zm.storeArr4(&app.ubo_matrices.projection[3], projection[3]);

    zm.storeArr4(&app.ubo_matrices.view[0], app.camera.matrices.view[0]);
    zm.storeArr4(&app.ubo_matrices.view[1], app.camera.matrices.view[1]);
    zm.storeArr4(&app.ubo_matrices.view[2], app.camera.matrices.view[2]);
    zm.storeArr4(&app.ubo_matrices.view[3], app.camera.matrices.view[3]);
    const rotation_degrees = if (app.current_object_index == 1) @as(f32, -45.0) else @as(f32, -90.0);
    const model = zm.rotationY(rotation_degrees);
    zm.storeArr4(&app.ubo_matrices.model[0], model[0]);
    zm.storeArr4(&app.ubo_matrices.model[1], model[1]);
    zm.storeArr4(&app.ubo_matrices.model[2], model[2]);
    zm.storeArr4(&app.ubo_matrices.model[3], model[3]);
    app.ubo_matrices.camera_position = .{
        -app.camera.position[0],
        -app.camera.position[1],
        -app.camera.position[2],
    };
    app.queue.writeBuffer(app.uniform_buffers.ubo_matrices.buffer, 0, &[_]UboMatrices{app.ubo_matrices});
}

fn updateLights(app: *App) void {
    const p: f32 = 15.0;
    app.ubo_params.lights[0] = Vec4{ -p, -p * 0.5, -p, 1.0 };
    app.ubo_params.lights[1] = Vec4{ -p, -p * 0.5, p, 1.0 };
    app.ubo_params.lights[2] = Vec4{ p, -p * 0.5, p, 1.0 };
    app.ubo_params.lights[3] = Vec4{ p, -p * 0.5, -p, 1.0 };
    const base_value = toRadians(app.timer * 360.0);
    app.ubo_params.lights[0][0] = @sin(base_value) * 20.0;
    app.ubo_params.lights[0][2] = @cos(base_value) * 20.0;
    app.ubo_params.lights[1][0] = @cos(base_value) * 20.0;
    app.ubo_params.lights[1][1] = @sin(base_value) * 20.0;
    app.queue.writeBuffer(
        app.uniform_buffers.ubo_params.buffer,
        0,
        &[_]UboParams{app.ubo_params},
    );
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
                .min_binding_size = app.uniform_buffers.ubo_matrices.size,
            },
        },
        .{
            .binding = 1,
            .visibility = .{ .fragment = true },
            .buffer = .{
                .@"type" = .uniform,
                .has_dynamic_offset = false,
                .min_binding_size = app.uniform_buffers.ubo_params.size,
            },
        },
        .{
            .binding = 2,
            .visibility = .{ .fragment = true },
            .buffer = .{
                .@"type" = .uniform,
                .has_dynamic_offset = true,
                .min_binding_size = app.uniform_buffers.material_params.model_size,
            },
        },
        .{
            .binding = 3,
            .visibility = .{ .vertex = true },
            .buffer = .{
                .@"type" = .uniform,
                .has_dynamic_offset = true,
                .min_binding_size = app.uniform_buffers.object_params.model_size,
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

    const vertex_shader_code = @embedFile(vertex_shader_path);
    const vertex_shader_module = core.device.createShaderModule(&.{
        .next_in_chain = .{ .spirv_descriptor = &.{
            .code = @ptrCast([*]const u32, @alignCast(4, vertex_shader_code)),
            .code_size = vertex_shader_code.len / 4,
        } },
    });

    const fragment_shader_code = @embedFile(fragment_shader_path);
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
                .buffer = app.uniform_buffers.ubo_matrices.buffer,
                .size = app.uniform_buffers.ubo_matrices.size,
            },
            .{
                .binding = 1,
                .buffer = app.uniform_buffers.ubo_params.buffer,
                .size = app.uniform_buffers.ubo_params.size,
            },
            .{
                .binding = 2,
                .buffer = app.uniform_buffers.material_params.buffer,
                .size = app.uniform_buffers.material_params.model_size,
            },
            .{
                .binding = 3,
                .buffer = app.uniform_buffers.object_params.buffer,
                .size = app.uniform_buffers.object_params.model_size,
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
        .clear_stencil = 0,
        .stencil_load_op = .clear,
        .stencil_store_op = .store,
    };
}

fn projectRootPath() []const u8 {
    comptime {
        return std.fs.path.dirname(@src().file).?;
    }
}

inline fn roundToMultipleOf4(comptime T: type, value: T) T {
    return (value + 3) & ~@as(T, 3);
}

inline fn calculateConstantBufferByteSize(byte_size: usize) usize {
    return (byte_size + 255) & ~@as(usize, 255);
}

inline fn toRadians(degrees: f32) f32 {
    return degrees * (std.math.pi / 180.0);
}
