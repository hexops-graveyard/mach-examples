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
  pos_x: f32,
  pos_y: f32,
  width: f32,
  height: f32,
  world_x: f32,
  world_y: f32,
  sheet_width: f32,
  sheet_height: f32,
};
@binding(3) @group(0) var<storage, read> sprites: array<Sprite>;

@vertex
fn vertex_main(
  @builtin(vertex_index) VertexIndex : u32
) -> VertexOutput {
  var width = sprites[0].width;
  var height = sprites[0].height;
  var positions = array<vec2<f32>, 6>(
      vec2<f32>(0.0, 0.0),      // bottom-left
      vec2<f32>(0.0, height),   // top-left
      vec2<f32>(width, 0.0),    // bottom-right
      vec2<f32>(width, 0.0),    // bottom-right
      vec2<f32>(0.0, height),   // top-left
      vec2<f32>(width, height), // top-right
  );
  var uvs = array<vec2<f32>, 6>(
      vec2<f32>((sprites[0].pos_x / sprites[0].sheet_width), ((sprites[0].pos_y + sprites[0].height) / sprites[0].sheet_height)), // bottom-left
      vec2<f32>((sprites[0].pos_x / sprites[0].sheet_width), (sprites[0].pos_y / sprites[0].sheet_height)), // top-left
      vec2<f32>(((sprites[0].pos_x + sprites[0].width) / sprites[0].sheet_width), ((sprites[0].pos_y + sprites[0].height) / sprites[0].sheet_height)), // bottom-right
      vec2<f32>(((sprites[0].pos_x + sprites[0].width) / sprites[0].sheet_width), ((sprites[0].pos_y + sprites[0].height) / sprites[0].sheet_height)), // bottom-right
      vec2<f32>((sprites[0].pos_x / sprites[0].sheet_width), (sprites[0].pos_y / sprites[0].sheet_height)), // top-left
      vec2<f32>(((sprites[0].pos_x + sprites[0].width) / sprites[0].sheet_width), (sprites[0].pos_y / sprites[0].sheet_height)), // top-right
  );
  var pos = vec4<f32>(positions[VertexIndex % 6].x, 0.0, positions[VertexIndex % 6].y, 1.0);

  var output : VertexOutput;
  output.Position = pos * uniforms.modelViewProjectionMatrix;
  output.fragUV = uvs[VertexIndex % 6];
  output.fragUV.y = 1.0 - output.fragUV.y; // flip UV because .tga files are stored upside down

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