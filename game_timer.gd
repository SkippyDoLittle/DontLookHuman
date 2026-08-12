# game_timer.gd — GameSession coordinator attached to the GameTimer scene node.
# Delegates countdown/timing, scoring, persistence, HUD presentation, and transitions
# to focused components while preserving the existing scene-facing API.

class_name GameSession
extends Node

const MENU_SCENE: String = "res://MainMenu.tscn"
const FIRST_LEVEL_SCENE: String = "res://scenes/levels/Level01_Park.tscn"

const BLEND_THRESHOLD: float = 40.0
const BLEND_RADIUS: float = 3.5
const BLEND_BONUS_SECONDS: float = 5.0
const CHAOS_WINDOW_DURATION: float = 6.0
const CHAOS_BONUS_SECONDS: float = 4.0
const ALIBI_QUALIFY_DURATION: float = 2.6
const PERFECT_ALIBI_DURATION: float = 3.2
const ALIBI_REARM_DURATION: float = 5.0

signal session_state_changed(new_state: SessionState)
signal collectible_count_changed(remaining: int)
signal level_finished(success: bool)
signal blend_pickup_earned(origin: Vector3, bonus_seconds: float)
signal chaos_pickup_earned(origin: Vector3, bonus_seconds: float)
signal perfect_alibi_ready(origin: Vector3, joiner_count: int, duration: float)
signal perfect_alibi_pickup_earned(origin: Vector3, bonus_seconds: float)

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
var _result_transition_started: bool = false
var _controls_closed_frame: int = -1
var _capture_sequence_active: bool = false
var _chaos_window_timer: float = 0.0
var _alibi_candidate_timer: float = 0.0
var _perfect_alibi_timer: float = 0.0
var _alibi_rearm_timer: float = 0.0
var _alibi_origin: Vector3 = Vector3.ZERO
var _alibi_joiner_count: int = 0
var _food_connected: Dictionary = {}
var blend_bonus_count: int = 0
var chaos_bonus_count: int = 0
var perfect_alibi_ready_count: int = 0
var perfect_alibi_pickup_count: int = 0

var _timer := SessionTimer.new()
var _score_manager := ScoreManager.new()
var _score_store := BestScoreStore.new()
var _progress_store := CampaignProgressStore.new()
var _hud := SessionHUDController.new()
var _transition := TransitionController.new()

func _ready() -> void:
	_apply_level_config()

	var level_root := get_parent()
	_hud.configure(level_root)
	_transition.configure(self, level_root)
	_connect_components()

	_sound_manager.call("start_ambient")
	_sound_manager.call("begin_level_score", level_id)
	_sound_manager.call("set_music_session_state", &"title")
	escape_zone.connect("player_escaped", _on_player_escaped)
	if escape_zone.has_signal("escape_blocked"):
		escape_zone.connect("escape_blocked", _on_escape_blocked)
	if _pause_menu.has_signal("resumed"):
		_pause_menu.connect("resumed", _on_pause_menu_resumed)
	if _how_to_play != null:
		if _how_to_play.has_signal("controls_opened"):
			_how_to_play.connect("controls_opened", _on_controls_opened)
		if _how_to_play.has_signal("controls_closed"):
			_how_to_play.connect("controls_closed", _on_controls_closed)

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
			_process_paused_input()
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
	_hud.result_action_requested.connect(_on_result_action_requested)

func _initialize_world_connections() -> void:
	_connect_new_rangers()
	_connect_food()
	_connect_chaos_controller()
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
	if _capture_sequence_active:
		return
	if Input.is_action_just_pressed("pause_game"):
		_pause_session()
		return

	var remaining := _refresh_collectible_count()
	_update_opportunity_windows(delta)

	_timer.advance(delta)
	_update_exit_marker(remaining)

func _pause_session() -> void:
	_pause_menu.visible = true
	_pause_menu.call_deferred("focus_resume")
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_set_state(SessionState.PAUSED)

func _process_paused_input() -> void:
	if Input.is_action_just_pressed("pause_game"):
		if _how_to_play != null and _how_to_play.visible:
			_how_to_play.call("close_controls")
		elif _controls_closed_frame != Engine.get_process_frames():
			_resume_session()
	elif not _pause_menu.visible and not (_how_to_play != null and _how_to_play.visible):
		_resume_session()

