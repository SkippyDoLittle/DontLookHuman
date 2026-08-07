# npc_animal.gd — Attached to reusable and procedurally spawned pigeon NPCs.
# Background pigeon NPCs that wander, pause-and-peck, and flee from nearby rangers.
# Their presence near the player reduces "Acting alone" suspicion.

extends CharacterBody3D

const PARK_REACTIONS = preload("res://park_reaction_director.gd")

signal mimic_peck_started(origin: Vector3)
signal mistaken_capture_started(carrier: Node3D)
signal mistaken_capture_released(origin: Vector3)

@export var speed:          float = 1.2    # normal wander speed (matches player walk speed)
@export var flee_speed:     float = 2.2    # speed when running from the ranger
@export var wander_radius:  float = 8.0   # max distance from park centre
@export var flee_distance:  float = 4.5    # ranger must be closer than this to trigger flee

# Peck animation parameters — identical to player.gd values for visual consistency.
const PECK_FORWARD:     float = 0.12
const PECK_DROP:        float = 0.13
const PECK_DURATION:    float = 0.55
const PECK_STRIKE_FRAC: float = 0.40
const HEAD_BOB_Z:       float = 0.05   # slightly less than player (0.06) for subtle distinction

@onready var head:   MeshInstance3D = $PigeonVisual/Head
@onready var beak:   MeshInstance3D = $PigeonVisual/Beak
@onready var body:   MeshInstance3D = $PigeonVisual/Body
@onready var pigeon_visual: Node3D = $PigeonVisual

enum ReactionMode { NONE, WATCH, PANIC, SWARM }

var ranger: Node3D = null   # closest valid ranger, refreshed each frame

var direction:         Vector3 = Vector3.FORWARD
var time_until_change: float   = 0.0
var is_pausing:        bool    = false
var is_fleeing:        bool    = false

# Head/beak rest positions — recorded in _ready(); animations offset from these.
var head_y_rest: float = 0.0
var beak_y_rest: float = 0.0
var head_z_rest: float = 0.0
var beak_z_rest: float = 0.0

var is_pecking:        bool  = false
var peck_time:         float = 0.0
var next_peck_timer:   float = 0.0   # countdown to next automatic peck while paused
var bob_time:          float = 0.0
var _prev_sin:         float = 0.0   # previous frame sin value — for footstep zero-crossing

var _desired_move: Vector3 = Vector3.ZERO   # set by AI, consumed by _physics_process
var _peck_sfx:  AudioStreamPlayer3D         # 3D positional audio — fades with distance
var _step_sfx:  AudioStreamPlayer3D
var _reaction_mode: ReactionMode = ReactionMode.NONE
var _reaction_origin: Vector3 = Vector3.ZERO
var _reaction_delay: float = 0.0
var _reaction_timer: float = 0.0
var _reaction_time: float = 0.0
var _reaction_target: Vector3 = Vector3.ZERO
var reaction_count: int = 0
var _body_rest_rotation: Vector3
var _body_rest_scale: Vector3
var _mimic_pending: bool = false
var _mimic_active: bool = false
var _mimic_delay: float = 0.0
var _mimic_origin: Vector3 = Vector3.ZERO
var mimic_peck_count: int = 0
var _mistaken_capture_active: bool = false
var _mistaken_capture_timer: float = 0.0
var _mistaken_capture_time: float = 0.0
var _mistaken_carrier: Node3D
var _mistaken_collision_layer: int = 0
var _mistaken_collision_mask: int = 0
var _mistaken_visual_rest_rotation: Vector3
var _mistaken_left_wing: MeshInstance3D
var _mistaken_right_wing: MeshInstance3D
var mistaken_capture_count: int = 0

func _ready() -> void:
	add_to_group("pigeons")

	head_y_rest = head.position.y
	beak_y_rest = beak.position.y
	head_z_rest = head.position.z
	beak_z_rest = beak.position.z
	_body_rest_rotation = body.rotation
	_body_rest_scale = body.scale
	_mistaken_visual_rest_rotation = pigeon_visual.rotation

	next_peck_timer = randf_range(0.5, 1.5)
	choose_new_behavior()

	# AudioStreamPlayer3D is attached to this NPC's body so Godot automatically
	# fades the sound as the player moves away — nearby pigeons are loud, distant ones silent.
	_peck_sfx = AudioStreamPlayer3D.new()
	_peck_sfx.stream       = SoundManager.npc_peck_stream()
	_peck_sfx.volume_db    = 4.0
	_peck_sfx.unit_size    = 2.0    # full volume within 2 units, fades beyond
	_peck_sfx.max_distance = 7.0
	_peck_sfx.bus          = "SFX"
	add_child(_peck_sfx)

	_step_sfx = AudioStreamPlayer3D.new()
	_step_sfx.stream       = SoundManager.npc_step_stream()
	_step_sfx.volume_db    = 2.0
	_step_sfx.unit_size    = 2.0
	_step_sfx.max_distance = 6.0
	_step_sfx.bus          = "SFX"
	add_child(_step_sfx)

