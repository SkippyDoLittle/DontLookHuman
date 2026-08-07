# ranger.gd — Scene-facing ranger coordinator.
# Detection, state selection, movement, and presentation are delegated to focused
# components. The exported tuning API remains stable for every existing level.

extends CharacterBody3D

const PARK_REACTIONS = preload("res://park_reaction_director.gd")

signal suspicion_changed(value: float)
signal state_changed(new_state: int)
signal player_caught
signal observation_changed(reason: String, is_nearby: bool, active_gain: float)
signal grab_started
signal grab_missed
signal capture_started
signal personality_reaction_started(kind: StringName, callout: String)
signal teammate_reaction_started(callout: String)
signal close_call(distance: float)
signal wrong_pigeon_grabbed(pigeon: Node)
signal wrong_pigeon_released(pigeon: Node)

enum RangerState { PATROL, INVESTIGATE, CHASE }
enum GrabPhase { IDLE, WINDUP, LUNGE, RECOVERY, CAPTURED }

@export var notice_distance: float = 6.5
@export var suspicious_speed: float = 2.0
@export var suspicion_gain_per_second: float = 30.0
@export var suspicion_loss_per_second: float = 22.0
@export var peck_loss_per_second: float = 20.0
@export var patrol_speed: float = 1.1
@export var patrol_radius: float = 9.5
@export var investigate_threshold: float = 65.0
@export var investigate_speed: float = 1.8
@export var chase_threshold: float = 90.0
@export var chase_speed: float = 3.5
@export var approach_stop_distance: float = 1.8
@export var food_aim_threshold: float = 0.9
@export var food_aim_delay: float = 0.8
@export var food_aim_gain_per_second: float = 18.0
@export var stare_threshold: float = 0.85
@export var stare_delay: float = 0.9
@export var stare_gain_per_second: float = 16.0
@export var separation_distance: float = 5.0
@export var separation_gain_per_second: float = 10.0
@export var straight_line_threshold: float = 2.5
@export var straight_line_dot: float = 0.97
@export var straight_line_gain_per_second: float = 10.0
@export var still_threshold: float = 3.5
@export var still_gain_per_second: float = 8.0
@export var is_primary: bool = true

@export_group("Physical Capture")
@export var physical_capture_enabled: bool = false
@export_enum("Rookie", "Steady", "Hothead", "Veteran") var capture_personality: String = "Steady"
@export var grab_start_distance: float = 2.65
@export var grab_contact_distance: float = 0.82
@export var grab_windup_duration: float = 0.42
@export var grab_lunge_duration: float = 0.34
@export var grab_lunge_speed: float = 7.2
@export var grab_recovery_duration: float = 1.05
@export var capture_hold_duration: float = 0.85
@export_range(0.1, 1.5, 0.05) var close_call_margin: float = 0.55
@export_range(0.4, 1.25, 0.05) var wrong_pigeon_grab_radius: float = 0.9
@export var wrong_pigeon_grab_cooldown: float = 6.0

@onready var player: CharacterBody3D = get_node("../Player")
@onready var pigeon_visual: Node3D = get_node("../Player/PigeonVisual")
@onready var _alert_label: Label3D = $AlertLabel
@onready var _sound_manager: Node = get_node("/root/SoundManager")

var suspicion: float = 0.0
var caught: bool = false
var state: int = RangerState.PATROL
var last_suspicion_reason: String = ""
var grab_phase: GrabPhase = GrabPhase.IDLE
var successful_grabs: int = 0
var missed_grabs: int = 0
var failed_grab_streak: int = 0
var teammate_reaction_count: int = 0
var last_personality_callout: String = ""
var last_lunge_closest_distance: float = INF
var close_call_count: int = 0
var wrong_pigeon_grab_count: int = 0

var _suspicion_model := RangerSuspicion.new()
var _state_machine := RangerStateMachine.new()
var _movement := RangerMovement.new()
var _presentation := RangerPresentation.new()
var _reaction_director := PARK_REACTIONS.new()
var _grab_timer: float = 0.0
var _grab_direction: Vector3 = Vector3.ZERO
var _player_exposed: bool = false
var _capture_signal_emitted: bool = false
var _session_capture_in_progress: bool = false
var _chaos_distraction_timer: float = 0.0
var chaos_reaction_count: int = 0
var _teammate_reaction_cooldown: float = 0.0
var _wrong_pigeon_cooldown: float = 0.0
var _wrong_pigeon_target: Node

