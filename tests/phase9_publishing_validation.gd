extends SceneTree

var _failures: int = 0
var _temporary_paths: Array[String] = []

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	_validate_store_reset()
	await _validate_menu_settings_and_reset()
	await _validate_player_camera_settings()
	_validate_release_branding()
	_cleanup_temporary_files()

	if _failures == 0:
		print("PHASE9_PUBLISHING_VALIDATION_OK")
	quit(_failures)

func _validate_store_reset() -> void:
	var progress_path := _temporary_path("store_progress")
	var score_path := _temporary_path("store_scores")
	var legacy_path := _temporary_path("store_legacy")
	var progress := CampaignProgressStore.new(progress_path)
	var scores := BestScoreStore.new(score_path, legacy_path)
	_check(progress.record_completion(&"level_01") == OK, "Reset validation creates campaign progress")
	_check(scores.save_best(&"level_01", 750) == OK, "Reset validation creates a best score")
	var legacy_file := FileAccess.open(legacy_path, FileAccess.WRITE)
	if legacy_file != null:
		legacy_file.store_32(500)
		legacy_file.close()
	_check(progress.clear_all() == OK, "Campaign progress can be cleared")
	_check(scores.clear_all() == OK, "Best and legacy scores can be cleared")
	_check(progress.load_highest_unlocked() == 0, "Cleared progress returns to Level 1")
	_check(scores.load_best(&"level_01") == 0, "Cleared records do not retain legacy fallback data")

func _validate_menu_settings_and_reset() -> void:
	var progress_path := _temporary_path("menu_progress")
	var score_path := _temporary_path("menu_scores")
	var legacy_path := _temporary_path("menu_legacy")
	var settings_path := _temporary_path("menu_settings")
	var progress := CampaignProgressStore.new(progress_path)
	var scores := BestScoreStore.new(score_path, legacy_path)
	progress.record_completion(&"level_01")
	scores.save_best(&"level_01", 750)

	var settings := ConfigFile.new()
	settings.set_value("audio", "music", 0.7)
	settings.set_value("audio", "sfx", 0.8)
	settings.set_value("camera", "mouse_sensitivity", 0.006)
	settings.set_value("camera", "controller_sensitivity", 3.5)
	settings.set_value("camera", "invert_y", true)
	settings.set_value("display", "fullscreen", false)
	settings.save(settings_path)

	var menu := (load("res://MainMenu.tscn") as PackedScene).instantiate()
	menu.set("_progress_store", progress)
	menu.set("_score_store", scores)
	menu.set("settings_path", settings_path)
	root.add_child(menu)
	await process_frame
	await process_frame

	var settings_box := menu.get_node("CanvasLayer/SettingsPanel/VBoxContainer")
	var mouse_slider := settings_box.get_node("MouseSensitivitySlider") as HSlider
	var controller_slider := settings_box.get_node("ControllerSensitivitySlider") as HSlider
	var invert_check := settings_box.get_node("InvertYCheck") as CheckButton
	_check(is_equal_approx(mouse_slider.value, 0.006), "Menu loads mouse sensitivity")
	_check(is_equal_approx(controller_slider.value, 3.5), "Menu loads controller sensitivity")
	_check(invert_check.button_pressed, "Menu loads inverted camera preference")
	_check(menu.has_node("CanvasLayer/ResetCampaignDialog"), "Reset requires a confirmation dialog")

	mouse_slider.value = 0.0055
	controller_slider.value = 3.2
	invert_check.button_pressed = false
	var saved_settings := ConfigFile.new()
	_check(saved_settings.load(settings_path) == OK, "Camera preferences save from menu controls")
	_check(
		is_equal_approx(float(saved_settings.get_value("camera", "mouse_sensitivity", 0.0)), 0.0055),
		"Menu saves mouse sensitivity"
	)
	_check(
		is_equal_approx(float(saved_settings.get_value("camera", "controller_sensitivity", 0.0)), 3.2),
		"Menu saves controller sensitivity"
	)
	_check(
		not bool(saved_settings.get_value("camera", "invert_y", true)),
		"Menu saves inverted camera preference"
	)

	menu.call("_on_reset_campaign_confirmed")
	var level_2 := menu.get_node("CanvasLayer/LevelSelectPanel/VBoxContainer/Level2Button") as Button
	var play := menu.get_node("CanvasLayer/MainPanel/PlayButton") as Button
	_check(progress.load_highest_unlocked() == 0 and level_2.disabled, "Confirmed reset relocks the campaign")
	_check(scores.load_best(&"level_01") == 0, "Confirmed reset clears best scores")
	_check(play.text == "PLAY", "Confirmed reset restores the new-campaign action")

	menu.queue_free()
	await process_frame

func _validate_player_camera_settings() -> void:
	var settings_path := _temporary_path("player_settings")
	var settings := ConfigFile.new()
	settings.set_value("camera", "mouse_sensitivity", 0.007)
	settings.set_value("camera", "controller_sensitivity", 4.0)
	settings.set_value("camera", "invert_y", true)
	settings.save(settings_path)

	var level := (
		load("res://scenes/levels/Level01_Park.tscn") as PackedScene
	).instantiate() as BaseLevel
	var player := level.get_node("Player") as CharacterBody3D
	player.set("settings_path", settings_path)
	root.add_child(level)
	await process_frame
	await process_frame
	_check(is_equal_approx(float(player.get("mouse_sensitivity")), 0.007), "Player applies saved mouse sensitivity")
	_check(is_equal_approx(float(player.get("controller_look_speed")), 4.0), "Player applies saved controller sensitivity")
	_check(bool(player.get("invert_camera_y")), "Player applies saved inverted Y preference")

	paused = false
	level.queue_free()
	await process_frame

func _validate_release_branding() -> void:
	_check(
		ProjectSettings.get_setting("application/config/version") == "0.9.0",
		"Project metadata identifies the release candidate"
	)
	_check(
		ProjectSettings.get_setting("application/config/icon") == "res://assets/branding/game_icon.png",
		"Project metadata uses the custom pigeon icon"
	)
	_check(FileAccess.file_exists("res://assets/branding/game_icon.png"), "Custom game icon is present")
	_check(FileAccess.file_exists("res://docs/branding/store_capsule.png"), "Store capsule artwork is present")
	var export_config := ConfigFile.new()
	_check(export_config.load("res://export_presets.cfg") == OK, "Windows export metadata loads")
	_check(
		export_config.get_value("preset.0.options", "application/icon", "")
		== "res://assets/branding/game_icon.png",
		"Windows export embeds the custom icon"
	)

func _temporary_path(label: String) -> String:
	var path := "user://phase9_%s_%s.cfg" % [label, Time.get_ticks_usec()]
	_temporary_paths.append(path)
	return path

func _cleanup_temporary_files() -> void:
	for path in _temporary_paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("Phase 9 publishing validation failed: %s" % message)
