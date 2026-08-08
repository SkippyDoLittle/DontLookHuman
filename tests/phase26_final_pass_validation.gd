extends SceneTree

# Phase 26 validation: final replayability, balance, and marketing pass.
# Run headless: --headless --path . --script res://tests/phase26_final_pass_validation.gd

var _pass_count: int = 0
var _fail_count: int = 0

func _init() -> void:
	_run_all()
	print("PHASE26 RESULTS: %d passed, %d failed" % [_pass_count, _fail_count])
	quit(0 if _fail_count == 0 else 1)

func _run_all() -> void:
	_test_trailer_has_collision_comedy_function()
	_test_trailer_shot_kind_is_collision()
	_test_trailer_has_ranger_a_variable()
	_test_trailer_has_body_a_variable()
	_test_trailer_seconds_unchanged()
	_test_architecture_mentions_near_exit_alert()
	_test_architecture_mentions_body_lean()
	_test_architecture_mentions_playground_collision()
	_test_architecture_mentions_bonus_seconds()
	_test_portfolio_checklist_has_phase26_section()
	_test_portfolio_checklist_mentions_collision()
	_test_known_issues_exists()
	_test_phase25_monitor_still_exists()
	_test_finalizer_has_frame_count_parameter()

func _assert(label: String, condition: bool) -> void:
	if condition:
		print("PHASE26_%s_OK" % label.to_upper().replace(" ", "_"))
		_pass_count += 1
	else:
		print("PHASE26_%s_FAIL" % label.to_upper().replace(" ", "_"))
		_fail_count += 1

func _read_source(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var src := file.get_as_text()
	file.close()
	return src

# --- capture_gameplay_video.gd ---

func _test_trailer_has_collision_comedy_function() -> void:
	var src := _read_source("res://tools/capture_gameplay_video.gd")
	_assert("trailer defines _capture_collision_comedy function",
		src.contains("func _capture_collision_comedy("))

func _test_trailer_shot_kind_is_collision() -> void:
	var src := _read_source("res://tools/capture_gameplay_video.gd")
	_assert("trailer SHOT_SPECS uses collision kind for Playground shot",
		src.contains("\"collision\""))

func _test_trailer_has_ranger_a_variable() -> void:
	var src := _read_source("res://tools/capture_gameplay_video.gd")
	_assert("collision comedy stages ranger_a", src.contains("ranger_a"))

func _test_trailer_has_body_a_variable() -> void:
	var src := _read_source("res://tools/capture_gameplay_video.gd")
	_assert("collision comedy manipulates body_a for stumble", src.contains("body_a"))

func _test_trailer_seconds_unchanged() -> void:
	var src := _read_source("res://tools/capture_gameplay_video.gd")
	_assert("trailer TRAILER_SECONDS is still 33.0", src.contains("TRAILER_SECONDS: float = 33.0"))

# --- docs/architecture.md ---

func _test_architecture_mentions_near_exit_alert() -> void:
	var src := _read_source("res://docs/architecture.md")
	_assert("architecture mentions near-exit alert (Phase 23)", src.contains("near-exit alert"))

func _test_architecture_mentions_body_lean() -> void:
	var src := _read_source("res://docs/architecture.md")
	_assert("architecture mentions body lean (Phase 25)", src.contains("body lean"))

func _test_architecture_mentions_playground_collision() -> void:
	var src := _read_source("res://docs/architecture.md")
	_assert("architecture trailer description mentions Playground collision",
		src.contains("Playground ranger collision"))

func _test_architecture_mentions_bonus_seconds() -> void:
	var src := _read_source("res://docs/architecture.md")
	_assert("architecture mentions chaos window bonus seconds (Phase 24)",
		src.contains("bonus seconds"))

# --- docs/portfolio_checklist.md ---

func _test_portfolio_checklist_has_phase26_section() -> void:
	var src := _read_source("res://docs/portfolio_checklist.md")
	_assert("portfolio checklist has Phase 26 completed section", src.contains("Phase 26"))

func _test_portfolio_checklist_mentions_collision() -> void:
	var src := _read_source("res://docs/portfolio_checklist.md")
	_assert("portfolio checklist trailer structure updated to mention collision",
		src.contains("collision"))

# --- existence checks ---

func _test_known_issues_exists() -> void:
	_assert("known_issues.md exists", FileAccess.file_exists("res://docs/known_issues.md"))

func _test_phase25_monitor_still_exists() -> void:
	_assert("phase25_anim_monitor.gd still exists",
		FileAccess.file_exists("res://tools/phase25_anim_monitor.gd"))

func _test_finalizer_has_frame_count_parameter() -> void:
	var src := _read_source("res://tools/finalize_trailer.ps1")
	_assert("finalize_trailer.ps1 supports -FrameCount parameter", src.contains("FrameCount"))
