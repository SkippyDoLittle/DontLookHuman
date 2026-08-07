# park_visitor.gd — Attached to each ParkVisitor node (or Visitor.tscn instance).
# Human background NPCs that wander and pause. No interaction with the suspicion system.

extends CharacterBody3D

const PARK_REACTIONS = preload("res://park_reaction_director.gd")

signal visitor_startled(origin: Vector3)

const PIGEON_STARTLE_RADIUS: float = 1.5

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
var reaction_count: int = 0
var _reaction_event: StringName = &""
var _reaction_origin: Vector3 = Vector3.ZERO
var _reaction_delay: float = 0.0
var _reaction_timer: float = 0.0
var _reaction_time: float = 0.0
var _body_rest_rotation: Vector3
var _head_rest_position: Vector3
var _startle_cooldown: float = 0.0
var startle_count: int = 0
var _capture_reaction_variant: int = 0

func _ready() -> void:
	add_to_group("visitors")
	# Apply per-instance colours to clothing meshes.
	# New materials so tinting one visitor never affects other instances.
	var shirt_mat := StandardMaterial3D.new()
	shirt_mat.albedo_color = shirt_color
	$VisitorBody.set_surface_override_material(0, shirt_mat)

	var pants_mat := StandardMaterial3D.new()
	pants_mat.albedo_color = pants_color
	$VisitorPants.set_surface_override_material(0, pants_mat)
	_body_rest_rotation = $VisitorBody.rotation
	_head_rest_position = $VisitorHead.position

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

func react_to_park_event(event_name: StringName, origin: Vector3) -> bool:
	var distance := global_position.distance_to(origin)
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
		$VisitorBody.rotation = _body_rest_rotation
		$VisitorHead.position = _head_rest_position
		_pick_new_target()
		return false

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
	$VisitorHead.position.y = _head_rest_position.y + bounce * (0.12 if is_startled else 0.07)
	$VisitorBody.rotation.z = _body_rest_rotation.z + sin(_reaction_time * bounce_speed) * (0.14 if is_startled else 0.08)
	if is_startled:
		$VisitorBody.rotation.x = _body_rest_rotation.x - bounce * 0.22
	return true

func _update_captured_reaction() -> void:
	var to_event := _reaction_origin - global_position
	to_event.y = 0.0
	if to_event.length_squared() > 0.001:
		look_at(Vector3(_reaction_origin.x, global_position.y, _reaction_origin.z), Vector3.UP)
	match _capture_reaction_variant:
		0:  # cheer
			var bounce := absf(sin(_reaction_time * 24.0))
			$VisitorHead.position.y = _head_rest_position.y + bounce * 0.11
			$VisitorBody.rotation.z = _body_rest_rotation.z + sin(_reaction_time * 24.0) * 0.12
			$VisitorBody.rotation.x = _body_rest_rotation.x - bounce * 0.10
		1:  # gasp
			var lean := minf(_reaction_time / 0.18, 1.0) * 0.16
			var t := maxf(_reaction_time - 0.18, 0.0)
			$VisitorBody.rotation.x = _body_rest_rotation.x + lean
			$VisitorHead.position.y = _head_rest_position.y - absf(sin(t * 11.0)) * 0.04
			$VisitorBody.rotation.z = _body_rest_rotation.z + sin(t * 11.0) * 0.07
		2:  # confused
			var sway := sin(_reaction_time * 7.0) * 0.06
			$VisitorBody.rotation.z = _body_rest_rotation.z + sway
			$VisitorHead.position.y = _head_rest_position.y + absf(sway) * 0.04

func receive_pigeon_flyby(pigeon: Node) -> bool:
	if _startle_cooldown > 0.0 or not _reaction_event.is_empty():
		return false
	var origin := (pigeon as Node3D).global_position if pigeon is Node3D else global_position
	if not react_to_park_event(PARK_REACTIONS.EVENT_VISITOR_STARTLED, origin):
		return false
	_startle_cooldown = 15.0
	startle_count += 1
	PARK_REACTIONS.new().broadcast_chain(
		get_tree(), PARK_REACTIONS.EVENT_VISITOR_STARTLED, global_position, 1, 1, self
	)
	visitor_startled.emit(global_position)
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
