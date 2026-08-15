extends SceneTree

# P6 performance/release tooling contract checks.
# Run headless: --headless --path . --script res://tests/p6_release_tooling_validation.gd

const BENCHMARK_SCRIPT = preload("res://tools/performance_benchmark.gd")
const JSON_REPORT_PATH: String = "res://docs/performance/performance_baseline.json"
const MARKDOWN_REPORT_PATH: String = "res://docs/performance/performance_baseline.md"

const EXPECTED_LEVEL_IDS: Array[String] = [
	"level_01", "level_02", "level_03", "level_04", "level_05",
]
const EXPECTED_MONITORS: Array[String] = [
	"fps", "process_ms", "physics_ms", "node_count", "resource_count",
	"orphan_node_count", "render_objects", "render_primitives", "draw_calls",
	"video_memory_mb", "wall_frame_ms",
]

var _pass_count: int = 0
var _fail_count: int = 0

func _initialize() -> void:
	_validate_benchmark_source_contract()
	_validate_benchmark_runner_contract()
	_validate_package_source_contract()
	_validate_summary_runtime()
	_validate_committable_reports()
	print("P6_RELEASE_TOOLING RESULTS: %d passed, %d failed" % [_pass_count, _fail_count])
	quit(0 if _fail_count == 0 else 1)

func _validate_benchmark_source_contract() -> void:
	var source := _read_source("res://tools/performance_benchmark.gd")
	for level_number in range(1, 6):
		_assert(
			"benchmark includes level %02d" % level_number,
			source.contains("Level%02d_" % level_number)
		)
	_assert("benchmark rejects headless renderer", source.contains("DisplayServer.get_name().to_lower() == \"headless\""))
	_assert("benchmark has bounded warmup", source.contains("DEFAULT_WARMUP_SECONDS") and source.contains("_wait_for_seconds"))
	_assert("benchmark has bounded sample window", source.contains("DEFAULT_SAMPLE_SECONDS") and source.contains("_sample_monitors"))
	_assert("benchmark samples engine fps", source.contains("Performance.TIME_FPS"))
	_assert("benchmark samples per-frame wall time", source.contains("wall_frame_ms"))
	_assert("benchmark samples object counts", source.contains("Performance.OBJECT_NODE_COUNT"))
	_assert("benchmark samples draw calls", source.contains("Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME"))
	_assert("benchmark uses structural budgets", source.contains("STRUCTURAL_BUDGETS"))
	_assert("frame target is explicitly advisory", source.contains("release_blocking\": false"))
	_assert(
		"benchmark pins accessibility without persisting",
		source.contains("AccessibilitySettings._reduced_motion_cache")
		and source.contains('"reduced_motion": false')
		and not source.contains("set_reduced_motion(")
	)
	_assert("benchmark writes json", source.contains("performance_baseline.json"))
	_assert("benchmark writes markdown", source.contains("performance_baseline.md"))

func _validate_benchmark_runner_contract() -> void:
	var source := _read_source("res://tools/run_performance_benchmark.ps1")
	_assert("benchmark runner exists", not source.is_empty())
	_assert("runner does not request headless renderer", not source.contains("--headless"))
	_assert("runner enforces bounded timeout", source.contains("WaitForExit($TimeoutSeconds * 1000)"))
	_assert("runner terminates only timed out child", source.contains("$process.Kill($true)"))
	_assert("runner rejects runtime errors", source.contains("SCRIPT ERROR|ERROR"))
	_assert("runner confines report inside project", source.contains("Benchmark output must stay inside the project"))

func _validate_package_source_contract() -> void:
	var source := _read_source("res://tools/package_windows_release.ps1")
	_assert("package keeps release export", source.contains("--export-release"))
	_assert("package output is configurable", source.contains("[string]$OutputRoot"))
	_assert("package confines output below export", source.contains("Release output must be a child"))
	_assert("package refuses implicit overwrite", source.contains("Release targets already exist"))
	_assert("package checks executable size", source.contains("Assert-WindowsExecutable"))
	_assert("package checks executable MZ header", source.contains("0x4D") and source.contains("0x5A"))
	_assert("package inspects zip entries", source.contains("[System.IO.Compression.ZipFile]::OpenRead"))
	_assert("package creates sha256", source.contains("-Algorithm SHA256"))
	_assert("package verifies written checksum", source.contains("Written SHA-256 checksum does not match"))
	_assert("package smoke is bounded", source.contains("SmokeTimeoutSeconds") and source.contains("WaitForExit($TimeoutSeconds * 1000)"))
	_assert("package smoke boots exported game", source.contains("--headless --audio-driver Dummy --quit-after 30"))
	_assert("package smoke rejects runtime errors", source.contains("Exported-game smoke test emitted a runtime ERROR/SCRIPT ERROR"))
	_assert(
		"package smoke isolates player app data",
		source.contains('$startInfo.Environment["APPDATA"] = $smokeAppData')
		and source.contains('$startInfo.Environment["LOCALAPPDATA"] = $smokeLocalAppData')
		and source.contains('$startInfo.Environment["USERPROFILE"] = $smokeProfileRoot')
	)
	_assert("package avoids broad output-root deletion", not source.contains("Remove-Item -LiteralPath $releaseRoot"))

