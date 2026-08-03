# game_timer.gd — GameSession coordinator attached to the GameTimer scene node.
# Delegates countdown/timing, scoring, persistence, HUD presentation, and transitions
# to focused components while preserving the existing scene-facing API.

class_name GameSession
extends Node

signal session_state_changed(new_state: SessionState)
signal collectible_count_changed(remaining: int)
signal level_finished(success: bool)

enum SessionState { TITLE, COUNTDOWN, ACTIVE, PAUSED, FINISHED }

@export var time_limit: float = 60.0
@export var items_total: int = 5
@export var next_level_scene: String = ""

@onready var escape_zone: Node = get_node("../EscapeZone")
@onready var _title_screen: CanvasLayer = get_node("../TitleScreen")
@onready var _exit_marker: MeshInstance3D = get_node("../EscapeZone/ExitMarker")
@onready var _pause_menu: CanvasLayer = get_node("../PauseMenu")
@onready var _how_to_play: Node = get_node_or_null("../HowToPlayScreen")
@onready var _sound_manager: Node = get_node("/root/SoundManager")

var time_remaining: float = 0.0
var peak_suspicion: float = 0.0
var game_over: bool = false
var game_started: bool = false
var state: SessionState = SessionState.TITLE
var level_id: StringName = &"legacy_level"

var _success: bool = false
var _exit_material: StandardMaterial3D
var _exit_pulse_time: float = 0.0
var _last_collectible_count: int = -1
var _connected_rangers: Dictionary = {}
var _caught_reason: String = ""
var _grade_thresholds: Array[float] = ScoreManager.default_thresholds()

var _timer := SessionTimer.new()
var _score_manager := ScoreManager.new()
var _score_store := BestScoreStore.new()
var _hud := SessionHUDController.new()
var _transition := TransitionController.new()

func _ready() -> void:
	_apply_level_config()

	var level_root := get_parent()
	_hud.configure(level_root)
	_transition.configure(self, level_root)
	_connect_components()

	_sound_manager.call("start_ambient")
	escape_zone.connect("player_escaped", _on_player_escaped)
	if escape_zone.has_signal("escape_blocked"):
		escape_zone.connect("escape_blocked", _on_escape_blocked)
	if _pause_menu.has_signal("resumed"):
		_pause_menu.connect("resumed", _on_pause_menu_resumed)

	_transition.fade_in()
	_timer.reset(time_limit)

	_exit_material = StandardMaterial3D.new()
	_exit_material.albedo_color = Color(0.0, 1.0, 0.0, 1.0)
	_exit_marker.set_surface_override_material(0, _exit_material)

	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	_hud.add_controls_hint()
	call_deferred("_initialize_world_connections")

func _process(delta: float) -> void:
	_transition.update_shake(delta)

	match state:
		SessionState.TITLE:
			if Input.is_action_just_pressed("ui_accept"):
				_begin_countdown()
		SessionState.COUNTDOWN:
			_timer.advance_countdown(delta)
		SessionState.ACTIVE:
			_process_active_session(delta)
		SessionState.PAUSED:
			if Input.is_action_just_pressed("pause_game") or not _pause_menu.visible:
				_resume_session()
		SessionState.FINISHED:
			_process_finished_input()

func _apply_level_config() -> void:
	if get_parent() is BaseLevel:
		var config := (get_parent() as BaseLevel).level_config
		if config != null:
			level_id = config.level_id
			time_limit = config.time_limit
			next_level_scene = config.next_level_scene
			_grade_thresholds = config.grade_thresholds()
			return
	var scene_path := get_parent().scene_file_path
	if not scene_path.is_empty():
		level_id = StringName(scene_path.get_file().get_basename().to_snake_case())

func _connect_components() -> void:
	_timer.time_changed.connect(_on_time_changed)
	_timer.urgency_tick.connect(Callable(_sound_manager, "play_tick"))
	_timer.expired.connect(_on_timer_expired)
	_timer.countdown_changed.connect(_hud.show_countdown)
	_timer.countdown_finished.connect(_on_countdown_finished)

func _initialize_world_connections() -> void:
	_connect_new_rangers()
	items_total = get_tree().get_nodes_in_group("collectibles").size()
	_last_collectible_count = -1
	_refresh_collectible_count()

