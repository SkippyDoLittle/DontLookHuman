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
@export var grab_start_distance: float = 2.65
@export var grab_contact_distance: float = 0.82
@export var grab_windup_duration: float = 0.42
@export var grab_lunge_duration: float = 0.34
@export var grab_lunge_speed: float = 7.2
@export var grab_recovery_duration: float = 1.05
@export var capture_hold_duration: float = 0.85

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

func _ready() -> void:
	add_to_group("rangers")
	_suspicion_model.configure(self, player, pigeon_visual, _suspicion_config())
	_movement.configure(self, player, _movement_config())
	_presentation.configure(self, _alert_label, _sound_manager)

func _process(delta: float) -> void:
	if caught or _session_capture_in_progress:
		_movement.stop()
		return
	if grab_phase != GrabPhase.IDLE:
		_update_grab(delta)
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
	_presentation.grab_windup(grab_windup_duration)
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
			if _distance_to_player_flat() <= grab_contact_distance:
				_complete_physical_capture()
			elif _grab_timer <= 0.0:
				_begin_miss_recovery()
		GrabPhase.RECOVERY:
			_movement.stop()
			if _grab_timer <= 0.0:
				grab_phase = GrabPhase.IDLE
				_presentation.reset_grab_pose()

func _begin_lunge() -> void:
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
	_grab_timer = grab_recovery_duration
	missed_grabs += 1
	_movement.stop()
	_presentation.grab_missed(grab_recovery_duration)
	_sound_manager.call("play_grab_miss")
	_sound_manager.call("play_flock_panic")
	_reaction_director.broadcast(
		get_tree(),
		PARK_REACTIONS.EVENT_GRAB_MISSED,
		global_position,
		self
	)
	grab_missed.emit()

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
	_presentation.player_captured()
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
