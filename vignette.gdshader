shader_type canvas_item;

// Suspicion should frame the action, never hide it. The aspect ratio is derived
// from the viewport so the falloff stays circular at every supported resolution.
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 danger_color : source_color = vec4(0.18, 0.01, 0.015, 1.0);
uniform float inner_radius : hint_range(0.0, 1.0) = 0.32;
uniform float outer_radius : hint_range(0.0, 1.5) = 0.92;

void fragment() {
	vec2 centered_uv = UV - vec2(0.5);
	float aspect_ratio = SCREEN_PIXEL_SIZE.y / max(SCREEN_PIXEL_SIZE.x, 0.000001);
	centered_uv.x *= aspect_ratio;
	float edge = smoothstep(inner_radius, outer_radius, length(centered_uv));
	COLOR = vec4(danger_color.rgb, edge * intensity * danger_color.a);
}