func _begin_countdown() -> void:
	_transition.fade_to_black(0.20, func():
		_title_screen.visible = false
		_transition.clear_transition()
		if _how_to_play:
			_how_to_play.visible = false
		_hud.hide_controls_hint()
		_set_state(SessionState.COUNTDOWN)
		_timer.start_countdown(3)
	)

func _on_countdown_finished() -> void:
	_hud.show_go()
	_set_state(SessionState.ACTIVE)
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	var tween := create_tween()
	tween.tween_interval(0.55)
	tween.tween_callback(_hud.hide_countdown)

func _process_active_session(delta: float) -> void:
	if Input.is_action_just_pressed("pause_game"):
		_pause_session()
		return

	_connect_new_rangers()
	_refresh_collectible_count()

	_timer.advance(delta)
	_update_exit_marker()

func _pause_session() -> void:
	_pause_menu.visible = true
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_set_state(SessionState.PAUSED)

func _resume_session() -> void:
	_pause_menu.visible = false
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_set_state(SessionState.ACTIVE)

func _on_pause_menu_resumed() -> void:
	if state == SessionState.PAUSED:
		_resume_session()

func _process_finished_input() -> void:
	if Input.is_action_just_pressed("restart"):
		_transition.fade_to_black(0.4, func(): get_tree().reload_current_scene())
	elif _success and not next_level_scene.is_empty() and Input.is_action_just_pressed("ui_accept"):
		_transition.fade_to_black(0.4, func(): get_tree().change_scene_to_file(next_level_scene))

func _connect_new_rangers() -> void:
	for ranger_node in get_tree().get_nodes_in_group("rangers"):
		var instance_id := ranger_node.get_instance_id()
		if _connected_rangers.has(instance_id):
			continue
		_connected_rangers[instance_id] = ranger_node
		ranger_node.connect("suspicion_changed", _on_ranger_suspicion_changed)
		ranger_node.connect("player_caught", _on_ranger_caught.bind(ranger_node))

func _on_ranger_suspicion_changed(value: float) -> void:
	peak_suspicion = maxf(peak_suspicion, value)

func _on_ranger_caught(ranger_node: Node) -> void:
	_caught_reason = String(ranger_node.get("last_suspicion_reason"))
	_finish(false, "CAUGHT!")

func _refresh_collectible_count() -> int:
	var remaining := get_tree().get_nodes_in_group("collectibles").size()
	if remaining != _last_collectible_count:
		_last_collectible_count = remaining
		_hud.update_objective(remaining, items_total)
		collectible_count_changed.emit(remaining)
	return remaining

func _update_exit_marker() -> void:
	if _refresh_collectible_count() != 0:
		return
	_exit_pulse_time += get_process_delta_time()
	var pulse := sin(_exit_pulse_time * TAU * 1.5) * 0.5 + 0.5
	_exit_material.albedo_color = Color(pulse * 0.3, 0.5 + pulse * 0.5, pulse * 0.2, 1.0)

func _on_time_changed(remaining: float) -> void:
	time_remaining = remaining
	_hud.update_timer(remaining)

func _on_timer_expired() -> void:
	_finish(false, "TIME'S UP!")

func _on_player_escaped() -> void:
	_finish(true, "ESCAPED!")

func _on_escape_blocked(remaining: int) -> void:
	_hud.show_escape_blocked(remaining)

func _finish(success: bool, headline: String) -> void:
	if state == SessionState.FINISHED:
		return

	_success = success
	_set_state(SessionState.FINISHED)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	if success:
		_sound_manager.call("play_escape")
	else:
		_sound_manager.call("play_caught")
		_transition.start_shake()

	var remaining := _refresh_collectible_count()
	var summary := _score_manager.calculate(
		success,
		time_limit,
		time_remaining,
		items_total,
		remaining,
		_grade_thresholds
	)
	var best_score := _score_store.load_best(level_id)
	var score: int = int(summary.score)
	var is_new_best: bool = success and score > 0 and score > best_score
	if is_new_best:
		_score_store.save_best(level_id, score)

	_hud.show_result(
		headline,
		success,
		summary,
		best_score,
		is_new_best,
		not next_level_scene.is_empty(),
		_caught_reason
	)
	_sound_manager.call("stop_ambient")
	level_finished.emit(success)

func _set_state(new_state: SessionState) -> void:
	if state == new_state:
		return
	state = new_state
	game_started = state in [SessionState.ACTIVE, SessionState.PAUSED, SessionState.FINISHED]
	game_over = state == SessionState.FINISHED
	session_state_changed.emit(state)
