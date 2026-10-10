// The club hall floor: maple planks running the length of the table, a pool
// of light under the lamp and the gym's painted lines, fading to ink at
// the edges of the hall. Unshaded, so it reads the same under software GL.
shader_type spatial;
render_mode cull_back, unshaded;

uniform vec4 plank_color : source_color = vec4(0.49, 0.31, 0.19, 1.0);
uniform vec4 plank_dark : source_color = vec4(0.33, 0.20, 0.13, 1.0);
uniform vec4 joint_color : source_color = vec4(0.16, 0.10, 0.09, 1.0);
uniform vec4 ink : source_color = vec4(0.10, 0.09, 0.19, 1.0);
uniform vec4 line_paper : source_color = vec4(0.96, 0.93, 0.86, 1.0);
uniform vec4 line_orange : source_color = vec4(1.0, 0.48, 0.18, 1.0);
// Plank width across the hall and length along it, in metres.
uniform float plank_width = 0.16;
uniform float plank_length = 1.9;
uniform float joint_width = 0.012;
// The pool of light: full inside pool_radius, gone by pool_radius + pool_soft.
uniform float pool_radius = 2.4;
uniform float pool_soft = 3.2;
uniform float pool_boost = 0.35;
// Beyond this the hall fades to ink.
uniform float fade_start = 5.0;
uniform float fade_end = 9.5;
// The painted court around the table and the centre circle.
uniform vec2 court_half = vec2(2.75, 2.3);
uniform float circle_radius = 1.9;
uniform float line_width = 0.045;
uniform float line_alpha = 0.42;

varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	// Planks: rows across z, staggered along x by a hash of the row.
	float row = floor(p.y / plank_width);
	float offset = hash(vec2(row, 3.0)) * plank_length;
	float along = p.x + offset;
	float col = floor(along / plank_length);
	float shade = hash(vec2(row, col));
	vec3 wood = mix(plank_dark.rgb, plank_color.rgb, 0.35 + 0.65 * shade);
	// A faint grain along the plank.
	float grain = 0.5 + 0.5 * sin(p.y * 90.0 + shade * 20.0 + sin(along * 3.0) * 1.5);
	wood *= 0.94 + 0.06 * grain;
	// Joints between planks.
	float across = abs(fract(p.y / plank_width) - 0.5) * plank_width;
	float end = abs(fract(along / plank_length) - 0.5) * plank_length;
	float joint = 1.0 - smoothstep(joint_width * 0.5, joint_width * 0.5 + 0.004, min(plank_width * 0.5 - across, plank_length * 0.5 - end));
	wood = mix(wood, joint_color.rgb, joint * 0.85);

	// Painted lines: the court rectangle and the centre circle.
	vec2 d = abs(p) - court_half;
	float rect = 1.0 - smoothstep(line_width * 0.5, line_width * 0.5 + 0.01, abs(max(d.x, d.y)));
	float circ = 1.0 - smoothstep(line_width * 0.5, line_width * 0.5 + 0.01, abs(length(p) - circle_radius));
	wood = mix(wood, line_paper.rgb, rect * line_alpha);
	wood = mix(wood, line_orange.rgb, circ * line_alpha);

	// The lamp over the table, then the dark of the hall.
	float dist = length(p);
	float pool = 1.0 - smoothstep(pool_radius, pool_radius + pool_soft, dist);
	wood *= 1.0 - pool_boost * 0.6 + pool_boost * pool;
	float fade = smoothstep(fade_start, fade_end, dist);
	ALBEDO = mix(wood, ink.rgb, fade);
}
