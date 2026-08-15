extends SceneTree

# Visible-renderer benchmark for the five shipping levels.
# Run through tools/run_performance_benchmark.ps1 so runtime errors are treated as
# failures. Frame-rate targets are advisory; only malformed scenes and deliberately
# generous structural guardrails fail the benchmark.

const REPORT_SCHEMA_VERSION: int = 1
const DEFAULT_OUTPUT_DIRECTORY: String = "res://docs/performance"
const DEFAULT_WARMUP_SECONDS: float = 2.0
const DEFAULT_SAMPLE_SECONDS: float = 5.0
const SAMPLE_INTERVAL_USEC: int = 100000
const BENCHMARK_RESOLUTION: Vector2i = Vector2i(1280, 720)
const BENCHMARK_QUALITY: String = "Medium"
const DETERMINISTIC_SEED: int = 6052026
const ADVISORY_AVERAGE_FPS: float = 60.0
const ADVISORY_LOW_FPS: float = 45.0

const LEVEL_SPECS: Array[Dictionary] = [
	{"id": "level_01", "name": "Community Park", "scene": "res://scenes/levels/Level01_Park.tscn"},
	{"id": "level_02", "name": "Playground", "scene": "res://scenes/levels/Level02_Playground.tscn"},
	{"id": "level_03", "name": "Lakeside", "scene": "res://scenes/levels/Level03_Lakeside.tscn"},
	{"id": "level_04", "name": "Festival", "scene": "res://scenes/levels/Level04_Festival.tscn"},
	{"id": "level_05", "name": "Botanical Gardens", "scene": "res://scenes/levels/Level05_BotanicalGardens.tscn"},
]

const MONITOR_SPECS: Array[Dictionary] = [
	{"key": "fps", "monitor": Performance.TIME_FPS, "scale": 1.0},
	{"key": "process_ms", "monitor": Performance.TIME_PROCESS, "scale": 1000.0},
	{"key": "physics_ms", "monitor": Performance.TIME_PHYSICS_PROCESS, "scale": 1000.0},
	{"key": "node_count", "monitor": Performance.OBJECT_NODE_COUNT, "scale": 1.0},
	{"key": "resource_count", "monitor": Performance.OBJECT_RESOURCE_COUNT, "scale": 1.0},
	{"key": "orphan_node_count", "monitor": Performance.OBJECT_ORPHAN_NODE_COUNT, "scale": 1.0},
	{"key": "render_objects", "monitor": Performance.RENDER_TOTAL_OBJECTS_IN_FRAME, "scale": 1.0},
	{"key": "render_primitives", "monitor": Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME, "scale": 1.0},
	{"key": "draw_calls", "monitor": Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME, "scale": 1.0},
	{"key": "video_memory_mb", "monitor": Performance.RENDER_VIDEO_MEM_USED, "scale": 1.0 / (1024.0 * 1024.0)},
]

# These are runaway-scene guards, not performance targets. Ordinary frame-rate
# variation never fails a release benchmark.
const STRUCTURAL_BUDGETS: Dictionary = {
	"node_count": 5000.0,
	"resource_count": 12000.0,
	"orphan_node_count": 256.0,
	"render_objects": 20000.0,
	"render_primitives": 5000000.0,
	"draw_calls": 5000.0,
}

