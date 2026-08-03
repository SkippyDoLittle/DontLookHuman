extends SceneTree

var _failures: int = 0
var _temporary_paths: Array[String] = []

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	_validate_campaign_store()
	_validate_controller_actions()
	await _validate_level_select_and_focus()
	await _validate_session_progress_and_diagnostics()
	_cleanup_temporary_files()

	if _failures == 0:
		print("PHASE7_RELEASE_VALIDATION_OK")
	quit(_failures)

func _validate_campaign_store() -> void:
	var path := _temporary_path("campaign")
	var store := CampaignProgressStore.new(path)
	_check(store.load_highest_unlocked() == 0, "A new campaign starts with Level 1 unlocked")
	_check(store.is_unlocked(0), "Level 1 is playable on a new save")
	_check(not store.is_unlocked(1), "Level 2 starts locked")
	_check(store.record_completion(&"level_01") == OK, "A Level 1 clear saves")
	_check(store.is_completed(&"level_01"), "A completed level remains marked complete")
	_check(store.load_highest_unlocked() == 1, "Clearing Level 1 unlocks Level 2")
	_check(store.record_completion(&"unknown") == ERR_INVALID_PARAMETER, "Unknown level IDs are rejected")
	_check(store.load_highest_unlocked() == 1, "Invalid writes do not change campaign progress")

func _validate_controller_actions() -> void:
	var motion_actions: Array[StringName] = [
		&"move_left", &"move_right", &"move_forward", &"move_back",
		&"look_left", &"look_right", &"look_up", &"look_down",
	]
	for action in motion_actions:
		_check(InputMap.has_action(action), "%s input action exists" % action)
		_check(_action_has_event_type(action, InputEventJoypadMotion), "%s accepts a controller axis" % action)

	var button_actions: Array[StringName] = [&"run", &"peck", &"pause_game", &"restart", &"zoom_in", &"zoom_out"]
	for action in button_actions:
		_check(InputMap.has_action(action), "%s input action exists" % action)
		_check(_action_has_event_type(action, InputEventJoypadButton), "%s accepts a controller button" % action)

func _validate_level_select_and_focus() -> void:
	var score_path := _temporary_path("scores")
	var legacy_path := _temporary_path("legacy")
	var progress_path := _temporary_path("menu_progress")
	var score_store := BestScoreStore.new(score_path, legacy_path)
	var progress_store := CampaignProgressStore.new(progress_path)
	var menu := (load("res://MainMenu.tscn") as PackedScene).instantiate()
	menu.set("_score_store", score_store)
	menu.set("_progress_store", progress_store)
	root.add_child(menu)
	await process_frame
	await process_frame

	var play_button := menu.get_node("CanvasLayer/MainPanel/PlayButton") as Button
	var level_1 := menu.get_node("CanvasLayer/LevelSelectPanel/VBoxContainer/Level1Button") as Button
	var level_2 := menu.get_node("CanvasLayer/LevelSelectPanel/VBoxContainer/Level2Button") as Button
	var level_3 := menu.get_node("CanvasLayer/LevelSelectPanel/VBoxContainer/Level3Button") as Button
	_check(not level_1.disabled and level_2.disabled, "Level Select enforces new-campaign locks")
	_check(play_button.text == "PLAY", "A new campaign shows the Play action")
	_check(root.get_viewport().gui_get_focus_owner() == play_button, "The main menu gives controller focus to Play")

	_check(score_store.save_best(&"level_01", 750) == OK, "A menu record can be saved")
	_check(progress_store.record_completion(&"level_01") == OK, "Menu progress can advance")
	menu.call("_refresh_campaign_ui")
	_check(not level_2.disabled and level_3.disabled, "Only the next campaign level unlocks")
	_check("Best: 750" in level_1.text, "Level Select presents the saved record")
	_check(play_button.text == "CONTINUE - LEVEL 2", "Play becomes Continue after progression")

	menu.call("_on_level_select_pressed")
	await process_frame
	_check(root.get_viewport().gui_get_focus_owner() == level_2, "Level Select focuses the current campaign level")

	menu.queue_free()
	await process_frame

func _validate_session_progress_and_diagnostics() -> void:
	var progress_path := _temporary_path("session_progress")
	var score_path := _temporary_path("session_scores")
	var legacy_path := _temporary_path("session_legacy")
	var progress_store := CampaignProgressStore.new(progress_path)
	var level := (
		load("res://scenes/levels/Level01_Park.tscn") as PackedScene
	).instantiate() as BaseLevel
	var session := level.get_node("GameTimer") as GameSession
	session.set("_progress_store", progress_store)
	session.set("_score_store", BestScoreStore.new(score_path, legacy_path))
	root.add_child(level)
	await process_frame
	await process_frame

	session.call("_finish", true, "ESCAPED!")
	_check(progress_store.is_completed(&"level_01"), "A successful session records campaign completion")
	_check(progress_store.load_highest_unlocked() == 1, "A successful session unlocks the next level")

	var overlay := level.get_node("HUD/DebugOverlay") as DebugOverlay
	var toggle_event := InputEventKey.new()
	toggle_event.keycode = KEY_F3
	toggle_event.pressed = true
	overlay.set_diagnostics_enabled(false)
	overlay.call("_unhandled_input", toggle_event)
	_check(not overlay.visible and not overlay.is_processing(), "Release gating disables F3 diagnostics")
	overlay.set_diagnostics_enabled(true)
	overlay.call("_unhandled_input", toggle_event)
	_check(overlay.visible and overlay.is_processing(), "Debug builds retain the F3 overlay")

	paused = false
	level.queue_free()
	await process_frame

func _action_has_event_type(action: StringName, event_type: Variant) -> bool:
	for event in InputMap.action_get_events(action):
		if is_instance_of(event, event_type):
			return true
	return false

func _temporary_path(label: String) -> String:
	var path := "user://phase7_%s_%s.cfg" % [label, Time.get_ticks_usec()]
	_temporary_paths.append(path)
	return path

func _cleanup_temporary_files() -> void:
	for path in _temporary_paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("Phase 7 release validation failed: %s" % message)
