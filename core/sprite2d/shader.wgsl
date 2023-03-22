struct Uniforms {
  modelViewProjectionMatrix : mat4x4<f32>,
};
@binding(0) @group(0) var<uniform> uniforms : Uniforms;

struct VertexOutput {
  @builtin(position) Position : vec4<f32>,
  @location(0) fragUV : vec2<f32>,
  @location(1) fragPosition: vec4<f32>,
};

@vertex
fn vertex_main(
  @location(0) position : vec4<f32>,
  @location(1) uv : vec2<f32>,
  @builtin(vertex_index) VertexIndex : u32
) -> VertexOutput {
  var width = 64.0;
  var height = 96.0;
  var positions = array<vec2<f32>, 6>(
      vec2<f32>(0.0, 0.0),      // bottom-left
      vec2<f32>(0.0, height),   // top-left
      vec2<f32>(width, 0.0),    // bottom-right
      vec2<f32>(width, 0.0),    // bottom-right
      vec2<f32>(0.0, height),   // top-left
      vec2<f32>(width, height), // top-right
  );
  var uvs = array<vec2<f32>, 6>(
      vec2<f32>(0.0, 0.0), // bottom-left
      vec2<f32>(0.0, 1.0), // top-left
      vec2<f32>(1.0, 0.0), // bottom-right
      vec2<f32>(1.0, 0.0), // bottom-right
      vec2<f32>(0.0, 1.0), // top-left
      vec2<f32>(1.0, 1.0), // top-right
  );
  var pos = vec4<f32>(positions[VertexIndex % 6].x, 0.0, positions[VertexIndex % 6].y, 1.0);

  var width = 64.0;
  var height = 96.0;
  var positions = array<vec2<f32>, 6>(
      vec2<f32>(0.0, 0.0),      // bottom-left
      vec2<f32>(0.0, height),   // top-left
      vec2<f32>(width, 0.0),    // bottom-right
      vec2<f32>(width, 0.0),    // bottom-right
      vec2<f32>(0.0, height),   // top-left
      vec2<f32>(width, height), // top-right
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