func _ready() -> void:
	add_to_group("rangers")
	_suspicion_model.configure(self, player, pigeon_visual, _suspicion_config())
	_movement.configure(self, player, _movement_config())
	_presentation.configure(self, _alert_label, _sound_manager)

func _process(delta: float) -> void:
	_teammate_reaction_cooldown = maxf(_teammate_reaction_cooldown - delta, 0.0)
	_wrong_pigeon_cooldown = maxf(_wrong_pigeon_cooldown - delta, 0.0)
	if caught or _session_capture_in_progress:
		_movement.stop()
		return
	if grab_phase != GrabPhase.IDLE:
		_update_grab(delta)
		_presentation.update(delta, state)
		return
	if _chaos_distraction_timer > 0.0:
		_chaos_distraction_timer = maxf(_chaos_distraction_timer - delta, 0.0)
		_movement.stop()
		_presentation.update(delta, state)
		return

	var previous_suspicion := suspicion
	var observation := _suspicion_model.update(delta)
	var active_gain := float(observation.active_gain)
	var reason := String(observation.reason)
	if active_gain > 0.0 and not reason.is_empty():
		last_suspicion_reason = reason
	suspicion = _suspicion_model.suspicion
	if not is_equal_approx(suspicion, previous_suspicion):
		suspicion_changed.emit(suspicion)

	if _suspicion_model.caught:
		_complete_legacy_capture()
		return

	var new_state := int(_state_machine.update(
		suspicion,
		investigate_threshold,
		chase_threshold
	))
	if new_state != state:
		state = new_state
		_presentation.state_changed(state)
		state_changed.emit(state)

	if physical_capture_enabled:
		_update_exposed_state()
		if _can_begin_grab():
			_begin_grab()
			_presentation.update(delta, state)
			observation_changed.emit(reason, bool(observation.is_nearby), active_gain)
			return

	_movement.update(delta, state)
	_presentation.update(delta, state)
	observation_changed.emit(
		reason,
		bool(observation.is_nearby),
		active_gain
	)

func _physics_process(delta: float) -> void:
	_movement.physics_step(delta)

func choose_new_patrol_direction() -> void:
	_movement.choose_new_patrol_direction()

func halt_for_capture() -> void:
	_session_capture_in_progress = true
	_movement.stop()

func apply_chaos_distraction(
	origin: Vector3,
	duration: float = 0.8,
	suspicion_drop: float = 0.0,
	callout: String = "WHAT?!"
) -> bool:
	if caught or _session_capture_in_progress or grab_phase == GrabPhase.CAPTURED:
		return false
	_chaos_distraction_timer = maxf(_chaos_distraction_timer, duration)
	var look_target := Vector3(origin.x, global_position.y, origin.z)
	if global_position.distance_squared_to(look_target) > 0.001:
		look_at(look_target, Vector3.UP)
	var previous_suspicion := suspicion
	_suspicion_model.suspicion = maxf(_suspicion_model.suspicion - suspicion_drop, 0.0)
	suspicion = _suspicion_model.suspicion
	if not is_equal_approx(previous_suspicion, suspicion):
		suspicion_changed.emit(suspicion)
	chaos_reaction_count += 1
	_presentation.chaos_reaction(callout, duration)
	_movement.stop()
	return true

func stumble_from_environment(origin: Vector3, callout: String = "WHOA!") -> bool:
	if caught or _session_capture_in_progress or grab_phase == GrabPhase.CAPTURED:
		return false
	var look_target := Vector3(origin.x, global_position.y, origin.z)
	if global_position.distance_squared_to(look_target) > 0.001:
		look_at(look_target, Vector3.UP)
	grab_phase = GrabPhase.RECOVERY
	_grab_timer = maxf(grab_recovery_duration, 1.15)
	chaos_reaction_count += 1
	_movement.stop()
	_presentation.grab_missed(_grab_timer, capture_personality, 1)
	_alert_label.text = callout
	_sound_manager.call("play_grab_miss")
	_spawn_stumble_dust()
	return true

