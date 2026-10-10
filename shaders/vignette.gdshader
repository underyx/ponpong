// Over the 3D view, under the HUD: the print's ink creeping in at the
// corners as halftone dots, and a touch of paper grain, so the arena sits
// on the same sheet as the cards.
shader_type canvas_item;

uniform vec4 ink : source_color = vec4(0.10, 0.09, 0.19, 1.0);
uniform float strength : hint_range(0.0, 1.0) = 0.3;
// Where the dots start, as a distance from the centre (0..1 is the corner).
uniform float start : hint_range(0.0, 1.0) = 0.62;
uniform float dot_px = 7.0;
uniform float grain : hint_range(0.0, 0.2) = 0.035;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 centred = (UV - 0.5) * 2.0;
	float dist = length(centred * vec2(1.0, 0.85));
	float edge = smoothstep(start, 1.25, dist);
	vec2 cell = fract(FRAGCOORD.xy / dot_px) - 0.5;
	float radius = 0.72 * edge;
	float dot = 1.0 - smoothstep(radius - 0.12, radius, length(cell));
	float veil = max(dot * edge, edge * edge * 0.5) * strength;
	float speck = (hash(floor(FRAGCOORD.xy / 2.0)) - 0.5) * grain;
	COLOR = vec4(ink.rgb, clamp(veil + speck, 0.0, 1.0));
}
