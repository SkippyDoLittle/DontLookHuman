shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 uv = UV - vec2(0.5);
	float d = length(uv * vec2(1.0, 1.778));
	float v = smoothstep(0.25, 0.65, d) * intensity;
	COLOR = vec4(0.8, 0.0, 0.0, v);
}
