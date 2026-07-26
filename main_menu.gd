# main_menu.gd — Attached to the root of MainMenu.tscn
# Manages three panels (Main, How to Play, Settings). Settings persist to disk.

extends Node

const SETTINGS_PATH: String = "user://settings.cfg"
const GAME_SCENE:    String = "res://Main.tscn"

@onready var _main_panel:       VBoxContainer = $CanvasLayer/MainPanel
@onready var _howto_panel:      Control       = $CanvasLayer/HowToPlayPanel
@onready var _settings_panel:   Control       = $CanvasLayer/SettingsPanel
@onready var _music_slider:     HSlider       = $CanvasLayer/SettingsPanel/VBoxContainer/MusicSlider
@onready var _sfx_slider:       HSlider       = $CanvasLayer/SettingsPanel/VBoxContainer/SFXSlider
@onready var _fullscreen_check: CheckButton   = $CanvasLayer/SettingsPanel/VBoxContainer/FullscreenCheck

func _ready() -> void:
	_show_panel(_main_panel)
	_load_settings_into_ui()

func _show_panel(panel: Node) -> void:
	# Exactly one panel is visible at a time.
	_main_panel.visible     = (panel == _main_panel)
	_howto_panel.visible    = (panel == _howto_panel)
	_settings_panel.visible = (panel == _settings_panel)

func _on_play_pressed() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)

func _on_how_to_play_pressed() -> void:
	_show_panel(_howto_panel)

func _on_settings_pressed() -> void:
	_show_panel(_settings_panel)

func _on_quit_pressed() -> void:
	get_tree().quit()

func _on_back_pressed() -> void:
	_show_panel(_main_panel)

func _on_music_slider_changed(value: float) -> void:
	SoundManager.set_music_volume(value)
	_save_settings()

func _on_sfx_slider_changed(value: float) -> void:
	SoundManager.set_sfx_volume(value)
	_save_settings()

func _on_fullscreen_toggled(pressed: bool) -> void:
	if pressed:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	_save_settings()

func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio",   "music",      _music_slider.value)
	config.set_value("audio",   "sfx",        _sfx_slider.value)
	config.set_value("display", "fullscreen",  _fullscreen_check.button_pressed)
	config.save(SETTINGS_PATH)

func _load_settings_into_ui() -> void:
	# SoundManager already applied the saved volumes on startup.
	# This only updates the slider positions to match what was loaded.
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return   # first run — UI defaults are fine
	_music_slider.value              = config.get_value("audio",   "music",      1.0)
	_sfx_slider.value                = config.get_value("audio",   "sfx",        1.0)
	_fullscreen_check.button_pressed = config.get_value("display", "fullscreen", false)
