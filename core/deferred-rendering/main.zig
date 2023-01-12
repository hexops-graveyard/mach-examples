const std = @import("std");
const mach = @import("mach");
const gpu = @import("gpu");
const zm = @import("zmath");
const m3d = @import("model3d");
const assets = @import("assets");
const imgui = @import("mach-imgui").MachImgui(mach);
const VertexWriter = mach.gfx.VertexWriter;

pub const App = @This();

const Vec2 = [2]f32;
const Vec3 = [3]f32;
const Vec4 = [4]f32;
const Mat4 = [4]Vec4;

fn Dimensions2D(comptime T: type) type {
    return struct {
        width: T,
        height: T,
    };
}

const Vertex = extern struct {
    position: Vec3,
    normal: Vec3,
    uv: Vec2,
};

const ViewMatrices = struct {
    up_vector: zm.Vec,
    origin: zm.Vec,
    projection_matrix: zm.Mat,
    view_proj_matrix: zm.Mat,
};

const TextureQuadPass = struct {
    color_attachment: gpu.RenderPassColorAttachment,
    descriptor: gpu.RenderPassDescriptor,
};

const WriteGBufferPass = struct {
    color_attachments: [3]gpu.RenderPassColorAttachment,
    depth_stencil_attachment: gpu.RenderPassDepthStencilAttachment,
    descriptor: gpu.RenderPassDescriptor,
};

const RenderMode = enum(u32) {
    rendering,
    gbuffer_view,
};

const Settings = struct {
    render_mode: RenderMode,
    lights_count: i32,
};

//
// Constants
//

const max_num_lights = 1024;
const light_data_stride = 8;
const light_extent_min = Vec3{ -50.0, -30.0, -50.0 };
const light_extent_max = Vec3{ 50.0, 30.0, 50.0 };

//
// Member variables
//

const GBuffer = struct {
    texture_2d_float: *gpu.Texture,
    texture_albedo: *gpu.Texture,
    texture_views: [3]*gpu.TextureView,
};

const Lights = struct {
    buffer: *gpu.Buffer,
    buffer_size: u64,
    extent_buffer: *gpu.Buffer,
    extent_buffer_size: u64,
    config_uniform_buffer: *gpu.Buffer,
    config_uniform_buffer_size: u64,
    buffer_bind_group: *gpu.BindGroup,
    buffer_bind_group_layout: *gpu.BindGroupLayout,
    buffer_compute_bind_group: *gpu.BindGroup,
    buffer_compute_bind_group_layout: *gpu.BindGroupLayout,
};

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

core: mach.Core,

timer: mach.Timer,
delta_time: f32,

queue: *gpu.Queue,
camera_rotation: f32,
depth_texture: *gpu.Texture,
depth_texture_view: *gpu.TextureView,
vertex_buffer: *gpu.Buffer,
vertex_count: u32,
index_buffer: *gpu.Buffer,
index_count: u32,
gbuffer: GBuffer,
model_uniform_buffer: *gpu.Buffer,
camera_uniform_buffer: *gpu.Buffer,
surface_size_uniform_buffer: *gpu.Buffer,
lights: Lights,
view_matrices: ViewMatrices,

// Bind groups
scene_uniform_bind_group: *gpu.BindGroup,
surface_size_uniform_bind_group: *gpu.BindGroup,
gbuffer_textures_bind_group: *gpu.BindGroup,

// Bind group layouts
scene_uniform_bind_group_layout: *gpu.BindGroupLayout,
surface_size_uniform_bind_group_layout: *gpu.BindGroupLayout,
gbuffer_textures_bind_group_layout: *gpu.BindGroupLayout,

// Pipelines
write_gbuffers_pipeline: *gpu.RenderPipeline,
gbuffers_debug_view_pipeline: *gpu.RenderPipeline,
deferred_render_pipeline: *gpu.RenderPipeline,
light_update_compute_pipeline: *gpu.ComputePipeline,
imgui_render_pipeline: *gpu.RenderPipeline,

// Pipeline layouts
write_gbuffers_pipeline_layout: *gpu.PipelineLayout,
gbuffers_debug_view_pipeline_layout: *gpu.PipelineLayout,
deferred_render_pipeline_layout: *gpu.PipelineLayout,
light_update_compute_pipeline_layout: *gpu.PipelineLayout,

// Render pass descriptor
write_gbuffer_pass: WriteGBufferPass,
texture_quad_pass: TextureQuadPass,
settings: Settings,

screen_dimensions: Dimensions2D(u32),
is_paused: bool,

//
// Functions
//

pub fn init(app: *App) !void {
    app.core = try mach.Core.init(gpa.allocator(), .{});

    app.timer = try mach.Timer.start();

    app.queue = app.core.device().getQueue();
    app.camera_rotation = 0.0;
    app.is_paused = false;
    app.settings.render_mode = .rendering;
    app.settings.lights_count = 128;

    app.screen_dimensions = Dimensions2D(u32){
        .width = app.core.descriptor().width,
        .height = app.core.descriptor().height,
    };

    try app.loadMeshFromFile(std.heap.c_allocator, assets.stanford_dragon.path);
    app.prepareGBufferTextureRenderTargets();
    app.prepareDepthTexture();
    app.prepareBindGroupLayouts();
    app.prepareRenderPipelineLayouts();
    app.prepareWriteGBuffersPipeline();
    app.prepareGBuffersDebugViewPipeline();
    app.prepareDeferredRenderPipeline();
    app.setupRenderPasses();
    app.prepareUniformBuffers();
    app.prepareComputePipelineLayout();
    app.prepareLightUpdateComputePipeline();
    app.prepareLights();
    app.prepareViewMatrices();

    app.setupImgui();
}

