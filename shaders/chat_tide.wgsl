// The water inside her chat while she thinks: soft caustics drifting under
// the thread, the light that water throws on the bottom of a pool. Strongest
// near the foot of the panel —where you write—, fading upwards, and gone
// when she is still.
//
// s.a.x how much (0 still, 1 at work) · s.color the light's tint

fn shade(s: Shader) -> vec4<f32> {
    let k = s.a.x;
    if (k <= 0.001) {
        return vec4<f32>(0.0);
    }
    let t = s.time * 0.32;
    var p = s.pos / 120.0;
    var light = 0.0;
    // Three layers of warped sines: each one bends the next, which is what
    // makes the bright threads meet and part like caustics, not stripes.
    for (var i = 0; i < 3; i = i + 1) {
        let f = f32(i);
        p = p + vec2<f32>(sin(p.y * 1.6 + t * (1.0 + f * 0.35)), cos(p.x * 1.25 - t * (0.85 + f * 0.25))) * 0.38;
        light = light + 1.0 / (1.0 + 36.0 * abs(sin(p.x * 2.05 + p.y * 1.65 + t * 1.3)));
    }
    light = light / 3.0;
    // Up the panel it fades: the water is deeper at the foot.
    let depth = smoothstep(0.05, 0.95, s.pos.y / s.size.y);
    let a = clamp(light * 0.55, 0.0, 1.0) * k * (0.18 + 0.82 * depth) * 0.32;
    return vec4<f32>(s.color.rgb, a);
}
