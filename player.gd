# player.gd — Attached to Player (CharacterBody3D)
# Handles movement, sprint stamina, pigeon visual rotation, head-bob, peck animation, and water.

extends CharacterBody3D

# Inspector-tunable values
@export var walk_speed:      float = 1.2
@export var run_speed:       float = 4.0
@export var turn_speed:        float = 10.0
@export var mouse_sensitivity: float = 0.003
@export var peck_duration:   float = 0.55
@export var peck_cooldown:   float = 0.3
@export var max_stamina:     float = 100.0
@export var stamina_drain:   float = 30.0   # points/sec while sprinting
@export var stamina_recover: float = 15.0   # points/sec when not sprinting

# Peck animation shape constants
const PECK_FORWARD:     float = 0.12   # how far head lunges forward
const PECK_DROP:        float = 0.13   # how far head drops down
const PECK_STRIKE_FRAC: float = 0.40   # first 40% of peck = strike, last 60% = recovery
const HEAD_BOB_Z:       float = 0.06   # max head swing forward/back while walking

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var is_pecking:          bool  = false
var peck_time:           float = 0.0
var peck_cooldown_timer: float = 0.0

# Head/beak resting positions — recorded in _ready() so animations can offset from them.
var head_y_rest: float = 0.0
var beak_y_rest: float = 0.0
var head_z_rest: float = 0.0
var beak_z_rest: float = 0.0

var bob_time:  float = 0.0
var _prev_sin: float = 0.0   # previous frame's sin value — for zero-crossing footstep detection

var _stamina:          float = 100.0
var _stamina_depleted: bool  = false   # prevents exhaust sound firing every frame while empty
var _wall_bump_cooldown: float = 0.0  # prevents bump sound repeating every frame while held against wall

var in_water: bool = false   # read by ranger.gd for suspicion; updated each frame

# Camera orbit angles — driven by mouse input in _input(), applied to spring_arm each frame.
var camera_yaw:   float = 0.0
var camera_pitch: float = 0.0

# Pond shape constants — must match the CylinderMesh in Main.tscn (z-scale 0.72 makes it oval)
const _POND_CENTER         := Vector3(-3.0, 0.0, -7.0)
const _POND_RADIUS_X:       float = 1.6
const _POND_RADIUS_Z:       float = 1.6 * 0.72
const _WATER_SPEED_FACTOR:  float = 0.5

@onready var spring_arm:    SpringArm3D   = $SpringArm3D
@onready var pigeon_visual: Node3D        = $PigeonVisual
@onready var head:          MeshInstance3D = $PigeonVisual/Head
@onready var beak:          MeshInstance3D = $PigeonVisual/Beak
@onready var _stamina_bar:  ProgressBar   = get_node("../HUD/StaminaBar")

func _ready() -> void:
	# Record rest positions so peck and bob animations know where to return to.
	head_y_rest = head.position.y
	beak_y_rest = beak.position.y
	head_z_rest = head.position.z
	beak_z_rest = beak.position.z

	# Initialise camera angles from whatever the scene has set on the spring arm,
	# so there's no snap on the first frame of mouse input.
	camera_yaw   = spring_arm.rotation.y
	camera_pitch = spring_arm.rotation.x

func _input(event: InputEvent) -> void:
	# Only rotate the camera when the cursor is captured (i.e., during active gameplay).
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		camera_yaw   -= event.relative.x * mouse_sensitivity
		camera_pitch -= event.relative.y * mouse_sensitivity
		# Clamp pitch: negative = looking up, positive = looking down at the character.
		camera_pitch  = clampf(camera_pitch, -1.1, 0.5)
		spring_arm.rotation = Vector3(camera_pitch, camera_yaw, 0.0)