func _validate_summary_runtime() -> void:
	var benchmark := BENCHMARK_SCRIPT.new()
	var values: Array[float] = [30.0, 45.0, 60.0, 75.0, 90.0]
	var summary := benchmark.call("_summarize", values) as Dictionary
	_assert("runtime summary minimum is correct", is_equal_approx(float(summary["minimum"]), 30.0))
	_assert("runtime summary average is correct", is_equal_approx(float(summary["average"]), 60.0))
	_assert("runtime summary maximum is correct", is_equal_approx(float(summary["maximum"]), 90.0))
	_assert(
		"runtime summary percentiles are ordered",
		float(summary["p05"]) <= float(summary["p50"])
		and float(summary["p50"]) <= float(summary["p95"])
		and float(summary["p95"]) <= float(summary["p99"])
	)
	benchmark.free()

func _validate_committable_reports() -> void:
	_assert("machine-readable baseline exists", FileAccess.file_exists(JSON_REPORT_PATH))
	_assert("human-readable baseline exists", FileAccess.file_exists(MARKDOWN_REPORT_PATH))
	if not FileAccess.file_exists(JSON_REPORT_PATH):
		return
	var json := JSON.new()
	var parse_error := json.parse(_read_source(JSON_REPORT_PATH))
	_assert("baseline json parses", parse_error == OK)
	if parse_error != OK or not json.data is Dictionary:
		return
	var report := json.data as Dictionary
	_assert("baseline schema is versioned", int(report.get("schema_version", 0)) == 1)
	_assert("baseline declares machine specificity", bool(report.get("advisory_machine_specific", false)))
	_assert("baseline records deterministic seed", int(report.get("configuration", {}).get("deterministic_seed", 0)) != 0)
	_assert("baseline records medium quality", String(report.get("configuration", {}).get("quality_preset", "")) == "Medium")
	_assert("baseline records full-motion benchmark mode", not bool(report.get("configuration", {}).get("reduced_motion", true)))
	var levels := report.get("levels", []) as Array
	_assert("baseline contains five levels", levels.size() == 5)
	var found_ids: Dictionary = {}
	for level_value in levels:
		var level := level_value as Dictionary
		found_ids[String(level.get("id", ""))] = true
		_assert("%s sampled frames" % level.get("id", "unknown"), int(level.get("sample_count", 0)) > 0)
		var monitors := level.get("monitors", {}) as Dictionary
		for monitor_name in EXPECTED_MONITORS:
			_assert("%s reports %s" % [level.get("id", "unknown"), monitor_name], monitors.has(monitor_name))
		var advisory := level.get("advisory_frame_targets", {}) as Dictionary
		_assert("%s fps is nonblocking" % level.get("id", "unknown"), not bool(advisory.get("release_blocking", true)))
		_assert(
			"%s reports one percent low" % level.get("id", "unknown"),
			float(advisory.get("one_percent_low_fps", 0.0)) > 0.0
		)
	for expected_id in EXPECTED_LEVEL_IDS:
		_assert("baseline includes %s" % expected_id, found_ids.has(expected_id))
	var markdown := _read_source(MARKDOWN_REPORT_PATH)
	_assert("markdown labels snapshot advisory", markdown.contains("Machine-specific advisory snapshot"))
	_assert("markdown includes performance table", markdown.contains("| Level | Avg FPS |"))

func _read_source(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var source := file.get_as_text()
	file.close()
	return source

func _assert(label: String, condition: bool) -> void:
	if condition:
		print("P6_RELEASE_TOOLING_%s_OK" % label.to_upper().replace(" ", "_"))
		_pass_count += 1
	else:
		print("P6_RELEASE_TOOLING_%s_FAIL" % label.to_upper().replace(" ", "_"))
		_fail_count += 1
