extends Node

@export var time_limit: float = 90.0
@export var items_total: int = 3

@onready var timer_label: Label = get_node("../HUD/TimerLabel")
@onready var result_bg: ColorRect = get_node("../HUD/ResultBackground")
@onready var result_label: Label = get_node("../HUD/ResultLabel")
@onready var status_label: Label = get_node("../HUD/RangerStatus")
@onready var objective_label: Label = get_node("../HUD/ObjectiveStatus")
@onready var suspicion_bar: ProgressBar = get_node("../HUD/SuspicionBar")
@onready var ranger: Node3D = get_node("../Ranger")
@onready var exit_area: Node = get_node("../EscapeZone/ExitArea")
@onready var _camera: Camera3D = get_node("../Player/SpringArm3D/Camera3D")
@onready var _title_screen: CanvasLayer = get_node("../TitleScreen")
@onready var _exit_marker: MeshInstance3D = get_node("../EscapeZone/ExitMarker")

const SAVE_PATH: String = "user://best_time.dat"

var time_remaining: float = 0.0
var peak_suspicion: float = 0.0
var game_over: bool = false
var game_started: bool = false
var _tick_timer: float = 0.0
var _shake_trauma: float = 0.0
var _exit_mat: StandardMaterial3D
var _exit_pulse_time: float = 0.0

func _ready() -> void:
	time_remaining = time_limit
	_exit_mat = StandardMaterial3D.new()
	_exit_mat.albedo_color = Color(0.0, 1.0, 0.0, 1.0)
	_exit_marker.set_surface_override_material(0, _exit_mat)
	var best := _load_best()
	if best != INF:
		var bm: int = int(best / 60.0)
		var bs: int = int(best) % 60
		_title_screen.get_node("StartLabel").text = "Best: %d:%02d          Press SPACE to start" % [bm, bs]

func _process(delta: float) -> void:
	if _shake_trauma > 0.0:
		_shake_trauma = maxf(_shake_trauma - delta * 1.8, 0.0)
		var mag: float = _shake_trauma * _shake_trauma * 0.04
		_camera.h_offset = randf_range(-mag, mag)
		_camera.v_offset = randf_range(-mag, mag)
	else:
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0

	if not game_started:
		if Input.is_action_just_pressed("ui_accept"):
			game_started = true
			_title_screen.visible = false
		return

	if game_over:
		if Input.is_action_just_pressed("restart"):
			get_tree().reload_current_scene()
		return

	var s: float = float(ranger.get("suspicion"))
	if s > peak_suspicion:
		peak_suspicion = s

	if bool(ranger.get("caught")):
		_finish(false, "CAUGHT!")
		return

	if bool(exit_area.get("escaped")):
		_finish(true, "ESCAPED!")
		return

	time_remaining = maxf(time_remaining - delta, 0.0)
	_update_timer()

	var items_left: int = get_tree().get_nodes_in_group("collectibles").size()
	if items_left == 0:
		_exit_pulse_time += delta
		var pulse: float = sin(_exit_pulse_time * TAU * 1.5) * 0.5 + 0.5
		_exit_mat.albedo_color = Color(pulse * 0.3, 0.5 + pulse * 0.5, pulse * 0.2, 1.0)

	if time_remaining > 0.0 and time_remaining < 20.0:
		_tick_timer -= delta
		if _tick_timer <= 0.0:
			SoundManager.play_tick()
			_tick_timer = 1.0 if time_remaining < 10.0 else 2.0

	if time_remaining <= 0.0:
		_finish(false, "TIME'S UP!")

func _update_timer() -> void:
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
		return
	game_over = true

	if success:
		SoundManager.play_escape()
	else:
		SoundManager.play_caught()
		_shake_trauma = 1.0

	var remaining: int = get_tree().get_nodes_in_group("collectibles").size()
	var collected: int = items_total - remaining
	var used: float = time_limit - time_remaining
	var m: int = int(used / 60.0)
	var s: int = int(used) % 60

	result_label.text = (
		headline
		+ "\n\nTime:           %d:%02d"
		+ "\nItems stolen:   %d / %d"
		+ "\nPeak suspicion: %d%%"
		+ "\n\nPress R to play again"
	) % [m, s, collected, items_total, int(peak_suspicion)]

	if success:
		var best: float = _load_best()
		var is_new_best: bool = (best == INF or used < best)
		if is_new_best:
			_save_best(used)
			result_label.text += "\nNew best time!"
		else:
			var bm: int = int(best / 60.0)
			var bs: int = int(best) % 60
			result_label.text += "\nBest: %d:%02d" % [bm, bs]

	result_label.modulate = Color(0.35, 1.0, 0.45) if success else Color(1.0, 0.35, 0.35)

func _load_best() -> float:
	if not FileAccess.file_exists(SAVE_PATH):
		return INF
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	return f.get_float() if f != null else INF

func _save_best(time_used: float) -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_float(time_used)
	result_bg.visible = true
	result_label.visible = true
	timer_label.visible = false
	status_label.visible = false
	objective_label.visible = false
	suspicion_bar.visible = false