pub fn deinit(app: *App) void {
    defer _ = gpa.deinit();
    defer app.core.deinit();

    app.write_gbuffers_pipeline.release();
    app.gbuffers_debug_view_pipeline.release();
    app.deferred_render_pipeline.release();
    app.light_update_compute_pipeline.release();

    app.write_gbuffers_pipeline_layout.release();
    app.gbuffers_debug_view_pipeline_layout.release();
    app.deferred_render_pipeline_layout.release();
    app.light_update_compute_pipeline_layout.release();

    app.scene_uniform_bind_group.release();
    app.surface_size_uniform_bind_group.release();
    app.gbuffer_textures_bind_group.release();

    app.lights.buffer.release();
    app.lights.extent_buffer.release();
    app.lights.config_uniform_buffer.release();
    app.lights.buffer_bind_group.release();
    app.lights.buffer_bind_group_layout.release();
    app.lights.buffer_compute_bind_group.release();
    app.lights.buffer_compute_bind_group_layout.release();

    app.gbuffer.texture_views[0].release();
    app.gbuffer.texture_views[1].release();
    app.gbuffer.texture_views[2].release();

    app.gbuffer.texture_2d_float.release();
    app.gbuffer.texture_albedo.release();

    app.scene_uniform_bind_group_layout.release();
    app.surface_size_uniform_bind_group_layout.release();
    app.gbuffer_textures_bind_group_layout.release();

    app.depth_texture_view.release();
    app.depth_texture.release();
    app.vertex_buffer.release();
    app.index_buffer.release();
    app.model_uniform_buffer.release();
    app.camera_uniform_buffer.release();

    imgui.backend.deinit();
}

pub fn update(app: *App) !bool {
    app.delta_time = app.timer.lap();

    while (app.core.pollEvents()) |event| {
        switch (event) {
            .framebuffer_resize => |ev| {
                app.screen_dimensions.width = ev.width;
                app.screen_dimensions.height = ev.height;

                app.depth_texture_view.release();
                app.depth_texture.release();

                app.gbuffer.texture_2d_float.release();
                app.gbuffer.texture_albedo.release();
                app.gbuffer.texture_views[0].release();
                app.gbuffer.texture_views[1].release();
                app.gbuffer.texture_views[2].release();

                app.prepareGBufferTextureRenderTargets();
                app.prepareDepthTexture();
                app.setupRenderPasses();

                const bind_group_entries = [_]gpu.BindGroup.Entry{
                    gpu.BindGroup.Entry.textureView(0, app.gbuffer.texture_views[0]),
                    gpu.BindGroup.Entry.textureView(1, app.gbuffer.texture_views[1]),
                    gpu.BindGroup.Entry.textureView(2, app.gbuffer.texture_views[2]),
                };
                app.gbuffer_textures_bind_group = app.core.device().createBindGroup(
                    &gpu.BindGroup.Descriptor.init(.{
                        .layout = app.gbuffer_textures_bind_group_layout,
                        .entries = &bind_group_entries,
                    }),
                );

                app.prepareViewMatrices();
            },
            .close => return true,
            else => {},
        }

        imgui.backend.passEvent(event);
    }

    const command = try app.buildCommandBuffer();
    app.queue.submit(&[_]*gpu.CommandBuffer{command});

    command.release();
    app.core.swapChain().present();
    app.core.swapChain().getCurrentTextureView().release();

    if (!app.is_paused) {
        app.updateUniformBuffers();
    }

    return false;
}

