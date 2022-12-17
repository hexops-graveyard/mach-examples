const std = @import("std");
const mach = @import("mach");
const gpu = @import("gpu");
const sysaudio = mach.sysaudio;
const js = mach.sysjs;
const builtin = @import("builtin");

pub const App = @This();

audio_ctx: sysaudio.Context,
player: sysaudio.Player,
tone_engine: ToneEngine = .{},

pub fn init(app: *App, core: *mach.Core) !void {
    app.audio_ctx = try sysaudio.Context.init(null, core.allocator, .{});
    errdefer app.audio_ctx.deinit();
    try app.audio_ctx.refresh();

    const device = app.audio_ctx.defaultDevice(.playback) orelse return error.NoDeviceFound;
    app.player = try app.audio_ctx.createPlayer(device, callback, .{ .userdata = app });

    try app.player.start();
}

fn callback(player_op: *anyopaque, frames: usize) void {
    // TODO(sysaudio): should make user_data pointer type-safe
    var player = @ptrCast(*sysaudio.Player, @alignCast(@alignOf(*sysaudio.Player), player_op));
    const app: *App = @ptrCast(*App, @alignCast(@alignOf(App), player.userdata));
    // Where the magic happens: fill our audio_ctx buffer with PCM dat.
    app.tone_engine.render(player, frames);
}

pub fn deinit(app: *App, core: *mach.Core) void {
    _ = core;
    app.player.deinit();
    app.audio_ctx.deinit();
}

pub fn update(app: *App, engine: *mach.Core) !void {
    while (engine.pollEvent()) |event| {
        switch (event) {
            .key_press => |ev| {
                app.tone_engine.fillTone(app.player, ToneEngine.keyToFrequency(ev.key));
            },
            else => {},
        }
    }

    if (builtin.cpu.arch != .wasm32) {
        const back_buffer_view = engine.swap_chain.?.getCurrentTextureView();

        engine.swap_chain.?.present();
        back_buffer_view.release();
    }
}

// A simple tone engine.
//
// It renders 2048 tones simultaneously, each with their own frequency and duration.
//
// `keyToFrequency` can be used to convert a keyboard key to a frequency, so that the
// keys asdfghj on your QWERTY keyboard will map to the notes C/D/E/F/G/A/B[4], the
// keys above qwertyu will map to C5 and the keys below zxcvbnm will map to C3.
//
// The duration is hard-coded to 1.5s. To prevent clicking, tones are faded in linearly over
// the first 1/64th duration of the tone. To provide a cool sustained effect, tones are faded
// out using 1-log10(x*10) (google it to see how it looks, it's strong for most of the duration of
// the note then fades out slowly.)
pub const ToneEngine = struct {
    playing: [2048]Tone = std.mem.zeroes([2048]Tone),

    const Tone = struct {
        frequency: f32,
        sample_counter: usize,
        duration: usize,
    };

    pub fn render(engine: *ToneEngine, player: *sysaudio.Player, frames: usize) void {
        var frame: usize = 0;
        while (frame < frames) : (frame += 1) {
            // Render the sample for this frame (e.g. for both left and right audio_ctx channels.)
            var sample: f32 = 0;
            for (engine.playing) |*tone| {
                if (tone.sample_counter >= tone.duration) {
                    continue;
                }
                tone.sample_counter += 1;
                const sample_counter = @intToFloat(f32, tone.sample_counter);
                const duration = @intToFloat(f32, tone.duration);

                // The sine wave that plays the frequency.
                const gain = 0.1;
                const sine_wave = std.math.sin(tone.frequency * 2.0 * std.math.pi * sample_counter / @intToFloat(f32, player.sampleRate())) * gain;

                // A number ranging from 0.0 to 1.0 in the first 1/64th of the duration of the tone.
                const fade_in = std.math.min(sample_counter / (duration / 64.0), 1.0);

                // A number ranging from 1.0 to 0.0 over half the duration of the tone.
                const progression = sample_counter / duration; // 0.0 (tone start) to 1.0 (tone end)
                const fade_out = 1.0 - std.math.clamp(std.math.log10(progression * 10.0), 0.0, 1.0);

                // Mix this tone into the sample we'll actually play on e.g. the speakers, reducing
                // sine wave intensity if we're fading in or out over the entire duration of the
                // tone.
                sample += sine_wave * fade_in * fade_out;
            }

            // Emit the sample on all channels.
            player.writeAll(frame, sample);
        }
    }

    pub fn fillTone(engine: *ToneEngine, player: sysaudio.Player, frequency: f32) void {
        for (engine.playing) |*tone| {
            if (tone.sample_counter >= tone.duration) {
                tone.* = Tone{
                    .frequency = frequency,
                    .sample_counter = 0,
                    .duration = @floatToInt(usize, 1.5 * @intToFloat(f32, player.sampleRate())), // play the tone for 1.5s
                };
                return;
            }
        }
    }

    pub fn keyToFrequency(key: mach.Key) f32 {
        // The frequencies here just come from a piano frequencies chart. You can google for them.
        return switch (key) {
            // First row of piano keys, the highest.
            .q => 523.25, // C5
            .w => 587.33, // D5
            .e => 659.26, // E5
            .r => 698.46, // F5
            .t => 783.99, // G5
            .y => 880.0, // A5
            .u => 987.77, // B5
            .i => 1046.5, // C6
            .o => 1174.7, // D6
            .p => 1318.5, // E6
            .left_bracket => 1396.9, // F6
            .right_bracket => 1568.0, // G6

            // Second row of piano keys, the middle.
            .a => 261.63, // C4
            .s => 293.67, // D4
            .d => 329.63, // E4
            .f => 349.23, // F4
            .g => 392.0, // G4
            .h => 440.0, // A4
            .j => 493.88, // B4
            .k => 523.25, // C5
            .l => 587.33, // D5
            .semicolon => 659.26, // E5
            .apostrophe => 698.46, // F5

            // Third row of piano keys, the lowest.
            .z => 130.81, // C3
            .x => 146.83, // D3
            .c => 164.81, // E3
            .v => 174.61, // F3
            .b => 196.00, // G3
            .n => 220.0, // A3
            .m => 246.94, // B3
            .comma => 261.63, // C4
            .period => 293.67, // D4
            .slash => 329.63, // E5
            else => 0.0,
        };
    }
};