func _physics_process(delta: float) -> void:

	# ── GRAVITY ──────────────────────────────────────────────────────────────────
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = -0.1   # small downward push keeps is_on_floor() reliable next frame

	# ── INPUT ────────────────────────────────────────────────────────────────────
	# get_vector maps four actions to a 2D direction: x = left/right, y = forward/back.
	var input_vector: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var want_sprint:  bool    = Input.is_action_pressed("run")

	# ── STAMINA ──────────────────────────────────────────────────────────────────
	# Recovery only happens when the sprint key is released — if we recovered while
	# holding shift at zero stamina the bar would refill instantly, making the limit pointless.
	if want_sprint and _stamina > 0.0:
		_stamina -= stamina_drain * delta
	elif not want_sprint:
		_stamina += stamina_recover * delta
	_stamina = clamp(_stamina, 0.0, max_stamina)

	var sprinting: bool = want_sprint and _stamina > 0.0

	# One-shot exhaust sound when stamina first hits zero; rearms once above 10.
	if _stamina <= 0.0 and not _stamina_depleted:
		_stamina_depleted = true
		SoundManager.play_exhaust()
	elif _stamina > 10.0:
		_stamina_depleted = false

	_stamina_bar.value = _stamina
	var current_speed: float = run_speed if sprinting else walk_speed

	# ── WATER SLOW ───────────────────────────────────────────────────────────────
	# Point-in-ellipse test: normalise X/Z offsets by each radius, then check unit circle.
	var _dx: float = (global_position.x - _POND_CENTER.x) / _POND_RADIUS_X
	var _dz: float = (global_position.z - _POND_CENTER.z) / _POND_RADIUS_Z
	in_water = (_dx * _dx + _dz * _dz) <= 1.0
	if in_water:
		current_speed *= _WATER_SPEED_FACTOR

	# ── MOVEMENT (camera-relative) ──────────────────────────────────────────────
	# Build world-space forward/right vectors from the camera's horizontal yaw,
	# then project WASD input onto them so "forward" always means camera-forward.
	# input.y = -1 when W is pressed (get_vector convention), hence the negation.
	if input_vector.length() > 0.01:
		var cam_fwd   := Vector3(-sin(camera_yaw), 0.0, -cos(camera_yaw))
		var cam_right := Vector3( cos(camera_yaw), 0.0, -sin(camera_yaw))
		var move_dir  := (cam_fwd * (-input_vector.y) + cam_right * input_vector.x).normalized()
		velocity.x = move_dir.x * current_speed
		velocity.z = move_dir.z * current_speed
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	# ── ROTATION ─────────────────────────────────────────────────────────────────
	# Rotate the visual only — not the physics body — to avoid collision glitches.
	# Derive the target angle from actual world-space velocity so the pigeon turns
	# to face wherever it's walking, regardless of camera direction.
	if Vector2(velocity.x, velocity.z).length() > 0.1:
		var target_angle := atan2(velocity.x, velocity.z)
		pigeon_visual.rotation.y = lerp_angle(pigeon_visual.rotation.y, target_angle, delta * turn_speed)

	# ── HEAD BOB ─────────────────────────────────────────────────────────────────
	if not is_pecking:
		if input_vector.length() > 0.1:
			bob_time += delta * current_speed * 5.0
			var bob_sin: float = sin(bob_time)
			var bob: float     = bob_sin * HEAD_BOB_Z
			head.position.z = head_z_rest + bob
			beak.position.z = beak_z_rest + bob

			# Zero-crossing detection: sine going negative → positive = one step completed.
			if _prev_sin <= 0.0 and bob_sin > 0.0:
				SoundManager.play_step(sprinting)
			_prev_sin = bob_sin
		else:
			# Ease head/beak back to rest when stopped.
			head.position.z = lerp(head.position.z, head_z_rest, delta * 10.0)
			beak.position.z = lerp(beak.position.z, beak_z_rest, delta * 10.0)
			_prev_sin = 0.0

	# ── PECK COOLDOWN ────────────────────────────────────────────────────────────
	if peck_cooldown_timer > 0.0:
		peck_cooldown_timer -= delta

	# ── PECK INPUT ───────────────────────────────────────────────────────────────
	if Input.is_action_just_pressed("peck") and not is_pecking and peck_cooldown_timer <= 0.0 and not sprinting:
		is_pecking = true
		peck_time  = 0.0
		SoundManager.play_peck()

	# ── PECK ANIMATION ───────────────────────────────────────────────────────────
	if is_pecking:
		peck_time += delta
		var t: float   = peck_time / peck_duration
		var z_off: float
		var y_off: float

		if t < PECK_STRIKE_FRAC:
			# Strike phase (0–40%): head lunges forward, then drops.
			# The drop starts at 20% of the strike so forward motion leads.
			var st:  float = t / PECK_STRIKE_FRAC
			z_off = sin(st * PI * 0.5) * PECK_FORWARD
			var yst: float = clampf((st - 0.2) / 0.8, 0.0, 1.0)
			y_off = sin(yst * PI * 0.5) * PECK_DROP
		else:
			# Recovery phase (40–100%): head eases back to rest.
			var rt: float = (t - PECK_STRIKE_FRAC) / (1.0 - PECK_STRIKE_FRAC)
			@warning_ignore("shadowed_global_identifier")
			var recovery_weight: float = 1.0 - sin(rt * PI * 0.5)
			z_off = recovery_weight * PECK_FORWARD
			y_off = recovery_weight * PECK_DROP

		head.position.z = head_z_rest + z_off
		head.position.y = head_y_rest - y_off   # subtract because +Y is up
		beak.position.z = beak_z_rest + z_off
		beak.position.y = beak_y_rest - y_off

		if peck_time >= peck_duration:
			is_pecking = false
			peck_cooldown_timer = peck_cooldown
			# Snap to exact rest to prevent floating-point drift accumulating over many pecks.
			head.position.z = head_z_rest
			head.position.y = head_y_rest
			beak.position.z = beak_z_rest
			beak.position.y = beak_y_rest

	move_and_slide()

	_wall_bump_cooldown = maxf(_wall_bump_cooldown - delta, 0.0)
	if is_on_wall() and _wall_bump_cooldown <= 0.0:
		SoundManager.play_wall_bump()
		_wall_bump_cooldown = 0.6
