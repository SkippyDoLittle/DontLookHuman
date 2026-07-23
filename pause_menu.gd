# =============================================================================
# SCRIPT: pause_menu.gd
# ATTACHED TO: PauseMenu CanvasLayer in Main.tscn
# =============================================================================
#
# OVERVIEW
# --------
# This script manages the in-game pause menu. It is opened when game_timer.gd
# detects an Escape key press during active gameplay, and closed when the player
# presses Escape again or clicks the Resume button.
#
# IMPORTANT: The PauseMenu CanvasLayer sets process_mode = PROCESS_MODE_ALWAYS
# in _ready() so its buttons stay clickable even while get_tree().paused == true.
# All child nodes (VBoxContainer, Buttons, Sliders) inherit this mode automatically
# via PROCESS_MODE_INHERIT, which means they also keep running while paused.
#
# PANEL CONTENTS
# --------------
#   Resume button     — closes menu, unpauses scene tree
#   Music/SFX sliders — same settings as the main-menu Settings panel, saved to disk
#   Main Menu button  — returns to MainMenu.tscn (unpauses first to avoid frozen menu)
#   Quit button       — closes the game application

extends CanvasLayer


# =============================================================================
# CONSTANTS
# =============================================================================

# Where settings are saved — same file used by main_menu.gd so both panels
# read and write the same persistent values.
const SETTINGS_PATH: String = "user://settings.cfg"

# The scene to load when the player clicks "Main Menu".
const MENU_SCENE: String = "res://MainMenu.tscn"


# =============================================================================
# NODE REFERENCES — filled by @onready when the scene loads
# =============================================================================

@onready var _music_slider: HSlider      = $VBoxContainer/AudioPanel/MusicSlider
# _music_slider — Controls music bus volume (0.0 silent → 1.0 full volume).

@onready var _sfx_slider:   HSlider      = $VBoxContainer/AudioPanel/SFXSlider
# _sfx_slider — Controls SFX bus volume (0.0 silent → 1.0 full volume).

@onready var _resume_btn:   Button       = $VBoxContainer/ResumeButton
@onready var _menu_btn:     Button       = $VBoxContainer/MainMenuButton
@onready var _quit_btn:     Button       = $VBoxContainer/QuitButton
@onready var _audio_btn:    Button       = $VBoxContainer/AudioButton
@onready var _audio_panel:  VBoxContainer = $VBoxContainer/AudioPanel
# _audio_btn/_audio_panel — Clicking the AUDIO button toggles the slider panel
# open or closed. The panel starts hidden so the pause menu stays compact.


# =============================================================================
# _ready(): Setup when the pause menu loads
# =============================================================================

func _ready() -> void:
	# CRITICAL: CanvasLayer must keep running while the scene tree is paused so that
	# the Resume button (and all children) can still receive mouse clicks.
	# PROCESS_MODE_ALWAYS = run regardless of get_tree().paused state.
	# Children default to PROCESS_MODE_INHERIT, so they all become ALWAYS too.
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Wire button signals to this script's handler functions.
	# Connecting in code avoids needing [connection] blocks in Main.tscn.
	_resume_btn.pressed.connect(_on_resume_pressed)
	_menu_btn.pressed.connect(_on_main_menu_pressed)
	_quit_btn.pressed.connect(_on_quit_pressed)
	_audio_btn.pressed.connect(_on_audio_pressed)
	_music_slider.value_changed.connect(_on_music_slider_changed)
	_sfx_slider.value_changed.connect(_on_sfx_slider_changed)

	# Initialise sliders to the currently active bus volumes so the sliders
	# display the correct position even if settings were changed in the main menu.
	# db_to_linear() converts a decibel value back to a 0.0–1.0 linear scale
	# that the HSlider can display directly.
	var music_idx: int = AudioServer.get_bus_index("Music")
	var sfx_idx:   int = AudioServer.get_bus_index("SFX")
	if music_idx >= 0:
		_music_slider.value = db_to_linear(AudioServer.get_bus_volume_db(music_idx))
	if sfx_idx >= 0:
		_sfx_slider.value = db_to_linear(AudioServer.get_bus_volume_db(sfx_idx))


# =============================================================================
# BUTTON HANDLERS
# =============================================================================

func _on_resume_pressed() -> void:
	# Hide this menu — game_timer.gd will see visible == false on its next frame
	# and stop returning early, letting game logic resume normally.
	visible = false
	# Unpause the scene tree so player, NPCs, and ranger start moving again.
	get_tree().paused = false

func _on_main_menu_pressed() -> void:
	# Unpause BEFORE changing scene. If we changed the scene while still paused,
	# the new scene (MainMenu.tscn) would inherit the paused state and be frozen.
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)

func _on_quit_pressed() -> void:
	# get_tree().quit() closes the application immediately.
	get_tree().quit()

func _on_audio_pressed() -> void:
	# Toggle the audio slider panel open or closed.
	# The arrow on the button flips to show the current state.
	_audio_panel.visible = !_audio_panel.visible
	_audio_btn.text = "AUDIO  ▼" if _audio_panel.visible else "AUDIO  ▶"


# =============================================================================
# VOLUME SLIDER HANDLERS — apply volume changes and save them to disk
# =============================================================================

func _on_music_slider_changed(value: float) -> void:
	# value is a float from 0.0 (silent) to 1.0 (full volume).
	# set_ambient_volume() converts it to dB and applies it to the Ambient bus.
	SoundManager.set_music_volume(value)
	_save_settings()

func _on_sfx_slider_changed(value: float) -> void:
	SoundManager.set_sfx_volume(value)
	_save_settings()


# =============================================================================
# PERSISTENCE — save volume settings so they survive across sessions
# =============================================================================

func _save_settings() -> void:
	# We only save audio keys here — we don't have access to the fullscreen toggle
	# from this script. We merge by loading first, then writing only our keys.
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)   # OK if file doesn't exist yet — load() returns an error but config stays empty.
	config.set_value("audio", "music",   _music_slider.value)
	config.set_value("audio", "sfx",   _sfx_slider.value)
	config.save(SETTINGS_PATH)
