shader_type spatial;

// Projects Lucas's photo onto the front of a 3D head sphere so it wraps
// with the skull's curvature instead of floating as a flat card.

uniform sampler2D face_tex : source_color, filter_linear;
uniform vec3 skin_color : source_color = vec3(0.72, 0.55, 0.45);
uniform float face_emission = 0.2;

// face region within the 512x512 photo (normalized, top-left origin)
uniform vec2 face_center = vec2(0.51, 0.33);
uniform vec2 face_extent = vec2(0.24, 0.25);
// head half-size the face maps across (local mesh units)
uniform vec2 head_span = vec2(0.20, 0.22);

varying vec3 v_local;
varying vec3 v_normal;

void vertex() {
	v_local = VERTEX;
	v_normal = NORMAL;
}

void fragment() {
	// map local X/Y on the head to the photo's face region
	float u = face_center.x + (v_local.x / head_span.x) * face_extent.x;
	float v = face_center.y - (v_local.y / head_span.y) * face_extent.y;
	vec3 face = texture(face_tex, vec2(u, v)).rgb;

	// oval mask so the face fades into skin at the edges
	float ox = v_local.x / (head_span.x * 0.9);
	float oy = (v_local.y - 0.01) / (head_span.y * 1.0);
	float oval = 1.0 - smoothstep(0.75, 1.05, sqrt(ox * ox + oy * oy));

	// only paint the forward-facing hemisphere
	float front = smoothstep(0.1, 0.5, v_normal.z);
	float mask = oval * front;

	ALBEDO = mix(skin_color, face, mask);
	ROUGHNESS = 0.8;
	METALLIC = 0.0;
	EMISSION = face * mask * face_emission;
}