fn loadMeshFromFile(app: *App, allocator: std.mem.Allocator, model_path: []const u8) !void {
    var model_file = std.fs.cwd().openFile(model_path, .{}) catch |err| {
        std.log.err("Failed to load model: '{s}' Error: {}", .{ model_path, err });
        return error.LoadModelFileFailed;
    };
    defer model_file.close();

    var model_data = try model_file.readToEndAllocOptions(allocator, 4048 * 1024, 4048 * 1024, @alignOf(u8), 0);
    defer allocator.free(model_data);

    const m3d_model = m3d.load(model_data, null, null, null) orelse return error.LoadModelFailed;

    const vertex_count = m3d_model.handle.numvertex;
    const vertices = m3d_model.handle.vertex[0..vertex_count];

    const face_count = m3d_model.handle.numface;
    app.index_count = (face_count * 3) + 6;

    var vertex_writer = try VertexWriter(Vertex, u16).init(
        allocator,
        @intCast(u16, app.index_count),
        @intCast(u16, vertex_count),
        @intCast(u16, face_count * 3),
    );
    defer vertex_writer.deinit(allocator);

    const scale: f32 = 80.0;
    const plane_xy = [2]usize{ 0, 1 };
    var extent_min = [2]f32{ std.math.floatMax(f32), std.math.floatMax(f32) };
    var extent_max = [2]f32{ std.math.floatMin(f32), std.math.floatMin(f32) };

    var i: usize = 0;
    while (i < face_count) : (i += 1) {
        const face = m3d_model.handle.face[i];
        var x: usize = 0;
        while (x < 3) : (x += 1) {
            const vertex_index = face.vertex[x];
            const normal_index = face.normal[x];
            const position = Vec3{
                vertices[vertex_index].x * scale,
                vertices[vertex_index].y * scale,
                vertices[vertex_index].z * scale,
            };
            extent_min[0] = @min(position[plane_xy[0]], extent_min[0]);
            extent_min[1] = @min(position[plane_xy[1]], extent_min[1]);
            extent_max[0] = @max(position[plane_xy[0]], extent_max[0]);
            extent_max[1] = @max(position[plane_xy[1]], extent_max[1]);
            const vertex = Vertex{ .position = position, .normal = .{
                vertices[normal_index].x,
                vertices[normal_index].y,
                vertices[normal_index].z,
            }, .uv = .{ position[plane_xy[0]], position[plane_xy[1]] } };
            vertex_writer.put(vertex, @intCast(u16, vertex_index));
        }
    }

    const vertex_buffer = vertex_writer.vertices[0 .. vertex_writer.next_packed_index + 4];
    const index_buffer = vertex_writer.indices;

    app.vertex_count = @intCast(u32, vertex_buffer.len);

    //
    // Compute UV values
    //
    for (vertex_buffer) |*vertex| {
        vertex.uv = .{
            (vertex.uv[0] - extent_min[0]) / (extent_max[0] - extent_min[0]),
            (vertex.uv[1] - extent_min[1]) / (extent_max[1] - extent_min[1]),
        };
    }

    //
    // Manually append ground plane to mesh
    //
    {
        const last_vertex_index: u16 = @intCast(u16, vertex_buffer.len - 4);
        const index_base = index_buffer.len - 6;
        index_buffer[index_base + 0] = last_vertex_index;
        index_buffer[index_base + 1] = last_vertex_index + 2;
        index_buffer[index_base + 2] = last_vertex_index + 1;
        index_buffer[index_base + 3] = last_vertex_index;
        index_buffer[index_base + 4] = last_vertex_index + 1;
        index_buffer[index_base + 5] = last_vertex_index + 3;
    }

    {
        const index_base = vertex_buffer.len - 4;
        vertex_buffer[index_base + 0].position = .{ -100.0, 20.0, -100.0 };
        vertex_buffer[index_base + 1].position = .{ 100.0, 20.0, 100.0 };
        vertex_buffer[index_base + 2].position = .{ -100.0, 20.0, 100.0 };
        vertex_buffer[index_base + 3].position = .{ 100.0, 20.0, -100.0 };
        vertex_buffer[index_base + 0].normal = .{ 0.0, 1.0, 0.0 };
        vertex_buffer[index_base + 1].normal = .{ 0.0, 1.0, 0.0 };
        vertex_buffer[index_base + 2].normal = .{ 0.0, 1.0, 0.0 };
        vertex_buffer[index_base + 3].normal = .{ 0.0, 1.0, 0.0 };
        vertex_buffer[index_base + 0].uv = .{ 0.0, 0.0 };
        vertex_buffer[index_base + 1].uv = .{ 1.0, 1.0 };
        vertex_buffer[index_base + 2].uv = .{ 0.0, 1.0 };
        vertex_buffer[index_base + 3].uv = .{ 1.0, 0.0 };
    }

    {
        const buffer_size = vertex_buffer.len * @sizeOf(Vertex);
        app.vertex_buffer = app.core.device().createBuffer(&.{
            .usage = .{ .vertex = true },
            .size = roundToMultipleOf4(u64, buffer_size),
            .mapped_at_creation = true,
        });
        var mapping = app.vertex_buffer.getMappedRange(Vertex, 0, vertex_buffer.len).?;
        std.mem.copy(Vertex, mapping[0..vertex_buffer.len], vertex_buffer);
        app.vertex_buffer.unmap();
    }
    {
        const buffer_size = index_buffer.len * @sizeOf(u16);
        app.index_buffer = app.core.device().createBuffer(&.{
            .usage = .{ .index = true },
            .size = roundToMultipleOf4(u64, buffer_size),
            .mapped_at_creation = true,
        });
        var mapping = app.index_buffer.getMappedRange(u16, 0, index_buffer.len).?;
        std.mem.copy(u16, mapping[0..index_buffer.len], index_buffer);
        app.index_buffer.unmap();
    }
}

fn prepareGBufferTextureRenderTargets(app: *App) void {
    var screen_extent = gpu.Extent3D{
        .width = app.screen_dimensions.width,
        .height = app.screen_dimensions.height,
        .depth_or_array_layers = 2,
    };
    app.gbuffer.texture_2d_float = app.core.device().createTexture(&.{
        .size = screen_extent,
        .format = .rgba32_float,
        .usage = .{
            .texture_binding = true,
            .render_attachment = true,
        },
    });
    screen_extent.depth_or_array_layers = 1;
    app.gbuffer.texture_albedo = app.core.device().createTexture(&.{
        .size = screen_extent,
        .format = .bgra8_unorm,
        .usage = .{
            .texture_binding = true,
            .render_attachment = true,
        },
    });

    var texture_view_descriptor = gpu.TextureView.Descriptor{
        .format = .rgba32_float,
        .dimension = .dimension_2d,
        .array_layer_count = 1,
        .aspect = .all,
        .base_array_layer = 0,
    };

    app.gbuffer.texture_views[0] = app.gbuffer.texture_2d_float.createView(&texture_view_descriptor);
    texture_view_descriptor.base_array_layer = 1;
    app.gbuffer.texture_views[1] = app.gbuffer.texture_2d_float.createView(&texture_view_descriptor);
    texture_view_descriptor.base_array_layer = 0;
    texture_view_descriptor.format = .bgra8_unorm;
    app.gbuffer.texture_views[2] = app.gbuffer.texture_albedo.createView(&texture_view_descriptor);
}

fn prepareDepthTexture(app: *App) void {
    const screen_extent = gpu.Extent3D{
        .width = app.screen_dimensions.width,
        .height = app.screen_dimensions.height,
    };
    app.depth_texture = app.core.device().createTexture(&.{
        .usage = .{ .render_attachment = true },
        .format = .depth24_plus,
        .size = .{
            .width = screen_extent.width,
            .height = screen_extent.height,
            .depth_or_array_layers = 1,
        },
    });
    app.depth_texture_view = app.depth_texture.createView(&gpu.TextureView.Descriptor{
        .format = .depth24_plus,
        .dimension = .dimension_2d,
        .array_layer_count = 1,
        .aspect = .all,
    });
}