func _resume_session() -> void:
	_pause_menu.visible = false
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_set_state(SessionState.ACTIVE)

func _on_pause_menu_resumed() -> void:
	if state == SessionState.PAUSED:
		_resume_session()

func _on_controls_opened() -> void:
	if state == SessionState.ACTIVE:
		_pause_session()

func _on_controls_closed() -> void:
	_controls_closed_frame = Engine.get_process_frames()

func _process_finished_input() -> void:
	if _result_transition_started:
		return
	if Input.is_action_just_pressed("restart"):
		_on_result_action_requested(SessionHUDController.ACTION_RETRY)
	elif Input.is_action_just_pressed("ui_cancel"):
		_on_result_action_requested(SessionHUDController.ACTION_MENU)

func _on_result_action_requested(action: StringName) -> void:
	if state != SessionState.FINISHED or _result_transition_started:
		return

	match action:
		SessionHUDController.ACTION_NEXT:
			if _success and not next_level_scene.is_empty():
				_transition_from_result(func(): _change_scene_unpaused(next_level_scene))
		SessionHUDController.ACTION_RETRY:
			_transition_from_result(func():
				get_tree().paused = false
				get_tree().reload_current_scene()
			)
		SessionHUDController.ACTION_REPLAY_CAMPAIGN:
			if _success and next_level_scene.is_empty():
				_transition_from_result(func(): _change_scene_unpaused(FIRST_LEVEL_SCENE))
		SessionHUDController.ACTION_MENU:
			_transition_from_result(func(): _change_scene_unpaused(MENU_SCENE))

func _transition_from_result(completion: Callable) -> void:
	_result_transition_started = true
	_hud.disable_result_actions()
	_sound_manager.call("end_level_score")
	_transition.fade_to_black(0.4, completion)

func _change_scene_unpaused(scene_path: String) -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(scene_path)

func _connect_new_rangers() -> void:
	for ranger_node in get_tree().get_nodes_in_group("rangers"):
		var instance_id := ranger_node.get_instance_id()
		if _connected_rangers.has(instance_id):
			continue
		_connected_rangers[instance_id] = ranger_node
		ranger_node.connect("suspicion_changed", _on_ranger_suspicion_changed)
		ranger_node.connect("player_caught", _on_ranger_caught.bind(ranger_node))
		if ranger_node.has_signal("capture_started"):
			ranger_node.connect("capture_started", _on_capture_started)
		if ranger_node.has_signal("grab_missed"):
			ranger_node.connect("grab_missed", _on_ranger_grab_missed)
		if ranger_node.has_signal("collision_stumble_started"):
			ranger_node.connect("collision_stumble_started",
				func(_t: StringName, _o: Vector3) -> void:
					_start_chaos_window()
			)

func _connect_food() -> void:
	for food in get_tree().get_nodes_in_group("collectibles"):
		var id := food.get_instance_id()
		if _food_connected.has(id):
			continue
		_food_connected[id] = true
		if food.has_signal("food_collected"):
			food.food_collected.connect(_on_food_collected_bonus)

func _connect_chaos_controller() -> void:
	var controller := get_node_or_null("../ParkChaosController")
	if controller == null or not controller.has_signal("flock_sync_started"):
		return
	if not controller.is_connected("flock_sync_started", _on_flock_sync_started):
		controller.connect("flock_sync_started", _on_flock_sync_started)

