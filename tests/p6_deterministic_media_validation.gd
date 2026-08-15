extends SceneTree

# P6 deterministic capture-tool contracts.
# Run headless: --headless --path . --script res://tests/p6_deterministic_media_validation.gd

const SCREENSHOT_SCRIPT = preload("res://tools/capture_portfolio_screenshots.gd")
const TRAILER_SCRIPT = preload("res://tools/capture_gameplay_video.gd")

var _pass_count: int = 0
var _fail_count: int = 0

func _initialize() -> void:
	call_deferred("_run_all")

func _run_all() -> void:
	var screenshot_source := _read_source("res://tools/capture_portfolio_screenshots.gd")
	var trailer_source := _read_source("res://tools/capture_gameplay_video.gd")
	_validate_screenshot_contract(screenshot_source)
	_validate_trailer_contract(trailer_source)
	_validate_actor_freeze_runtime()
	_validate_camera_and_accessibility_runtime()
	print("P6_DETERMINISTIC_MEDIA RESULTS: %d passed, %d failed" % [_pass_count, _fail_count])
	quit(0 if _fail_count == 0 else 1)

func _validate_screenshot_contract(source: String) -> void:
	_assert("screenshots force windowed mode", source.contains("WINDOW_MODE_WINDOWED"))
	_assert("screenshots force 1280 by 720", source.contains("Vector2i(1280, 720)"))
	_assert("screenshots use five per-level seeds", source.count("\"seed\":") == 5)
	_assert("screenshots seed before instantiate", _ordered(source, "seed(int(spec.seed))", "packed.instantiate()"))
	_assert("screenshots request High without persistence", source.contains("apply_preset\", \"High\", false"))
	_assert("screenshots never persist quality", not source.contains("apply_preset\", \"High\", true"))
	_assert("screenshots override accessibility only in cache", source.contains("AccessibilitySettings._reduced_motion_cache"))
	_assert("screenshots never write accessibility setting", not source.contains("set_reduced_motion("))
	_assert("screenshots stop adaptive music", source.contains("call(\"stop_music\")"))
	_assert("screenshots stop ambience", source.contains("call(\"stop_ambient\")"))
	_assert("screenshots explicitly hide chaos callout", source.contains("HUD/ChaosWindowCallout"))
	_assert("screenshots have deterministic settle frames", source.contains("SETTLE_FRAMES: int = 20"))
	var capture_body := _function_body(source, "func _capture_level", "func _apply_capture_quality")
	_assert(
		"screenshots pause simulation before settle",
		_ordered(capture_body, "paused = true", "for frame in SETTLE_FRAMES")
	)
	_assert(
		"screenshots freeze only after settle",
		_ordered(capture_body, "for frame in SETTLE_FRAMES", "_freeze_capture_actors(level)")
	)
	_assert(
		"screenshots restage composition before freeze",
		_ordered(capture_body, "_stage_level(level, spec)\n\t_freeze_capture_actors", "_freeze_capture_actors(level)")
	)
	for group_name in ["rangers", "pigeons", "visitors"]:
		_assert("screenshots freeze %s" % group_name, source.contains("&\"%s\"" % group_name))
	_assert("screenshots freeze Player", source.contains("get_node_or_null(\"Player\")"))
	_assert("screenshots do not mutate shipping lights", not source.contains("light_energy") and not source.contains("WorldEnvironment"))

	var expected_outputs: Array[String] = [
		"res://docs/screenshots/level_01_park.png",
		"res://docs/screenshots/level_02_playground.png",
		"res://docs/screenshots/level_03_lakeside.png",
		"res://docs/screenshots/level_04_festival.png",
		"res://docs/screenshots/level_05_botanical_gardens.png",
	]
	for output_path in expected_outputs:
		_assert("screenshot keeps %s" % output_path.get_file(), source.contains(output_path))
	_assert("screenshots use five intentional camera positions", source.count("\"camera_position\":") == 5)
	_assert("screenshots use five intentional camera targets", source.count("\"camera_target\":") == 5)
	_assert("screenshots stage five player positions", source.count("\"player_position\":") == 5)
	_assert("screenshots stage five real ranger focal points", source.count("\"ranger_name\":") == 5)
	_assert("screenshots stage five real objective items", source.count("\"food_name\":") == 5)
	_assert("screenshots identify five authored landmarks", source.count("\"landmark\":") == 5)
	_assert("screenshots use a capture-only free camera", source.contains("Camera3D.new()") and source.contains("camera.make_current()"))