fn prepareBindGroupLayouts(app: *App) void {
    {
        const bind_group_layout_entries = [_]gpu.BindGroupLayout.Entry{
            gpu.BindGroupLayout.Entry.texture(0, .{ .fragment = true }, .unfilterable_float, .dimension_2d, false),
            gpu.BindGroupLayout.Entry.texture(1, .{ .fragment = true }, .unfilterable_float, .dimension_2d, false),
            gpu.BindGroupLayout.Entry.texture(2, .{ .fragment = true }, .unfilterable_float, .dimension_2d, false),
        };
        app.gbuffer_textures_bind_group_layout = app.core.device().createBindGroupLayout(
            &gpu.BindGroupLayout.Descriptor.init(.{
                .entries = &bind_group_layout_entries,
            }),
        );
    }
    {
        const min_binding_size = light_data_stride * max_num_lights * @sizeOf(f32);
        const visibility = gpu.ShaderStageFlags{ .fragment = true, .compute = true };
        const bind_group_layout_entries = [_]gpu.BindGroupLayout.Entry{
            gpu.BindGroupLayout.Entry.buffer(
                0,
                visibility,
                .read_only_storage,
                false,
                min_binding_size,
            ),
            gpu.BindGroupLayout.Entry.buffer(1, visibility, .uniform, false, @sizeOf(u32)),
        };
        app.lights.buffer_bind_group_layout = app.core.device().createBindGroupLayout(
            &gpu.BindGroupLayout.Descriptor.init(.{
                .entries = &bind_group_layout_entries,
            }),
        );
    }
    {
        const bind_group_layout_entries = [_]gpu.BindGroupLayout.Entry{
            gpu.BindGroupLayout.Entry.buffer(0, .{ .fragment = true }, .uniform, false, @sizeOf(Vec2)),
        };
        app.surface_size_uniform_bind_group_layout = app.core.device().createBindGroupLayout(
            &gpu.BindGroupLayout.Descriptor.init(.{
                .entries = &bind_group_layout_entries,
            }),
        );
    }
    {
        const bind_group_layout_entries = [_]gpu.BindGroupLayout.Entry{
            gpu.BindGroupLayout.Entry.buffer(0, .{ .vertex = true }, .uniform, false, @sizeOf(Mat4) * 2),
            gpu.BindGroupLayout.Entry.buffer(1, .{ .vertex = true }, .uniform, false, @sizeOf(Mat4)),
        };
        app.scene_uniform_bind_group_layout = app.core.device().createBindGroupLayout(
            &gpu.BindGroupLayout.Descriptor.init(.{
                .entries = &bind_group_layout_entries,
            }),
        );
    }
    {
        const bind_group_layout_entries = [_]gpu.BindGroupLayout.Entry{
            gpu.BindGroupLayout.Entry.buffer(0, .{ .compute = true }, .storage, false, @sizeOf(f32) * light_data_stride * max_num_lights),
            gpu.BindGroupLayout.Entry.buffer(1, .{ .compute = true }, .uniform, false, @sizeOf(u32)),
            gpu.BindGroupLayout.Entry.buffer(2, .{ .compute = true }, .uniform, false, @sizeOf(Vec4) * 2),
        };
        app.lights.buffer_compute_bind_group_layout = app.core.device().createBindGroupLayout(
            &gpu.BindGroupLayout.Descriptor.init(.{
                .entries = &bind_group_layout_entries,
            }),
        );
    }
}

fn prepareRenderPipelineLayouts(app: *App) void {
    {
        // Write GBuffers pipeline layout
        const bind_group_layouts = [_]*gpu.BindGroupLayout{app.scene_uniform_bind_group_layout};
        app.write_gbuffers_pipeline_layout = app.core.device().createPipelineLayout(&gpu.PipelineLayout.Descriptor.init(.{
            .bind_group_layouts = &bind_group_layouts,
        }));
    }
    {
        // GBuffers debug view pipeline layout
        const bind_group_layouts = [_]*gpu.BindGroupLayout{
            app.gbuffer_textures_bind_group_layout,
            app.surface_size_uniform_bind_group_layout,
        };
        app.gbuffers_debug_view_pipeline_layout = app.core.device().createPipelineLayout(&gpu.PipelineLayout.Descriptor.init(.{
            .bind_group_layouts = &bind_group_layouts,
        }));
    }
    {
        // Deferred render pipeline layout
        const bind_group_layouts = [_]*gpu.BindGroupLayout{
            app.gbuffer_textures_bind_group_layout,
            app.lights.buffer_bind_group_layout,
            app.surface_size_uniform_bind_group_layout,
        };
        app.deferred_render_pipeline_layout = app.core.device().createPipelineLayout(&gpu.PipelineLayout.Descriptor.init(.{
            .bind_group_layouts = &bind_group_layouts,
        }));
    }
}

