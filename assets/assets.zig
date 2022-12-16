const std = @import("std");

// Relative to root folder
// Use with std.fs.cwd().openFile(assets.some_file_path)
const root_path = "assets/";

pub const sphere_path = root_path ++ "sphere.m3d";
pub const teapot_path = root_path ++ "teapot.m3d";
pub const torusknot_path = root_path ++ "torusknot.m3d";
pub const venus_path = root_path ++ "venus.m3d";

pub const sphere_model_m3d = @embedFile("sphere.m3d");
pub const teapot_model_m3d = @embedFile("teapot.m3d");
pub const torusknot_model_m3d = @embedFile("torusknot.m3d");
pub const venus_model_m3d = @embedFile("venus.m3d");

const gotta_go_fast_image_path = root_path ++ "gotta-go-fast.png";
pub const gotta_go_fast_image = @embedFile("gotta-go-fast.png");

pub const stanford_dragon = struct {
    pub const path = root_path ++ "stanford_dragon.m3d";
};

pub const fonts = struct {
    pub const roboto_medium = struct {
        pub const path = root_path ++ "fonts/Roboto-Medium.ttf";
        pub const bytes = @embedFile("fonts/Roboto-Medium.ttf");
    };

    pub const firasans_regular = struct {
        // Font part of Freetype lib
        pub const path = "libs/mach/libs/freetype/upstream/assets/FiraSans-Regular.ttf";
    };
};

pub const shaders = struct {
    pub const imgui = struct {
        pub const path = root_path ++ "shaders/imgui.wgsl";
        pub const bytes = @embedFile("shaders/imgui.wgsl");
    };
};

pub const skybox = struct {
    const negx_image_path = root_path ++ "skybox/negx.png";
    const negy_image_path = root_path ++ "skybox/negy.png";
    const negz_image_path = root_path ++ "skybox/negz.png";
    const posx_image_path = root_path ++ "skybox/posx.png";
    const posy_image_path = root_path ++ "skybox/posy.png";
    const posz_image_path = root_path ++ "skybox/posz.png";

    pub const negx_image = @embedFile("skybox/negx.png");
    pub const negy_image = @embedFile("skybox/negy.png");
    pub const negz_image = @embedFile("skybox/negz.png");
    pub const posx_image = @embedFile("skybox/posx.png");
    pub const posy_image = @embedFile("skybox/posy.png");
    pub const posz_image = @embedFile("skybox/posz.png");
};