func react_to_teammate_miss(origin: Vector3) -> bool:
	if (
		caught
		or _session_capture_in_progress
		or grab_phase != GrabPhase.IDLE
		or _teammate_reaction_cooldown > 0.0
	):
		return false
	var look_target := Vector3(origin.x, global_position.y, origin.z)
	if global_position.distance_squared_to(look_target) > 0.001:
		look_at(look_target, Vector3.UP)
	_teammate_reaction_cooldown = 2.4
	teammate_reaction_count += 1
	var callout := _presentation.teammate_miss_reaction(capture_personality)
	teammate_reaction_started.emit(callout)
	return true

func react_to_teammate_wrong_pigeon(origin: Vector3) -> bool:
	if (
		caught
		or _session_capture_in_progress
		or grab_phase != GrabPhase.IDLE
		or _teammate_reaction_cooldown > 0.0
	):
		return false
	var look_target := Vector3(origin.x, global_position.y, origin.z)
	if global_position.distance_squared_to(look_target) > 0.001:
		look_at(look_target, Vector3.UP)
	_teammate_reaction_cooldown = 2.4
	teammate_reaction_count += 1
	var callout := _presentation.teammate_wrong_pigeon_reaction(capture_personality)
	teammate_reaction_started.emit(callout)
	return true

func _update_exposed_state() -> void:
	if suspicion >= 99.5:
		_player_exposed = true
	elif suspicion < chase_threshold:
		_player_exposed = false

func _can_begin_grab() -> bool:
	if not _player_exposed or state != RangerState.CHASE:
		return false
	var flat_offset := player.global_position - global_position
	flat_offset.y = 0.0
	return flat_offset.length() <= grab_start_distance

func _begin_grab() -> void:
	grab_phase = GrabPhase.WINDUP
	_grab_timer = grab_windup_duration
	_movement.stop()
	_face_player()
	_presentation.grab_windup(grab_windup_duration, capture_personality)
	_sound_manager.call("play_ranger_whistle")
	_reaction_director.broadcast(
		get_tree(),
		PARK_REACTIONS.EVENT_GRAB_WINDUP,
		global_position,
		self
	)
	grab_started.emit()

func _update_grab(delta: float) -> void:
	_grab_timer = maxf(_grab_timer - delta, 0.0)
	match grab_phase:
		GrabPhase.WINDUP:
			_movement.stop()
			_face_player()
			if _grab_timer <= 0.0:
				_begin_lunge()
		GrabPhase.LUNGE:
			_movement.move_in_direction(_grab_direction, grab_lunge_speed)
			var contact_distance := _distance_to_player_flat()
			last_lunge_closest_distance = minf(
				last_lunge_closest_distance,
				contact_distance
			)
			if contact_distance <= grab_contact_distance:
				_complete_physical_capture()
			elif _grab_timer <= 0.0:
				_begin_miss_recovery()
		GrabPhase.RECOVERY:
			_movement.stop()
			if _grab_timer <= 0.0:
				grab_phase = GrabPhase.IDLE
				_presentation.reset_grab_pose()

func _begin_lunge() -> void:
	last_lunge_closest_distance = _distance_to_player_flat()
	_grab_direction = player.global_position - global_position
	_grab_direction.y = 0.0
	if _grab_direction.length_squared() < 0.001:
		_grab_direction = -global_transform.basis.z
	_grab_direction = _grab_direction.normalized()
	grab_phase = GrabPhase.LUNGE
	_grab_timer = grab_lunge_duration
	_presentation.grab_lunge()
	_sound_manager.call("play_grab_whoosh")

func _begin_miss_recovery() -> void:
	grab_phase = GrabPhase.RECOVERY
	missed_grabs += 1
	failed_grab_streak += 1
	_grab_timer = grab_recovery_duration + _repeated_miss_recovery_bonus()
	_movement.stop()
	var mistaken_target := _try_grab_wrong_pigeon()
	if mistaken_target != null:
		last_personality_callout = _presentation.wrong_pigeon_grabbed(
			_grab_timer,
			capture_personality
		)
		_sound_manager.call("play_capture_flap")
		_sound_manager.call("play_wrong_pigeon")
		_spawn_feather_burst()
		get_tree().create_timer(0.48).timeout.connect(
			_notify_teammates_of_wrong_pigeon
		)
	else:
		last_personality_callout = _presentation.grab_missed(
			_grab_timer,
			capture_personality,
			failed_grab_streak
		)
		_sound_manager.call("play_grab_miss")
		_spawn_stumble_dust()
		_notify_teammates_of_miss()
	_sound_manager.call("play_flock_panic")
	_reaction_director.broadcast(
		get_tree(),
		PARK_REACTIONS.EVENT_GRAB_MISSED,
		global_position,
		self
	)
	personality_reaction_started.emit(
		&"wrong_pigeon" if mistaken_target != null else &"grab_missed",
		last_personality_callout
	)
	grab_missed.emit()
	if mistaken_target != null:
		wrong_pigeon_grabbed.emit(mistaken_target)
	else:
		_emit_close_call_if_needed()