func _process(delta: float) -> void:
	_desired_move = Vector3.ZERO
	if _update_mistaken_capture(delta):
		return
	_update_peck(delta)
	ranger = _find_nearest_ranger()
	if _update_park_reaction(delta):
		_update_walk_bob(delta)
		return

	if is_instance_valid(ranger):
		is_fleeing = global_position.distance_to(ranger.global_position) < flee_distance
	else:
		is_fleeing = false

	if is_fleeing:
		_cancel_mimic_peck()
		_do_flee(delta)
	elif _update_mimic_peck(delta):
		pass
	else:
		_do_wander(delta)

	_update_walk_bob(delta)

func react_to_park_event(event_name: StringName, origin: Vector3) -> bool:
	if _mistaken_capture_active:
		return false
	var distance := global_position.distance_to(origin)
	var next_mode := ReactionMode.NONE
	var duration := 0.0
	var max_distance := 0.0
	match event_name:
		PARK_REACTIONS.EVENT_GRAB_WINDUP:
			next_mode = ReactionMode.WATCH
			# Covers the slowest campaign wind-up plus the full lunge. Without this
			# buffer the pigeon resumes flee behavior just before a possible miss.
			duration = 1.1
			max_distance = 7.0
		PARK_REACTIONS.EVENT_GRAB_MISSED:
			next_mode = ReactionMode.PANIC
			duration = 1.45
			max_distance = 10.0
		PARK_REACTIONS.EVENT_PLAYER_CAUGHT:
			next_mode = ReactionMode.PANIC
			duration = 1.8
			max_distance = 11.0
		PARK_REACTIONS.EVENT_FOOD_FRENZY:
			next_mode = ReactionMode.SWARM
			duration = 2.7
			max_distance = 16.0
		PARK_REACTIONS.EVENT_FESTIVAL_FRENZY:
			next_mode = ReactionMode.SWARM
			duration = 3.4
			max_distance = 24.0
		PARK_REACTIONS.EVENT_SWING_CHAOS:
			next_mode = ReactionMode.PANIC
			duration = 1.65
			max_distance = 11.0
		PARK_REACTIONS.EVENT_WATER_SPLASH:
			next_mode = ReactionMode.PANIC
			duration = 1.9
			max_distance = 14.0
		PARK_REACTIONS.EVENT_SPRINKLER_BURST:
			next_mode = ReactionMode.PANIC
			duration = 2.15
			max_distance = 18.0
		PARK_REACTIONS.EVENT_PLAYER_EXPOSED:
			next_mode = ReactionMode.PANIC
			duration = 2.35
			max_distance = 36.0
		_:
			return false
	if distance > max_distance:
		return false

	_cancel_mimic_peck()
	_reaction_mode = next_mode
	_reaction_origin = origin
	_reaction_delay = distance * 0.035 if next_mode in [ReactionMode.PANIC, ReactionMode.SWARM] else 0.0
	_reaction_timer = duration
	_reaction_time = 0.0
	var ring_angle := float(get_instance_id() % 19) / 19.0 * TAU
	var ring_radius := 0.55 + float(get_instance_id() % 5) * 0.16
	_reaction_target = origin + Vector3(sin(ring_angle), 0.0, cos(ring_angle)) * ring_radius
	reaction_count += 1
	is_pecking = false
	return true

func can_mimic_player_peck(origin: Vector3) -> bool:
	if (
		_mistaken_capture_active
		or _reaction_mode != ReactionMode.NONE
		or _mimic_pending
		or _mimic_active
		or is_pecking
	):
		return false
	if global_position.distance_to(origin) > 5.5:
		return false
	var nearest_ranger := _find_nearest_ranger()
	return (
		not is_instance_valid(nearest_ranger)
		or global_position.distance_to(nearest_ranger.global_position) >= flee_distance
	)

func request_mimic_peck(origin: Vector3, delay: float) -> bool:
	if not can_mimic_player_peck(origin):
		return false
	_mimic_pending = true
	_mimic_delay = maxf(delay, 0.0)
	_mimic_origin = origin
	is_pausing = true
	return true

