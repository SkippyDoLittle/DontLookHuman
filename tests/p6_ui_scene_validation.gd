extends SceneTree

# P6 scene-only validation for the branded responsive UI pass.

const THEME_PATH := "res://assets/ui/park_ui_theme.tres"
const ICON_PATH := "res://assets/branding/game_icon.png"

var _pass_count: int = 0
var _fail_count: int = 0
var _temporary_paths: Array[String] = []

func _initialize() -> void:
	call_deferred("_run_all")

func _run_all() -> void:
	_test_theme_contract()
	_test_capture_tool_contract()
	await _test_main_menu_contract()
	_test_hud_contract()
	await _test_pause_contract()
	_cleanup_temporary_files()
	print("P6 UI SCENE RESULTS: %d passed, %d failed" % [_pass_count, _fail_count])
	quit(0 if _fail_count == 0 else 1)

func _test_theme_contract() -> void:
	var park_theme := load(THEME_PATH) as Theme
	_assert("shared park theme loads", park_theme != null)
	if park_theme == null:
		return
	var focus_style := park_theme.get_stylebox(&"focus", &"Button") as StyleBoxFlat
	_assert(
		"button focus has a strong visible border",
		focus_style != null
		and focus_style.border_width_left >= 3
		and focus_style.border_color.a >= 0.95
	)
	_assert("runtime game icon exists", ResourceLoader.exists(ICON_PATH))

func _test_capture_tool_contract() -> void:
	var source := FileAccess.get_file_as_string("res://tools/capture_release_ui.gd")
	_assert(
		"UI capture isolates player save stores",
		source.contains('menu.set("settings_path", settings_path)')
		and source.contains('BestScoreStore.new(_temporary_path("menu_scores")')
		and source.contains('CampaignProgressStore.new(_temporary_path("menu_progress"))')
	)
	_assert(
		"UI capture pins quality and pauses level settling",
		source.contains('quality_settings.call("apply_preset", "High", false)')
		and source.contains("paused = true")
	)
	_assert(
		"UI capture pins live pause-menu audio levels",
		source.contains('sound_manager.call("set_music_volume", 0.8)')
		and source.contains('sound_manager.call("set_ambient_volume", 0.8)')
		and source.contains('sound_manager.call("set_sfx_volume", 0.8)')
	)
	var pause_source := FileAccess.get_file_as_string("res://pause_menu.gd")
	_assert(
		"pause initialization cannot rewrite settings",
		pause_source.contains("_loading_settings = true")
		and pause_source.count("if _loading_settings:") >= 4
	)

func _test_main_menu_contract() -> void:
	var menu := (load("res://MainMenu.tscn") as PackedScene).instantiate()
	menu.set("settings_path", _temporary_path("settings"))
	menu.set("_score_store", BestScoreStore.new(_temporary_path("scores"), _temporary_path("legacy")))
	menu.set("_progress_store", CampaignProgressStore.new(_temporary_path("progress")))
	root.add_child(menu)
	await process_frame
	await process_frame
	var canvas := menu.get_node("CanvasLayer")
	var main_panel := canvas.get_node("MainPanel") as VBoxContainer
	var emblem := canvas.get_node("BrandEmblem") as TextureRect
	var settings_box := canvas.get_node("SettingsPanel/VBoxContainer") as VBoxContainer
	var reduced_motion := settings_box.get_node("ReducedMotionCheck") as CheckButton
	_assert("main panel keeps all scripted paths", main_panel.has_node("PlayButton") and main_panel.has_node("SettingsButton"))
	_assert("main panel is left balanced", is_equal_approx(main_panel.anchor_left, 0.25) and is_equal_approx(main_panel.anchor_right, 0.25))
	_assert("main panel uses shared park theme", main_panel.theme != null and main_panel.theme.resource_path == THEME_PATH)
	_assert("menu emblem uses runtime icon only", emblem.texture != null and emblem.texture.resource_path == ICON_PATH)
	_assert("menu source never references store capsule", not FileAccess.get_file_as_string("res://MainMenu.tscn").contains("store_capsule"))
	var menu_rect_720 := main_panel.get_global_rect()
	var emblem_rect_720 := emblem.get_global_rect()
	_assert(
		"main composition separates controls and art at 720p",
		menu_rect_720.end.x < emblem_rect_720.position.x
		and menu_rect_720.position.x >= 0.0
		and emblem_rect_720.end.x <= 1280.0
	)
	_assert("settings expose reduced motion and flashes", reduced_motion.text == "Reduce Motion & Flashes")
	_assert(
		"reduced motion participates in controller focus chain",
		not reduced_motion.focus_neighbor_top.is_empty()
		and not reduced_motion.focus_neighbor_bottom.is_empty()
	)
	_assert("settings controls fit at 720p", settings_box.get_combined_minimum_size().y <= settings_box.size.y)
	root.size = Vector2i(2560, 1080)
	await process_frame
	var menu_rect_1080 := main_panel.get_global_rect()
	var emblem_rect_1080 := emblem.get_global_rect()
	_assert(
		"main composition remains separated at 2560 by 1080",
		menu_rect_1080.end.x < emblem_rect_1080.position.x
		and menu_rect_1080.position.x >= 0.0
		and emblem_rect_1080.end.x <= 2560.0
	)
	root.size = Vector2i(1280, 720)
	await process_frame
	menu.queue_free()
	await process_frame

