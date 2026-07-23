# =============================================================================
# SCRIPT: main_menu.gd
# ATTACHED TO: The root Node of MainMenu.tscn
# =============================================================================
#
# OVERVIEW
# --------
# This script controls the main menu — the first screen the player sees when the
# game launches. It manages three panels that slide in and out:
#
#   MAIN  — Play, How to Play, Settings, Quit buttons
#   HOW TO PLAY — controls reference
#   SETTINGS    — music volume, SFX volume, fullscreen toggle
#
# Settings are saved to disk (user://settings.cfg) so they persist between sessions.
# Volume changes are applied immediately via SoundManager's audio bus system.
#
# HOW PANELS WORK
# ---------------
# All three panels exist in the scene at all times, but only one is visible.
# Showing a panel = make it visible. Hiding = make it invisible. No scene changes.
# This avoids loading screens between menu sections.

extends Node


# =============================================================================
# CONSTANTS
# =============================================================================

# Path where settings are saved on the player's computer.
# "user://" is Godot's shorthand for the game's save-data folder.
# On Windows: C:\Users\[name]\AppData\Roaming\Godot\app_userdata\[project]\
const SETTINGS_PATH: String = "user://settings.cfg"

# Path to the game level scene. Loaded when the player presses Play.
const GAME_SCENE: String = "res://Main.tscn"


# =============================================================================
# NODE REFERENCES — filled in automatically when the scene loads (@onready)
# =============================================================================

# The "$" shorthand is equivalent to get_node(). It finds a child node by path.

@onready var _main_panel:       VBoxContainer = $CanvasLayer/MainPanel
# _main_panel — The central VBoxContainer holding the title and main nav buttons.

@onready var _howto_panel:      Control       = $CanvasLayer/HowToPlayPanel
# _howto_panel — Full-screen panel showing the controls reference.

@onready var _settings_panel:   Control       = $CanvasLayer/SettingsPanel
# _settings_panel — Full-screen panel with volume sliders and fullscreen toggle.

@onready var _music_slider:     HSlider       = $CanvasLayer/SettingsPanel/VBoxContainer/MusicSlider
# _music_slider — Horizontal slider (0.0–1.0) controlling music bus volume.

@onready var _sfx_slider:       HSlider       = $CanvasLayer/SettingsPanel/VBoxContainer/SFXSlider
# _sfx_slider — Horizontal slider (0.0–1.0) controlling SFX bus volume.

@onready var _fullscreen_check: CheckButton   = $CanvasLayer/SettingsPanel/VBoxContainer/FullscreenCheck
# _fullscreen_check — Toggle button for fullscreen mode.


# =============================================================================
# _ready(): Runs once when the scene loads
# =============================================================================

func _ready() -> void:
	# Show the main panel and hide the others.
	_show_panel(_main_panel)

	# Load saved settings and populate the UI with the saved values.
	# This makes the sliders and toggle reflect whatever the player set last time.
	_load_settings_into_ui()


# =============================================================================
# PANEL NAVIGATION — called by button signals
# =============================================================================

func _show_panel(panel: Node) -> void:
	# Show only the requested panel; hide all others.
	# "panel == _main_panel" evaluates to true or false, which directly sets .visible.
	# This means exactly one panel is visible at any time.
	_main_panel.visible     = (panel == _main_panel)
	_howto_panel.visible    = (panel == _howto_panel)
	_settings_panel.visible = (panel == _settings_panel)

func _on_play_pressed() -> void:
	# Load the game level. change_scene_to_file() discards this scene entirely
	# and loads the new one — the main menu is gone from memory while playing.
	get_tree().change_scene_to_file(GAME_SCENE)

func _on_how_to_play_pressed() -> void:
	_show_panel(_howto_panel)

func _on_settings_pressed() -> void:
	_show_panel(_settings_panel)

func _on_quit_pressed() -> void:
	# get_tree().quit() closes the game application immediately.
	get_tree().quit()

func _on_back_pressed() -> void:
	# The Back button appears on both sub-panels. Both call this same function.
	_show_panel(_main_panel)


# =============================================================================
# SETTINGS — volume sliders and fullscreen toggle
# =============================================================================

func _on_music_slider_changed(value: float) -> void:
	# Called every time the ambient slider moves (even while dragging).
	# value is a float from 0.0 (silent) to 1.0 (full volume).
	SoundManager.set_music_volume(value)
	_save_settings()

func _on_sfx_slider_changed(value: float) -> void:
	SoundManager.set_sfx_volume(value)
	_save_settings()

func _on_fullscreen_toggled(pressed: bool) -> void:
	# pressed = true means the button is ON (fullscreen requested).
	# DisplayServer is Godot's interface to the OS window manager.
	if pressed:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	_save_settings()


# =============================================================================
# PERSISTENCE — save and load settings from disk
# =============================================================================

func _save_settings() -> void:
	# ConfigFile is Godot's built-in INI-style file format.
	# set_value(section, key, value) stores a named value in a named section.
	var config := ConfigFile.new()
	config.set_value("audio",   "music",      _music_slider.value)
	config.set_value("audio",   "sfx",        _sfx_slider.value)
	config.set_value("display", "fullscreen",  _fullscreen_check.button_pressed)
	# save() writes the file to disk. It returns an error code (OK = 0 = success).
	config.save(SETTINGS_PATH)

func _load_settings_into_ui() -> void:
	# Load saved values and update the slider/toggle positions so the UI
	# shows what was actually saved — not just the scene defaults.
	#
	# NOTE: SoundManager._ready() already loaded and APPLIED the settings when the
	# game started. This function only updates the UI to DISPLAY those values.
	# They are separate concerns: applying audio is SoundManager's job,
	# showing the current values is main_menu.gd's job.
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		# No settings file yet (first run). UI defaults are already set in the scene.
		return

	# Read saved values, falling back to 1.0 / false if a key is missing.
	# The third argument to get_value() is the default returned if the key doesn't exist.
	_music_slider.value            = config.get_value("audio",   "music",     1.0)
	_sfx_slider.value              = config.get_value("audio",   "sfx",       1.0)
	_fullscreen_check.button_pressed = config.get_value("display", "fullscreen", false)
