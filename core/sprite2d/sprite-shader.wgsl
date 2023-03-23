struct Uniforms {
  modelViewProjectionMatrix : mat4x4<f32>,
};
@binding(0) @group(0) var<uniform> uniforms : Uniforms;

struct VertexOutput {
  @builtin(position) Position : vec4<f32>,
  @location(0) fragUV : vec2<f32>,
  @location(1) fragPosition: vec4<f32>,
};

struct Sprite {
  pos: vec2<f32>,
  size: vec2<f32>,
  world_pos: vec2<f32>,
  sheet_size: vec2<f32>,
};
@binding(3) @group(0) var<storage, read> sprites: array<Sprite>;

@vertex
fn vertex_main(
  @builtin(vertex_index) VertexIndex : u32
) -> VertexOutput {
  var sprite_index = VertexIndex / 6;
  var sprite = sprites[sprite_index];
  var width = sprite.size.x;
  var height = sprite.size.y;
  var positions = array<vec2<f32>, 6>(
      vec2<f32>(sprite.world_pos.x, sprite.world_pos.y),      // bottom-left
      vec2<f32>(sprite.world_pos.x, (sprite.world_pos.y + height)),   // top-left
      vec2<f32>((sprite.world_pos.x + width), sprite.world_pos.y),    // bottom-right
      vec2<f32>((sprite.world_pos.x + width), sprite.world_pos.y),    // bottom-right
      vec2<f32>(sprite.world_pos.x, (sprite.world_pos.y + height)),   // top-left
      vec2<f32>((sprite.world_pos.x + width), (sprite.world_pos.y + height)), // top-right
  );
  var uvs = array<vec2<f32>, 6>(
      vec2<f32>((sprite.pos.x / sprite.sheet_size.x), ((sprite.pos.y + sprite.size.y) / sprite.sheet_size.y)), // bottom-left
      vec2<f32>((sprite.pos.x / sprite.sheet_size.x), (sprite.pos.y / sprite.sheet_size.y)), // top-left
      vec2<f32>(((sprite.pos.x + sprite.size.x) / sprite.sheet_size.x), ((sprite.pos.y + sprite.size.y) / sprite.sheet_size.y)), // bottom-right
      vec2<f32>(((sprite.pos.x + sprite.size.x) / sprite.sheet_size.x), ((sprite.pos.y + sprite.size.y) / sprite.sheet_size.y)), // bottom-right
      vec2<f32>((sprite.pos.x / sprite.sheet_size.x), (sprite.pos.y / sprite.sheet_size.y)), // top-left
      vec2<f32>(((sprite.pos.x + sprite.size.x) / sprite.sheet_size.x), (sprite.pos.y / sprite.sheet_size.y)), // top-right
  );
  var pos = vec4<f32>(positions[VertexIndex % 6].x, 0.0, positions[VertexIndex % 6].y, 1.0);

  var output : VertexOutput;
  output.Position = pos * uniforms.modelViewProjectionMatrix;
  output.fragUV = uvs[VertexIndex % 6];
  // output.fragUV.y = 1.0 - output.fragUV.y; // flip UV because .tga files are stored upside down

  output.fragPosition = 0.5 * (pos + vec4<f32>(1.0, 1.0, 1.0, 1.0));
  return output;
}

@group(0) @binding(1) var mySampler: sampler;
@group(0) @binding(2) var myTexture: texture_2d<f32>;

@fragment
fn frag_main(@location(0) fragUV: vec2<f32>,
        @location(1) fragPosition: vec4<f32>) -> @location(0) vec4<f32> {
    return textureSample(myTexture, mySampler, fragUV);
}