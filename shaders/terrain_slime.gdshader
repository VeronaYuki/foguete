shader_type spatial;

uniform sampler2D slime_noise;
uniform vec3 slime_color : source_color = vec3(0.25, 1.0, 0.45);
uniform float slime_strength = 1.4;
uniform float wet_roughness : hint_range(0.0, 1.0) = 0.3;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	// thin ribbons of noise, gated by a larger-scale patch mask, become veins
	float n = texture(slime_noise, wpos.xz * 0.05).r;
	float patch = smoothstep(0.42, 0.62, texture(slime_noise, wpos.xz * 0.007).r);
	float veins = smoothstep(0.53, 0.56, n) * (1.0 - smoothstep(0.60, 0.64, n));
	float m = veins * patch * COLOR.a;
	float pulse = 0.8 + 0.2 * sin(TIME * 1.6 + n * 12.0);
	EMISSION = slime_color * m * slime_strength * pulse;
	// wet sheen where slimy, dry rock elsewhere
	ROUGHNESS = mix(0.85, wet_roughness, COLOR.a);
	// faint fresnel so wet ground catches the lights
	EMISSION += slime_color * 0.015 * pow(1.0 - dot(NORMAL, VIEW), 3.0) * COLOR.a;
}
