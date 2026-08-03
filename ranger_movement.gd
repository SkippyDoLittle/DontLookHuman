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
	_desired_move = Vector3.ZERO
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
	_ranger.velocity.x = _desired_move.x
	_ranger.velocity.z = _desired_move.z
	if not _ranger.is_on_floor():
		_ranger.velocity.y -= 9.8 * delta
	else:
		_ranger.velocity.y = 0.0
	_ranger.move_and_slide()

func choose_new_patrol_direction() -> void:
	var angle := randf_range(0.0, TAU)
	_patrol_direction = Vector3(sin(angle), 0.0, cos(angle))
	_time_until_turn = randf_range(2.0, 4.0)

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