func _update_mimic_peck(delta: float) -> bool:
	if _mimic_active:
		if is_pecking:
			is_pausing = true
			return true
		_mimic_active = false
		choose_new_behavior()
		return false
	if not _mimic_pending:
		return false

	is_pausing = true
	_desired_move = Vector3.ZERO
	var toward_player := _mimic_origin - global_position
	toward_player.y = 0.0
	if toward_player.length_squared() > 0.001:
		look_at(global_position - toward_player.normalized(), Vector3.UP)
	_mimic_delay = maxf(_mimic_delay - delta, 0.0)
	if _mimic_delay > 0.0:
		return true

	_mimic_pending = false
	_mimic_active = true
	is_pecking = true
	peck_time = 0.0
	mimic_peck_count += 1
	_peck_sfx.play()
	mimic_peck_started.emit(_mimic_origin)
	return true

func _cancel_mimic_peck() -> void:
	if not _mimic_pending and not _mimic_active:
		return
	_mimic_pending = false
	_mimic_delay = 0.0
	if _mimic_active:
		is_pecking = false
		peck_time = 0.0
		head.position = Vector3(head.position.x, head_y_rest, head_z_rest)
		beak.position = Vector3(beak.position.x, beak_y_rest, beak_z_rest)
	_mimic_active = false

func can_be_mistaken_target(origin: Vector3, radius: float) -> bool:
	if _mistaken_capture_active or _mimic_pending or _mimic_active or is_pecking:
		return false
	if _reaction_mode not in [ReactionMode.NONE, ReactionMode.WATCH]:
		return false
	return global_position.distance_to(origin) <= radius

func start_mistaken_capture(carrier: Node3D, duration: float) -> bool:
	if not is_instance_valid(carrier) or _mistaken_capture_active:
		return false
	if _reaction_mode not in [ReactionMode.NONE, ReactionMode.WATCH]:
		return false
	_cancel_mimic_peck()
	_reaction_mode = ReactionMode.NONE
	_reaction_delay = 0.0
	_reaction_timer = 0.0
	is_pecking = false
	peck_time = 0.0
	is_pausing = true
	is_fleeing = false
	_desired_move = Vector3.ZERO
	head.position = Vector3(head.position.x, head_y_rest, head_z_rest)
	beak.position = Vector3(beak.position.x, beak_y_rest, beak_z_rest)
	_ensure_mistaken_capture_wings()
	_mistaken_capture_active = true
	_mistaken_capture_timer = maxf(duration, 0.25)
	_mistaken_capture_time = 0.0
	_mistaken_carrier = carrier
	_mistaken_collision_layer = collision_layer
	_mistaken_collision_mask = collision_mask
	collision_layer = 0
	collision_mask = 0
	mistaken_capture_count += 1
	_mistaken_left_wing.visible = true
	_mistaken_right_wing.visible = true
	mistaken_capture_started.emit(carrier)
	return true

func _update_mistaken_capture(delta: float) -> bool:
	if not _mistaken_capture_active:
		return false
	if not is_instance_valid(_mistaken_carrier):
		_finish_mistaken_capture(Vector3.ZERO, false)
		return false

	_mistaken_capture_timer = maxf(_mistaken_capture_timer - delta, 0.0)
	_mistaken_capture_time += delta
	velocity = Vector3.ZERO
	global_position = (
		_mistaken_carrier.global_position
		+ Vector3.UP * 0.92
		- _mistaken_carrier.global_transform.basis.z * 0.22
	)
	global_rotation.y = _mistaken_carrier.global_rotation.y
	var flutter := sin(_mistaken_capture_time * 32.0)
	var kick := sin(_mistaken_capture_time * 21.0 + 0.8)
	pigeon_visual.rotation.z = _mistaken_visual_rest_rotation.z + flutter * 0.32
	pigeon_visual.rotation.x = _mistaken_visual_rest_rotation.x + kick * 0.11
	body.scale = _body_rest_scale * (1.0 + absf(flutter) * 0.1)
	_mistaken_left_wing.rotation.z = 0.18 + absf(flutter) * 1.18
	_mistaken_right_wing.rotation.z = -0.18 - absf(flutter) * 1.18
	if _mistaken_capture_timer <= 0.0:
		_finish_mistaken_capture(_mistaken_carrier.global_position, true)
		return false
	return true

