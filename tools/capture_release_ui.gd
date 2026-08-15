extends SceneTree

# Captures the shipping UI from real project scenes for repeatable visual QA.
# Outputs are generated under the ignored export/ tree and are not release assets.
# Temporary stores keep capture runs isolated from the player's real saves.

const OUTPUT_DIR := "res://export/p6-ui-review"
const MENU_SCENE_PATH := "res://MainMenu.tscn"
const LEVEL_SCENE_PATH := "res://scenes/levels/Level01_Park.tscn"

var _failures: int = 0
var _temporary_paths: Array[String] = []

func _initialize() -> void:
	call_deferred("_capture_all")

func _capture_all() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	seed(606)
	var output_absolute := ProjectSettings.globalize_path(OUTPUT_DIR)
	var directory_error := DirAccess.make_dir_recursive_absolute(output_absolute)
	if directory_error != OK:
		_fail("Could not create %s: %s" % [output_absolute, error_string(directory_error)])
		quit(_failures)
		return

	await _capture_menu_frames()
	await _capture_level_frames()
	_cleanup_temporary_files()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if _failures == 0:
		print("P6_UI_CAPTURE_OK|output=%s|frames=6" % OUTPUT_DIR)
	quit(_failures)

func _capture_menu_frames() -> void:
	await _set_capture_size(Vector2i(1280, 720))
	var menu := (load(MENU_SCENE_PATH) as PackedScene).instantiate()
	var settings_path := _temporary_path("menu_settings")
	_write_capture_settings(settings_path)
	menu.set("settings_path", settings_path)
	menu.set(
		"_score_store",
		BestScoreStore.new(_temporary_path("menu_scores"), _temporary_path("menu_legacy"))
	)
	menu.set("_progress_store", CampaignProgressStore.new(_temporary_path("menu_progress")))
	root.add_child(menu)
	await _settle(4)
	await _save_frame("main_menu_1280x720.png")

	var settings_panel := menu.get_node("CanvasLayer/SettingsPanel")
	menu.call("_show_panel", settings_panel)
	await _settle(3)
	await _save_frame("settings_1280x720.png")

	menu.call("_show_panel", menu.get_node("CanvasLayer/MainPanel"))
	await _set_capture_size(Vector2i(2560, 1080))
	await _settle(4)
	await _save_frame("main_menu_2560x1080.png")

	menu.queue_free()
	await process_frame
	await _set_capture_size(Vector2i(1280, 720))

func _capture_level_frames() -> void:
	seed(607)
	_apply_capture_audio_levels()
	var settings_path := _temporary_path("level_settings")
	_write_capture_settings(settings_path)
	var level := (load(LEVEL_SCENE_PATH) as PackedScene).instantiate()
	var session := level.get_node("GameTimer") as GameSession
	session.set(
		"_score_store",
		BestScoreStore.new(_temporary_path("level_scores"), _temporary_path("level_legacy"))
	)
	session.set("_progress_store", CampaignProgressStore.new(_temporary_path("level_progress")))
	var pause_menu := level.get_node("PauseMenu")
	pause_menu.set("settings_path", settings_path)
	var chaos_controller := level.get_node_or_null("ParkChaosController")
	if chaos_controller != null:
		chaos_controller.set("settings_path", settings_path)
	var ranger_hud := level.get_node_or_null("HUD") as RangerHUDController
	if ranger_hud != null:
		ranger_hud.settings_path = settings_path
	for child in level.get_children():
		if child.name.begins_with("Ranger"):
			var presentation := child.get("_presentation") as RangerPresentation
			if presentation != null:
				presentation.settings_path = settings_path
	root.add_child(level)
	_apply_capture_quality()
	paused = true
	await _settle(5)

	for overlay_path in ["TitleScreen", "TransitionLayer", "PauseMenu", "HowToPlayScreen"]:
		var overlay := level.get_node_or_null(overlay_path) as CanvasLayer
		if overlay != null:
			overlay.visible = false
	var fade := level.get_node_or_null("HUD/FadeOverlay") as ColorRect
	if fade != null:
		fade.visible = false
	var debug := level.get_node_or_null("HUD/DebugOverlay") as Control
	if debug != null:
		debug.visible = false
	session.call("_set_state", GameSession.SessionState.ACTIVE)
	var hud_controller := session.get("_hud") as SessionHUDController
	hud_controller.hide_controls_hint()
	await _settle(5)
	session.process_mode = Node.PROCESS_MODE_DISABLED
	level.get_node("HUD").process_mode = Node.PROCESS_MODE_DISABLED
	for ranger in get_nodes_in_group(&"rangers"):
		if level.is_ancestor_of(ranger):
			ranger.process_mode = Node.PROCESS_MODE_DISABLED
	_stage_active_hud(level)
	await _save_frame("level01_active_hud_1280x720.png")

	paused = false
	session.call("_pause_session")
	pause_menu.call("_on_audio_pressed")
	await _settle(3)
	await _save_frame("pause_settings_1280x720.png")

	paused = false
	pause_menu.visible = false
	hud_controller.show_result(
		"ESCAPED!",
		true,
		{
			"score": 750,
			"tier": "★★  Great escape!",
			"minutes": 0,
			"seconds": 31,
			"collected": 5,
			"total": 5,
		},
		500,
		true,
		true,
		""
	)
	await _settle(3)
	await _save_frame("result_1280x720.png")

	paused = false
	level.queue_free()
	await process_frame