func _test_hud_contract() -> void:
	var hud := (load("res://scenes/game/HUD.tscn") as PackedScene).instantiate()
	var status := hud.get_node("RangerStatus") as Label
	var timer := hud.get_node("TimerLabel") as Label
	var result_frame := hud.get_node("ResultBackground/ResultFrame") as Panel
	var minimap_frame := hud.get_node("Minimap/MapFrame") as Panel
	var result_actions := hud.get_node("ResultActions") as HBoxContainer
	_assert("HUD keeps scripted status paths", hud.has_node("RangerStatus") and hud.has_node("SuspicionBar") and hud.has_node("ObjectiveStatus"))
	_assert(
		"HUD branded panels follow scripted visibility",
		status.get_theme_stylebox(&"normal") is StyleBoxFlat
		and timer.get_theme_stylebox(&"normal") is StyleBoxFlat
		and result_frame != null
		and minimap_frame != null
	)
	_assert("timer leaves P5 callout lane clear", timer.offset_bottom <= 38.0)
	_assert("result buttons use shared focus theme", result_actions.theme != null and result_actions.theme.resource_path == THEME_PATH)
	hud.free()

func _test_pause_contract() -> void:
	var level := (load("res://scenes/levels/Level01_Park.tscn") as PackedScene).instantiate()
	root.add_child(level)
	await process_frame
	await process_frame
	var pause_menu := level.get_node("PauseMenu")
	var pause_box := pause_menu.get_node("VBoxContainer") as VBoxContainer
	var audio_panel := pause_box.get_node("AudioPanel") as VBoxContainer
	var reduced_motion := audio_panel.get_node("ReducedMotionCheck") as CheckButton
	var settings_button := pause_box.get_node("AudioButton") as Button
	_assert("pause keeps scripted button paths", pause_box.has_node("ResumeButton") and pause_box.has_node("MainMenuButton"))
	_assert("pause labels the disclosure as settings", settings_button.text.begins_with("SETTINGS"))
	_assert("pause exposes reduced motion in existing settings panel", reduced_motion.text == "Reduce Motion & Flashes")
	audio_panel.visible = true
	pause_menu.visible = true
	await process_frame
	_assert("expanded pause settings fit at 720p", pause_box.get_combined_minimum_size().y <= pause_box.size.y)
	paused = false
	level.queue_free()
	await process_frame

func _assert(label: String, condition: bool) -> void:
	if condition:
		print("P6_UI_SCENE_%s_OK" % label.to_upper().replace(" ", "_"))
		_pass_count += 1
	else:
		push_error("P6_UI_SCENE_%s_FAIL" % label.to_upper().replace(" ", "_"))
		_fail_count += 1

func _temporary_path(label: String) -> String:
	var path := "user://p6_ui_%s_%s.cfg" % [label, Time.get_ticks_usec()]
	_temporary_paths.append(path)
	return path

func _cleanup_temporary_files() -> void:
	for path in _temporary_paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
