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

  // Starting vertex positions & uv coordinates that represent a square (two triangles)
  var positions = array<vec2<f32>, 6>(
      vec2<f32>(0.0, 0.0), // bottom-left
      vec2<f32>(0.0, 1.0), // top-left
      vec2<f32>(1.0, 0.0), // bottom-right
      vec2<f32>(1.0, 0.0), // bottom-right
      vec2<f32>(0.0, 1.0), // top-left
      vec2<f32>(1.0, 1.0), // top-right
  );
  /*
  var uvs = array<vec2<f32>, 6>(
      vec2<f32>(0.0, 0.0), // bottom-left
      vec2<f32>(0.0, 1.0), // top-left
      vec2<f32>(1.0, 0.0), // bottom-right
      vec2<f32>(1.0, 0.0), // bottom-right
      vec2<f32>(0.0, 1.0), // top-left
      vec2<f32>(1.0, 1.0), // top-right
  );
  */

  // Make the vertex position account for the sprite size and world position.
  var pos = positions[VertexIndex % 6];
  pos.x *= sprite.size.x;
  pos.y *= sprite.size.y;
  pos.x += sprite.world_pos.x;
  pos.y += sprite.world_pos.y;

  // Make the UV account for the sprite position in the sprite sheet.
  var uvs = array<vec2<f32>, 6>(
      vec2<f32>((sprite.pos.x / sprite.sheet_size.x), ((sprite.pos.y + sprite.size.y) / sprite.sheet_size.y)), // bottom-left
      vec2<f32>((sprite.pos.x / sprite.sheet_size.x), (sprite.pos.y / sprite.sheet_size.y)), // top-left
      vec2<f32>(((sprite.pos.x + sprite.size.x) / sprite.sheet_size.x), ((sprite.pos.y + sprite.size.y) / sprite.sheet_size.y)), // bottom-right
      vec2<f32>(((sprite.pos.x + sprite.size.x) / sprite.sheet_size.x), ((sprite.pos.y + sprite.size.y) / sprite.sheet_size.y)), // bottom-right
      vec2<f32>((sprite.pos.x / sprite.sheet_size.x), (sprite.pos.y / sprite.sheet_size.y)), // top-left
      vec2<f32>(((sprite.pos.x + sprite.size.x) / sprite.sheet_size.x), (sprite.pos.y / sprite.sheet_size.y)), // top-right
  );

  var output : VertexOutput;
  output.Position = vec4<f32>(pos.x, 0.0, pos.y, 1.0) * uniforms.modelViewProjectionMatrix;
  output.fragUV = uvs[VertexIndex % 6];
  // output.fragUV.y = 1.0 - output.fragUV.y; // flip UV because .tga files are stored upside down

  output.fragPosition = 0.5 * (output.Position + vec4<f32>(1.0, 1.0, 1.0, 1.0));
  return output;
}

@group(0) @binding(1) var mySampler: sampler;
@group(0) @binding(2) var myTexture: texture_2d<f32>;

@fragment
fn frag_main(@location(0) fragUV: vec2<f32>,
        @location(1) fragPosition: vec4<f32>) -> @location(0) vec4<f32> {
    return textureSample(myTexture, mySampler, fragUV);
}