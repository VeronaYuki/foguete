shader_type canvas_item;

// Dark curved vignette that frames the screen like the inside of a helmet
// visor, with faint breath-fog at the bottom.

uniform float strength : hint_range(0.0, 1.0) = 0.92;

void fragment() {
	vec2 uv = UV - 0.5;
	uv.x *= 1.35;
	float d = length(uv);
	float dark = smoothstep(0.40, 0.72, d) * strength;
	// breath fog rising from the bottom edge
	float fog = smoothstep(0.35, 0.5, UV.y) * (1.0 - smoothstep(0.5, 1.0, d)) * 0.06;
	COLOR = vec4(vec3(0.02, 0.03, 0.04), dark) + vec4(0.5, 0.6, 0.7, fog);
}