fn prepareWriteGBuffersPipeline(app: *App) void {
    const color_target_states = [_]gpu.ColorTargetState{
        .{ .format = .rgba32_float },
        .{ .format = .rgba32_float },
        .{ .format = .bgra8_unorm },
    };

    const write_gbuffers_vertex_buffer_layout = gpu.VertexBufferLayout.init(.{
        .array_stride = @sizeOf(Vertex),
        .step_mode = .vertex,
        .attributes = &.{
            .{ .format = .float32x3, .offset = @offsetOf(Vertex, "position"), .shader_location = 0 },
            .{ .format = .float32x3, .offset = @offsetOf(Vertex, "normal"), .shader_location = 1 },
            .{ .format = .float32x2, .offset = @offsetOf(Vertex, "uv"), .shader_location = 2 },
        },
    });

    const vertex_shader_module = app.core.device().createShaderModuleWGSL(
        "vertexWriteGBuffers.wgsl",
        @embedFile("vertexWriteGBuffers.wgsl"),
    );
    const fragment_shader_module = app.core.device().createShaderModuleWGSL(
        "fragmentWriteGBuffers.wgsl",
        @embedFile("fragmentWriteGBuffers.wgsl"),
    );

    const pipeline_descriptor = gpu.RenderPipeline.Descriptor{
        .layout = app.write_gbuffers_pipeline_layout,
        .primitive = .{ .cull_mode = .back },
        .depth_stencil = &.{
            .format = .depth24_plus,
            .depth_write_enabled = true,
            .depth_compare = .less,
        },
        .vertex = gpu.VertexState.init(.{
            .module = vertex_shader_module,
            .entry_point = "main",
            .buffers = &.{write_gbuffers_vertex_buffer_layout},
        }),
        .fragment = &gpu.FragmentState.init(.{
            .module = fragment_shader_module,
            .entry_point = "main",
            .targets = &color_target_states,
        }),
    };
    app.write_gbuffers_pipeline = app.core.device().createRenderPipeline(&pipeline_descriptor);

    vertex_shader_module.release();
    fragment_shader_module.release();
}

fn prepareGBuffersDebugViewPipeline(app: *App) void {
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

    const vertex_shader_module = app.core.device().createShaderModuleWGSL(
        "vertexTextureQuad.wgsl",
        @embedFile("vertexTextureQuad.wgsl"),
    );
    const fragment_shader_module = app.core.device().createShaderModuleWGSL(
        "fragmentGBuffersDebugView.wgsl",
        @embedFile("fragmentGBuffersDebugView.wgsl"),
    );
    const pipeline_descriptor = gpu.RenderPipeline.Descriptor{
        .layout = app.gbuffers_debug_view_pipeline_layout,
        .primitive = .{
            .cull_mode = .back,
        },
        .vertex = gpu.VertexState.init(.{
            .module = vertex_shader_module,
            .entry_point = "main",
        }),
        .fragment = &gpu.FragmentState.init(.{
            .module = fragment_shader_module,
            .entry_point = "main",
            .targets = &.{color_target_state},
        }),
    };
    app.gbuffers_debug_view_pipeline = app.core.device().createRenderPipeline(&pipeline_descriptor);
    vertex_shader_module.release();
    fragment_shader_module.release();
}

fn prepareDeferredRenderPipeline(app: *App) void {
    const blend_component_descriptor = gpu.BlendComponent{
        .operation = .add,
        .src_factor = .one,
        .dst_factor = .zero,
    };

    const color_target_state = gpu.ColorTargetState{
        .format = .bgra8_unorm,
        .blend = &.{
            .color = blend_component_descriptor,
            .alpha = blend_component_descriptor,
        },
    };

    const vertex_shader_module = app.core.device().createShaderModuleWGSL(
        "vertexTextureQuad.wgsl",
        @embedFile("vertexTextureQuad.wgsl"),
    );
    const fragment_shader_module = app.core.device().createShaderModuleWGSL(
        "fragmentDeferredRendering.wgsl",
        @embedFile("fragmentDeferredRendering.wgsl"),
    );
    const pipeline_descriptor = gpu.RenderPipeline.Descriptor{
        .layout = app.deferred_render_pipeline_layout,
        .primitive = .{
            .cull_mode = .back,
        },
        .vertex = gpu.VertexState.init(.{
            .module = vertex_shader_module,
            .entry_point = "main",
        }),
        .fragment = &gpu.FragmentState.init(.{
            .module = fragment_shader_module,
            .entry_point = "main",
            .targets = &.{color_target_state},
        }),
    };
    app.deferred_render_pipeline = app.core.device().createRenderPipeline(&pipeline_descriptor);
    vertex_shader_module.release();
    fragment_shader_module.release();
}

fn setupRenderPasses(app: *App) void {
    {
        // Write GBuffer pass
        app.write_gbuffer_pass.color_attachments = [3]gpu.RenderPassColorAttachment{
            .{
                .view = app.gbuffer.texture_views[0],
                .clear_value = .{
                    .r = std.math.floatMax(f32),
                    .g = std.math.floatMax(f32),
                    .b = std.math.floatMax(f32),
                    .a = 1.0,
                },
                .load_op = .clear,
                .store_op = .store,
            },
            .{
                .view = app.gbuffer.texture_views[1],
                .clear_value = .{
                    .r = 0.0,
                    .g = 0.0,
                    .b = 1.0,
                    .a = 1.0,
                },
                .load_op = .clear,
                .store_op = .store,
            },
            .{
                .view = app.gbuffer.texture_views[2],
                .clear_value = .{
                    .r = 0.0,
                    .g = 0.0,
                    .b = 0.0,
                    .a = 1.0,
                },
                .load_op = .clear,
                .store_op = .store,
            },
        };

        app.write_gbuffer_pass.depth_stencil_attachment = gpu.RenderPassDepthStencilAttachment{
            .view = app.depth_texture_view,
            .depth_load_op = .clear,
            .depth_store_op = .store,
            .depth_clear_value = 1.0,
            .stencil_clear_value = 1.0,
        };

        app.write_gbuffer_pass.descriptor = gpu.RenderPassDescriptor{
            .color_attachment_count = 3,
            .color_attachments = &app.write_gbuffer_pass.color_attachments,
            .depth_stencil_attachment = &app.write_gbuffer_pass.depth_stencil_attachment,
        };
    }
    {
        // Texture Quad Pass
        app.texture_quad_pass.color_attachment = gpu.RenderPassColorAttachment{
            .clear_value = .{
                .r = 0.0,
                .g = 0.0,
                .b = 0.0,
                .a = 1.0,
            },
            .load_op = .clear,
            .store_op = .store,
        };

        app.texture_quad_pass.descriptor = gpu.RenderPassDescriptor{
            .color_attachment_count = 1,
            .color_attachments = &[_]gpu.RenderPassColorAttachment{app.texture_quad_pass.color_attachment},
        };
    }
}

