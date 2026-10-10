// One target zone on the table. Border lines, risk halftone, highlight tint.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

uniform vec4 fill : source_color = vec4(0.12, 0.47, 0.38, 1.0);
uniform vec4 line_color : source_color = vec4(0.96, 0.94, 0.88, 1.0);
uniform vec4 highlight_color : source_color = vec4(1.0, 0.8, 0.3, 1.0);
uniform float highlight : hint_range(0.0, 1.0) = 0.0;
uniform float dim : hint_range(0.0, 1.0) = 0.0;
// 0..1, how easy this zone is to miss. Drives the halftone dot size.
uniform float risk : hint_range(0.0, 1.0) = 0.0;
// World-space size of the quad so borders and dots stay the same width everywhere.
uniform vec2 size = vec2(1.0, 1.0);
uniform float line_width = 0.014;
uniform float dot_cell = 0.055;

void fragment() {
	vec2 px = UV * size;
	float edge = min(min(px.x, size.x - px.x), min(px.y, size.y - px.y));
	float line = 1.0 - smoothstep(line_width, line_width + 0.006, edge);

	vec2 cell = fract(px / dot_cell) - 0.5;
	float radius = 0.95 * risk;
	float dots = (1.0 - smoothstep(radius - 0.06, radius, length(cell))) * step(0.01, risk);

	vec3 base = mix(fill.rgb, fill.rgb * 0.68, dots);
	base = mix(base, base * 0.6, dim);
	base = mix(base, highlight_color.rgb, highlight * 0.7);
	vec3 border = mix(line_color.rgb, highlight_color.rgb, highlight);
	ALBEDO = mix(base, border, line);
}
