# main_menu.gd — Attached to the root of MainMenu.tscn
# Manages menu panels, campaign progress, level records, and persistent settings.

extends Node

const SETTINGS_PATH: String = "user://settings.cfg"
const AMBIENCE_DIRECTOR = preload("res://park_ambience_director.gd")
const LEVEL_SCENES: Array[String] = [
	"res://scenes/levels/Level01_Park.tscn",
	"res://scenes/levels/Level02_Playground.tscn",
	"res://scenes/levels/Level03_Lakeside.tscn",
	"res://scenes/levels/Level04_Festival.tscn",
	"res://scenes/levels/Level05_BotanicalGardens.tscn",
]
const LEVEL_IDS: Array[StringName] = [
	&"level_01",
	&"level_02",
	&"level_03",
	&"level_04",
	&"level_05",
]
const LEVEL_NAMES: Array[String] = [
	"Level 1 - Community Park",
	"Level 2 - Playground",
	"Level 3 - Lakeside",
	"Level 4 - Festival",
	"Level 5 - Botanical Gardens",
]

@onready var _main_panel:        VBoxContainer = $CanvasLayer/MainPanel
@onready var _howto_panel:       Control       = $CanvasLayer/HowToPlayPanel
@onready var _settings_panel:    Control       = $CanvasLayer/SettingsPanel
@onready var _levelselect_panel: Control       = $CanvasLayer/LevelSelectPanel
@onready var _quality_settings: VisualQualitySettings = get_node("/root/QualitySettings")
@onready var _music_slider:     HSlider       = $CanvasLayer/SettingsPanel/VBoxContainer/MusicSlider
@onready var _ambient_slider:   HSlider       = $CanvasLayer/SettingsPanel/VBoxContainer/AmbientSlider
@onready var _sfx_slider:       HSlider       = $CanvasLayer/SettingsPanel/VBoxContainer/SFXSlider
@onready var _mouse_slider:     HSlider       = $CanvasLayer/SettingsPanel/VBoxContainer/MouseSensitivitySlider
@onready var _controller_slider: HSlider      = $CanvasLayer/SettingsPanel/VBoxContainer/ControllerSensitivitySlider
@onready var _quality_option:   OptionButton  = $CanvasLayer/SettingsPanel/VBoxContainer/QualityPresetOption
@onready var _invert_y_check:   CheckButton   = $CanvasLayer/SettingsPanel/VBoxContainer/InvertYCheck
@onready var _fullscreen_check: CheckButton   = $CanvasLayer/SettingsPanel/VBoxContainer/FullscreenCheck
@onready var _reset_dialog: ConfirmationDialog = $CanvasLayer/ResetCampaignDialog
@onready var _play_button:      Button        = $CanvasLayer/MainPanel/PlayButton
@onready var _level_buttons: Array[Button] = [
	$CanvasLayer/LevelSelectPanel/VBoxContainer/Level1Button,
	$CanvasLayer/LevelSelectPanel/VBoxContainer/Level2Button,
	$CanvasLayer/LevelSelectPanel/VBoxContainer/Level3Button,
	$CanvasLayer/LevelSelectPanel/VBoxContainer/Level4Button,
	$CanvasLayer/LevelSelectPanel/VBoxContainer/Level5Button,
]

var _score_store := BestScoreStore.new()
var _progress_store := CampaignProgressStore.new()
var _continue_level_index: int = 0
var settings_path: String = SETTINGS_PATH
var _loading_settings: bool = false

func _ready() -> void:
	_migrate_score_progress()
	_refresh_campaign_ui()
	_show_panel(_main_panel)
	_configure_quality_options()
	_load_settings_into_ui()

func _show_panel(panel: Node) -> void:
	# Exactly one panel is visible at a time.
	_main_panel.visible        = (panel == _main_panel)
	_howto_panel.visible       = (panel == _howto_panel)
	_settings_panel.visible    = (panel == _settings_panel)
	_levelselect_panel.visible = (panel == _levelselect_panel)
	if panel == _levelselect_panel:
		_refresh_campaign_ui()
	_focus_panel.call_deferred(panel)

func _on_play_pressed() -> void:
	get_tree().change_scene_to_file(LEVEL_SCENES[_continue_level_index])

func _on_level_select_pressed() -> void:
	_show_panel(_levelselect_panel)

func _on_level_pressed(index: int) -> void:
	if index < 0 or index >= LEVEL_SCENES.size() or not _progress_store.is_unlocked(index):
		return
	get_tree().change_scene_to_file(LEVEL_SCENES[index])

func _on_how_to_play_pressed() -> void:
	_show_panel(_howto_panel)

func _on_settings_pressed() -> void:
	_show_panel(_settings_panel)

func _on_quit_pressed() -> void:
	get_tree().quit()

func _on_back_pressed() -> void:
	_show_panel(_main_panel)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _main_panel.visible:
		_show_panel(_main_panel)
		get_viewport().set_input_as_handled()

func _migrate_score_progress() -> void:
	# A successful run already creates a score, so Phase 6 saves can unlock the
	# same campaign progress without making returning players start over.
	for index in LEVEL_IDS.size():
		if _score_store.load_best(LEVEL_IDS[index]) > 0:
			_progress_store.record_completion(LEVEL_IDS[index])

