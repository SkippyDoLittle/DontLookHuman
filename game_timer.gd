# game_timer.gd — Attached to GameTimer node in Main.tscn
# Manages the full game session: title screen, countdown, timer, win/lose detection,
# screen shake, exit marker pulse, tick sounds, result screen, and best-time save.

extends Node

@export var time_limit:        float  = 60.0
@export var items_total:       int    = 5      # must match the number of PicnicFood nodes in the scene
@export var next_level_scene:  String = ""     # empty on the final level

@onready var timer_label:       Label        = get_node("../HUD/TimerLabel")
@onready var result_bg:         ColorRect    = get_node("../HUD/ResultBackground")
@onready var result_label:      Label        = get_node("../HUD/ResultLabel")
@onready var status_label:      Label        = get_node("../HUD/RangerStatus")
@onready var objective_label:   Label        = get_node("../HUD/ObjectiveStatus")
@onready var suspicion_bar:     ProgressBar  = get_node("../HUD/SuspicionBar")
@onready var ranger:            Node3D       = get_node("../Ranger")   # primary ranger (kept for compatibility)
@onready var escape_zone:       Node         = get_node("../EscapeZone")
@onready var _camera:           Camera3D     = get_node("../Player/SpringArm3D/Camera3D")
@onready var _title_screen:     CanvasLayer  = get_node("../TitleScreen")
@onready var _exit_marker:      MeshInstance3D = get_node("../EscapeZone/ExitMarker")
@onready var _fade_overlay:     ColorRect    = get_node("../HUD/FadeOverlay")
@onready var _transition_rect:  ColorRect    = get_node("../TransitionLayer/FadeRect")
# _transition_rect lives on CanvasLayer layer=20 — above TitleScreen (10) and HUD (1),
# so it can cover everything for scene transitions.
@onready var _stamina_bar:      ProgressBar  = get_node("../HUD/StaminaBar")
@onready var _countdown_label:  Label        = get_node("../HUD/CountdownLabel")
@onready var _pause_menu:       CanvasLayer  = get_node("../PauseMenu")
@onready var _how_to_play:      Node         = get_node_or_null("../HowToPlayScreen")

const SAVE_PATH: String = "user://best_score.dat"

var time_remaining:  float = 0.0
var peak_suspicion:  float = 0.0
var game_over:       bool  = false
var _success:        bool  = false   # stored so the input handler can gate SPACE on win only
var game_started:    bool  = false
var _tick_timer:     float = 0.0
var _shake_trauma:   float = 0.0   # 1.0 = max shake; decays to 0 each frame
var _exit_mat:       StandardMaterial3D
var _exit_pulse_time: float = 0.0
var _counting_down:  bool  = false
var _countdown_val:  int   = 3
var _countdown_timer: float = 0.0
var _help_hint:      Label  = null

func _ready() -> void:
	var config: LevelConfig = null
	if get_parent() is BaseLevel:
		config = (get_parent() as BaseLevel).level_config
	if config != null:
		time_limit = config.time_limit
		next_level_scene = config.next_level_scene

	# SoundManager persists between scenes, so restart ambience if the previous
	# level's result screen stopped it.
	SoundManager.start_ambient()
	escape_zone.connect("player_escaped", _on_player_escaped)

	# Fade in from black on scene load.
	var tween := create_tween()
	tween.tween_property(_fade_overlay, "modulate:a", 0.0, 0.8)
	tween.tween_callback(func(): _fade_overlay.visible = false)

	time_remaining = time_limit

	# Create a unique material for the exit marker so we can change its color at runtime
	# without affecting other meshes that share the same default material.
	_exit_mat = StandardMaterial3D.new()
	_exit_mat.albedo_color = Color(0.0, 1.0, 0.0, 1.0)
	_exit_marker.set_surface_override_material(0, _exit_mat)

	# PROCESS_MODE_ALWAYS so this node runs even while the scene tree is paused
	# (e.g., during the title screen, countdown, and pause menu).
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true   # freeze everything until countdown finishes

	# "H — controls" hint shown in the corner during the title screen.
	_help_hint = Label.new()
	_help_hint.text = "H — controls"
	_help_hint.add_theme_font_size_override("font_size", 13)
	_help_hint.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 0.60))
	_help_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_help_hint.offset_bottom = -10
	_help_hint.offset_left   = 12
	get_node("../HUD").add_child(_help_hint)

