# park_visitor.gd — Attached to each ParkVisitor node (or Visitor.tscn instance).
# Human background NPCs that wander and pause. No interaction with the suspicion system.

extends CharacterBody3D

const PARK_REACTIONS = preload("res://park_reaction_director.gd")

signal visitor_startled(origin: Vector3)

const PIGEON_STARTLE_RADIUS: float = 1.5
const PRESENTATION_PHASE_STEP: float = 2.39996323
const WALK_CADENCE: float = 8.0
const IDLE_CADENCE: float = 1.6

@export var walk_speed:    float = 0.9    # slightly slower than the pigeon so you can weave around them
@export var wander_radius: float = 7.5   # max distance from park centre

# Per-instance clothing colours — set on each instance in the level scene.
# _ready() creates a fresh material so colour changes on one visitor never bleed to others.
@export var shirt_color: Color = Color(0.25, 0.45, 0.8, 1)    # default: blue (ParkVisitor1)
@export var pants_color: Color = Color(0.2, 0.25, 0.45, 1)    # default: navy

@onready var _body: MeshInstance3D = $VisitorBody
@onready var _pants: MeshInstance3D = $VisitorPants
@onready var _head: MeshInstance3D = $VisitorHead
@onready var _left_arm: Node3D = get_node_or_null("LeftArm") as Node3D
@onready var _right_arm: Node3D = get_node_or_null("RightArm") as Node3D
@onready var _left_leg: Node3D = get_node_or_null("LeftLeg") as Node3D
@onready var _right_leg: Node3D = get_node_or_null("RightLeg") as Node3D
@onready var _left_arm_mesh: MeshInstance3D = get_node_or_null("LeftArm/Mesh") as MeshInstance3D
@onready var _right_arm_mesh: MeshInstance3D = get_node_or_null("RightArm/Mesh") as MeshInstance3D
@onready var _left_leg_mesh: MeshInstance3D = get_node_or_null("LeftLeg/Mesh") as MeshInstance3D
@onready var _right_leg_mesh: MeshInstance3D = get_node_or_null("RightLeg/Mesh") as MeshInstance3D

var _target:       Vector3 = Vector3.ZERO
var _wait_timer:   float   = 0.0
var _is_waiting:   bool    = false
var _desired_move: Vector3 = Vector3.ZERO   # bridge between AI logic and physics
var _blocked_time: float = 0.0
var obstacle_recoveries: int = 0
var _reaction_director := PARK_REACTIONS.new()
var reaction_count: int = 0
var _reaction_event: StringName = &""
var _reaction_origin: Vector3 = Vector3.ZERO
var _reaction_delay: float = 0.0
var _reaction_timer: float = 0.0
var _reaction_time: float = 0.0
var _body_rest_rotation: Vector3
var _pants_rest_rotation: Vector3
var _head_rest_rotation: Vector3
var _left_arm_rest_rotation: Vector3
var _right_arm_rest_rotation: Vector3
var _left_leg_rest_rotation: Vector3
var _right_leg_rest_rotation: Vector3
var _head_rest_position: Vector3
var _body_rest_transform: Transform3D
var _pants_rest_transform: Transform3D
var _head_rest_transform: Transform3D
var _left_arm_rest_transform: Transform3D
var _right_arm_rest_transform: Transform3D
var _left_leg_rest_transform: Transform3D
var _right_leg_rest_transform: Transform3D
var _presentation_phase: float = 0.0
var _presentation_time: float = 0.0
var _has_presentation_limbs: bool = false
var _startle_cooldown: float = 0.0
var startle_count: int = 0
var _capture_reaction_variant: int = 0

func _ready() -> void:
	add_to_group("visitors")
	# Apply per-instance colours to clothing meshes.
	# New materials so tinting one visitor never affects other instances.
	var shirt_mat := StandardMaterial3D.new()
	shirt_mat.albedo_color = shirt_color
	_body.set_surface_override_material(0, shirt_mat)

	var pants_mat := StandardMaterial3D.new()
	pants_mat.albedo_color = pants_color
	_pants.set_surface_override_material(0, pants_mat)
	_has_presentation_limbs = (
		_left_arm != null
		and _right_arm != null
		and _left_leg != null
		and _right_leg != null
		and _left_arm_mesh != null
		and _right_arm_mesh != null
		and _left_leg_mesh != null
		and _right_leg_mesh != null
	)
	if _has_presentation_limbs:
		_left_arm_mesh.set_surface_override_material(0, shirt_mat)
		_right_arm_mesh.set_surface_override_material(0, shirt_mat)
		_left_leg_mesh.set_surface_override_material(0, pants_mat)
		_right_leg_mesh.set_surface_override_material(0, pants_mat)
	_capture_presentation_rest_pose()
	_presentation_phase = fmod(
		float(get_instance_id() % 10007) * PRESENTATION_PHASE_STEP,
		TAU
	)

	_pick_new_target()