var _output_directory: String = DEFAULT_OUTPUT_DIRECTORY
var _warmup_seconds: float = DEFAULT_WARMUP_SECONDS
var _sample_seconds: float = DEFAULT_SAMPLE_SECONDS
var _structural_failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_parse_user_arguments()
	if DisplayServer.get_name().to_lower() == "headless":
		push_error("Performance benchmark requires a visible renderer; omit --headless.")
		quit(2)
		return

	paused = false
	seed(DETERMINISTIC_SEED)
	# Pin presentation behavior without persisting over the player's preference.
	AccessibilitySettings._reduced_motion_cache[
		AccessibilitySettings.DEFAULT_SETTINGS_PATH
	] = false
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(BENCHMARK_RESOLUTION)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var quality_settings := root.get_node_or_null("QualitySettings")
	if quality_settings != null and quality_settings.has_method("apply_preset"):
		quality_settings.call("apply_preset", BENCHMARK_QUALITY, false)

	var level_reports: Array[Dictionary] = []
	for level_spec in LEVEL_SPECS:
		var level_report := await _benchmark_level(level_spec)
		if level_report.is_empty():
			quit(3)
			return
		level_reports.append(level_report)

	var report := _build_report(level_reports)
	var write_error := _write_reports(report)
	if write_error != OK:
		push_error("Could not write benchmark reports (error %d)." % write_error)
		quit(4)
		return

	if not _structural_failures.is_empty():
		for failure in _structural_failures:
			push_error("Structural benchmark budget exceeded: %s" % failure)
		quit(5)
		return
	print(
		"PERFORMANCE_BENCHMARK_OK|levels=%d|warmup=%.2f|sample=%.2f|output=%s"
		% [LEVEL_SPECS.size(), _warmup_seconds, _sample_seconds, _absolute_output_directory()]
	)
	quit(0)

func _parse_user_arguments() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output-dir="):
			_output_directory = argument.trim_prefix("--output-dir=").strip_edges()
		elif argument.begins_with("--warmup-seconds="):
			_warmup_seconds = clampf(
				float(argument.trim_prefix("--warmup-seconds=")),
				0.1,
				30.0
			)
		elif argument.begins_with("--sample-seconds="):
			_sample_seconds = clampf(
				float(argument.trim_prefix("--sample-seconds=")),
				0.25,
				60.0
			)

func _benchmark_level(level_spec: Dictionary) -> Dictionary:
	seed(DETERMINISTIC_SEED + String(level_spec["id"]).hash())
	var packed_scene := load(String(level_spec["scene"])) as PackedScene
	if packed_scene == null:
		push_error("Benchmark could not load %s." % level_spec["scene"])
		return {}
	var level := packed_scene.instantiate()
	if level == null:
		push_error("Benchmark could not instantiate %s." % level_spec["scene"])
		return {}
	root.add_child(level)
	await process_frame
	await process_frame
	paused = false

	var title_screen := level.get_node_or_null("TitleScreen") as CanvasLayer
	if title_screen != null:
		title_screen.visible = false
	var how_to_play := level.get_node_or_null("HowToPlayScreen") as CanvasLayer
	if how_to_play != null:
		how_to_play.visible = false
	var session := level.get_node_or_null("GameTimer")
	if session == null or not session.has_method("_set_state"):
		push_error("Benchmark level %s has no usable GameTimer." % level_spec["id"])
		level.queue_free()
		await process_frame
		return {}
	session.call("_set_state", 2) # GameSession.SessionState.ACTIVE

	await _wait_for_seconds(_warmup_seconds)
	var samples := await _sample_monitors(_sample_seconds)
	var monitor_summary: Dictionary = {}
	for monitor_spec in MONITOR_SPECS:
		var key := String(monitor_spec["key"])
		monitor_summary[key] = _summarize(samples[key] as Array[float])
	monitor_summary["wall_frame_ms"] = _summarize(samples["wall_frame_ms"] as Array[float])
	var p99_frame_ms := maxf(float(monitor_summary["wall_frame_ms"]["p99"]), 0.001)
	var one_percent_low_fps := 1000.0 / p99_frame_ms

	var advisory := {
		"average_fps_target": ADVISORY_AVERAGE_FPS,
		"low_fps_target": ADVISORY_LOW_FPS,
		"average_fps_meets_target": float(monitor_summary["fps"]["average"]) >= ADVISORY_AVERAGE_FPS,
		"one_percent_low_fps": one_percent_low_fps,
		"one_percent_low_meets_target": one_percent_low_fps >= ADVISORY_LOW_FPS,
		"release_blocking": false,
	}
	var structural_status: Dictionary = {}
	for metric in STRUCTURAL_BUDGETS:
		var maximum := float(monitor_summary[metric]["maximum"])
		var budget := float(STRUCTURAL_BUDGETS[metric])
		var passed := maximum <= budget
		structural_status[metric] = {"maximum": maximum, "budget": budget, "passed": passed}
		if not passed:
			_structural_failures.append("%s %s > %s" % [level_spec["id"], metric, budget])

	var report := {
		"id": String(level_spec["id"]),
		"name": String(level_spec["name"]),
		"scene": String(level_spec["scene"]),
		"sample_count": int((samples["wall_frame_ms"] as Array[float]).size()),
		"monitors": monitor_summary,
		"advisory_frame_targets": advisory,
		"structural_budgets": structural_status,
	}
	print(
		"PERFORMANCE_LEVEL_OK|id=%s|avg_fps=%.1f|one_percent_low_fps=%.1f|p95_frame_ms=%.2f|draw_calls_max=%.0f"
		% [
			report["id"],
			monitor_summary["fps"]["average"],
			one_percent_low_fps,
			monitor_summary["wall_frame_ms"]["p95"],
			monitor_summary["draw_calls"]["maximum"],
		]
	)
	level.queue_free()
	await process_frame
	await process_frame
	paused = false
	return report

