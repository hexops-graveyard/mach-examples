const std = @import("std");
const gpu = @import("mach").gpu;

pipeline: *gpu.RenderPipeline,
queue: *gpu.Queue,

pub const name = .renderer;

pub const components = .{
    .location = Vec3,
    .rotation = Vec3,
};

pub const Vec3 = extern struct { x: f32, y: f32, z: f32 };

pub fn init(adapter: anytype) !void {
    var mach = adapter.mod(.mach);
    var renderer = adapter.mod(.renderer);
    const core = mach.state().core;
    const device = mach.state().device;

    const shader_module = device.createShaderModuleWGSL("shader.wgsl", @embedFile("shader.wgsl"));

    // Fragment state
    const blend = gpu.BlendState{};
    const color_target = gpu.ColorTargetState{
        .format = core.descriptor().format,
        .blend = &blend,
        .write_mask = gpu.ColorWriteMaskFlags.all,
    };
    const fragment = gpu.FragmentState.init(.{
        .module = shader_module,
        .entry_point = "frag_main",
        .targets = &.{color_target},
    });
    const pipeline_descriptor = gpu.RenderPipeline.Descriptor{
        .fragment = &fragment,
        .vertex = gpu.VertexState{
            .module = shader_module,
            .entry_point = "vertex_main",
        },
    };

    renderer.initState(.{
        .pipeline = device.createRenderPipeline(&pipeline_descriptor),
        .queue = device.getQueue(),
    });
    shader_module.release();
}

pub fn tick(adapter: anytype) !void {
    var mach = adapter.mod(.mach);
    var renderer = adapter.mod(.renderer);
    const core = mach.state().core;
    const device = mach.state().device;

    // TODO(engine): event polling should occur in mach.Module and get fired as ECS events.
    var iter = core.pollEvents();
    while (iter.next()) |event| {
        switch (event) {
            .close => try adapter.send(.machExit),
            else => {},
        }
    }

    const back_buffer_view = core.swapChain().getCurrentTextureView();
    const color_attachment = gpu.RenderPassColorAttachment{
        .view = back_buffer_view,
        .clear_value = std.mem.zeroes(gpu.Color),
        .load_op = .clear,
        .store_op = .store,
    };

    const encoder = device.createCommandEncoder(null);
    const render_pass_info = gpu.RenderPassDescriptor.init(.{
        .color_attachments = &.{color_attachment},
    });
    const pass = encoder.beginRenderPass(&render_pass_info);
    pass.setPipeline(renderer.state().pipeline);
    pass.draw(3, 1, 0, 0);
    pass.end();
    pass.release();

    var command = encoder.finish(null);
    encoder.release();

    renderer.state().queue.submit(&[_]*gpu.CommandBuffer{command});
    command.release();
    core.swapChain().present();
    back_buffer_view.release();
}