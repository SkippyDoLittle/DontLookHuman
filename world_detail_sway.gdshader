shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform float sway_amplitude : hint_range(0.0, 0.08, 0.005) = 0.025;
uniform float sway_speed : hint_range(0.0, 2.0, 0.05) = 0.9;

void vertex() {
	// MODEL_MATRIX includes each MultiMesh instance transform, so neighboring
	// blades receive different phases without per-instance CPU updates.
	vec3 world_origin = MODEL_MATRIX[3].xyz;
	float phase = world_origin.x * 0.73 + world_origin.z * 0.51 + TIME * sway_speed;
	float tip_weight = clamp(VERTEX.y * 5.0 + 0.5, 0.0, 1.0);
	VERTEX.x += sin(phase) * sway_amplitude * tip_weight;
	VERTEX.z += cos(phase * 0.83) * sway_amplitude * 0.4 * tip_weight;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.92;
}