func _wait_for_seconds(seconds: float) -> void:
	var deadline := Time.get_ticks_usec() + int(seconds * 1000000.0)
	while Time.get_ticks_usec() < deadline:
		await process_frame

func _sample_monitors(seconds: float) -> Dictionary:
	var result: Dictionary = {}
	for monitor_spec in MONITOR_SPECS:
		result[String(monitor_spec["key"])] = [] as Array[float]
	result["wall_frame_ms"] = [] as Array[float]
	var deadline := Time.get_ticks_usec() + int(seconds * 1000000.0)
	var next_sample_usec := Time.get_ticks_usec()
	var previous_frame_usec := Time.get_ticks_usec()
	while Time.get_ticks_usec() < deadline:
		await process_frame
		var now_usec := Time.get_ticks_usec()
		var frame_values := result["wall_frame_ms"] as Array[float]
		frame_values.append(float(now_usec - previous_frame_usec) / 1000.0)
		previous_frame_usec = now_usec
		if now_usec < next_sample_usec:
			continue
		next_sample_usec += SAMPLE_INTERVAL_USEC
		for monitor_spec in MONITOR_SPECS:
			var key := String(monitor_spec["key"])
			var values := result[key] as Array[float]
			values.append(
				float(Performance.get_monitor(int(monitor_spec["monitor"])))
				* float(monitor_spec["scale"])
			)
	return result

