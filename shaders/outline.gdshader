// Inverted-hull outline. Used as the next_pass of the toon materials.
shader_type spatial;
render_mode cull_front, unshaded, depth_draw_opaque;

uniform vec4 outline_color : source_color = vec4(0.09, 0.07, 0.14, 1.0);
uniform float outline_width : hint_range(0.0, 0.05) = 0.006;

void vertex() {
	// Scale the outline with distance so thin objects keep a visible edge.
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float dist_scale = clamp(clip.w * 0.35, 0.6, 2.5);
	VERTEX += NORMAL * outline_width * dist_scale;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
