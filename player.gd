# player.gd — Attached to Player (CharacterBody3D)
# Handles movement, sprint stamina, pigeon visual rotation, head-bob, peck animation, and water.

extends CharacterBody3D

const SETTINGS_PATH: String = "user://settings.cfg"

@export var settings_path: String = SETTINGS_PATH

# Inspector-tunable values
@export var walk_speed:      float = 1.2
@export var run_speed:       float = 4.0
@export var turn_speed:        float = 10.0
@export var mouse_sensitivity: float = 0.003
@export var controller_look_speed: float = 2.4
@export var invert_camera_y: bool = false
@export var peck_duration:   float = 0.55
@export var peck_cooldown:   float = 0.3
@export var max_stamina:     float = 100.0
@export var stamina_drain:   float = 30.0   # points/sec while sprinting
@export var stamina_recover: float = 15.0   # points/sec when not sprinting
@export var zoom_step:       float = 0.5    # world units per scroll click
@export var zoom_smooth:     float = 12.0   # how quickly the camera eases to the target distance

const ZOOM_MIN: float = 2.0   # closest the camera can get to the player
const ZOOM_MAX: float = 8.0   # furthest the camera can pull back

# Peck animation shape constants
const PECK_FORWARD:     float = 0.12   # how far head lunges forward
const PECK_DROP:        float = 0.13   # how far head drops down
const PECK_STRIKE_FRAC: float = 0.40   # first 40% of peck = strike, last 60% = recovery
const HEAD_BOB_Z:       float = 0.06   # max head swing forward/back while walking

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var is_pecking:          bool  = false
var peck_time:           float = 0.0
var peck_cooldown_timer: float = 0.0
var _peck_consumed:      bool  = false

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
var _water_zones: Dictionary = {}
var _water_speed_multiplier: float = 1.0

# Camera orbit angles — driven by mouse input in _input(), applied to spring_arm each frame.
var camera_yaw:   float = 0.0
var camera_pitch: float = 0.0

# Scroll-wheel zoom: _zoom_target is where we want to be; spring_length lerps toward it each frame.
var _zoom_target: float = 4.0

@onready var spring_arm:    SpringArm3D   = $SpringArm3D
@onready var pigeon_visual: Node3D        = $PigeonVisual
@onready var head:          MeshInstance3D = $PigeonVisual/Head
@onready var beak:          MeshInstance3D = $PigeonVisual/Beak
@onready var _stamina_bar:  ProgressBar   = get_node("../HUD/StaminaBar")

func _ready() -> void:
	_load_camera_settings()
	# Record rest positions so peck and bob animations know where to return to.
	head_y_rest = head.position.y
	beak_y_rest = beak.position.y
	head_z_rest = head.position.z
	beak_z_rest = beak.position.z

	# Initialise camera angles from whatever the scene has set on the spring arm,
	# so there's no snap on the first frame of mouse input.
	camera_yaw   = spring_arm.rotation.y
	camera_pitch = spring_arm.rotation.x
	# Seed the zoom target from the scene's spring_length so Inspector edits take effect.
	_zoom_target = spring_arm.spring_length

func _input(event: InputEvent) -> void:
	# Only handle camera input when the cursor is captured (active gameplay).
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return

	if event is InputEventMouseMotion:
		camera_yaw   -= event.relative.x * mouse_sensitivity
		var pitch_direction := 1.0 if invert_camera_y else -1.0
		camera_pitch += event.relative.y * mouse_sensitivity * pitch_direction
		# Clamp pitch: negative = looking up, positive = looking down at the character.
		camera_pitch  = clampf(camera_pitch, -1.1, 0.5)
		spring_arm.rotation = Vector3(camera_pitch, camera_yaw, 0.0)

	# Scroll wheel zoom: adjust the target distance and let _physics_process smooth it.
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_target = clampf(_zoom_target - zoom_step, ZOOM_MIN, ZOOM_MAX)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_target = clampf(_zoom_target + zoom_step, ZOOM_MIN, ZOOM_MAX)

func _update_controller_camera(delta: float) -> void:
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return

	var look_input := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look_input.length_squared() > 0.001:
		camera_yaw -= look_input.x * controller_look_speed * delta
		var pitch_direction := 1.0 if invert_camera_y else -1.0
		camera_pitch = clampf(
			camera_pitch + look_input.y * controller_look_speed * delta * pitch_direction,
			-1.1,
			0.5
		)
		spring_arm.rotation = Vector3(camera_pitch, camera_yaw, 0.0)

	if Input.is_action_just_pressed("zoom_in"):
		_zoom_target = clampf(_zoom_target - zoom_step, ZOOM_MIN, ZOOM_MAX)
	elif Input.is_action_just_pressed("zoom_out"):
		_zoom_target = clampf(_zoom_target + zoom_step, ZOOM_MIN, ZOOM_MAX)

func _load_camera_settings() -> void:
	var config := ConfigFile.new()
	if config.load(settings_path) != OK:
		return
	mouse_sensitivity = clampf(
		float(config.get_value("camera", "mouse_sensitivity", mouse_sensitivity)),
		0.001,
		0.008
	)
	controller_look_speed = clampf(
		float(config.get_value("camera", "controller_sensitivity", controller_look_speed)),
		0.8,
		4.5
	)
	invert_camera_y = bool(config.get_value("camera", "invert_y", invert_camera_y))

func _physics_process(delta: float) -> void:
	_update_controller_camera(delta)

	# ── CAMERA ZOOM ──────────────────────────────────────────────────────────────
	# Smoothly ease spring_length toward wherever the scroll wheel last set it.
	spring_arm.spring_length = lerp(spring_arm.spring_length, _zoom_target, delta * zoom_smooth)

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
	if in_water:
		current_speed *= _water_speed_multiplier

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
		_peck_consumed = false
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

# Lets one nearby food item claim the current peck. Keeping this state on the
# player prevents overlapping collectibles from all responding to the same input.
func try_consume_peck() -> bool:
	if not is_pecking or _peck_consumed:
		return false
	_peck_consumed = true
	return true

func enter_water_zone(zone: Area3D, speed_multiplier: float) -> void:
	_water_zones[zone] = clampf(speed_multiplier, 0.05, 1.0)
	_refresh_water_state()

func exit_water_zone(zone: Area3D) -> void:
	_water_zones.erase(zone)
	_refresh_water_state()

func _refresh_water_state() -> void:
	_water_speed_multiplier = 1.0
	for zone in _water_zones.keys():
		if not is_instance_valid(zone):
			_water_zones.erase(zone)
			continue
		_water_speed_multiplier = minf(
			_water_speed_multiplier,
			float(_water_zones[zone])
		)
	in_water = not _water_zones.is_empty()