func _stage_active_hud(level: Node) -> void:
	var hud := level.get_node("HUD")
	var suspicion := hud.get_node("SuspicionBar") as ProgressBar
	var ranger_status := hud.get_node("RangerStatus") as Label
	var objective := hud.get_node("ObjectiveStatus") as Label
	var timer := hud.get_node("TimerLabel") as Label
	suspicion.value = 62.0
	ranger_status.text = "Ranger: Suspicious — moving too directly"
	objective.text = "3 item(s) left to steal!"
	timer.text = "1:04"

func _set_capture_size(size: Vector2i) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(size)
	root.size = size
	await _settle(2)

func _apply_capture_quality() -> void:
	var quality_settings := root.get_node_or_null("QualitySettings")
	if quality_settings != null and quality_settings.has_method("apply_preset"):
		quality_settings.call("apply_preset", "High", false)

func _apply_capture_audio_levels() -> void:
	var sound_manager := root.get_node_or_null("SoundManager")
	if sound_manager == null:
		_fail("SoundManager autoload is unavailable for UI capture")
		return
	sound_manager.call("set_music_volume", 0.8)
	sound_manager.call("set_ambient_volume", 0.8)
	sound_manager.call("set_sfx_volume", 0.8)

func _write_capture_settings(path: String) -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "music", 0.8)
	config.set_value("audio", "ambient", 0.8)
	config.set_value("audio", "sfx", 0.8)
	config.set_value("camera", "mouse_sensitivity", 0.003)
	config.set_value("camera", "controller_sensitivity", 2.4)
	config.set_value("camera", "invert_y", false)
	config.set_value("display", "fullscreen", false)
	config.set_value("display", "quality_preset", "High")
	config.set_value("accessibility", "reduced_motion", false)
	var save_error := config.save(path)
	if save_error != OK:
		_fail("Could not write isolated capture settings: %s" % error_string(save_error))

func _temporary_path(label: String) -> String:
	var path := "user://p6_release_ui_%s_%s.cfg" % [label, Time.get_ticks_usec()]
	_temporary_paths.append(path)
	return path

func _cleanup_temporary_files() -> void:
	for path in _temporary_paths:
		AccessibilitySettings.invalidate_cache(path)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _settle(frame_count: int) -> void:
	for _frame in frame_count:
		await process_frame

func _save_frame(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var expected_size := Vector2i(root.size)
	if image.get_size() != expected_size:
		_fail("%s was %s, expected %s" % [file_name, image.get_size(), expected_size])
		return
	var output_path := "%s/%s" % [OUTPUT_DIR, file_name]
	var save_error := image.save_png(output_path)
	if save_error != OK:
		_fail("Could not save %s: %s" % [output_path, error_string(save_error)])
	else:
		print("CAPTURED|%s|%dx%d" % [output_path, image.get_width(), image.get_height()])

func _fail(message: String) -> void:
	_failures += 1
	push_error("P6 UI capture failed: %s" % message)