func _on_food_collected_bonus(_food: Node3D, origin: Vector3) -> void:
	if state != SessionState.ACTIVE:
		return
	var is_blend := _check_blend_condition()
	var is_chaos := _chaos_window_timer > 0.0
	var is_perfect_alibi := is_blend and _perfect_alibi_timer > 0.0
	# A food theft is the one attempt attached to this alibi. It consumes both
	# the qualifying beat and the ready window whether or not the player stayed
	# close enough to the flock to earn the existing blend reward.
	_consume_alibi_opportunity()
	if not is_blend and not is_chaos:
		return
	var total_bonus := 0.0
	if is_blend:
		total_bonus += BLEND_BONUS_SECONDS
		blend_bonus_count += 1
		blend_pickup_earned.emit(origin, BLEND_BONUS_SECONDS)
	if is_chaos:
		total_bonus += CHAOS_BONUS_SECONDS
		chaos_bonus_count += 1
		chaos_pickup_earned.emit(origin, CHAOS_BONUS_SECONDS)
	if is_perfect_alibi:
		perfect_alibi_pickup_count += 1
		perfect_alibi_pickup_earned.emit(origin, BLEND_BONUS_SECONDS)
	_timer.add_time(total_bonus)
	var bonus_text: String
	var bonus_color: Color
	if is_perfect_alibi and is_chaos:
		bonus_text = "PERFECT ALIBI!  +%.0fs" % total_bonus
		bonus_color = Color(1.0, 0.95, 0.35)
	elif is_perfect_alibi:
		bonus_text = "PERFECT ALIBI!  +%.0fs" % BLEND_BONUS_SECONDS
		bonus_color = Color(0.42, 1.0, 0.86)
	elif is_blend and is_chaos:
		bonus_text = "PERFECT TIMING!  +%.0fs" % total_bonus
		bonus_color = Color(1.0, 0.95, 0.35)
	elif is_blend:
		bonus_text = "BLENDED!  +%.0fs" % BLEND_BONUS_SECONDS
		bonus_color = Color(0.4, 1.0, 0.55)
	else:
		bonus_text = "CHAOS WINDOW!  +%.0fs" % CHAOS_BONUS_SECONDS
		bonus_color = Color(1.0, 0.72, 0.2)
	_hud.show_pickup_bonus(bonus_text, bonus_color)

func _check_blend_condition() -> bool:
	var player_node := get_node_or_null("../Player")
	if not is_instance_valid(player_node) or not player_node is Node3D:
		return false
	for ranger in get_tree().get_nodes_in_group("rangers"):
		if float(ranger.get("suspicion")) >= BLEND_THRESHOLD:
			return false
	var player_pos := (player_node as Node3D).global_position
	for pigeon in get_tree().get_nodes_in_group("pigeons"):
		if pigeon is Node3D and (pigeon as Node3D).global_position.distance_to(player_pos) <= BLEND_RADIUS:
			return true
	return false

func _on_ranger_suspicion_changed(value: float) -> void:
	peak_suspicion = maxf(peak_suspicion, value)

func _on_capture_started() -> void:
	_capture_sequence_active = true
	_cancel_alibi_opportunity()
	_refresh_opportunity_hud()
	_transition.start_shake(0.8)

func _on_ranger_grab_missed() -> void:
	_start_chaos_window()
	_transition.start_shake(0.45)

func _start_chaos_window() -> void:
	_chaos_window_timer = CHAOS_WINDOW_DURATION
	_refresh_opportunity_hud()

func _update_chaos_window(delta: float) -> void:
	_chaos_window_timer = maxf(_chaos_window_timer - maxf(delta, 0.0), 0.0)
	_refresh_opportunity_hud()

func _update_opportunity_windows(delta: float) -> void:
	var safe_delta := maxf(delta, 0.0)
	var promoted_this_frame := false
	_chaos_window_timer = maxf(_chaos_window_timer - safe_delta, 0.0)
	_alibi_rearm_timer = maxf(_alibi_rearm_timer - safe_delta, 0.0)

	if _alibi_candidate_timer > 0.0:
		if not _alibi_runtime_is_safe():
			_clear_alibi_candidate()
		else:
			_alibi_candidate_timer = maxf(_alibi_candidate_timer - safe_delta, 0.0)
			if _check_blend_condition():
				_promote_perfect_alibi()
				promoted_this_frame = true
			elif _alibi_candidate_timer <= 0.0:
				_clear_alibi_candidate()

	if _perfect_alibi_timer > 0.0 and not promoted_this_frame:
		if not _alibi_runtime_is_safe() or not _check_blend_condition():
			_perfect_alibi_timer = 0.0
		else:
			_perfect_alibi_timer = maxf(_perfect_alibi_timer - safe_delta, 0.0)

	_refresh_opportunity_hud()

func _on_flock_sync_started(joiner_count: int, origin: Vector3) -> void:
	if (
		state != SessionState.ACTIVE
		or joiner_count < 2
		or _capture_sequence_active
		or _alibi_candidate_timer > 0.0
		or _perfect_alibi_timer > 0.0
		or _alibi_rearm_timer > 0.0
		or not _alibi_runtime_is_safe()
		or _maximum_ranger_suspicion() < BLEND_THRESHOLD
	):
		return
	_alibi_candidate_timer = ALIBI_QUALIFY_DURATION
	_alibi_origin = origin
	_alibi_joiner_count = joiner_count