fn prepareUniformBuffers(app: *App) void {
    {
        // Config uniform buffer
        app.lights.config_uniform_buffer_size = @sizeOf(i32);
        app.lights.config_uniform_buffer = app.core.device().createBuffer(&.{
            .usage = .{ .copy_dst = true, .uniform = true },
            .size = app.lights.config_uniform_buffer_size,
            .mapped_at_creation = true,
        });
        var config_data = app.lights.config_uniform_buffer.getMappedRange(i32, 0, 1).?;
        config_data[0] = app.settings.lights_count;
        app.lights.config_uniform_buffer.unmap();
    }
    {
        // Model uniform buffer
        app.model_uniform_buffer = app.core.device().createBuffer(&.{
            .usage = .{ .copy_dst = true, .uniform = true },
            .size = @sizeOf(Mat4) * 2,
        });
    }
    {
        // Camera uniform buffer
        app.camera_uniform_buffer = app.core.device().createBuffer(&.{
            .usage = .{ .copy_dst = true, .uniform = true },
            .size = @sizeOf(Mat4),
        });
    }
    {
        // Scene uniform bind group
        const bind_group_entries = [_]gpu.BindGroup.Entry{
            .{
                .binding = 0,
                .buffer = app.model_uniform_buffer,
                .size = @sizeOf(Mat4) * 2,
            },
            .{
                .binding = 1,
                .buffer = app.camera_uniform_buffer,
                .size = @sizeOf(Mat4),
            },
        };
        app.scene_uniform_bind_group = app.core.device().createBindGroup(
            &gpu.BindGroup.Descriptor.init(.{
                .layout = app.write_gbuffers_pipeline.getBindGroupLayout(0),
                .entries = &bind_group_entries,
            }),
        );
    }
    {
        // Surface size uniform buffer
        app.surface_size_uniform_buffer = app.core.device().createBuffer(&.{
            .usage = .{ .copy_dst = true, .uniform = true },
            .size = @sizeOf(f32) * 4,
        });
    }
    {
        // Surface size uniform bind group
        const bind_group_entries = [_]gpu.BindGroup.Entry{
            .{
                .binding = 0,
                .buffer = app.surface_size_uniform_buffer,
                .size = @sizeOf(f32) * 2,
            },
        };
        app.surface_size_uniform_bind_group = app.core.device().createBindGroup(
            &gpu.BindGroup.Descriptor.init(.{
                .layout = app.surface_size_uniform_bind_group_layout,
                .entries = &bind_group_entries,
            }),
        );
    }
    {
        // GBuffer textures bind group
        const bind_group_entries = [_]gpu.BindGroup.Entry{
            gpu.BindGroup.Entry.textureView(0, app.gbuffer.texture_views[0]),
            gpu.BindGroup.Entry.textureView(1, app.gbuffer.texture_views[1]),
            gpu.BindGroup.Entry.textureView(2, app.gbuffer.texture_views[2]),
        };
        app.gbuffer_textures_bind_group = app.core.device().createBindGroup(
            &gpu.BindGroup.Descriptor.init(.{
                .layout = app.gbuffer_textures_bind_group_layout,
                .entries = &bind_group_entries,
            }),
        );
    }
}

fn prepareComputePipelineLayout(app: *App) void {
    const bind_group_layouts = [_]*gpu.BindGroupLayout{app.lights.buffer_compute_bind_group_layout};
    app.light_update_compute_pipeline_layout = app.core.device().createPipelineLayout(&gpu.PipelineLayout.Descriptor.init(.{
        .bind_group_layouts = &bind_group_layouts,
    }));
}

fn prepareLightUpdateComputePipeline(app: *App) void {
    const shader_module = app.core.device().createShaderModuleWGSL(
        "lightUpdate.wgsl",
        @embedFile("lightUpdate.wgsl"),
    );
    app.light_update_compute_pipeline = app.core.device().createComputePipeline(&gpu.ComputePipeline.Descriptor{
        .compute = gpu.ProgrammableStageDescriptor{
            .module = shader_module,
            .entry_point = "main",
        },
        .layout = app.light_update_compute_pipeline_layout,
    });
    shader_module.release();
}