func _finish_mistaken_capture(origin: Vector3, panic_after_release: bool) -> void:
	var carrier := _mistaken_carrier
	_mistaken_capture_active = false
	_mistaken_capture_timer = 0.0
	_mistaken_capture_time = 0.0
	_mistaken_carrier = null
	collision_layer = _mistaken_collision_layer
	collision_mask = _mistaken_collision_mask
	pigeon_visual.rotation = _mistaken_visual_rest_rotation
	body.rotation = _body_rest_rotation
	body.scale = _body_rest_scale
	_mistaken_left_wing.visible = false
	_mistaken_right_wing.visible = false
	if is_instance_valid(carrier):
		var release_side := -1.0 if get_instance_id() % 2 == 0 else 1.0
		global_position = (
			carrier.global_position
			+ carrier.global_transform.basis.x * release_side * 0.65
			- carrier.global_transform.basis.z * 0.2
			+ Vector3.UP * 0.475
		)
	if panic_after_release:
		react_to_park_event(PARK_REACTIONS.EVENT_GRAB_MISSED, origin)
	else:
		choose_new_behavior()
	mistaken_capture_released.emit(origin)

func _ensure_mistaken_capture_wings() -> void:
	if _mistaken_left_wing != null and _mistaken_right_wing != null:
		return
	_mistaken_left_wing = _create_mistaken_capture_wing("MistakenLeftWing", -0.2, 0.18)
	_mistaken_right_wing = _create_mistaken_capture_wing("MistakenRightWing", 0.2, -0.18)

func _create_mistaken_capture_wing(
	wing_name: String,
	x_position: float,
	z_rotation: float
) -> MeshInstance3D:
	var wing := MeshInstance3D.new()
	wing.name = wing_name
	wing.position = Vector3(x_position, 0.0, -0.01)
	wing.rotation.z = z_rotation
	wing.visible = false
	var wing_mesh := BoxMesh.new()
	wing_mesh.size = Vector3(0.15, 0.04, 0.3)
	wing.mesh = wing_mesh
	var wing_material := StandardMaterial3D.new()
	wing_material.albedo_color = Color(0.4, 0.46667, 0.53333, 1.0)
	wing.set_surface_override_material(0, wing_material)
	pigeon_visual.add_child(wing)
	return wing

func _update_park_reaction(delta: float) -> bool:
	if _reaction_mode == ReactionMode.NONE:
		return false
	_reaction_time += delta
	if _reaction_delay > 0.0:
		_reaction_delay = maxf(_reaction_delay - delta, 0.0)
		_watch_reaction()
		return true

	_reaction_timer = maxf(_reaction_timer - delta, 0.0)
	if _reaction_timer <= 0.0:
		_finish_park_reaction()
		return false

	match _reaction_mode:
		ReactionMode.WATCH:
			_watch_reaction()
		ReactionMode.PANIC:
			_panic_reaction()
		ReactionMode.SWARM:
			_swarm_reaction()
	return true

func _watch_reaction() -> void:
	is_pausing = true
	is_fleeing = false
	_desired_move = Vector3.ZERO
	var to_event := _reaction_origin - global_position
	to_event.y = 0.0
	if to_event.length_squared() > 0.001:
		look_at(global_position - to_event.normalized(), Vector3.UP)
	head.position.y = head_y_rest + 0.045
	beak.position.y = beak_y_rest + 0.045
	body.scale = _body_rest_scale * (1.0 + sin(_reaction_time * 18.0) * 0.035)

func _panic_reaction() -> void:
	is_pausing = false
	is_fleeing = true
	var away := global_position - _reaction_origin
	away.y = 0.0
	if away.length_squared() < 0.001:
		away = direction
	away = away.normalized()
	direction = away
	_desired_move = away * flee_speed * 1.35
	look_at(global_position - away, Vector3.UP)
	body.rotation.z = _body_rest_rotation.z + sin(_reaction_time * 26.0) * 0.13
	body.scale = _body_rest_scale * (1.0 + absf(sin(_reaction_time * 20.0)) * 0.08)

func _swarm_reaction() -> void:
	is_fleeing = false
	var toward_food := _reaction_target - global_position
	toward_food.y = 0.0
	if toward_food.length() > 0.42:
		is_pausing = false
		direction = toward_food.normalized()
		_desired_move = direction * flee_speed * 1.15
		look_at(global_position - direction, Vector3.UP)
		body.rotation.z = _body_rest_rotation.z + sin(_reaction_time * 22.0) * 0.08
	else:
		is_pausing = true
		_desired_move = Vector3.ZERO
		var peck_pulse := absf(sin(_reaction_time * 16.0))
		head.position.y = head_y_rest - peck_pulse * 0.1
		beak.position.y = beak_y_rest - peck_pulse * 0.1
		body.scale = _body_rest_scale * (1.0 + peck_pulse * 0.06)

