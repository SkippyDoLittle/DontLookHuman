# game_timer.gd — Attached to GameTimer node in Main.tscn
# Manages the full game session: title screen, countdown, timer, win/lose detection,
# screen shake, exit marker pulse, tick sounds, result screen, and best-time save.

extends Node

@export var time_limit:   float = 60.0
@export var items_total:  int   = 3   # must match the number of PicnicFood nodes in the scene

@onready var timer_label:       Label        = get_node("../HUD/TimerLabel")
@onready var result_bg:         ColorRect    = get_node("../HUD/ResultBackground")
@onready var result_label:      Label        = get_node("../HUD/ResultLabel")
@onready var status_label:      Label        = get_node("../HUD/RangerStatus")
@onready var objective_label:   Label        = get_node("../HUD/ObjectiveStatus")
@onready var suspicion_bar:     ProgressBar  = get_node("../HUD/SuspicionBar")
@onready var ranger:            Node3D       = get_node("../Ranger")
@onready var exit_area:         Node         = get_node("../EscapeZone/ExitArea")
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

const SAVE_PATH: String = "user://best_time.dat"

var time_remaining:  float = 0.0
var peak_suspicion:  float = 0.0
var game_over:       bool  = false
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
			else:
				_pause_menu.visible = true
				get_tree().paused   = true

	if _pause_menu.visible:
		return   # skip game logic while paused

	# ── GAME OVER: RESTART ───────────────────────────────────────────────────────
	if game_over:
		if Input.is_action_just_pressed("restart"):
			# Fade to black before reload so the cut isn't jarring.
			# Use _transition_rect (layer 20) — it sits above the result screen's background.
			var tween := create_tween()
			tween.tween_property(_transition_rect, "color:a", 1.0, 0.4)
			tween.tween_callback(func(): get_tree().reload_current_scene())
		return

	# ── PEAK SUSPICION ───────────────────────────────────────────────────────────
	var s: float = float(ranger.get("suspicion"))
	if s > peak_suspicion:
		peak_suspicion = s

	# ── WIN / LOSE CHECK ─────────────────────────────────────────────────────────
	if bool(ranger.get("caught")):
		_finish(false, "CAUGHT!")
		return
	if bool(exit_area.get("escaped")):
		_finish(true, "ESCAPED!")
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

	if success:
		SoundManager.play_escape()
	else:
		SoundManager.play_caught()
		_shake_trauma = 1.0

	# ── STATISTICS ───────────────────────────────────────────────────────────────
	var remaining: int  = get_tree().get_nodes_in_group("collectibles").size()
	var collected: int  = items_total - remaining
	var used:      float = time_limit - time_remaining
	var m: int = int(used / 60.0)
	var s: int = int(used) % 60

	# ── LETTER GRADE (success only) ───────────────────────────────────────────────
	# Score = items (40 pts) + time remaining (35 pts) + low peak suspicion (25 pts).
	var grade: String = "F"
	if success:
		var item_score:  float = float(collected) / float(items_total) * 40.0
		var time_score:  float = maxf(0.0, (time_limit - used) / time_limit) * 35.0
		var susp_score:  float = maxf(0.0, 1.0 - peak_suspicion / 100.0) * 25.0
		var total_score: float = item_score + time_score + susp_score
		if   total_score >= 85.0: grade = "A"
		elif total_score >= 70.0: grade = "B"
		elif total_score >= 55.0: grade = "C"
		elif total_score >= 40.0: grade = "D"

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
		+ "\nGrade:          " + grade
		+ "\nTime:           %d:%02d"
		+ "\nItems stolen:   %d / %d"
		+ "\nPeak suspicion: %d%%"
		+ "\n──────────────────"
	) % [m, s, collected, items_total, int(peak_suspicion)]

	# ── BEST TIME ────────────────────────────────────────────────────────────────
	var best: float = _load_best()   # returns INF when no save exists
	if success:
		if best == INF or used < best:
			_save_best(used)
			result_label.text += "\n★  New best time!"
		else:
			result_label.text += "\nBest: %d:%02d" % [int(best / 60.0), int(best) % 60]
	else:
		if best != INF:
			result_label.text += "\nBest so far: %d:%02d" % [int(best / 60.0), int(best) % 60]

	result_label.text += "\n\nPress R to play again"

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

func _load_best() -> float:
	if not FileAccess.file_exists(SAVE_PATH):
		return INF   # sentinel value meaning "no best time saved yet"
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	return f.get_float() if f != null else INF

func _save_best(time_used: float) -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_float(time_used)
		# FileAccess closes automatically when f goes out of scope in Godot 4.
