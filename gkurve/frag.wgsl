struct FragUniform {
    type_: u32,
    padding: vec3<f32>,
    blend_color: vec4<f32>,
}
@binding(1) @group(0) var<storage> ubos: array<FragUniform>;
@binding(2) @group(0) var mySampler: sampler;
@binding(3) @group(0) var myTexture: texture_2d<f32>;

@fragment fn main( 
    @location(0) uv: vec2<f32>,
    @interpolate(linear) @location(1) bary_in: vec2<f32>,
    @interpolate(flat) @location(2) triangle_index: u32,
) -> @location(0) vec4<f32> {
    // Example 1: Visualize barycentric coordinates:
    // let bary = bary_in;
    // return vec4<f32>(1.0-d, 1.0-d, 1.0-d, 1.0);
    // return vec4<f32>(bary.x, bary.y, 0.0, 1.0);
    // return vec4<f32>(0.0, bary.x, 0.0, 1.0); // [1.0 (bottom-left vertex), 0.0 (bottom-right vertex)]
    // return vec4<f32>(0.0, bary.y, 0.0, 1.0); // [1.0 (bottom-left vertex), 0.0 (top-right face)]

    // Example 2: Very simple quadratic bezier
    // let bary = bary_in;
    // if (bary.x * bary.x - bary.y) > 0 {
    //     discard;
    // }
    // return vec4<f32>(0.0, 1.0, 0.0, 1.0);

    // Example 3: Render gkurve primitives
    // Concave (inverted quadratic bezier curve)
    // inversion = -1.0;
    // Convex (inverted quadratic bezier curve)
    // inversion = 1.0;
    let inversion = select( 1.0, -1.0, ubos[triangle_index].type_ == 0u || ubos[triangle_index].type_ == 1u);
    // Texture uvs
    // (These two could be cut with vec2(0.0,1.0) + uv * vec2(1.0,-1.0))
    var correct_uv = uv;
    correct_uv.y = 1.0 - correct_uv.y;
    var color = textureSample(myTexture, mySampler, correct_uv) * ubos[triangle_index].blend_color;

    // Signed distance to quadratic bézier
    const dist_scale_px = 300.0;
    let border_color = vec4<f32>(1.0, 0.0, 0.0, 1.0);
    let border_px = 30.0;
    let is_inverted = (inversion + 1.0) / 2.0; // 1.0 if inverted, 0.0 otherwise
    let dist = select(
        distanceToQuadratic(bary_in),
        distanceToSemicircle(bary_in),
        ubos[triangle_index].type_ == 1u || ubos[triangle_index].type_ == 3u,
    ) * inversion;

    let outer_dist = (dist + (border_px * is_inverted)) / dist_scale_px;
    let inner_dist = (dist - (border_px * (1.0-is_inverted))) / dist_scale_px;

    // // Wireframe rendering.
    // let right_face_dist = bary.y;
    // let bottom_face_dist = bary.x-bary.y;
    // let left_face_dist = 1.0 - ((bottom_face_dist*2.0) + bary.y);
    // let normal_bary = vec3<f32>(right_face_dist, bottom_face_dist, left_face_dist);

    // let border_smoothing = 1.0;
    // let fwd = fwidth(normal_bary);
    // let w = smoothstep(border_px * fwd, (border_px + border_smoothing) * fwd, normal_bary);
    // let width = 1.0 - min(min(w.x, w.y), w.z);
    // let epsilon = 0.001;
    // if (right_face_dist >= -epsilon && right_face_dist <= width
    //     || left_face_dist >= -epsilon && left_face_dist <= width
    //     || bottom_face_dist >= -epsilon && bottom_face_dist <= width) {
    //     color = mix(color, border_color, width);
    //     if (dist < 0.0 && ubos[triangle_index].type_ != 4u) {
    //         return vec4<f32>(border_color.rgb, width);
    //     }
    // }

    if (ubos[triangle_index].type_ == 4u) {
        return color;
    }
    if (outer_dist >= 0.0 && inner_dist < 0.0) {
        return border_color;
    } else if (outer_dist >= 0.0) {
        return color;
    } else {
        discard;
    }
}

// Calculates signed distance to a quadratic bézier curve using barycentric coordinates.
fn distanceToQuadratic(bary: vec2<f32>) -> f32 {
    // Gradients
    let px = dpdx(bary.xy);
    let py = dpdy(bary.xy);

    // Chain rule
    let fx = (2.0 * bary.x) * px.x - px.y;
    let fy = (2.0 * bary.x) * py.x - py.y;

    return (bary.x * bary.x - bary.y) / sqrt(fx * fx + fy * fy);
}

// Calculates signed distance to a semicircle using barycentric coordinates.
fn distanceToSemicircle(bary: vec2<f32>) -> f32 {
    let x = abs(((bary.x - 0.5) * 2.0)); // [0.0 left, 1.0 center, 0.0 right]
    let y = ((bary.x-bary.y) * 4.0); // [2.0 bottom, 0.0 top]
    let c = x*x + y*y;

    // Gradients
    let px = dpdx(bary.xy);
    let py = dpdy(bary.xy);

    // Chain rule
    let fx = c * px.x - px.y;
    let fy = c * py.x - py.y;

    let d = (1.0 - (x*x + y*y)) - 0.2;
    return (-d / 6.0) / sqrt(fx * fx + fy * fy);
}