fn prepareLights(app: *App) void {
    // Lights data are uploaded in a storage buffer
    // which could be updated/culled/etc. with a compute shader
    const extent = comptime Vec3{
        light_extent_max[0] - light_extent_min[0],
        light_extent_max[1] - light_extent_min[1],
        light_extent_max[2] - light_extent_min[2],
    };
    app.lights.buffer_size = @sizeOf(f32) * light_data_stride * max_num_lights;
    app.lights.buffer = app.core.device().createBuffer(&.{
        .usage = .{ .storage = true },
        .size = app.lights.buffer_size,
        .mapped_at_creation = true,
    });
    // We randomly populate lights randomly in a box range
    // And simply move them along y-axis per frame to show they are dynamic lightings
    var light_data = app.lights.buffer.getMappedRange(f32, 0, light_data_stride * max_num_lights).?;

    var xoroshiro = std.rand.Xoroshiro128.init(9273853284918);
    const rng = std.rand.Random.init(
        &xoroshiro,
        std.rand.Xoroshiro128.fill,
    );
    var i: usize = 0;
    var offset: usize = 0;
    while (i < max_num_lights) : (i += 1) {
        offset = light_data_stride * i;
        // Position
        light_data[offset + 0] = rng.float(f32) * extent[0] + light_extent_min[0];
        light_data[offset + 1] = rng.float(f32) * extent[1] + light_extent_min[1];
        light_data[offset + 2] = rng.float(f32) * extent[2] + light_extent_min[2];
        light_data[offset + 3] = 1.0;
        // Color
        light_data[offset + 4] = rng.float(f32) * 2.0;
        light_data[offset + 5] = rng.float(f32) * 2.0;
        light_data[offset + 6] = rng.float(f32) * 2.0;
        // Radius
        light_data[offset + 7] = 20.0;
    }
    app.lights.buffer.unmap();
    //
    // Lights extent buffer
    //
    app.lights.extent_buffer_size = @sizeOf(f32) * light_data_stride * max_num_lights;
    app.lights.extent_buffer = app.core.device().createBuffer(&.{
        .usage = .{ .uniform = true, .copy_dst = true },
        .size = app.lights.extent_buffer_size,
    });
    var light_extent_data = [1]f32{0.0} ** 8;
    std.mem.copy(f32, light_extent_data[0..3], &light_extent_min);
    std.mem.copy(f32, light_extent_data[4..7], &light_extent_max);
    app.queue.writeBuffer(
        app.lights.extent_buffer,
        0,
        &light_extent_data,
    );
    //
    // Lights buffer bind group
    //
    {
        const bind_group_entries = [_]gpu.BindGroup.Entry{
            .{
                .binding = 0,
                .buffer = app.lights.buffer,
                .size = app.lights.buffer_size,
            },
            .{
                .binding = 1,
                .buffer = app.lights.config_uniform_buffer,
                .size = app.lights.config_uniform_buffer_size,
            },
        };
        app.lights.buffer_bind_group = app.core.device().createBindGroup(
            &gpu.BindGroup.Descriptor.init(.{
                .layout = app.lights.buffer_bind_group_layout,
                .entries = &bind_group_entries,
            }),
        );
    }
    //
    // Lights buffer compute bind group
    //
    {
        const bind_group_entries = [_]gpu.BindGroup.Entry{
            .{
                .binding = 0,
                .buffer = app.lights.buffer,
                .size = app.lights.buffer_size,
            },
            .{
                .binding = 1,
                .buffer = app.lights.config_uniform_buffer,
                .size = app.lights.config_uniform_buffer_size,
            },
            .{
                .binding = 2,
                .buffer = app.lights.extent_buffer,
                .size = app.lights.extent_buffer_size,
            },
        };
        app.lights.buffer_compute_bind_group = app.core.device().createBindGroup(
            &gpu.BindGroup.Descriptor.init(.{
                .layout = app.light_update_compute_pipeline.getBindGroupLayout(0),
                .entries = &bind_group_entries,
            }),
        );
    }
}

fn prepareViewMatrices(app: *App) void {
    const screen_dimensions = Dimensions2D(f32){
        .width = @intToFloat(f32, app.screen_dimensions.width),
        .height = @intToFloat(f32, app.screen_dimensions.height),
    };
    const aspect: f32 = screen_dimensions.width / screen_dimensions.height;
    const fov: f32 = 2.0 * std.math.pi / 5.0;
    const znear: f32 = 1.0;
    const zfar: f32 = 2000.0;
    app.view_matrices.projection_matrix = zm.perspectiveFovRhGl(fov, aspect, znear, zfar);
    const eye_position = zm.Vec{ 0.0, 50.0, -100.0, 0.0 };
    app.view_matrices.up_vector = zm.Vec{ 0.0, 1.0, 0.0, 0.0 };
    app.view_matrices.origin = zm.Vec{ 0.0, 0.0, 0.0, 0.0 };
    const view_matrix = zm.lookAtRh(
        eye_position,
        app.view_matrices.origin,
        app.view_matrices.up_vector,
    );
    const view_proj_matrix: zm.Mat = zm.mul(view_matrix, app.view_matrices.projection_matrix);
    // Move the model so it's centered.
    const vec1 = zm.Vec{ 0.0, -5.0, 0.0, 0.0 };
    const vec2 = zm.Vec{ 0.0, -40.0, 0.0, 0.0 };
    const model_matrix = zm.mul(zm.translationV(vec2), zm.translationV(vec1));
    app.queue.writeBuffer(
        app.camera_uniform_buffer,
        0,
        &view_proj_matrix,
    );
    app.queue.writeBuffer(
        app.model_uniform_buffer,
        0,
        &model_matrix,
    );
    const invert_transpose_model_matrix = zm.transpose(zm.inverse(model_matrix));
    app.queue.writeBuffer(
        app.model_uniform_buffer,
        64,
        &invert_transpose_model_matrix,
    );
    // Pass the surface size to shader to help sample from gBuffer textures using coord
    const surface_size = Vec2{ screen_dimensions.width, screen_dimensions.height };
    app.queue.writeBuffer(
        app.surface_size_uniform_buffer,
        0,
        &surface_size,
    );
}