func _process(delta: float) -> void:
	_desired_move = Vector3.ZERO
	_startle_cooldown = maxf(_startle_cooldown - delta, 0.0)
	if _update_park_reaction(delta):
		return

	if _is_waiting:
		_wait_timer -= delta
		if _wait_timer <= 0.0:
			_is_waiting = false
			_pick_new_target()
		_update_locomotion_presentation(delta)
		return

	var to_target := _target - global_position
	to_target.y = 0.0

	if to_target.length() < 0.5:
		_is_waiting = true
		_wait_timer = randf_range(2.0, 6.0)
		_update_locomotion_presentation(delta)
		return

	var dir := to_target.normalized()
	_desired_move = dir * walk_speed

	# Build a flat look target to prevent the visitor from tilting up/down.
	var look_target := Vector3(global_position.x + dir.x, global_position.y, global_position.z + dir.z)
	look_at(look_target, Vector3.UP)
	_update_locomotion_presentation(delta)

func _capture_presentation_rest_pose() -> void:
	_body_rest_transform = _body.transform
	_pants_rest_transform = _pants.transform
	_head_rest_transform = _head.transform
	_body_rest_rotation = _body.rotation
	_pants_rest_rotation = _pants.rotation
	_head_rest_rotation = _head.rotation
	_head_rest_position = _head.position
	if not _has_presentation_limbs:
		return
	_left_arm_rest_transform = _left_arm.transform
	_right_arm_rest_transform = _right_arm.transform
	_left_leg_rest_transform = _left_leg.transform
	_right_leg_rest_transform = _right_leg.transform
	_left_arm_rest_rotation = _left_arm.rotation
	_right_arm_rest_rotation = _right_arm.rotation
	_left_leg_rest_rotation = _left_leg.rotation
	_right_leg_rest_rotation = _right_leg.rotation

func _restore_presentation_pose() -> void:
	_body.transform = _body_rest_transform
	_pants.transform = _pants_rest_transform
	_head.transform = _head_rest_transform
	if not _has_presentation_limbs:
		return
	_left_arm.transform = _left_arm_rest_transform
	_right_arm.transform = _right_arm_rest_transform
	_left_leg.transform = _left_leg_rest_transform
	_right_leg.transform = _right_leg_rest_transform

func _update_locomotion_presentation(delta: float) -> void:
	# Rebuild the lightweight pose from immutable rest transforms every frame.
	# This is allocation-free and prevents gait/idle offsets leaking into reactions.
	_restore_presentation_pose()
	_presentation_time += delta
	var intended_speed := Vector2(_desired_move.x, _desired_move.z).length()
	if intended_speed > 0.05:
		var speed_ratio := clampf(intended_speed / maxf(walk_speed, 0.01), 0.0, 1.5)
		var gait_phase := _presentation_time * WALK_CADENCE * speed_ratio + _presentation_phase
		var stride := sin(gait_phase)
		var bounce := absf(sin(gait_phase * 2.0)) * 0.018 * speed_ratio
		if _has_presentation_limbs:
			_left_arm.rotation.x = _left_arm_rest_rotation.x + stride * 0.48
			_right_arm.rotation.x = _right_arm_rest_rotation.x - stride * 0.48
			_left_leg.rotation.x = _left_leg_rest_rotation.x - stride * 0.42
			_right_leg.rotation.x = _right_leg_rest_rotation.x + stride * 0.42
		_body.position.y = _body_rest_transform.origin.y + bounce
		_pants.position.y = _pants_rest_transform.origin.y + bounce * 0.8
		_head.position.y = _head_rest_transform.origin.y + bounce * 1.2
		_body.rotation.x = _body_rest_rotation.x - 0.035 * speed_ratio
		_body.rotation.z = _body_rest_rotation.z + stride * 0.025
		return

	var idle_phase := _presentation_time * IDLE_CADENCE + _presentation_phase
	var idle_sway := sin(idle_phase)
	_body.rotation.z = _body_rest_rotation.z + idle_sway * 0.012
	_head.position.y = _head_rest_position.y + sin(idle_phase * 0.75) * 0.006
	if _has_presentation_limbs:
		_left_arm.rotation.x = _left_arm_rest_rotation.x + idle_sway * 0.025
		_right_arm.rotation.x = _right_arm_rest_rotation.x - idle_sway * 0.025

