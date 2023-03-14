const mach = @import("mach");
const gpu = @import("gpu");
const zmath = @import("zmath");

pub const Renderer = @This();

var queue: *gpu.Queue = undefined;
var pipeline: *gpu.RenderPipeline = undefined;
var vertex_buffer: *gpu.Buffer = undefined;
var index_buffer: *gpu.Buffer = undefined;

const F32x3 = @Vector(3, f32);
const VertexData = struct {
    position : F32x3,
    normal : F32x3,
};

const vertex_data = [3]VertexData {
    .{.position = F32x3{ -0.5, -0.5, 0.0 }, .normal = F32x3{-0.5, -0.5, 0.0 }},
    .{.position = F32x3{ 0.5, -0.5, 0.0 }, .normal = F32x3{ 0.5, -0.5, 0.0}},
    .{.position = F32x3{ 0.0, 0.5, 0.0 }, .normal = F32x3{ 0.0, 0.5, 0.0}},
};

const index_data = [3]u32 {
    0,1,2
};

pub fn rendererInit(core: *mach.Core) void {
    queue = core.device().getQueue();

    var shader = core.device().createShaderModuleWGSL("primitive.wgsl", @embedFile("primitive.wgsl"));
    defer shader.release();    
    
    const vertex_buffer_components = createVertexBufferComponents();
    vertex_buffer = core.device().createBuffer(&vertex_buffer_components.buffer_descriptor);
    queue.writeBuffer(vertex_buffer, 0, vertex_data[0..]);

    createIndexBufferDescriptor(core);

    pipeline = createPipeline(core, shader, vertex_buffer_components.layout);    
}

const VertexBufferComponents = struct {
    layout : gpu.VertexBufferLayout,
    buffer_descriptor : gpu.Buffer.Descriptor
};

fn createVertexBufferComponents() VertexBufferComponents {
    const vertex_buffer_descriptor = gpu.Buffer.Descriptor{
        .size = vertex_data.len * @sizeOf(VertexData),
        .usage = .{.vertex = true, .copy_dst = true},
        .mapped_at_creation = false,
    };

    const vertex_attributes = [_]gpu.VertexAttribute{
        .{ .format = .float32x3, .shader_location = 0, .offset = 0},
        .{ .format = .float32x3, .shader_location = 1, .offset = @sizeOf(F32x3)},
    };

    const vertex_buffer_layout = gpu.VertexBufferLayout.init(.{
        .array_stride = @sizeOf(VertexData),
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
        .size = index_data.len * @sizeOf(u32),
        .usage = .{.index = true, .copy_dst = true},
        .mapped_at_creation = false,
    };
    index_buffer = core.device().createBuffer(&index_buffer_descriptor);
    queue.writeBuffer(index_buffer, 0, index_data[0..]);
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
    pass.setVertexBuffer(0, vertex_buffer, 0, @sizeOf(VertexData) * vertex_data.len);
    pass.setIndexBuffer(index_buffer, .uint32, 0, @sizeOf(u32) * index_data.len);
    pass.drawIndexed(index_data.len, 1, 0, 0, 0);

    pass.end();
    pass.release();

    var command = encoder.finish(null);
    encoder.release();

    queue.submit(&[_]*gpu.CommandBuffer{command});
    command.release();
    core.swapChain().present();
    back_buffer_view.release();
}