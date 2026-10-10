// The net's mesh: a paper thread grid with holes, drawn from both sides.
// UVs are in metres (see tools/build_meshes.py) so the holes come out
// square whatever the net's size.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, unshaded;

uniform vec4 thread_color : source_color = vec4(0.86, 0.82, 0.76, 1.0);
uniform float cell = 0.024;
uniform float thread = 0.22;

void fragment() {
	vec2 g = abs(fract(UV / cell) - 0.5) * 2.0;
	float on_thread = max(step(1.0 - thread, g.x), step(1.0 - thread, g.y));
	ALBEDO = thread_color.rgb;
	ALPHA = on_thread;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
