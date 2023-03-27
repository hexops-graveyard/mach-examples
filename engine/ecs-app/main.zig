// Experimental ECS app example. Not yet ready for actual use.

const std = @import("std");
const mach = @import("mach");

const Renderer = @import("Renderer.zig");
const Physics2D = @import("Physics2D.zig");
const Game = @import("Game.zig");

// A Mach app is just a list of all the modules in our application. Our game itself is implemented
// in our own module called Game.
//
// TODO(engine): reevaluate module names docs below
//
// Modules can have components, systems, state, and/or global values in them. They can also send and
// receive messages to coordinate with each-other.
//
// Single-word module names (`.mach`, `.renderer`, etc.) are reserved for the application itself.
//
// Modules that come from libraries must be prefixed (e.g. `.bullet_physics`, `.ziglibs_box2d`)
// similar to GitHub repositories, to avoid conflicts with one another.
pub const App = mach.App(.{
    Game,
    mach.Module,
    Renderer,
    Physics2D,
});
