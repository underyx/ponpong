// Floor: flat colour with a faded grid, so the table floats in a stylised void.
shader_type spatial;
render_mode cull_back, unshaded;

uniform vec4 base_color : source_color = vec4(0.11, 0.13, 0.22, 1.0);
uniform vec4 line_color : source_color = vec4(0.22, 0.28, 0.42, 1.0);
uniform float grid_size = 1.0;
uniform float line_width : hint_range(0.001, 0.2) = 0.03;
uniform float fade_distance = 14.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 g = abs(fract(world_pos.xz / grid_size) - 0.5);
	float line = 1.0 - smoothstep(0.0, line_width, min(g.x, g.y));
	float fade = 1.0 - clamp(length(world_pos.xz) / fade_distance, 0.0, 1.0);
	ALBEDO = mix(base_color.rgb, line_color.rgb, line * fade);
}
