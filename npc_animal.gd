# npc_animal.gd — Attached to NPC_Animal, NPC_Animal2 … NPC_Animal5 in Main.tscn
# Background pigeon NPCs that wander, pause-and-peck, and flee from the ranger.
# Their presence near the player reduces "Acting alone" suspicion.

extends CharacterBody3D

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
@onready var ranger: Node3D         = get_node_or_null("../Ranger")   # null-safe; validated each frame

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

func _ready() -> void:
	head_y_rest = head.position.y
	beak_y_rest = beak.position.y
	head_z_rest = head.position.z
	beak_z_rest = beak.position.z

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

func _physics_process(delta: float) -> void:
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