func react_to_park_event(event_name: StringName, origin: Vector3) -> bool:
	var visitor_position := global_position if is_inside_tree() else position
	var distance := visitor_position.distance_to(origin)
	var max_distance := 0.0
	var duration := 0.0
	match event_name:
		PARK_REACTIONS.EVENT_GRAB_WINDUP:
			max_distance = 8.0
			duration = 0.8
		PARK_REACTIONS.EVENT_GRAB_MISSED:
			max_distance = 12.0
			duration = 1.25
		PARK_REACTIONS.EVENT_PLAYER_CAUGHT:
			max_distance = 13.0
			duration = 1.7
			_capture_reaction_variant = get_instance_id() % 3
		PARK_REACTIONS.EVENT_FOOD_FRENZY:
			max_distance = 14.0
			duration = 1.8
		PARK_REACTIONS.EVENT_FESTIVAL_FRENZY:
			max_distance = 24.0
			duration = 2.5
		PARK_REACTIONS.EVENT_SWING_CHAOS:
			max_distance = 12.0
			duration = 1.8
		PARK_REACTIONS.EVENT_WATER_SPLASH:
			max_distance = 15.0
			duration = 1.9
		PARK_REACTIONS.EVENT_SPRINKLER_BURST:
			max_distance = 20.0
			duration = 2.2
		PARK_REACTIONS.EVENT_PLAYER_EXPOSED:
			max_distance = 32.0
			duration = 2.4
		PARK_REACTIONS.EVENT_VISITOR_STARTLED:
			max_distance = 2.0
			duration = 1.2
		_:
			return false
	if distance > max_distance:
		return false

	_reaction_event = event_name
	_reaction_origin = origin
	_reaction_delay = distance * 0.025
	_reaction_timer = duration
	_reaction_time = 0.0
	_desired_move = Vector3.ZERO
	if _body != null:
		_restore_presentation_pose()
	reaction_count += 1
	return true

func _update_park_reaction(delta: float) -> bool:
	if _reaction_event.is_empty():
		return false
	_reaction_time += delta
	if _reaction_delay > 0.0:
		_reaction_delay = maxf(_reaction_delay - delta, 0.0)
		return true

	_reaction_timer = maxf(_reaction_timer - delta, 0.0)
	if _reaction_timer <= 0.0:
		_reaction_event = &""
		_restore_presentation_pose()
		_pick_new_target()
		return false
	_restore_presentation_pose()

	if _reaction_event == PARK_REACTIONS.EVENT_PLAYER_CAUGHT:
		_update_captured_reaction()
		return true

	var to_event := _reaction_origin - global_position
	to_event.y = 0.0
	if to_event.length_squared() > 0.001:
		look_at(Vector3(_reaction_origin.x, global_position.y, _reaction_origin.z), Vector3.UP)
	var is_startled := _reaction_event == PARK_REACTIONS.EVENT_VISITOR_STARTLED
	var bounce_speed := (
		14.0 if _reaction_event == PARK_REACTIONS.EVENT_GRAB_WINDUP
		else (26.0 if is_startled else 20.0)
	)
	var bounce := absf(sin(_reaction_time * bounce_speed))
	var reaction_wave := sin(_reaction_time * bounce_speed)
	_head.position.y = _head_rest_position.y + bounce * (0.12 if is_startled else 0.07)
	_body.rotation.z = _body_rest_rotation.z + reaction_wave * (0.14 if is_startled else 0.08)
	if is_startled:
		_body.rotation.x = _body_rest_rotation.x - bounce * 0.22
		_pants.rotation.x = _pants_rest_rotation.x - bounce * 0.08
		if not _has_presentation_limbs:
			return true
		_left_arm.rotation.z = _left_arm_rest_rotation.z - 1.05 - bounce * 0.24
		_right_arm.rotation.z = _right_arm_rest_rotation.z + 1.05 + bounce * 0.24
		_left_arm.rotation.x = _left_arm_rest_rotation.x + reaction_wave * 0.18
		_right_arm.rotation.x = _right_arm_rest_rotation.x - reaction_wave * 0.18
		_left_leg.rotation.x = _left_leg_rest_rotation.x - reaction_wave * 0.12
		_right_leg.rotation.x = _right_leg_rest_rotation.x + reaction_wave * 0.12
	else:
		if not _has_presentation_limbs:
			return true
		_left_arm.rotation.x = _left_arm_rest_rotation.x - 0.48 - bounce * 0.18
		_right_arm.rotation.x = _right_arm_rest_rotation.x - 0.48 - bounce * 0.18
		_left_arm.rotation.z = _left_arm_rest_rotation.z - 0.18 - reaction_wave * 0.08
		_right_arm.rotation.z = _right_arm_rest_rotation.z + 0.18 + reaction_wave * 0.08
	return true