func _process(delta: float) -> void:

	# ── SCREEN SHAKE ─────────────────────────────────────────────────────────────
	if _shake_trauma > 0.0:
		_shake_trauma = maxf(_shake_trauma - delta * 1.8, 0.0)
		# trauma² gives small trauma = barely any shake, large trauma = dramatic shake.
		var mag: float = _shake_trauma * _shake_trauma * 0.04
		_camera.h_offset = randf_range(-mag, mag)
		_camera.v_offset = randf_range(-mag, mag)
	else:
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0

	# ── COUNTDOWN ────────────────────────────────────────────────────────────────
	if _counting_down:
		_countdown_timer += delta
		if _countdown_timer >= 1.0:
			_countdown_timer -= 1.0
			_countdown_val   -= 1
			if _countdown_val > 0:
				_countdown_label.text = str(_countdown_val)
			else:
				_countdown_label.text = "GO!"
				_counting_down = false
				game_started   = true
				get_tree().paused = false
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
				var tween := create_tween()
				tween.tween_interval(0.55)
				tween.tween_callback(func(): _countdown_label.visible = false)
		return   # block all game logic while counting down

	# ── TITLE SCREEN ─────────────────────────────────────────────────────────────
	if not game_started:
		if Input.is_action_just_pressed("ui_accept"):
			var tween := create_tween()
			tween.tween_property(_transition_rect, "color:a", 1.0, 0.20)
			tween.tween_callback(func():
				_title_screen.visible    = false
				_transition_rect.color.a = 0.0   # clear instantly (the new scene fades in itself)
				if _how_to_play: _how_to_play.visible = false
				if _help_hint:   _help_hint.visible   = false
				_countdown_val           = 3
				_countdown_timer         = 0.0
				_counting_down           = true
				_countdown_label.text    = "3"
				_countdown_label.visible = true
			)
		return

	# ── PAUSE TOGGLE ─────────────────────────────────────────────────────────────
	if not game_over:
		if Input.is_action_just_pressed("pause_game"):
			if _pause_menu.visible:
				_pause_menu.visible = false
				get_tree().paused   = false
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			else:
				_pause_menu.visible = true
				get_tree().paused   = true
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	if _pause_menu.visible:
		return   # skip game logic while paused

	# ── GAME OVER: RESTART / ADVANCE ────────────────────────────────────────────
	if game_over:
		if Input.is_action_just_pressed("restart"):
			var tween := create_tween()
			tween.tween_property(_transition_rect, "color:a", 1.0, 0.4)
			tween.tween_callback(func(): get_tree().reload_current_scene())
		elif _success and next_level_scene != "" and Input.is_action_just_pressed("ui_accept"):
			# SPACE advances to the next level only after a successful escape.
			var tween := create_tween()
			tween.tween_property(_transition_rect, "color:a", 1.0, 0.4)
			tween.tween_callback(func(): get_tree().change_scene_to_file(next_level_scene))
		return

	# ── PEAK SUSPICION (across all rangers) ─────────────────────────────────────
	# Check every ranger so the end-screen stat reflects the worst threat the player faced.
	for r in get_tree().get_nodes_in_group("rangers"):
		if is_instance_valid(r):
			var s: float = float(r.get("suspicion"))
			if s > peak_suspicion:
				peak_suspicion = s

	# ── WIN / LOSE CHECK (any ranger catches player) ──────────────────────────────
	for r in get_tree().get_nodes_in_group("rangers"):
		if is_instance_valid(r) and bool(r.get("caught")):
			_finish(false, "CAUGHT!")
			return
	# ── TIMER ────────────────────────────────────────────────────────────────────
	time_remaining = maxf(time_remaining - delta, 0.0)
	_update_timer()

	# ── EXIT MARKER PULSE ────────────────────────────────────────────────────────
	if get_tree().get_nodes_in_group("collectibles").size() == 0:
		_exit_pulse_time += delta
		var pulse: float = sin(_exit_pulse_time * TAU * 1.5) * 0.5 + 0.5
		_exit_mat.albedo_color = Color(pulse * 0.3, 0.5 + pulse * 0.5, pulse * 0.2, 1.0)

	# ── COUNTDOWN TICKS ──────────────────────────────────────────────────────────
	if time_remaining > 0.0 and time_remaining < 20.0:
		_tick_timer -= delta
		if _tick_timer <= 0.0:
			SoundManager.play_tick()
			_tick_timer = 1.0 if time_remaining < 10.0 else 2.0

	if time_remaining <= 0.0:
		_finish(false, "TIME'S UP!")

