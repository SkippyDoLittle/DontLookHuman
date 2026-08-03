class_name RangerMovement
extends RefCounted

var _ranger: CharacterBody3D
var _player: CharacterBody3D
var _patrol_speed: float
var _patrol_radius: float
var _investigate_speed: float
var _chase_speed: float
var _approach_stop_distance: float

var _desired_move: Vector3 = Vector3.ZERO
var _patrol_direction: Vector3 = Vector3.FORWARD
var _time_until_turn: float = 0.0
var _current_state: int = RangerStateMachine.State.PATROL
var _blocked_time: float = 0.0
var _avoidance_time: float = 0.0
var _avoidance_direction: Vector3 = Vector3.ZERO
var obstacle_recoveries: int = 0

func configure(ranger: CharacterBody3D, player: CharacterBody3D, config: Dictionary) -> void:
	_ranger = ranger
	_player = player
	_patrol_speed = float(config.patrol_speed)
	_patrol_radius = float(config.patrol_radius)
	_investigate_speed = float(config.investigate_speed)
	_chase_speed = float(config.chase_speed)
	_approach_stop_distance = float(config.approach_stop_distance)
	choose_new_patrol_direction()

func update(delta: float, state: int) -> void:
	_current_state = state
	_desired_move = Vector3.ZERO
	if _avoidance_time > 0.0:
		_avoidance_time = maxf(_avoidance_time - delta, 0.0)
		_apply_avoidance_move(state)
		return
	match state:
		RangerStateMachine.State.PATROL:
			_do_patrol(delta)
		RangerStateMachine.State.INVESTIGATE:
			_move_toward_player(_investigate_speed)
		RangerStateMachine.State.CHASE:
			_move_toward_player(_chase_speed)

func stop() -> void:
	_desired_move = Vector3.ZERO

func physics_step(delta: float) -> void:
	var position_before := _ranger.global_position
	var intended_speed := Vector2(_desired_move.x, _desired_move.z).length()
	_ranger.velocity.x = _desired_move.x
	_ranger.velocity.z = _desired_move.z
	if not _ranger.is_on_floor():
		_ranger.velocity.y -= 9.8 * delta
	else:
		_ranger.velocity.y = 0.0
	_ranger.move_and_slide()

	var moved_distance := Vector2(
		_ranger.global_position.x - position_before.x,
		_ranger.global_position.z - position_before.z
	).length()
	if intended_speed > 0.1 and (
		_ranger.is_on_wall()
		or moved_distance < intended_speed * delta * 0.12
	):
		_blocked_time += delta
		if _blocked_time >= 0.25:
			_begin_obstacle_recovery()
	else:
		_blocked_time = maxf(_blocked_time - delta * 2.0, 0.0)

func choose_new_patrol_direction() -> void:
	var angle := randf_range(0.0, TAU)
	_patrol_direction = Vector3(sin(angle), 0.0, cos(angle))
	_time_until_turn = randf_range(2.0, 4.0)

func _begin_obstacle_recovery() -> void:
	var forward := _desired_move.normalized()
	if forward.length_squared() < 0.001:
		forward = _patrol_direction.normalized()
	var side := Vector3(-forward.z, 0.0, forward.x)
	if randf() < 0.5:
		side = -side
	_avoidance_direction = (side - forward * 0.2).normalized()
	_avoidance_time = 0.7
	_blocked_time = 0.0
	obstacle_recoveries += 1
	if _current_state == RangerStateMachine.State.PATROL:
		_patrol_direction = _avoidance_direction
		_time_until_turn = 1.0

func _apply_avoidance_move(state: int) -> void:
	var speed := _patrol_speed
	if state == RangerStateMachine.State.INVESTIGATE:
		speed = _investigate_speed
	elif state == RangerStateMachine.State.CHASE:
		speed = _chase_speed
	_desired_move = _avoidance_direction * speed
	if _avoidance_direction.length_squared() > 0.001:
		_ranger.look_at(_ranger.global_position + _avoidance_direction, Vector3.UP)

func _move_toward_player(speed: float) -> void:
	var to_player := _player.global_position - _ranger.global_position
	to_player.y = 0.0
	if to_player.length() < 0.1:
		return
	var look_target := Vector3(_player.global_position.x, _ranger.global_position.y, _player.global_position.z)
	_ranger.look_at(look_target, Vector3.UP)
	if to_player.length() > _approach_stop_distance:
		_desired_move = to_player.normalized() * speed

func _do_patrol(delta: float) -> void:
	_time_until_turn -= delta
	var outside_bounds := (
		absf(_ranger.position.x) > _patrol_radius
		or absf(_ranger.position.z) > _patrol_radius
	)
	if outside_bounds:
		_patrol_direction = Vector3(-_ranger.position.x, 0.0, -_ranger.position.z).normalized()
		_time_until_turn = 1.0
	elif _time_until_turn <= 0.0:
		choose_new_patrol_direction()

	if _patrol_direction.length() > 0.001:
		_ranger.look_at(_ranger.global_position + _patrol_direction, Vector3.UP)
	_desired_move = _patrol_direction * _patrol_speed
