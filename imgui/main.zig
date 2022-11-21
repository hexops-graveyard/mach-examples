const std = @import("std");
const mach = @import("mach");
const imgui = @import("imgui.zig");
const gpu = @import("gpu");
const assets = @import("assets");

const content = @import("content.zig");

pub const App = @This();

pipeline: *gpu.RenderPipeline,
queue: *gpu.Queue,

fn create_vertex_state(vs_module: *gpu.ShaderModule) gpu.VertexState {
    return gpu.VertexState{
        .module = vs_module,
        .entry_point = "main",
    };
}

fn create_fragment_state(fs_module: *gpu.ShaderModule, targets: []const gpu.ColorTargetState) gpu.FragmentState {
    return gpu.FragmentState.init(.{
        .module = fs_module,
        .entry_point = "main",
        .targets = targets,
    });
}

fn create_color_target_state(swap_chain_format: gpu.Texture.Format) gpu.ColorTargetState {
    const blend = gpu.BlendState{};
    const color_target = gpu.ColorTargetState{
        .format = swap_chain_format,
        .blend = &blend,
        .write_mask = gpu.ColorWriteMaskFlags.all,
    };

    return color_target;
}

pub fn init(app: *App, core: *mach.Core) !void {
    std.debug.print("backend type: {?}\n", .{core.backend_type});
    std.debug.print("\n", .{});

    try core.setOptions(mach.Options{
        .title = "Imgui in mach",
        .width = 1000,
        .height = 800,
    });

    imgui.init();

    const font_size = 18.0;
    const font_normal = imgui.io.addFontFromFile(assets.fonts.roboto_medium.path, font_size);

    const fs_module = core.device.createShaderModuleWGSL("vert.wgsl", @embedFile("frag.wgsl"));
    const vs_module = core.device.createShaderModuleWGSL("frag.wgsl", @embedFile("vert.wgsl"));

    const color_target = create_color_target_state(core.swap_chain_format);

    const pipeline_descriptor = gpu.RenderPipeline.Descriptor{ .fragment = &create_fragment_state(fs_module, &.{color_target}), .vertex = create_vertex_state(vs_module) };

    imgui.backend.init(core.device, core.swap_chain_format, null);
    imgui.io.setDefaultFont(font_normal);

    const style = imgui.getStyle();
    style.window_min_size = .{ 100.0, 100.0 };
    style.window_border_size = 8.0;
    style.scrollbar_size = 6.0;

    app.pipeline = core.device.createRenderPipeline(&pipeline_descriptor);
    app.queue = core.device.getQueue();

    vs_module.release();
    fs_module.release();
}

pub fn deinit(_: *App, _: *mach.Core) void {
    imgui.backend.deinit();
}

pub fn update(app: *App, core: *mach.Core) !void {
    if (core.hasEvent()) {
        const input_event: mach.Event = core.pollEvent().?;
        imgui.backend.passEvent(input_event);
    }

    const back_buffer_view = core.swap_chain.?.getCurrentTextureView();
    const color_attachment = gpu.RenderPassColorAttachment{
        .view = back_buffer_view,
        .clear_value = gpu.Color{ .r = 0.1, .g = 0.1, .b = 0.1, .a = 1.0 },
        .load_op = .clear,
        .store_op = .store,
    };

    const encoder = core.device.createCommandEncoder(null);
    const render_pass_info = gpu.RenderPassDescriptor.init(.{
        .color_attachments = &.{color_attachment},
    });
    const pass = encoder.beginRenderPass(&render_pass_info);
    pass.setPipeline(app.pipeline);
    pass.draw(3, 1, 0, 0);

    try content.render_content(core);

    imgui.backend.draw(pass);

    pass.end();
    pass.release();

    var command = encoder.finish(null);
    encoder.release();

    app.queue.submit(&[_]*gpu.CommandBuffer{command});
    command.release();

    core.swap_chain.?.present();
    back_buffer_view.release();
}
