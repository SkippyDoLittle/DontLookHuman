# park_visitor.gd — Attached to each ParkVisitor node (or Visitor.tscn instance).
# Human background NPCs that wander and pause. No interaction with the suspicion system.

extends CharacterBody3D

@export var walk_speed:    float = 0.9    # slightly slower than the pigeon so you can weave around them
@export var wander_radius: float = 7.5   # max distance from park centre

# Per-instance clothing colours — set on each instance in the level scene.
# _ready() creates a fresh material so colour changes on one visitor never bleed to others.
@export var shirt_color: Color = Color(0.25, 0.45, 0.8, 1)    # default: blue (ParkVisitor1)
@export var pants_color: Color = Color(0.2, 0.25, 0.45, 1)    # default: navy

var _target:       Vector3 = Vector3.ZERO
var _wait_timer:   float   = 0.0
var _is_waiting:   bool    = false
var _desired_move: Vector3 = Vector3.ZERO   # bridge between AI logic and physics
var _blocked_time: float = 0.0
var obstacle_recoveries: int = 0

func _ready() -> void:
	# Apply per-instance colours to clothing meshes.
	# New materials so tinting one visitor never affects other instances.
	var shirt_mat := StandardMaterial3D.new()
	shirt_mat.albedo_color = shirt_color
	$VisitorBody.set_surface_override_material(0, shirt_mat)

	var pants_mat := StandardMaterial3D.new()
	pants_mat.albedo_color = pants_color
	$VisitorPants.set_surface_override_material(0, pants_mat)

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
	var position_before := global_position
	var intended_speed := Vector2(_desired_move.x, _desired_move.z).length()
	velocity.x = _desired_move.x
	velocity.z = _desired_move.z
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	else:
		velocity.y = 0.0
	move_and_slide()

	var moved_distance := Vector2(
		global_position.x - position_before.x,
		global_position.z - position_before.z
	).length()
	if intended_speed > 0.1 and (
		is_on_wall()
		or moved_distance < intended_speed * delta * 0.12
	):
		_blocked_time += delta
		if _blocked_time >= 0.35:
			_recover_from_obstacle()
	else:
		_blocked_time = maxf(_blocked_time - delta * 2.0, 0.0)

func _recover_from_obstacle() -> void:
	_blocked_time = 0.0
	obstacle_recoveries += 1
	_is_waiting = true
	_wait_timer = 0.25
	_desired_move = Vector3.ZERO

func _pick_new_target() -> void:
	var angle: float = randf_range(0.0, TAU)
	var dist:  float = randf_range(1.5, wander_radius)
	_target = Vector3(sin(angle) * dist, 0.0, cos(angle) * dist)
