const std = @import("std");

pub const sphere_ascii_path = root_path ++ "/sphere_ascii.m3d";
pub const teapot_ascii_path = root_path ++ "/teapot_ascii.m3d";
pub const torusknot_ascii_path = root_path ++ "/torusknot_ascii.m3d";
pub const venus_ascii_path = root_path ++ "/venus_ascii.m3d";

pub const sphere_model_m3d = @embedFile(sphere_ascii_path);
pub const teapot_model_m3d = @embedFile(teapot_ascii_path);
pub const torusknot_model_m3d = @embedFile(torusknot_ascii_path);
pub const venus_model_m3d = @embedFile(venus_ascii_path);

const gotta_go_fast_image_path = root_path ++ "/gotta-go-fast.png";
pub const gotto_go_fast_image = @embedFile(gotta_go_fast_image_path);

pub const skybox = struct {
    const negx_image_path = root_path ++ "/skybox/negx.png";
    const negy_image_path = root_path ++ "/skybox/negy.png";
    const negz_image_path = root_path ++ "/skybox/negz.png";
    const posx_image_path = root_path ++ "/skybox/posx.png";
    const posy_image_path = root_path ++ "/skybox/posy.png";
    const posz_image_path = root_path ++ "/skybox/posz.png";

    pub const negx_image = @embedFile(negx_image_path);
    pub const negy_image = @embedFile(negy_image_path);
    pub const negz_image = @embedFile(negz_image_path);
    pub const posx_image = @embedFile(posx_image_path);
    pub const posy_image = @embedFile(posy_image_path);
    pub const posz_image = @embedFile(posz_image_path);
};

const root_path = rootPath();

fn rootPath() []const u8 {
    comptime {
        return std.fs.path.dirname(@src().file).?;
    }
}
