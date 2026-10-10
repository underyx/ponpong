// The landing ring: a thin band on a flat quad that ImpactFx scales up and
// fades out where the ball hit the table. Unshaded and additive-looking, so
// it reads the same under software GL as on a desktop.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.85, 0.45, 1.0);
// 1 at the impact, tweened to 0 as the ring spreads.
uniform float fade : hint_range(0.0, 1.0) = 1.0;
// Where the band sits, as a fraction of the quad's half size, and how wide it is.
uniform float radius : hint_range(0.0, 1.0) = 0.78;
uniform float thickness : hint_range(0.01, 0.5) = 0.26;

float band(float dist) {
	return 1.0 - smoothstep(0.0, thickness, abs(dist - radius));
}

void fragment() {
	float dist = length(UV - vec2(0.5)) * 2.0;
	ALBEDO = color.rgb;
	ALPHA = band(dist) * fade * color.a;
}
