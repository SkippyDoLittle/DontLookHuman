// sky.gdshader — Daytime procedural sky: gradient, scrolling cloud layer, sun disc.
// Attach as ShaderMaterial on a Sky resource inside WorldEnvironment.
// Every tunable is a shader parameter — adjust them in Inspector → ShaderMaterial.
shader_type sky;

// ── Sky gradient ──────────────────────────────────────────────────────────────
uniform vec4  sky_top_color:     source_color = vec4(0.15, 0.38, 0.78, 1.0);
uniform vec4  sky_horizon_color: source_color = vec4(0.68, 0.84, 0.97, 1.0);
// Lower value = sharper blue band at horizon; higher = gentler gradient up to zenith.
uniform float sky_curve: hint_range(0.02, 1.0) = 0.09;

// ── Ground (below the horizon line) ──────────────────────────────────────────
uniform vec4 ground_color: source_color = vec4(0.29, 0.52, 0.19, 1.0);

// ── Clouds ────────────────────────────────────────────────────────────────────
uniform vec4  cloud_color:    source_color          = vec4(1.0, 1.0, 1.0, 1.0);
// 0 = clear sky · 0.5 = patchy cumulus · 1.0 = overcast
uniform float cloud_coverage: hint_range(0.0, 1.0)  = 0.45;
// Smaller values = larger cloud puffs; larger = many small wisps
uniform float cloud_scale:    hint_range(0.5, 8.0)  = 3.0;
// Slow drift speed; set to 0 for a completely static sky
uniform float cloud_speed:    hint_range(0.0, 0.2)  = 0.015;

// ── Sun ───────────────────────────────────────────────────────────────────────
// Half-angle of the visible sun disc in degrees (real sun ≈ 0.25°; 4° is more readable in-game).
// The disc automatically appears wherever the DirectionalLight3D is pointing — no manual positioning needed.
uniform float sun_angle_max: hint_range(0.5, 20.0) = 4.0;

// ── Noise utilities ───────────────────────────────────────────────────────────
float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash2(i),                hash2(i + vec2(1.0, 0.0)), f.x),
		mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), f.x),
		f.y);
}

// 4-octave FBM gives soft, irregular cloud shapes cheaply
float fbm(vec2 p) {
	float v = 0.0, w = 0.5;
	for (int i = 0; i < 4; i++) {
		v += w * noise2(p);
		p *= 2.0;
		w *= 0.5;
	}
	return v;
}

void sky() {
	float up = EYEDIR.y;   // +1 = zenith · 0 = horizon · -1 = nadir

	// ── Sky gradient ──────────────────────────────────────────────────────────
	float t   = pow(max(up, 0.0), sky_curve);
	vec3  col = mix(sky_horizon_color.rgb, sky_top_color.rgb, t);

	// ── Ground ────────────────────────────────────────────────────────────────
	if (up < 0.0) {
		col = ground_color.rgb;
	}

	// ── Clouds ────────────────────────────────────────────────────────────────
	// Only draw above the horizon.  Dividing xz by y projects the ray onto a
	// virtual horizontal plane — produces natural perspective foreshortening so
	// cloud puffs look smaller near the zenith and larger near the horizon.
	if (up > 0.005) {
		vec2  uv    = EYEDIR.xz / (up + 0.01) * cloud_scale + TIME * cloud_speed;
		float cloud = fbm(uv);
		cloud       = smoothstep(1.0 - cloud_coverage, 1.0 - cloud_coverage + 0.3, cloud);
		// Feather clouds at the horizon so they don't cut in sharply
		cloud      *= smoothstep(0.0, 0.10, up);
		col         = mix(col, cloud_color.rgb, cloud * 0.88);
	}

	// ── Sun disc ──────────────────────────────────────────────────────────────
	// LIGHT0_DIRECTION is Godot's built-in that points from the scene toward the
	// DirectionalLight3D — so the disc appears exactly where the light comes from.
	float cos_max = cos(radians(sun_angle_max));
	float sdot    = dot(EYEDIR, LIGHT0_DIRECTION);
	float disc    = smoothstep(cos_max - 0.002, cos_max, sdot);
	float glow    = pow(max(sdot, 0.0), 48.0) * 0.55;
	col          += LIGHT0_COLOR * LIGHT0_ENERGY * (disc + glow);

	COLOR = col;
}