func _on_player_escaped() -> void:
	_finish(true, "ESCAPED!")

func _update_timer() -> void:
	# ceili() rounds UP so the display reads "1" while any fraction of a second remains.
	var secs: int = ceili(time_remaining)
	timer_label.text = "%d:%02d" % [secs / 60.0, secs % 60]

	if time_remaining <= 20.0:
		timer_label.modulate = Color(1.0, 0.3, 0.3)
	elif time_remaining <= 40.0:
		timer_label.modulate = Color(1.0, 0.75, 0.2)
	else:
		timer_label.modulate = Color.WHITE

func _finish(success: bool, headline: String) -> void:
	if game_over:
		return   # guard against simultaneous triggers (e.g., caught + time's up same frame)
	game_over = true
	_success  = success   # persist so the input handler can gate SPACE on win only
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	if success:
		SoundManager.play_escape()
	else:
		SoundManager.play_caught()
		_shake_trauma = 1.0

	# ── STATISTICS ───────────────────────────────────────────────────────────────
	var remaining: int   = get_tree().get_nodes_in_group("collectibles").size()
	var collected: int   = items_total - remaining
	var used:      float = time_limit - time_remaining
	var m: int = int(used / 60.0)
	var s: int = int(used) % 60

	# ── TIME-BASED SCORE ─────────────────────────────────────────────────────────
	# Score tiers are based on how quickly the player escapes with all items.
	# Failure (caught or time out) always scores 0.
	var score: int    = 0
	var tier:  String = ""
	if success:
		if used <= 20.0:
			score = 1000
			tier  = "★★★  Lightning fast!"
		elif used <= 35.0:
			score = 750
			tier  = "★★  Great escape!"
		elif used <= 50.0:
			score = 500
			tier  = "★  Nice work!"
		else:
			score = 250
			tier  = "Completed"

	var flavor: String
	if headline == "ESCAPED!":
		flavor = "\"Just a pigeon. Nothing to see here.\""
	elif headline == "CAUGHT!":
		flavor = "Caught red-beaked by the ranger!"
	else:
		flavor = "The picnic packed up before you could escape."

	result_label.text = (
		headline
		+ "\n" + flavor
		+ "\n\n──────────────────"
		+ "\nScore:          %d pts"
		+ (("\n                " + tier) if tier != "" else "")
		+ "\nTime:           %d:%02d"
		+ "\nItems stolen:   %d / %d"
		+ "\n──────────────────"
	) % [score, m, s, collected, items_total]

	# ── BEST SCORE ───────────────────────────────────────────────────────────────
	var best_score: int = _load_best()
	if success and score > 0:
		if score > best_score:
			_save_best(score)
			result_label.text += "\n★  New best score!"
		else:
			result_label.text += "\nBest score: %d pts" % best_score
	elif not success and best_score > 0:
		result_label.text += "\nBest score: %d pts" % best_score

	if success and next_level_scene != "":
		result_label.text += "\n\nSPACE — next level    R — restart"
	elif success and next_level_scene == "":
		result_label.text += "\n\n★  ALL LEVELS COMPLETE!  ★\nPress R to play again"
	else:
		result_label.text += "\n\nPress R to retry"

	result_label.modulate = Color(0.35, 1.0, 0.45) if success else Color(1.0, 0.35, 0.35)
	result_bg.color       = Color(0.03, 0.14, 0.06, 0.88) if success else Color(0.14, 0.03, 0.03, 0.88)

	result_bg.visible       = true
	result_label.visible    = true
	timer_label.visible     = false
	status_label.visible    = false
	objective_label.visible = false
	suspicion_bar.visible   = false
	_stamina_bar.visible    = false

	SoundManager.stop_ambient()

func _load_best() -> int:
	# Returns 0 when no save file exists yet.
	if not FileAccess.file_exists(SAVE_PATH):
		return 0
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	return f.get_32() if f != null else 0

func _save_best(score: int) -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_32(score)
		# FileAccess closes automatically when f goes out of scope in Godot 4.
