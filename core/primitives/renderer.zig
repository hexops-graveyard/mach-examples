const std = @import("std");
const mach = @import("mach");
const gpu = @import("gpu");
const zmath = @import("zmath");
const primitives = @import("parametric-primitives.zig");

pub const Renderer = @This();

var queue: *gpu.Queue = undefined;
var pipeline: *gpu.RenderPipeline = undefined;
var vertex_buffer: *gpu.Buffer = undefined;
var index_buffer: *gpu.Buffer = undefined;

var triangle_primitive : primitives.Primitive = undefined;

pub fn rendererInit(core: *mach.Core, allocator : std.mem.Allocator) void {
    queue = core.device().getQueue();

    triangle_primitive = primitives.createTrianglePrimitive(allocator);


    var shader = core.device().createShaderModuleWGSL("primitive.wgsl", @embedFile("primitive.wgsl"));
    defer shader.release();    
    
    const vertex_buffer_components = createVertexBufferComponents();
    vertex_buffer = core.device().createBuffer(&vertex_buffer_components.buffer_descriptor);
    queue.writeBuffer(vertex_buffer, 0, triangle_primitive.vertex_data.items[0..]);

    createIndexBufferDescriptor(core);

    pipeline = createPipeline(core, shader, vertex_buffer_components.layout);    
}

const VertexBufferComponents = struct {
    layout : gpu.VertexBufferLayout,
    buffer_descriptor : gpu.Buffer.Descriptor
};

fn createVertexBufferComponents() VertexBufferComponents {
    const vertex_buffer_descriptor = gpu.Buffer.Descriptor{
        .size = triangle_primitive.vertex_count * @sizeOf(primitives.VertexData),
        .usage = .{.vertex = true, .copy_dst = true},
        .mapped_at_creation = false,
    };

    const vertex_attributes = [_]gpu.VertexAttribute{
        .{ .format = .float32x3, .shader_location = 0, .offset = 0},
        .{ .format = .float32x3, .shader_location = 1, .offset = @sizeOf(primitives.F32x3)},
    };

    const vertex_buffer_layout = gpu.VertexBufferLayout.init(.{
        .array_stride = @sizeOf(primitives.VertexData),
        .step_mode = .vertex,
        .attributes = &vertex_attributes,
    });

    var componenets = VertexBufferComponents{
        .layout = vertex_buffer_layout,
        .buffer_descriptor = vertex_buffer_descriptor
    };

    return componenets;
}

fn createIndexBufferDescriptor (core : *mach.Core) void {
    const index_buffer_descriptor = gpu.Buffer.Descriptor{
        .size = triangle_primitive.index_count * @sizeOf(u32),
        .usage = .{.index = true, .copy_dst = true},
        .mapped_at_creation = false,
    };
    index_buffer = core.device().createBuffer(&index_buffer_descriptor);
    queue.writeBuffer(index_buffer, 0, triangle_primitive.index_data.items[0..]);
}

fn createPipeline(core: *mach.Core, shader_module : *gpu.ShaderModule, vertex_buffer_layout : gpu.VertexBufferLayout) *gpu.RenderPipeline {
    
    var vertex_pipeline_state = gpu.VertexState.init(.{
        .module = shader_module,
        .entry_point = "vertex_main",
        .buffers = &.{vertex_buffer_layout}
    });

    const primitive_pipeline_state = gpu.PrimitiveState{
        .topology = .triangle_list,
        .front_face = .ccw,
        .cull_mode = .back,
    };

    // Fragment Pipeline State
    const blend = gpu.BlendState{
        .color = gpu.BlendComponent{
            .operation = .add,
            .src_factor = .src_alpha,
            .dst_factor = .one_minus_src_alpha
        },
        .alpha = gpu.BlendComponent{
            .operation = .add,
            .src_factor = .zero,
            .dst_factor = .one
        },        
    };
    const color_target = gpu.ColorTargetState{
        .format = core.descriptor().format,
        .blend = &blend,
        .write_mask = gpu.ColorWriteMaskFlags.all,
    };
    const fragment_pipeline_state = gpu.FragmentState.init(.{
        .module = shader_module,
        .entry_point = "frag_main",
        .targets = &.{color_target},
    });

    const multi_sample_state = gpu.MultisampleState{
        .count = 1,
        .mask = 0xFFFFFFFF,
        .alpha_to_coverage_enabled = false,
    };

    // Pipeline Layout
    const pipeline_layout_descriptor = gpu.PipelineLayout.Descriptor.init(.{
        .bind_group_layouts = &.{}
    });
    const pipeline_layout = core.device().createPipelineLayout(&pipeline_layout_descriptor);
    
    const pipeline_descriptor = gpu.RenderPipeline.Descriptor{
        .label = "Main Pipeline",
        .layout = pipeline_layout,
        .vertex = vertex_pipeline_state,
        .primitive = primitive_pipeline_state,
        .depth_stencil = null,
        .multisample = multi_sample_state,
        .fragment = &fragment_pipeline_state,
    };

    return core.device().createRenderPipeline(&pipeline_descriptor);
}

pub fn renderUpdate (core: *mach.Core) void {

    const back_buffer_view = core.swapChain().getCurrentTextureView();
    const color_attachment = gpu.RenderPassColorAttachment{
        .view = back_buffer_view,
        .clear_value = gpu.Color{ .r = 0.0, .g = 0.0, .b = 1.0, .a = 1.0 },
        .load_op = .clear,
        .store_op = .store,
    };

    const encoder = core.device().createCommandEncoder(null);
    const render_pass_info = gpu.RenderPassDescriptor.init(.{
        .color_attachments = &.{color_attachment},
    });

    
    const pass = encoder.beginRenderPass(&render_pass_info);

    pass.setPipeline(pipeline);
    pass.setVertexBuffer(0, vertex_buffer, 0, @sizeOf(primitives.VertexData) * triangle_primitive.vertex_count);
    pass.setIndexBuffer(index_buffer, .uint32, 0, @sizeOf(u32) * triangle_primitive.index_count);
    pass.drawIndexed(triangle_primitive.index_count, 1, 0, 0, 0);

    pass.end();
    pass.release();

    var command = encoder.finish(null);
    encoder.release();

    queue.submit(&[_]*gpu.CommandBuffer{command});
    command.release();
    core.swapChain().present();
    back_buffer_view.release();
}