func _refresh_campaign_ui() -> void:
	var highest_unlocked := _progress_store.load_highest_unlocked()
	for index in _level_buttons.size():
		var button := _level_buttons[index]
		var unlocked := index <= highest_unlocked
		var best_score := _score_store.load_best(LEVEL_IDS[index])
		button.disabled = not unlocked
		if not unlocked:
			button.text = "%s  [LOCKED]" % LEVEL_NAMES[index]
		elif best_score > 0:
			button.text = "%s  -  Best: %d" % [LEVEL_NAMES[index], best_score]
		else:
			button.text = LEVEL_NAMES[index]

	if _progress_store.is_completed(LEVEL_IDS[-1]):
		_continue_level_index = 0
		_play_button.text = "PLAY AGAIN"
	else:
		_continue_level_index = highest_unlocked
		_play_button.text = "PLAY" if highest_unlocked == 0 else "CONTINUE - LEVEL %d" % (highest_unlocked + 1)

func _focus_panel(panel: Node) -> void:
	var target: Control = null
	if panel == _main_panel:
		target = _play_button
	elif panel == _levelselect_panel:
		target = _level_buttons[_progress_store.load_highest_unlocked()]
	elif panel == _howto_panel:
		target = $CanvasLayer/HowToPlayPanel/VBoxContainer/BackButton
	elif panel == _settings_panel:
		target = _music_slider
	if target != null and target.is_visible_in_tree():
		target.grab_focus()

func _on_music_slider_changed(value: float) -> void:
	if _loading_settings:
		return
	SoundManager.set_music_volume(value)
	_save_settings()

func _on_ambient_slider_changed(value: float) -> void:
	if _loading_settings:
		return
	_apply_ambient_volume(value)
	_save_settings()

func _on_sfx_slider_changed(value: float) -> void:
	if _loading_settings:
		return
	SoundManager.set_sfx_volume(value)
	_save_settings()

func _on_camera_setting_changed(_value: float = 0.0) -> void:
	if _loading_settings:
		return
	_save_settings()

func _on_invert_y_toggled(_pressed: bool) -> void:
	if _loading_settings:
		return
	_save_settings()

func _on_quality_preset_selected(index: int) -> void:
	if _loading_settings:
		return
	_quality_settings.apply_preset_index(index, false)
	_save_settings()

func _on_fullscreen_toggled(pressed: bool) -> void:
	if _loading_settings:
		return
	if pressed:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	_save_settings()

func _on_reset_campaign_pressed() -> void:
	_reset_dialog.popup_centered(Vector2i(480, 220))

func _on_reset_campaign_confirmed() -> void:
	var progress_error := _progress_store.clear_all()
	var score_error := _score_store.clear_all()
	if progress_error != OK or score_error != OK:
		push_warning(
			"Could not fully reset campaign data (progress %d, scores %d)."
			% [progress_error, score_error]
		)
		return
	_refresh_campaign_ui()

func _save_settings() -> void:
	var config := ConfigFile.new()
	config.load(settings_path)
	config.set_value("audio",   "music",      _music_slider.value)
	config.set_value("audio",   "ambient",    _ambient_slider.value)
	config.set_value("audio",   "sfx",        _sfx_slider.value)
	config.set_value("camera",  "mouse_sensitivity", _mouse_slider.value)
	config.set_value("camera",  "controller_sensitivity", _controller_slider.value)
	config.set_value("camera",  "invert_y", _invert_y_check.button_pressed)
	config.set_value("display", "fullscreen",  _fullscreen_check.button_pressed)
	config.set_value("display", "quality_preset", _quality_settings.preset_name_from_index(_quality_option.selected))
	config.save(settings_path)

func _configure_quality_options() -> void:
	_quality_option.clear()
	for preset_name in _quality_settings.preset_names():
		_quality_option.add_item(preset_name)
	_quality_option.select(_quality_settings.current_preset_index())

func _load_settings_into_ui() -> void:
	# SoundManager already applied the saved volumes on startup.
	# This only updates the slider positions to match what was loaded.
	var config := ConfigFile.new()
	if config.load(settings_path) != OK:
		return   # first run — UI defaults are fine
	_loading_settings = true
	_music_slider.value              = config.get_value("audio",   "music",      1.0)
	_ambient_slider.value            = config.get_value("audio",   "ambient",    1.0)
	_sfx_slider.value                = config.get_value("audio",   "sfx",        1.0)
	_mouse_slider.value              = config.get_value("camera",  "mouse_sensitivity", 0.003)
	_controller_slider.value         = config.get_value("camera",  "controller_sensitivity", 2.4)
	_invert_y_check.button_pressed   = config.get_value("camera",  "invert_y", false)
	_fullscreen_check.button_pressed = config.get_value("display", "fullscreen", false)
	var quality_preset := String(config.get_value("display", "quality_preset", _quality_settings.current_preset))
	_quality_option.select(_quality_settings.preset_index(quality_preset))
	_loading_settings = false
	_apply_ambient_volume(_ambient_slider.value)
	_quality_settings.apply_preset_index(_quality_option.selected, false)

func _apply_ambient_volume(value: float) -> void:
	# SoundManager owns this API once its audio pass is integrated.  The helper
	# fallback keeps this isolated UI slice bootable while that file is edited
	# concurrently, and applies the exact same Ambience-bus semantics.
	if SoundManager.has_method("set_ambient_volume"):
		SoundManager.call("set_ambient_volume", value)
	else:
		AMBIENCE_DIRECTOR.set_ambient_volume(value)
