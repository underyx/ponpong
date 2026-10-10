// One target zone on the table: the blue of the top, paper border lines,
// risk as halftone dots, a hatch over the lanes the other player covers,
// a tint and corner brackets for the cursor, and a paper flash when the
// ball lands here.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

uniform vec4 fill : source_color = vec4(0.18, 0.43, 0.72, 1.0);
uniform vec4 dot_color : source_color = vec4(0.13, 0.31, 0.54, 1.0);
uniform vec4 line_color : source_color = vec4(0.96, 0.93, 0.86, 1.0);
uniform vec4 hatch_color : source_color = vec4(0.10, 0.09, 0.19, 1.0);
uniform vec4 highlight_color : source_color = vec4(1.0, 0.78, 0.24, 1.0);
uniform vec4 bracket_color : source_color = vec4(1.0, 0.78, 0.24, 1.0);
uniform float highlight : hint_range(0.0, 1.0) = 0.0;
// The lanes the other player covers wear a hatch this strong.
uniform float dim : hint_range(0.0, 1.0) = 0.0;
// Corner brackets, for the zone the cursor is on.
uniform float bracket : hint_range(0.0, 1.0) = 0.0;
// A paper flash over everything else, for the moment the ball lands here.
// Separate from highlight so the zone's state shows through as it fades.
uniform float flash : hint_range(0.0, 1.0) = 0.0;
// 0..1, how easy this zone is to miss. Drives the halftone dot size.
uniform float risk : hint_range(0.0, 1.0) = 0.0;
// World-space size of the quad so borders and dots stay the same width everywhere.
uniform vec2 size = vec2(1.0, 1.0);
uniform float line_width = 0.012;
uniform float dot_cell = 0.05;
uniform float hatch_cell = 0.06;
uniform float bracket_length = 0.09;
uniform float bracket_width = 0.022;

void fragment() {
	vec2 px = UV * size;
	vec2 to_edge = min(px, size - px);
	float edge = min(to_edge.x, to_edge.y);
	float line = 1.0 - smoothstep(line_width, line_width + 0.005, edge);

	// Risk dots, in a staggered grid so they read as print.
	vec2 dp = px;
	dp.x += 0.5 * dot_cell * mod(floor(px.y / dot_cell), 2.0);
	vec2 cell = fract(dp / dot_cell) - 0.5;
	float radius = 0.9 * risk;
	float dots = (1.0 - smoothstep(radius - 0.08, radius, length(cell))) * step(0.01, risk);

	// The hatch over covered lanes: diagonal ink strokes.
	float diag = fract((px.x + px.y) / hatch_cell);
	float hatch = (1.0 - smoothstep(0.38, 0.43, abs(diag - 0.5))) * dim;

	// Corner brackets: an L in each corner, inset from the border.
	float inset = line_width + 0.012;
	vec2 c = to_edge - inset;
	float in_arm_x = step(0.0, c.x) * step(c.x, bracket_width) * step(0.0, c.y) * step(c.y, bracket_length);
	float in_arm_y = step(0.0, c.y) * step(c.y, bracket_width) * step(0.0, c.x) * step(c.x, bracket_length);
	float brackets = max(in_arm_x, in_arm_y) * bracket;

	vec3 base = mix(fill.rgb, dot_color.rgb, dots);
	base = mix(base, hatch_color.rgb, hatch * 0.45);
	base = mix(base, highlight_color.rgb, highlight * 0.9);
	vec3 border = mix(line_color.rgb, highlight_color.rgb, highlight * 0.3);
	vec3 shaded = mix(base, border, line);
	shaded = mix(shaded, bracket_color.rgb, brackets);
	ALBEDO = mix(shaded, line_color.rgb, flash * 0.9);
}
