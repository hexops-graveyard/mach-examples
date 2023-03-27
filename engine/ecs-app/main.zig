// Experimental ECS app example. Not yet ready for actual use.

const std = @import("std");
const mach = @import("mach");

const Renderer = @import("Renderer.zig");
const Physics2D = @import("Physics2D.zig");
const Game = @import("Game.zig");

// A Mach app is just a list of all the modules in our application. Our game itself is implemented
// in our own module called Game.
//
// Modules can have components, systems, state, etc. They can also send and receive messages to
// coordinate with each-other.
pub const App = mach.App(.{
    Game,
    mach.Module,
    Renderer,
    Physics2D,
});