func _validate_trailer_contract(source: String) -> void:
	_assert("trailer remains thirty fps", source.contains("const FPS: int = 30"))
	_assert("trailer remains exactly thirty three seconds", source.contains("TRAILER_SECONDS: float = 33.0"))
	_assert("trailer keeps four shot specs", source.count("\"kind\":") == 4)
	_assert("trailer keeps four deterministic shot seeds", source.count("\"seed\":") == 4)
	var durations := _shot_durations(source)
	var gameplay_frames := 0
	for duration in durations:
		gameplay_frames += ceili(duration * 30.0)
	var total_frames := gameplay_frames + ceili(0.8 * 30.0) + ceili(3.2 * 30.0)
	_assert("trailer shot durations remain 5 5 5 14", durations == [5.0, 5.0, 5.0, 14.0])
	_assert("trailer remains exactly 990 frames", total_frames == 990)
	_assert("trailer keeps final hook duration", source.contains("_show_final_hook(0.8)"))
	_assert("trailer keeps logo duration", source.contains("_show_logo_reveal(3.2)"))

	_assert("trailer forces windowed mode", source.contains("WINDOW_MODE_WINDOWED"))
	_assert("trailer forces 1280 by 720", source.contains("Vector2i(1280, 720)"))
	_assert("trailer resets frame for each level", source.contains("_capture_frame_index = 0"))
	_assert("trailer seeds each shot before instantiate", _ordered(source, "seed(_active_shot_seed)", "packed.instantiate()"))
	_assert("all four shots advance deterministic frame", source.count("_capture_frame_index = frame") == 4)
	_assert("camera shake has no wall clock", not source.contains("Time.get_ticks"))
	_assert("camera shake uses capture frame", source.contains("float(_capture_frame_index) / float(FPS)"))
	_assert("camera shake includes shot seed phase", source.contains("_active_shot_seed % 997"))

	_assert("trailer requests High without persistence", source.contains("apply_preset\", \"High\", false"))
	_assert("trailer never persists quality", not source.contains("apply_preset\", \"High\", true"))
	_assert("trailer overrides accessibility only in cache", source.contains("AccessibilitySettings._reduced_motion_cache"))
	_assert("trailer forces reduced motion false", source.contains("] = false"))
	_assert("trailer never writes accessibility setting", not source.contains("set_reduced_motion("))
	_assert("trailer explicitly hides chaos callout", source.contains("HUD/ChaosWindowCallout"))
	_assert("trailer hides gameplay controls hint", source.contains("HUD/HelpHint"))

	var load_body := _function_body(source, "func _load_level", "func _capture_hook")
	_assert("trailer stops shipping audio after every load", _ordered(load_body, "root.add_child(_active_level)", "_stop_shipping_audio()"))
	var stop_body := _function_body(source, "func _stop_shipping_audio", "func _fail")
	_assert("trailer stops adaptive music", stop_body.contains("call(\"stop_music\")"))
	_assert("trailer stops ambience", stop_body.contains("call(\"stop_ambient\")"))
	_assert("trailer stop helper leaves soundtrack alone", not stop_body.contains("_music_player.stop"))
	_assert("trailer still builds its soundtrack", source.contains("SOUNDTRACK_SCRIPT.build(TRAILER_SECONDS)"))
	_assert("trailer still plays its soundtrack", source.contains("_music_player.play()"))
	var collect_body := _function_body(source, "func _force_collect", "func _script_ranger")
	_assert("trailer uses shipping food collection path", collect_body.contains("call(\"_begin_collection\")"))
	_assert("trailer has no stale food burst call", not collect_body.contains("_spawn_burst"))

	for expected_path in [
		"res://scenes/levels/Level04_Festival.tscn",
		"res://scenes/levels/Level03_Lakeside.tscn",
		"res://scenes/levels/Level02_Playground.tscn",
		"res://scenes/levels/Level05_BotanicalGardens.tscn",
	]:
		_assert("trailer keeps %s" % expected_path.get_file(), source.contains(expected_path))