func _try_grab_wrong_pigeon() -> Node:
	if _wrong_pigeon_cooldown > 0.0:
		return null
	var candidates: Array[Node3D] = []
	for pigeon in get_tree().get_nodes_in_group("pigeons"):
		if not pigeon is Node3D or not pigeon.has_method("can_be_mistaken_target"):
			continue
		if bool(pigeon.call("can_be_mistaken_target", global_position, wrong_pigeon_grab_radius)):
			candidates.append(pigeon as Node3D)
	candidates.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		var a_distance := a.global_position.distance_squared_to(global_position)
		var b_distance := b.global_position.distance_squared_to(global_position)
		if is_equal_approx(a_distance, b_distance):
			return a.get_instance_id() < b.get_instance_id()
		return a_distance < b_distance
	)
	if candidates.is_empty():
		return null
	var target := candidates[0]
	var hold_duration := minf(maxf(_grab_timer - 0.12, 0.55), 0.9)
	if not bool(target.call("start_mistaken_capture", self, hold_duration)):
		return null
	_wrong_pigeon_cooldown = wrong_pigeon_grab_cooldown
	_wrong_pigeon_target = target
	wrong_pigeon_grab_count += 1
	if target.has_signal("mistaken_capture_released"):
		target.connect(
			"mistaken_capture_released",
			_on_wrong_pigeon_released.bind(target),
			CONNECT_ONE_SHOT
		)
	return target

func _on_wrong_pigeon_released(_origin: Vector3, pigeon: Node) -> void:
	if _wrong_pigeon_target == pigeon:
		_wrong_pigeon_target = null
	wrong_pigeon_released.emit(pigeon)

func _emit_close_call_if_needed() -> void:
	if last_lunge_closest_distance > grab_contact_distance + close_call_margin:
		return
	close_call_count += 1
	close_call.emit(last_lunge_closest_distance)

func _repeated_miss_recovery_bonus() -> float:
	var repeated_misses := maxi(failed_grab_streak - 1, 0)
	var bonus_per_miss := float({
		"Rookie": 0.16,
		"Hothead": 0.14,
		"Veteran": 0.06,
	}.get(capture_personality, 0.1))
	return minf(float(repeated_misses) * bonus_per_miss, 0.4)

func _notify_teammates_of_miss() -> void:
	for candidate in get_tree().get_nodes_in_group("rangers"):
		if candidate == self or not candidate is Node3D:
			continue
		var teammate := candidate as Node3D
		if teammate.global_position.distance_to(global_position) > 9.5:
			continue
		if teammate.has_method("react_to_teammate_miss"):
			teammate.call("react_to_teammate_miss", global_position)

func _notify_teammates_of_wrong_pigeon() -> void:
	for candidate in get_tree().get_nodes_in_group("rangers"):
		if candidate == self or not candidate is Node3D:
			continue
		var teammate := candidate as Node3D
		if teammate.global_position.distance_to(global_position) > 9.5:
			continue
		if teammate.has_method("react_to_teammate_wrong_pigeon"):
			teammate.call("react_to_teammate_wrong_pigeon", global_position)

func _spawn_stumble_dust() -> void:
	var dust := CPUParticles3D.new()
	dust.name = "RangerStumbleDust"
	dust.amount = 14
	dust.lifetime = 0.6
	dust.one_shot = true
	dust.explosiveness = 1.0
	dust.direction = Vector3.UP
	dust.spread = 145.0
	dust.gravity = Vector3(0.0, -3.2, 0.0)
	dust.initial_velocity_min = 0.7
	dust.initial_velocity_max = 1.6
	dust.scale_amount_min = 0.6
	dust.scale_amount_max = 1.25
	dust.color = Color(0.72, 0.62, 0.45, 0.78)
	var dust_mesh := SphereMesh.new()
	dust_mesh.radius = 0.055
	dust_mesh.height = 0.11
	dust_mesh.radial_segments = 4
	dust_mesh.rings = 2
	var dust_material := StandardMaterial3D.new()
	dust_material.vertex_color_use_as_albedo = true
	dust_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dust_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dust_mesh.material = dust_material
	dust.mesh = dust_mesh
	get_parent().add_child(dust)
	dust.global_position = global_position + Vector3.UP * 0.05
	dust.emitting = true
	get_tree().create_timer(0.85).timeout.connect(dust.queue_free)

