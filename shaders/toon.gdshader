// ponpong toon shader: banded diffuse, rim light, halftone shadows.
// Everything in the scene wears this so the look stays coherent.
shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_toon;

uniform vec4 albedo : source_color = vec4(0.8, 0.8, 0.8, 1.0);
uniform vec4 shadow_tint : source_color = vec4(0.30, 0.22, 0.42, 1.0);
uniform int bands : hint_range(1, 8) = 3;
uniform float band_softness : hint_range(0.0, 0.5) = 0.04;
uniform float rim_strength : hint_range(0.0, 3.0) = 0.9;
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform vec4 rim_color : source_color = vec4(1.0, 0.95, 0.85, 1.0);
uniform float specular_size : hint_range(0.0, 1.0) = 0.12;
uniform float specular_strength : hint_range(0.0, 2.0) = 0.6;
uniform bool halftone = true;
uniform float halftone_scale : hint_range(2.0, 24.0) = 7.0;
uniform float halftone_strength : hint_range(0.0, 1.0) = 0.35;

varying vec2 screen_px;

void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = 0.8;
	METALLIC = 0.0;
	screen_px = FRAGCOORD.xy;
}

float band(float x, float steps, float soft) {
	// Quantise x into `steps` levels with a little smoothing at the edges.
	float scaled = x * steps;
	float lower = floor(scaled);
	float frac = scaled - lower;
	float edge = smoothstep(0.5 - soft * steps, 0.5 + soft * steps, frac);
	return clamp((lower + edge) / steps, 0.0, 1.0);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float wrapped = clamp(ndl * 0.5 + 0.5, 0.0, 1.0);
	float lit = band(wrapped * ATTENUATION, float(bands), band_softness);

	// Halftone dots creep into the shadow bands.
	float dots = 1.0;
	if (halftone) {
		vec2 cell = fract(screen_px / halftone_scale) - 0.5;
		float radius = 0.55 * (1.0 - lit);
		float d = length(cell);
		dots = 1.0 - halftone_strength * (1.0 - smoothstep(radius - 0.08, radius, d));
	}

	vec3 shade = mix(shadow_tint.rgb, vec3(1.0), lit) * dots;
	DIFFUSE_LIGHT += shade * ALBEDO * LIGHT_COLOR / PI;

	// Hard-edged specular blob.
	vec3 half_vec = normalize(VIEW + LIGHT);
	float spec = dot(NORMAL, half_vec);
	float spec_band = step(1.0 - specular_size, spec) * step(0.0, ndl);
	SPECULAR_LIGHT += spec_band * specular_strength * LIGHT_COLOR / PI;

	// Rim light only on the lit side so it reads as backlight, not glow.
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	float rim = fresnel * rim_strength * smoothstep(-0.2, 0.3, ndl);
	SPECULAR_LIGHT += rim * rim_color.rgb * LIGHT_COLOR / PI;
}