func _update_captured_reaction() -> void:
	var to_event := _reaction_origin - global_position
	to_event.y = 0.0
	if to_event.length_squared() > 0.001:
		look_at(Vector3(_reaction_origin.x, global_position.y, _reaction_origin.z), Vector3.UP)
	match _capture_reaction_variant:
		0:  # cheer
			var bounce := absf(sin(_reaction_time * 24.0))
			var cheer_wave := sin(_reaction_time * 24.0)
			_head.position.y = _head_rest_position.y + bounce * 0.11
			_body.position.y = _body_rest_transform.origin.y + bounce * 0.035
			_pants.position.y = _pants_rest_transform.origin.y + bounce * 0.025
			_body.rotation.z = _body_rest_rotation.z + cheer_wave * 0.12
			_body.rotation.x = _body_rest_rotation.x - bounce * 0.10
			if _has_presentation_limbs:
				_left_arm.rotation.z = _left_arm_rest_rotation.z - 2.55 - bounce * 0.18
				_right_arm.rotation.z = _right_arm_rest_rotation.z + 2.55 + bounce * 0.18
				_left_leg.rotation.x = _left_leg_rest_rotation.x - cheer_wave * 0.10
				_right_leg.rotation.x = _right_leg_rest_rotation.x + cheer_wave * 0.10
		1:  # gasp
			var lean := minf(_reaction_time / 0.18, 1.0) * 0.16
			var t := maxf(_reaction_time - 0.18, 0.0)
			_body.rotation.x = _body_rest_rotation.x + lean
			_pants.rotation.x = _pants_rest_rotation.x + lean * 0.45
			_head.position.y = _head_rest_position.y - absf(sin(t * 11.0)) * 0.04
			_body.rotation.z = _body_rest_rotation.z + sin(t * 11.0) * 0.07
			if _has_presentation_limbs:
				_left_arm.rotation.x = _left_arm_rest_rotation.x - 1.18
				_right_arm.rotation.x = _right_arm_rest_rotation.x - 1.18
				_left_arm.rotation.z = _left_arm_rest_rotation.z + 0.25
				_right_arm.rotation.z = _right_arm_rest_rotation.z - 0.25
		2:  # confused
			var sway := sin(_reaction_time * 7.0) * 0.06
			_body.rotation.z = _body_rest_rotation.z + sway
			_head.position.y = _head_rest_position.y + absf(sway) * 0.04
			_head.rotation.z = _head_rest_rotation.z - sway * 2.2
			if _has_presentation_limbs:
				_left_arm.rotation.z = _left_arm_rest_rotation.z - 0.82 - sway * 2.0
				_left_arm.rotation.x = _left_arm_rest_rotation.x - 0.32
				_right_arm.rotation.z = _right_arm_rest_rotation.z + 0.12 + sway

func receive_pigeon_flyby(pigeon: Node) -> bool:
	if _startle_cooldown > 0.0 or not _reaction_event.is_empty():
		return false
	var visitor_position := global_position if is_inside_tree() else position
	var origin := visitor_position
	if pigeon is Node3D:
		var pigeon_node := pigeon as Node3D
		origin = pigeon_node.global_position if pigeon_node.is_inside_tree() else pigeon_node.position
	if not react_to_park_event(PARK_REACTIONS.EVENT_VISITOR_STARTLED, origin):
		return false
	_startle_cooldown = 15.0
	startle_count += 1
	if is_inside_tree():
		_reaction_director.broadcast_chain(
			get_tree(), PARK_REACTIONS.EVENT_VISITOR_STARTLED, visitor_position, 1, 1, self
		)
	visitor_startled.emit(visitor_position)
	return true

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
