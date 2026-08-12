# pause_menu.gd — Attached to PauseMenu CanvasLayer in Main.tscn
# In-game pause overlay. Opened/closed by game_timer.gd on Escape key.

extends CanvasLayer

signal resumed

const SETTINGS_PATH: String = "user://settings.cfg"
const MENU_SCENE:    String = "res://MainMenu.tscn"
const AMBIENCE_DIRECTOR = preload("res://park_ambience_director.gd")

@onready var _music_slider: HSlider       = $VBoxContainer/AudioPanel/MusicSlider
@onready var _ambient_slider: HSlider     = get_node_or_null("VBoxContainer/AudioPanel/AmbientSlider") as HSlider
@onready var _sfx_slider:   HSlider       = $VBoxContainer/AudioPanel/SFXSlider
@onready var _resume_btn:    Button        = $VBoxContainer/ResumeButton
@onready var _menu_btn:      Button        = $VBoxContainer/MainMenuButton
@onready var _quit_btn:      Button        = $VBoxContainer/QuitButton
@onready var _audio_btn:     Button        = $VBoxContainer/AudioButton
@onready var _audio_panel:   VBoxContainer = $VBoxContainer/AudioPanel
@onready var _controls_btn:  Button        = $VBoxContainer/ControlsButton

var settings_path: String = SETTINGS_PATH

func _ready() -> void:
	# PROCESS_MODE_ALWAYS so buttons stay clickable while get_tree().paused == true.
	# Children inherit this automatically via PROCESS_MODE_INHERIT.
	process_mode = Node.PROCESS_MODE_ALWAYS

	_resume_btn.pressed.connect(_on_resume_pressed)
	_menu_btn.pressed.connect(_on_main_menu_pressed)
	_quit_btn.pressed.connect(_on_quit_pressed)
	_audio_btn.pressed.connect(_on_audio_pressed)
	_controls_btn.pressed.connect(_on_controls_pressed)
	_music_slider.value_changed.connect(_on_music_slider_changed)
	if is_instance_valid(_ambient_slider):
		_ambient_slider.value_changed.connect(_on_ambient_slider_changed)
	_sfx_slider.value_changed.connect(_on_sfx_slider_changed)

	# Initialise sliders from the live bus volumes (not from the save file)
	# so they reflect any changes already applied this session.
	var music_idx: int = AudioServer.get_bus_index("Music")
	var ambient_idx: int = AMBIENCE_DIRECTOR.ensure_ambience_bus()
	var sfx_idx:   int = AudioServer.get_bus_index("SFX")
	if music_idx >= 0:
		_music_slider.value = db_to_linear(AudioServer.get_bus_volume_db(music_idx))
	if ambient_idx >= 0 and is_instance_valid(_ambient_slider):
		_ambient_slider.value = (
			0.0 if AudioServer.is_bus_mute(ambient_idx)
			else db_to_linear(AudioServer.get_bus_volume_db(ambient_idx))
		)
	if sfx_idx >= 0:
		_sfx_slider.value = db_to_linear(AudioServer.get_bus_volume_db(sfx_idx))

func _on_resume_pressed() -> void:
	visible = false
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	resumed.emit()

func focus_resume() -> void:
	if visible and is_instance_valid(_resume_btn):
		_resume_btn.grab_focus()

func _on_main_menu_pressed() -> void:
	# Unpause before changing scene — otherwise MainMenu.tscn inherits the paused state.
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)

func _on_quit_pressed() -> void:
	get_tree().quit()

func _on_audio_pressed() -> void:
	_audio_panel.visible = !_audio_panel.visible
	_audio_btn.text = "AUDIO  ▼" if _audio_panel.visible else "AUDIO  ▶"

func _on_controls_pressed() -> void:
	# Open the in-game controls screen (HowToPlayScreen). H key or its CLOSE button dismisses it.
	var htp := get_node_or_null("../HowToPlayScreen")
	if htp:
		if htp.has_method("show_controls"):
			htp.call("show_controls")
		else:
			htp.visible = true

func _on_music_slider_changed(value: float) -> void:
	SoundManager.set_music_volume(value)
	_save_settings()

func _on_ambient_slider_changed(value: float) -> void:
	_apply_ambient_volume(value)
	_save_settings()

func _on_sfx_slider_changed(value: float) -> void:
	SoundManager.set_sfx_volume(value)
	_save_settings()

func _save_settings() -> void:
	# Load first so we don't overwrite the fullscreen key we don't control here.
	var config := ConfigFile.new()
	config.load(settings_path)
	config.set_value("audio", "music", _music_slider.value)
	if is_instance_valid(_ambient_slider):
		config.set_value("audio", "ambient", _ambient_slider.value)
	config.set_value("audio", "sfx",   _sfx_slider.value)
	config.save(settings_path)

func _apply_ambient_volume(value: float) -> void:
	if SoundManager.has_method("set_ambient_volume"):
		SoundManager.call("set_ambient_volume", value)
	else:
		AMBIENCE_DIRECTOR.set_ambient_volume(value)