func _finish_park_reaction() -> void:
	_reaction_mode = ReactionMode.NONE
	_reaction_delay = 0.0
	_reaction_timer = 0.0
	body.rotation = _body_rest_rotation
	body.scale = _body_rest_scale
	head.position.y = head_y_rest
	beak.position.y = beak_y_rest
	choose_new_behavior()

func _find_nearest_ranger() -> Node3D:
	var nearest: Node3D = null
	var nearest_distance_squared: float = INF

	for candidate in get_tree().get_nodes_in_group("rangers"):
		if not candidate is Node3D:
			continue
		var candidate_node := candidate as Node3D
		var distance_squared := global_position.distance_squared_to(candidate_node.global_position)
		if distance_squared < nearest_distance_squared:
			nearest = candidate_node
			nearest_distance_squared = distance_squared

	return nearest

func _physics_process(delta: float) -> void:
	if _mistaken_capture_active:
		velocity = Vector3.ZERO
		return
	velocity.x = _desired_move.x
	velocity.z = _desired_move.z
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	else:
		velocity.y = 0.0
	move_and_slide()

func _do_wander(delta: float) -> void:
	var is_outside_bounds: bool = (absf(position.x) > wander_radius or absf(position.z) > wander_radius)

	if is_outside_bounds:
		# Turn back toward the centre.
		direction = Vector3(-position.x, 0.0, -position.z).normalized()
		is_pausing = false
		if direction.length() > 0.001:
			# look_at() aims -Z at the target. To move IN direction, the target must be
			# behind us (position - direction), not in front — this is Godot's axis convention.
			look_at(global_position - direction, Vector3.UP)
	else:
		time_until_change -= delta
		if time_until_change <= 0.0:
			choose_new_behavior()

	if is_pausing:
		_idle_peck(delta)
	else:
		_desired_move = direction * speed

func _do_flee(_delta: float) -> void:
	if not is_instance_valid(ranger):
		return

	var flee_dir := (global_position - ranger.global_position)
	flee_dir.y = 0.0

	if flee_dir.length() > 0.001:
		flee_dir = flee_dir.normalized()
		_desired_move = flee_dir * flee_speed
		look_at(global_position - flee_dir, Vector3.UP)   # same look_at trick as _do_wander
		direction = flee_dir

	is_pausing = false

func _idle_peck(delta: float) -> void:
	if is_pecking:
		return

	next_peck_timer -= delta
	if next_peck_timer <= 0.0:
		is_pecking  = true
		peck_time   = 0.0
		_peck_sfx.play()
		next_peck_timer = randf_range(0.8, 2.5)

func _update_peck(delta: float) -> void:
	if not is_pecking:
		return

	peck_time += delta
	var t: float   = peck_time / PECK_DURATION
	var z_off: float
	var y_off: float

	if t < PECK_STRIKE_FRAC:
		# Strike phase: forward lunge then drop (same math as player.gd).
		var st:  float = t / PECK_STRIKE_FRAC
		z_off = sin(st * PI * 0.5) * PECK_FORWARD
		var yst: float = clampf((st - 0.2) / 0.8, 0.0, 1.0)
		y_off = sin(yst * PI * 0.5) * PECK_DROP
	else:
		# Recovery phase: ease back to rest.
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
		# Snap to exact rest to eliminate floating-point drift.
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
		var bob_sin := sin(bob_time)
		var bob     := bob_sin * HEAD_BOB_Z
		head.position.z = head_z_rest + bob
		beak.position.z = beak_z_rest + bob

		# Zero-crossing detection — same pattern as player.gd.
		if _prev_sin <= 0.0 and bob_sin > 0.0:
			_step_sfx.play()
		_prev_sin = bob_sin
	else:
		head.position.z = lerp(head.position.z, head_z_rest, delta * 10.0)
		beak.position.z = lerp(beak.position.z, beak_z_rest, delta * 10.0)

func choose_new_behavior() -> void:
	is_pausing = randf() < 0.35   # 35% chance to stand still, 65% to walk

	if is_pausing:
		time_until_change = randf_range(0.7, 2.0)
		next_peck_timer   = randf_range(0.2, 0.8)
	else:
		var angle: float = randf_range(0.0, TAU)
		direction = Vector3(sin(angle), 0.0, cos(angle))
		time_until_change = randf_range(1.0, 3.0)
		look_at(global_position - direction, Vector3.UP)   # same look_at trick as _do_wander