func _complete_physical_capture() -> void:
	if caught:
		return
	caught = true
	grab_phase = GrabPhase.CAPTURED
	successful_grabs += 1
	_movement.stop()
	for other_ranger in get_tree().get_nodes_in_group("rangers"):
		if other_ranger != self and other_ranger.has_method("halt_for_capture"):
			other_ranger.call("halt_for_capture")
	if player.has_method("start_capture_reaction"):
		player.call("start_capture_reaction", global_position)
	_presentation.player_captured(capture_personality)
	_spawn_feather_burst()
	_sound_manager.call("play_capture_impact")
	_sound_manager.call("play_flock_panic")
	_reaction_director.broadcast(
		get_tree(),
		PARK_REACTIONS.EVENT_PLAYER_CAUGHT,
		global_position,
		self
	)
	capture_started.emit()
	get_tree().create_timer(capture_hold_duration).timeout.connect(_emit_capture_result)

func _emit_capture_result() -> void:
	if _capture_signal_emitted or not is_instance_valid(self):
		return
	_capture_signal_emitted = true
	player_caught.emit()

func _complete_legacy_capture() -> void:
	caught = true
	_movement.stop()
	player_caught.emit()

func _face_player() -> void:
	var look_target := Vector3(player.global_position.x, global_position.y, player.global_position.z)
	if global_position.distance_squared_to(look_target) > 0.001:
		look_at(look_target, Vector3.UP)

func _distance_to_player_flat() -> float:
	var offset := player.global_position - global_position
	offset.y = 0.0
	return offset.length()

func _spawn_feather_burst() -> void:
	var burst := CPUParticles3D.new()
	burst.name = "CaptureFeathers"
	burst.amount = 18
	burst.lifetime = 0.8
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.direction = Vector3.UP
	burst.spread = 155.0
	burst.gravity = Vector3(0.0, -3.5, 0.0)
	burst.initial_velocity_min = 1.5
	burst.initial_velocity_max = 3.2
	burst.scale_amount_min = 0.7
	burst.scale_amount_max = 1.4
	var feather_mesh := QuadMesh.new()
	feather_mesh.size = Vector2(0.09, 0.035)
	var feather_material := StandardMaterial3D.new()
	feather_material.albedo_color = Color(0.88, 0.92, 1.0, 1.0)
	feather_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	feather_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	feather_mesh.material = feather_material
	burst.mesh = feather_mesh
	burst.position = Vector3(0.0, 0.15, 0.0)
	add_child(burst)
	burst.emitting = true
	get_tree().create_timer(1.1).timeout.connect(burst.queue_free)

func _suspicion_config() -> Dictionary:
	return {
		"notice_distance": notice_distance,
		"suspicious_speed": suspicious_speed,
		"suspicion_gain_per_second": suspicion_gain_per_second,
		"suspicion_loss_per_second": suspicion_loss_per_second,
		"peck_loss_per_second": peck_loss_per_second,
		"investigate_threshold": investigate_threshold,
		"chase_threshold": chase_threshold,
		"food_aim_threshold": food_aim_threshold,
		"food_aim_delay": food_aim_delay,
		"food_aim_gain_per_second": food_aim_gain_per_second,
		"stare_threshold": stare_threshold,
		"stare_delay": stare_delay,
		"stare_gain_per_second": stare_gain_per_second,
		"separation_distance": separation_distance,
		"separation_gain_per_second": separation_gain_per_second,
		"straight_line_threshold": straight_line_threshold,
		"straight_line_dot": straight_line_dot,
		"straight_line_gain_per_second": straight_line_gain_per_second,
		"still_threshold": still_threshold,
		"still_gain_per_second": still_gain_per_second,
		"physical_capture_enabled": physical_capture_enabled,
	}

func _movement_config() -> Dictionary:
	return {
		"patrol_speed": patrol_speed,
		"patrol_radius": patrol_radius,
		"investigate_speed": investigate_speed,
		"chase_speed": chase_speed,
		"approach_stop_distance": approach_stop_distance,
	}