fn buildCommandBuffer(app: *App) !*gpu.CommandBuffer {
    const back_buffer_view = app.core.swapChain().getCurrentTextureView();
    const encoder = app.core.device().createCommandEncoder(null);
    defer encoder.release();

    std.debug.assert(app.screen_dimensions.width == app.core.descriptor().width);
    std.debug.assert(app.screen_dimensions.height == app.core.descriptor().height);

    const dimensions = Dimensions2D(f32){
        .width = @intToFloat(f32, app.core.descriptor().width),
        .height = @intToFloat(f32, app.core.descriptor().height),
    };

    {
        // Write position, normal, albedo etc. data to gBuffers
        const pass = encoder.beginRenderPass(&app.write_gbuffer_pass.descriptor);
        pass.setViewport(
            0,
            0,
            dimensions.width,
            dimensions.height,
            0.0,
            1.0,
        );
        pass.setScissorRect(0, 0, app.core.descriptor().width, app.core.descriptor().height);
        pass.setPipeline(app.write_gbuffers_pipeline);
        pass.setBindGroup(0, app.scene_uniform_bind_group, null);
        pass.setVertexBuffer(0, app.vertex_buffer, 0, @sizeOf(Vertex) * app.vertex_count);
        pass.setIndexBuffer(app.index_buffer, .uint16, 0, @sizeOf(u16) * app.index_count);
        pass.drawIndexed(
            app.index_count,
            1, // instance_count
            0, // first_index
            0, // base_vertex
            0, // first_instance
        );
        pass.end();
        pass.release();
    }
    {
        // Update lights position
        const pass = encoder.beginComputePass(null);
        pass.setPipeline(app.light_update_compute_pipeline);
        pass.setBindGroup(0, app.lights.buffer_compute_bind_group, null);
        pass.dispatchWorkgroups(@divExact(max_num_lights, 64), 1, 1);
        pass.end();
        pass.release();
    }
    app.texture_quad_pass.color_attachment.view = back_buffer_view;
    app.texture_quad_pass.descriptor = gpu.RenderPassDescriptor{
        .color_attachment_count = 1,
        .color_attachments = &[_]gpu.RenderPassColorAttachment{app.texture_quad_pass.color_attachment},
    };

    const pass = encoder.beginRenderPass(&app.texture_quad_pass.descriptor);
    switch (app.settings.render_mode) {
        .gbuffer_view => {
            // GBuffers debug view
            // Left: position
            // Middle: normal
            // Right: albedo (use uv to mimic a checkerboard texture)
            pass.setPipeline(app.gbuffers_debug_view_pipeline);
            pass.setBindGroup(0, app.gbuffer_textures_bind_group, null);
            pass.setBindGroup(1, app.surface_size_uniform_bind_group, null);
            pass.draw(6, 1, 0, 0);
        },
        else => {
            // Deferred rendering
            pass.setPipeline(app.deferred_render_pipeline);
            pass.setBindGroup(0, app.gbuffer_textures_bind_group, null);
            pass.setBindGroup(1, app.lights.buffer_bind_group, null);
            pass.setBindGroup(2, app.surface_size_uniform_bind_group, null);
            pass.draw(6, 1, 0, 0);
        },
    }

    pass.setPipeline(app.imgui_render_pipeline);
    const window_size = app.core.size();
    imgui.backend.newFrame(
        &app.core,
        window_size.width,
        window_size.height,
    );
    app.drawUI();
    imgui.backend.draw(pass);

    pass.end();
    pass.release();

    return encoder.finish(null);
}

fn setupImgui(app: *App) void {
    imgui.init();
    const font_normal = imgui.io.addFontFromFile(assets.fonts.roboto_medium.path, 16.0);

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
    imgui.backend.init(app.core.device(), app.core.descriptor().format, null);

    const style = imgui.getStyle();
    style.window_min_size = .{ 300.0, 100.0 };
    style.window_border_size = 4.0;
    style.scrollbar_size = 3.0;
}

fn drawUI(app: *App) void {
    imgui.setNextWindowPos(.{ .x = 10, .y = 10 });
    if (!imgui.begin("Settings", .{})) {
        imgui.end();
        return;
    }
    _ = imgui.checkbox("Paused", .{ .v = &app.is_paused });
    var update_uniform_buffers: bool = false;
    const modes = [_][:0]const u8{ "rendering", "gbuffers view" };
    const mode_index = @enumToInt(app.settings.render_mode);
    if (imgui.beginCombo("Mode", .{ .preview_value = modes[mode_index] })) {
        for (modes) |mode, mode_i| {
            const i = @intCast(u32, mode_i);
            if (imgui.selectable(mode, .{ .selected = mode_index == i })) {
                update_uniform_buffers = true;
                app.settings.render_mode = @intToEnum(RenderMode, mode_i);
            }
        }
        imgui.endCombo();
    }
    if (imgui.sliderInt("Light count", .{ .v = &app.settings.lights_count, .min = 1, .max = max_num_lights })) {
        app.queue.writeBuffer(
            app.lights.config_uniform_buffer,
            0,
            &[1]i32{app.settings.lights_count},
        );
    }
    imgui.end();
}

fn updateUniformBuffers(app: *App) void {
    app.camera_rotation += toRadians(360.0) * (app.delta_time / 5.0); // one rotation every 5s
    const rotation = zm.rotationY(app.camera_rotation);
    const eye_position = zm.mul(rotation, zm.Vec{ 0, 50, -100, 0 });
    const view_matrix = zm.lookAtRh(eye_position, app.view_matrices.origin, app.view_matrices.up_vector);
    app.view_matrices.view_proj_matrix = zm.mul(view_matrix, app.view_matrices.projection_matrix);
    app.queue.writeBuffer(
        app.camera_uniform_buffer,
        0,
        &app.view_matrices.view_proj_matrix,
    );
}

inline fn roundToMultipleOf4(comptime T: type, value: T) T {
    return (value + 3) & ~@as(T, 3);
}

inline fn toRadians(degrees: f32) f32 {
    return degrees * (std.math.pi / 180.0);
}
