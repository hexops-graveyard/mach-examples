@vertex
fn vertex_main(@location(0) in_vertex_position: vec3<f32>) -> @builtin(position) vec4<f32> {
	return vec4<f32>(in_vertex_position, 1.0);
}
@fragment
fn frag_main() -> @location(0) vec4<f32> {
    return vec4<f32>(0.0, 0.4, 1.0, 1.0);
}