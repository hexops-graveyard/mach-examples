const std = @import("std");
const mach = @import("mach");
const gpu = @import("gpu");
const primitives = @import("parametric-primitives.zig");
const Primitive = primitives.Primitive;
const VertexData = primitives.VertexData;

pub const Renderer = @This();

var queue: *gpu.Queue = undefined;
var pipeline: *gpu.RenderPipeline = undefined;

const PrimitiveRenderData = struct {
    vertex_buffer: *gpu.Buffer,
    index_buffer: *gpu.Buffer,
    vertex_count : u32,
    index_count : u32,
};

var primitives_data : [4]PrimitiveRenderData = undefined;
pub var curr_primitive_index : u4 = 0;

pub fn init(core: *mach.Core, allocator : std.mem.Allocator) void {
    queue = core.device().getQueue();

    {
        const triangle_primitive = primitives.createTrianglePrimitive(allocator);
        primitives_data[0] = PrimitiveRenderData {
            .vertex_buffer = createVertexBuffer(core, triangle_primitive),
            .index_buffer = createIndexBuffer(core, triangle_primitive),
            .vertex_count = triangle_primitive.vertex_count,
            .index_count = triangle_primitive.index_count
        };
        defer triangle_primitive.vertex_data.deinit();
        defer triangle_primitive.index_data.deinit();
    }

    {
        const quad_primitive = primitives.createQuadPrimitive(allocator);
        primitives_data[1] = PrimitiveRenderData {
            .vertex_buffer = createVertexBuffer(core, quad_primitive),
            .index_buffer = createIndexBuffer(core, quad_primitive),
            .vertex_count = quad_primitive.vertex_count,
            .index_count = quad_primitive.index_count
        };
        defer quad_primitive.vertex_data.deinit();
        defer quad_primitive.index_data.deinit();
    }

    {
        const plane_primitive = primitives.createPlanePrimitive(allocator, 1000, 1000, 1.5);
        primitives_data[2] = PrimitiveRenderData {
            .vertex_buffer = createVertexBuffer(core, plane_primitive),
            .index_buffer = createIndexBuffer(core, plane_primitive),
            .vertex_count = plane_primitive.vertex_count,
            .index_count = plane_primitive.index_count
        };
        defer plane_primitive.vertex_data.deinit();
        defer plane_primitive.index_data.deinit();
    }

    {
        const circle_primitive = primitives.createCirclePrimitive(allocator, 64, 1);
        primitives_data[3] = PrimitiveRenderData {
            .vertex_buffer = createVertexBuffer(core, circle_primitive),
            .index_buffer = createIndexBuffer(core, circle_primitive),
            .vertex_count = circle_primitive.vertex_count,
            .index_count = circle_primitive.index_count
        };
        defer circle_primitive.vertex_data.deinit();
        defer circle_primitive.index_data.deinit();
    }


    var shader = core.device().createShaderModuleWGSL("primitive.wgsl", @embedFile("primitive.wgsl"));
    defer shader.release();    
 
    pipeline = createPipeline(core, shader);    
}

const VertexBufferComponents = struct {
    layout : gpu.VertexBufferLayout,
    buffer_descriptor : gpu.Buffer.Descriptor
};

fn createVertexBuffer(core: *mach.Core, primitive : Primitive) *gpu.Buffer {
    const vertex_buffer_descriptor = gpu.Buffer.Descriptor{
        .size = primitive.vertex_count * @sizeOf(VertexData),
        .usage = .{.vertex = true, .copy_dst = true},
        .mapped_at_creation = false,
    };

    const vertex_buffer = core.device().createBuffer(&vertex_buffer_descriptor);
    queue.writeBuffer(vertex_buffer, 0, primitive.vertex_data.items[0..]);

    return vertex_buffer;
}

fn createIndexBuffer (core : *mach.Core, primitive : Primitive) *gpu.Buffer {
    const index_buffer_descriptor = gpu.Buffer.Descriptor{
        .size = primitive.index_count * @sizeOf(u32),
        .usage = .{.index = true, .copy_dst = true},
        .mapped_at_creation = false,
    };
    const index_buffer = core.device().createBuffer(&index_buffer_descriptor);
    queue.writeBuffer(index_buffer, 0, primitive.index_data.items[0..]);
    
    return index_buffer;
}

fn createPipeline(core: *mach.Core, shader_module : *gpu.ShaderModule) *gpu.RenderPipeline {
    
    const vertex_attributes = [_]gpu.VertexAttribute{
        .{ .format = .float32x3, .shader_location = 0, .offset = 0},
        .{ .format = .float32x3, .shader_location = 1, .offset = @sizeOf(primitives.F32x3)},
    };

    const vertex_buffer_layout = gpu.VertexBufferLayout.init(.{
        .array_stride = @sizeOf(VertexData),
        .step_mode = .vertex,
        .attributes = &vertex_attributes,
    });

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

pub fn update (core: *mach.Core) void {

    const back_buffer_view = core.swapChain().getCurrentTextureView();
    const color_attachment = gpu.RenderPassColorAttachment{
        .view = back_buffer_view,
        .clear_value = gpu.Color{ .r = 0.2, .g = 0.2, .b = 0.2, .a = 1.0 },
        .load_op = .clear,
        .store_op = .store,
    };

    const encoder = core.device().createCommandEncoder(null);
    const render_pass_info = gpu.RenderPassDescriptor.init(.{
        .color_attachments = &.{color_attachment},
    });

    
    const pass = encoder.beginRenderPass(&render_pass_info);

    pass.setPipeline(pipeline);

    const vertex_buffer = primitives_data[curr_primitive_index].vertex_buffer;
    const vertex_count = primitives_data[curr_primitive_index].vertex_count;
    pass.setVertexBuffer(0, vertex_buffer, 0, @sizeOf(VertexData) * vertex_count);

    const index_buffer = primitives_data[curr_primitive_index].index_buffer;
    const index_count = primitives_data[curr_primitive_index].index_count;
    pass.setIndexBuffer(index_buffer, .uint32, 0, @sizeOf(u32) * index_count);
    pass.drawIndexed(index_count, 1, 0, 0, 0);

    pass.end();
    pass.release();

    var command = encoder.finish(null);
    encoder.release();

    queue.submit(&[_]*gpu.CommandBuffer{command});
    command.release();
    core.swapChain().present();
    back_buffer_view.release();
}

pub fn deinit() void {
    var i: u4 = 0;
    while (i < 4) : (i += 1) {
        primitives_data[i].vertex_buffer.release();
        primitives_data[i].index_buffer.release();
    }

}