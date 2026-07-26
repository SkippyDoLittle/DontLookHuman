# park_visitor.gd — Attached to each ParkVisitor node in Main.tscn
# Human background NPCs that wander and pause. No interaction with the suspicion system.

extends CharacterBody3D

@export var walk_speed:    float = 0.9   # slightly slower than the pigeon so you can weave around them
@export var wander_radius: float = 7.5   # max distance from park centre

var _target:       Vector3 = Vector3.ZERO
var _wait_timer:   float   = 0.0
var _is_waiting:   bool    = false
var _desired_move: Vector3 = Vector3.ZERO   # bridge between AI logic and physics

func _ready() -> void:
	_pick_new_target()

func _process(delta: float) -> void:
	_desired_move = Vector3.ZERO

	if _is_waiting:
		_wait_timer -= delta
		if _wait_timer <= 0.0:
			_is_waiting = false
			_pick_new_target()
		return

	var to_target := _target - global_position
	to_target.y = 0.0

	if to_target.length() < 0.5:
		_is_waiting = true
		_wait_timer = randf_range(2.0, 6.0)
		return

	var dir := to_target.normalized()
	_desired_move = dir * walk_speed

	# Build a flat look target to prevent the visitor from tilting up/down.
	var look_target := Vector3(global_position.x + dir.x, global_position.y, global_position.z + dir.z)
	look_at(look_target, Vector3.UP)

func _physics_process(delta: float) -> void:
	velocity.x = _desired_move.x
	velocity.z = _desired_move.z
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	else:
		velocity.y = 0.0
	move_and_slide()

func _pick_new_target() -> void:
	var angle: float = randf_range(0.0, TAU)
	var dist:  float = randf_range(1.5, wander_radius)
	_target = Vector3(sin(angle) * dist, 0.0, cos(angle) * dist)