func _validate_actor_freeze_runtime() -> void:
	var capture_tool := SCREENSHOT_SCRIPT.new() as SceneTree
	var level := Node.new()
	level.name = "CaptureLevel"
	var player := CharacterBody3D.new()
	player.name = "Player"
	level.add_child(player)
	var ranger := CharacterBody3D.new()
	ranger.name = "Ranger"
	ranger.add_to_group(&"rangers")
	level.add_child(ranger)
	var pigeon := Node3D.new()
	pigeon.name = "Pigeon"
	pigeon.add_to_group(&"pigeons")
	level.add_child(pigeon)
	var visitor := Node3D.new()
	visitor.name = "Visitor"
	visitor.add_to_group(&"visitors")
	level.add_child(visitor)
	var unrelated := Node.new()
	unrelated.name = "Unrelated"
	level.add_child(unrelated)
	root.add_child(level)
	capture_tool.call("_freeze_capture_actors", level)
	_assert("runtime freeze disables Player", player.process_mode == Node.PROCESS_MODE_DISABLED)
	_assert("runtime freeze disables ranger", ranger.process_mode == Node.PROCESS_MODE_DISABLED)
	_assert("runtime freeze disables pigeon", pigeon.process_mode == Node.PROCESS_MODE_DISABLED)
	_assert("runtime freeze disables visitor", visitor.process_mode == Node.PROCESS_MODE_DISABLED)
	_assert("runtime freeze preserves unrelated node", unrelated.process_mode != Node.PROCESS_MODE_DISABLED)
	level.free()
	capture_tool.free()

func _validate_camera_and_accessibility_runtime() -> void:
	var capture_tool := TRAILER_SCRIPT.new() as SceneTree
	var camera := Camera3D.new()
	root.add_child(camera)
	capture_tool.set("_camera", camera)
	capture_tool.set("_active_shot_seed", 40401)
	capture_tool.set("_capture_frame_index", 27)
	var base_position := Vector3(2.0, 1.5, 3.0)
	var target := Vector3(0.0, 0.5, 0.0)
	capture_tool.call("_set_camera", base_position, target, 58.0, 0.2)
	var first_position := camera.global_position
	camera.global_position = Vector3.ZERO
	capture_tool.call("_set_camera", base_position, target, 58.0, 0.2)
	var repeated_position := camera.global_position
	_assert("same capture frame gives identical shake", first_position.is_equal_approx(repeated_position))
	capture_tool.set("_capture_frame_index", 28)
	capture_tool.call("_set_camera", base_position, target, 58.0, 0.2)
	_assert("next capture frame advances shake", not first_position.is_equal_approx(camera.global_position))

	var settings_path: String = AccessibilitySettings.DEFAULT_SETTINGS_PATH
	var settings_existed: bool = FileAccess.file_exists(settings_path)
	var settings_before: PackedByteArray = (
		FileAccess.get_file_as_bytes(settings_path)
		if settings_existed
		else PackedByteArray()
	)
	AccessibilitySettings._reduced_motion_cache[settings_path] = true
	capture_tool.call("_force_capture_accessibility")
	_assert("runtime accessibility override is false", not AccessibilitySettings.is_reduced_motion_enabled(settings_path))
	_assert("runtime accessibility override creates no settings file", FileAccess.file_exists(settings_path) == settings_existed)
	if settings_existed:
		_assert("runtime accessibility override preserves settings bytes", FileAccess.get_file_as_bytes(settings_path) == settings_before)

	camera.free()
	capture_tool.free()

func _shot_durations(source: String) -> Array[float]:
	var durations: Array[float] = []
	var regex := RegEx.new()
	regex.compile("\\\"duration\\\":\\s*([0-9.]+)")
	for result in regex.search_all(source):
		durations.append(float(result.get_string(1)))
	return durations

func _ordered(source: String, before: String, after: String) -> bool:
	var before_position := source.find(before)
	var after_position := source.find(after, maxi(before_position, 0))
	return before_position >= 0 and after_position > before_position

func _function_body(source: String, start_marker: String, end_marker: String) -> String:
	var start := source.find(start_marker)
	if start < 0:
		return ""
	var end := source.find(end_marker, start + start_marker.length())
	if end < 0:
		end = source.length()
	return source.substr(start, end - start)

func _read_source(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var source := file.get_as_text()
	file.close()
	return source

func _assert(label: String, condition: bool) -> void:
	if condition:
		print("P6_DETERMINISTIC_MEDIA_%s_OK" % label.to_upper().replace(" ", "_"))
		_pass_count += 1
	else:
		print("P6_DETERMINISTIC_MEDIA_%s_FAIL" % label.to_upper().replace(" ", "_"))
		_fail_count += 1
