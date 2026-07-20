extends Node3D

@export var speed: float = 1.2
@export var flee_speed: float = 2.2
@export var wander_radius: float = 8.0
@export var flee_distance: float = 4.5

const PECK_FORWARD: float = 0.12
const PECK_DROP: float = 0.13
const PECK_DURATION: float = 0.55
const PECK_STRIKE_FRAC: float = 0.40
const HEAD_BOB_Z: float = 0.05

@onready var head: MeshInstance3D = $PigeonVisual/Head
@onready var beak: MeshInstance3D = $PigeonVisual/Beak
@onready var ranger: Node3D = get_node_or_null("../Ranger")

var direction: Vector3 = Vector3.FORWARD
var time_until_change: float = 0.0
var is_pausing: bool = false
var is_fleeing: bool = false

var head_y_rest: float = 0.0
var beak_y_rest: float = 0.0
var head_z_rest: float = 0.0
var beak_z_rest: float = 0.0

var is_pecking: bool = false
var peck_time: float = 0.0
var next_peck_timer: float = 0.0
var bob_time: float = 0.0

func _ready() -> void:
	head_y_rest = head.position.y
	beak_y_rest = beak.position.y
	head_z_rest = head.position.z
	beak_z_rest = beak.position.z
	next_peck_timer = randf_range(0.5, 1.5)
	choose_new_behavior()

func _process(delta: float) -> void:
	_update_peck(delta)

	if is_instance_valid(ranger):
		is_fleeing = global_position.distance_to(ranger.global_position) < flee_distance
	else:
		is_fleeing = false

	if is_fleeing:
		_do_flee(delta)
	else:
		_do_wander(delta)

	_update_walk_bob(delta)

func _do_wander(delta: float) -> void:
	var is_outside_bounds: bool = (
		absf(position.x) > wander_radius
		or absf(position.z) > wander_radius
	)
	if is_outside_bounds:
		is_pausing = false
		direction = Vector3(-position.x, 0.0, -position.z).normalized()
		if direction.length() > 0.001:
			look_at(global_position - direction, Vector3.UP)
	else:
		time_until_change -= delta
		if time_until_change <= 0.0:
			choose_new_behavior()

	if is_pausing:
		_idle_peck(delta)
	else:
		position += direction * speed * delta

func _do_flee(delta: float) -> void:
	if not is_instance_valid(ranger):
		return
	var flee_dir := (global_position - ranger.global_position)
	flee_dir.y = 0.0
	if flee_dir.length() > 0.001:
		flee_dir = flee_dir.normalized()
		position += flee_dir * flee_speed * delta
		look_at(global_position - flee_dir, Vector3.UP)
		direction = flee_dir
	is_pausing = false

func _idle_peck(delta: float) -> void:
	if is_pecking:
		return
	next_peck_timer -= delta
	if next_peck_timer <= 0.0:
		is_pecking = true
		peck_time = 0.0
		next_peck_timer = randf_range(0.8, 2.5)

func _update_peck(delta: float) -> void:
	if not is_pecking:
		return
	peck_time += delta
	var t: float = peck_time / PECK_DURATION
	var z_off: float
	var y_off: float
	if t < PECK_STRIKE_FRAC:
		var st: float = t / PECK_STRIKE_FRAC
		z_off = sin(st * PI * 0.5) * PECK_FORWARD
		var yst: float = clampf((st - 0.2) / 0.8, 0.0, 1.0)
		y_off = sin(yst * PI * 0.5) * PECK_DROP
	else:
		var rt: float = (t - PECK_STRIKE_FRAC) / (1.0 - PECK_STRIKE_FRAC)
		var recovery_weight: float = 1.0 - sin(rt * PI * 0.5)
		z_off = recovery_weight * PECK_FORWARD
		y_off = recovery_weight * PECK_DROP
	head.position.z = head_z_rest + z_off
	head.position.y = head_y_rest - y_off
	beak.position.z = beak_z_rest + z_off
	beak.position.y = beak_y_rest - y_off
	if peck_time >= PECK_DURATION:
		is_pecking = false
		head.position.z = head_z_rest
		head.position.y = head_y_rest
		beak.position.z = beak_z_rest
		beak.position.y = beak_y_rest

func _update_walk_bob(delta: float) -> void:
	if is_pecking:
		return
	var is_moving: bool = not is_pausing
	if is_moving:
		var move_speed := flee_speed if is_fleeing else speed
		bob_time += delta * move_speed * 5.0
		var bob := sin(bob_time) * HEAD_BOB_Z
		head.position.z = head_z_rest + bob
		beak.position.z = beak_z_rest + bob
	else:
		head.position.z = lerp(head.position.z, head_z_rest, delta * 10.0)
		beak.position.z = lerp(beak.position.z, beak_z_rest, delta * 10.0)

func choose_new_behavior() -> void:
	is_pausing = randf() < 0.35
	if is_pausing:
		time_until_change = randf_range(0.7, 2.0)
		next_peck_timer = randf_range(0.2, 0.8)
	else:
		var angle: float = randf_range(0.0, TAU)
		direction = Vector3(sin(angle), 0.0, cos(angle))
		time_until_change = randf_range(1.0, 3.0)
		look_at(global_position - direction, Vector3.UP)