func _summarize(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return {
			"minimum": 0.0, "average": 0.0, "p05": 0.0, "p50": 0.0,
			"p95": 0.0, "p99": 0.0, "maximum": 0.0,
		}
	var sorted_values := values.duplicate()
	sorted_values.sort()
	var total := 0.0
	for value in sorted_values:
		total += value
	return {
		"minimum": sorted_values.front(),
		"average": total / float(sorted_values.size()),
		"p05": _percentile(sorted_values, 0.05),
		"p50": _percentile(sorted_values, 0.50),
		"p95": _percentile(sorted_values, 0.95),
		"p99": _percentile(sorted_values, 0.99),
		"maximum": sorted_values.back(),
	}

func _percentile(sorted_values: Array[float], fraction: float) -> float:
	if sorted_values.size() == 1:
		return sorted_values[0]
	var index := clampi(
		roundi(float(sorted_values.size() - 1) * clampf(fraction, 0.0, 1.0)),
		0,
		sorted_values.size() - 1
	)
	return sorted_values[index]

func _build_report(level_reports: Array[Dictionary]) -> Dictionary:
	return {
		"schema_version": REPORT_SCHEMA_VERSION,
		"generated_utc": Time.get_datetime_string_from_system(true, true),
		"advisory_machine_specific": true,
		"release_policy": "Frame thresholds are advisory; runtime errors and structural budgets are blocking.",
		"machine": {
			"os": OS.get_name(),
			"processor": OS.get_processor_name(),
			"logical_processors": OS.get_processor_count(),
			"renderer": RenderingServer.get_current_rendering_method(),
			"rendering_driver": RenderingServer.get_current_rendering_driver_name(),
			"video_adapter": RenderingServer.get_video_adapter_name(),
			"display_refresh_rate_hz": DisplayServer.screen_get_refresh_rate(),
			"vsync_mode": int(DisplayServer.window_get_vsync_mode()),
			"engine_max_fps": Engine.max_fps,
		},
		"configuration": {
			"resolution": "%dx%d" % [BENCHMARK_RESOLUTION.x, BENCHMARK_RESOLUTION.y],
			"quality_preset": BENCHMARK_QUALITY,
			"reduced_motion": false,
			"deterministic_seed": DETERMINISTIC_SEED,
			"warmup_seconds": _warmup_seconds,
			"sample_seconds": _sample_seconds,
			"display_driver": DisplayServer.get_name(),
		},
		"levels": level_reports,
		"structural_failures": _structural_failures,
	}

func _write_reports(report: Dictionary) -> Error:
	var output_directory := _absolute_output_directory()
	var directory_error := DirAccess.make_dir_recursive_absolute(output_directory)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return directory_error
	var json_path := output_directory.path_join("performance_baseline.json")
	var markdown_path := output_directory.path_join("performance_baseline.md")
	var json_error := _write_text(json_path, JSON.stringify(report, "  ", false, true) + "\n")
	if json_error != OK:
		return json_error
	return _write_text(markdown_path, _markdown_report(report))

func _absolute_output_directory() -> String:
	if _output_directory.begins_with("res://") or _output_directory.begins_with("user://"):
		return ProjectSettings.globalize_path(_output_directory)
	return _output_directory

func _write_text(path: String, content: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(content)
	file.close()
	return OK

func _markdown_report(report: Dictionary) -> String:
	var machine := report["machine"] as Dictionary
	var configuration := report["configuration"] as Dictionary
	var lines: PackedStringArray = [
		"# Don't Look Human performance baseline",
		"",
		"> Machine-specific advisory snapshot. FPS thresholds do not block release; runtime errors and structural budgets do.",
		"",
		"- Generated (UTC): `%s`" % report["generated_utc"],
		"- OS: `%s`" % machine["os"],
		"- CPU: `%s` (%d logical processors)" % [machine["processor"], machine["logical_processors"]],
		"- GPU: `%s`" % machine["video_adapter"],
		"- Display: `%.1f Hz`, VSync mode `%d`, engine FPS cap `%d`" % [
			machine["display_refresh_rate_hz"],
			machine["vsync_mode"],
			machine["engine_max_fps"],
		],
		"- Renderer: `%s / %s`" % [machine["renderer"], machine["rendering_driver"]],
		"- Configuration: `%s`, `%s`, reduced motion `%s`, %.1fs warm-up + %.1fs sample per level" % [
			configuration["resolution"],
			configuration["quality_preset"],
			str(configuration["reduced_motion"]).to_lower(),
			configuration["warmup_seconds"],
			configuration["sample_seconds"],
		],
		"",
		"| Level | Avg FPS | 1% low FPS | Median frame ms | P95 frame ms | Max process ms | Max draw calls | Max nodes | Structural |",
		"|---|---:|---:|---:|---:|---:|---:|---:|:---:|",
	]
	for level_report in report["levels"]:
		var level := level_report as Dictionary
		var monitors := level["monitors"] as Dictionary
		var structural := level["structural_budgets"] as Dictionary
		var structural_pass := true
		for metric in structural:
			if not bool(structural[metric]["passed"]):
				structural_pass = false
				break
		lines.append(
			"| %s | %.1f | %.1f | %.2f | %.2f | %.2f | %.0f | %.0f | %s |" % [
				level["name"],
				monitors["fps"]["average"],
				level["advisory_frame_targets"]["one_percent_low_fps"],
				monitors["wall_frame_ms"]["p50"],
				monitors["wall_frame_ms"]["p95"],
				monitors["process_ms"]["maximum"],
				monitors["draw_calls"]["maximum"],
				monitors["node_count"]["maximum"],
				"PASS" if structural_pass else "FAIL",
			]
		)
	lines.append_array([
		"",
		"Advisory targets: average FPS >= %.0f and frame-time-derived 1%% low FPS >= %.0f." % [
			ADVISORY_AVERAGE_FPS,
			ADVISORY_LOW_FPS,
		],
		"",
		"Raw monitor distributions and every structural budget are available in `performance_baseline.json`.",
		"",
	])
	return "\n".join(lines)