func _promote_perfect_alibi() -> void:
	if _alibi_candidate_timer <= 0.0 or not _alibi_runtime_is_safe():
		return
	_alibi_candidate_timer = 0.0
	_perfect_alibi_timer = PERFECT_ALIBI_DURATION
	_alibi_rearm_timer = ALIBI_REARM_DURATION
	perfect_alibi_ready_count += 1
	perfect_alibi_ready.emit(_alibi_origin, _alibi_joiner_count, PERFECT_ALIBI_DURATION)

func _alibi_runtime_is_safe() -> bool:
	if state != SessionState.ACTIVE or _capture_sequence_active:
		return false
	var found_ranger := false
	for ranger in get_tree().get_nodes_in_group("rangers"):
		found_ranger = true
		if (
			bool(ranger.get("caught"))
			or int(ranger.get("state")) == RangerStateMachine.State.CHASE
			or int(ranger.get("grab_phase")) != 0
		):
			return false
	return found_ranger

func _maximum_ranger_suspicion() -> float:
	var maximum := 0.0
	for ranger in get_tree().get_nodes_in_group("rangers"):
		maximum = maxf(maximum, float(ranger.get("suspicion")))
	return maximum

func _clear_alibi_candidate() -> void:
	_alibi_candidate_timer = 0.0
	_alibi_origin = Vector3.ZERO
	_alibi_joiner_count = 0

func _consume_alibi_opportunity() -> void:
	_clear_alibi_candidate()
	_perfect_alibi_timer = 0.0
	_refresh_opportunity_hud()

func _cancel_alibi_opportunity() -> void:
	_clear_alibi_candidate()
	_perfect_alibi_timer = 0.0

func _refresh_opportunity_hud() -> void:
	if state != SessionState.ACTIVE or _capture_sequence_active:
		_hud.hide_chaos_window()
		return
	if _perfect_alibi_timer > 0.0 and _chaos_window_timer > 0.0:
		_hud.show_combined_window(
			minf(_perfect_alibi_timer, _chaos_window_timer),
			BLEND_BONUS_SECONDS + CHAOS_BONUS_SECONDS
		)
	elif _perfect_alibi_timer > 0.0:
		_hud.show_alibi_window(_perfect_alibi_timer, BLEND_BONUS_SECONDS)
	elif _chaos_window_timer > 0.0:
		_hud.show_chaos_window(_chaos_window_timer, CHAOS_BONUS_SECONDS)
	else:
		_hud.hide_chaos_window()

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

func _update_exit_marker(remaining: int) -> void:
	if remaining != 0:
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
	_capture_sequence_active = false
	_chaos_window_timer = 0.0
	_cancel_alibi_opportunity()
	_alibi_rearm_timer = 0.0
	_hud.hide_chaos_window()
	_set_state(SessionState.FINISHED)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	if success:
		_sound_manager.call("play_escape")
	else:
		_sound_manager.call("play_caught")
		_transition.start_shake()
	_sound_manager.call("finish_level_score", success)

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
	if success:
		_progress_store.record_completion(level_id)

	_hud.show_result(
		headline,
		success,
		summary,
		best_score,
		is_new_best,
		not next_level_scene.is_empty(),
		_caught_reason
	)
	_sound_manager.call("set_tension", 0.0)
	_sound_manager.call("stop_ambient")
	get_tree().paused = true
	level_finished.emit(success)

func _set_state(new_state: SessionState) -> void:
	if state == new_state:
		return
	state = new_state
	game_started = state in [SessionState.ACTIVE, SessionState.PAUSED, SessionState.FINISHED]
	game_over = state == SessionState.FINISHED
	_refresh_opportunity_hud()
	_sound_manager.call("set_music_session_state", _music_state_name(state))
	session_state_changed.emit(state)

func _music_state_name(session_state: SessionState) -> StringName:
	match session_state:
		SessionState.TITLE:
			return &"title"
		SessionState.COUNTDOWN:
			return &"countdown"
		SessionState.ACTIVE:
			return &"active"
		SessionState.PAUSED:
			return &"paused"
		SessionState.FINISHED:
			return &"finished"
	return &"active"
