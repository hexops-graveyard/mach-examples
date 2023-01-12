const std = @import("std");
const mach = @import("mach");
const imgui = @import("imgui.zig");
const gpu = @import("gpu");
const assets = @import("assets");

const content = @import("content.zig");

pub const App = @This();

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

core: mach.Core,
pipeline: *gpu.RenderPipeline,
queue: *gpu.Queue,

fn createVertexState(vs_module: *gpu.ShaderModule) gpu.VertexState {
    return gpu.VertexState{
        .module = vs_module,
        .entry_point = "main",
    };
}

fn createFragmentState(fs_module: *gpu.ShaderModule, targets: []const gpu.ColorTargetState) gpu.FragmentState {
    return gpu.FragmentState.init(.{
        .module = fs_module,
        .entry_point = "main",
        .targets = targets,
    });
}

fn createColorTargetState(format: gpu.Texture.Format) gpu.ColorTargetState {
    const blend = gpu.BlendState{};
    const color_target = gpu.ColorTargetState{
        .format = format,
        .blend = &blend,
        .write_mask = gpu.ColorWriteMaskFlags.all,
    };

    return color_target;
}

pub fn init(app: *App) !void {
    app.core = try mach.Core.init(gpa.allocator(), .{
        .title = "Imgui in mach",
        .size = .{
            .width = 1000,
            .height = 800,
        },
    });

    var adapter_props: gpu.Adapter.Properties = undefined;
    app.core.adapter().getProperties(&adapter_props);
    std.debug.print("backend type: {?}\n", .{adapter_props.backend_type});
    std.debug.print("\n", .{});

    imgui.init();

    const font_size = 18.0;
    const font_normal = imgui.io.addFontFromFile(assets.fonts.roboto_medium.path, font_size);

    const fs_module = app.core.device().createShaderModuleWGSL("vert.wgsl", @embedFile("frag.wgsl"));
    const vs_module = app.core.device().createShaderModuleWGSL("frag.wgsl", @embedFile("vert.wgsl"));

    const color_target = createColorTargetState(app.core.descriptor().format);

    const pipeline_descriptor = gpu.RenderPipeline.Descriptor{ .fragment = &createFragmentState(fs_module, &.{color_target}), .vertex = createVertexState(vs_module) };

    imgui.backend.init(app.core.device(), app.core.descriptor().format, null);
    imgui.io.setDefaultFont(font_normal);

    const style = imgui.getStyle();
    style.window_min_size = .{ 100.0, 100.0 };
    style.window_border_size = 8.0;
    style.scrollbar_size = 6.0;

    app.pipeline = app.core.device().createRenderPipeline(&pipeline_descriptor);
    app.queue = app.core.device().getQueue();

    vs_module.release();
    fs_module.release();
}

pub fn deinit(app: *App) void {
    defer _ = gpa.deinit();
    defer app.core.deinit();

    imgui.backend.deinit();
}

pub fn update(app: *App) !bool {
    while (app.core.pollEvents()) |event| {
        if (event == .close) return true;
        imgui.backend.passEvent(event);
    }

    const back_buffer_view = app.core.swapChain().getCurrentTextureView();
    const color_attachment = gpu.RenderPassColorAttachment{
        .view = back_buffer_view,
        .clear_value = gpu.Color{ .r = 0.1, .g = 0.1, .b = 0.1, .a = 1.0 },
        .load_op = .clear,
        .store_op = .store,
    };

    const encoder = app.core.device().createCommandEncoder(null);
    const render_pass_info = gpu.RenderPassDescriptor.init(.{
        .color_attachments = &.{color_attachment},
    });
    const pass = encoder.beginRenderPass(&render_pass_info);
    pass.setPipeline(app.pipeline);
    pass.draw(3, 1, 0, 0);

    content.renderContent(&app.core);

    imgui.backend.draw(pass);

    pass.end();
    pass.release();

    var command = encoder.finish(null);
    encoder.release();

    app.queue.submit(&[_]*gpu.CommandBuffer{command});
    command.release();

    app.core.swapChain().present();
    back_buffer_view.release();

    return false;
}
