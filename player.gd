# player.gd — Attached to Player (CharacterBody3D)
# Handles movement, sprint stamina, pigeon visual rotation, head-bob, peck animation, and water.

extends CharacterBody3D

signal food_snatch_started
signal food_snatch_completed
signal peck_started(origin: Vector3)

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
const LEAN_STRENGTH: float = 0.075          # max pigeon_visual forward/back lean (radians)
const TURN_ROLL_STRENGTH: float = 0.16      # max pigeon_visual roll on sharp direction change
const STOP_BOUNCE_DURATION: float = 0.20    # seconds for the body-squish when stopping
const STRAIN_WOBBLE_FREQ: float = 16.0      # Hz of the body wobble when stamina is near-empty
const STRAIN_STAMINA_THRESHOLD: float = 32.0  # stamina below this triggers strain wobble

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
var is_captured: bool = false
var _capture_reaction_time: float = 0.0
var _camera_shake_timer: float = 0.0
var _camera_shake_duration: float = 0.0
var _camera_shake_intensity: float = 0.0
var _camera_shake_time: float = 0.0
var camera_shake_count: int = 0
var _snatch_reaction_timer: float = 0.0
var _snatch_reaction_duration: float = 0.44
var food_snatch_count: int = 0

var _prev_velocity_xz: Vector2 = Vector2.ZERO  # previous frame XZ velocity for lean/roll computation
var _body_lean_x: float = 0.0
var _turn_roll: float = 0.0
var _stop_bounce_timer: float = 0.0
var _strain_time: float = 0.0

# Camera orbit angles — driven by mouse input in _input(), applied to spring_arm each frame.
var camera_yaw:   float = 0.0
var camera_pitch: float = 0.0

# Scroll-wheel zoom: _zoom_target is where we want to be; spring_length lerps toward it each frame.
var _zoom_target: float = 4.0

@onready var spring_arm:    SpringArm3D   = $SpringArm3D
@onready var gameplay_camera: Camera3D     = $SpringArm3D/Camera3D
@onready var pigeon_visual: Node3D        = $PigeonVisual
@onready var body:          MeshInstance3D = $PigeonVisual/Body
@onready var head:          MeshInstance3D = $PigeonVisual/Head
@onready var beak:          MeshInstance3D = $PigeonVisual/Beak
@onready var left_wing:     MeshInstance3D = get_node_or_null("PigeonVisual/LeftWing") as MeshInstance3D
@onready var right_wing:    MeshInstance3D = get_node_or_null("PigeonVisual/RightWing") as MeshInstance3D
@onready var _stamina_bar:  ProgressBar   = get_node("../HUD/StaminaBar")

var _body_rest_scale: Vector3
var _left_wing_rest_rotation: Vector3
var _right_wing_rest_rotation: Vector3

func _ready() -> void:
	_load_camera_settings()
	_ensure_food_snatch_wings()
	# Record rest positions so peck and bob animations know where to return to.
	head_y_rest = head.position.y
	beak_y_rest = beak.position.y
	head_z_rest = head.position.z
	beak_z_rest = beak.position.z
	_body_rest_scale = body.scale
	_left_wing_rest_rotation = left_wing.rotation
	_right_wing_rest_rotation = right_wing.rotation

	# Initialise camera angles from whatever the scene has set on the spring arm,
	# so there's no snap on the first frame of mouse input.
	camera_yaw   = spring_arm.rotation.y
	camera_pitch = spring_arm.rotation.x
	# Seed the zoom target from the scene's spring_length so Inspector edits take effect.
	_zoom_target = spring_arm.spring_length

func _ensure_food_snatch_wings() -> void:
	if left_wing == null:
		left_wing = _create_food_snatch_wing("LeftWing", -0.21, 0.12)
	if right_wing == null:
		right_wing = _create_food_snatch_wing("RightWing", 0.21, -0.12)

func _create_food_snatch_wing(
	wing_name: String,
	x_position: float,
	z_rotation: float
) -> MeshInstance3D:
	var wing := MeshInstance3D.new()
	wing.name = wing_name
	wing.position = Vector3(x_position, 0.0, -0.01)
	wing.rotation.z = z_rotation
	var wing_mesh := BoxMesh.new()
	wing_mesh.size = Vector3(0.16, 0.045, 0.32)
	wing.mesh = wing_mesh
	var wing_material := StandardMaterial3D.new()
	wing_material.albedo_color = Color(0.4, 0.46667, 0.53333, 1.0)
	wing.set_surface_override_material(0, wing_material)
	pigeon_visual.add_child(wing)
	return wing

func _input(event: InputEvent) -> void:
	if is_captured:
		return
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
	if is_captured:
		return
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

func add_camera_trauma(intensity: float = 0.16, duration: float = 0.42) -> void:
	_camera_shake_intensity = maxf(_camera_shake_intensity, clampf(intensity, 0.0, 0.35))
	_camera_shake_duration = maxf(_camera_shake_duration, duration)
	_camera_shake_timer = maxf(_camera_shake_timer, duration)
	_camera_shake_time = 0.0
	camera_shake_count += 1

func _update_camera_shake(delta: float) -> void:
	if _camera_shake_timer <= 0.0:
		gameplay_camera.h_offset = lerpf(gameplay_camera.h_offset, 0.0, minf(delta * 18.0, 1.0))
		gameplay_camera.v_offset = lerpf(gameplay_camera.v_offset, 0.0, minf(delta * 18.0, 1.0))
		return
	_camera_shake_timer = maxf(_camera_shake_timer - delta, 0.0)
	_camera_shake_time += delta
	var fade := _camera_shake_timer / maxf(_camera_shake_duration, 0.001)
	var strength := _camera_shake_intensity * fade * fade
	gameplay_camera.h_offset = sin(_camera_shake_time * 63.0) * strength
	gameplay_camera.v_offset = sin(_camera_shake_time * 47.0 + 1.7) * strength * 0.62
	if _camera_shake_timer <= 0.0:
		_camera_shake_intensity = 0.0
		_camera_shake_duration = 0.0

func _physics_process(delta: float) -> void:
	_update_controller_camera(delta)
	_update_camera_shake(delta)
	_update_food_snatch_reaction(delta)

	# ── CAMERA ZOOM ──────────────────────────────────────────────────────────────
	# Smoothly ease spring_length toward wherever the scroll wheel last set it.
	spring_arm.spring_length = lerp(spring_arm.spring_length, _zoom_target, delta * zoom_smooth)

	if is_captured:
		_update_capture_reaction(delta)
		if not is_on_floor():
			velocity.y -= gravity * delta
		else:
			velocity.y = -0.1
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

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
	if Input.is_action_just_pressed("peck") and not sprinting:
		start_player_peck()

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
			# Anticipation: brief head lift in the first 14% of the strike telegraphs the peck.
			# Negative y_off means head_y_rest - (-0.022) = head_y_rest + 0.022 (upward).
			if st < 0.14:
				y_off -= sin((st / 0.14) * PI) * 0.022
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
	_update_movement_animation(delta, sprinting)

	_wall_bump_cooldown = maxf(_wall_bump_cooldown - delta, 0.0)
	if is_on_wall() and _wall_bump_cooldown <= 0.0:
		SoundManager.play_wall_bump()
		_wall_bump_cooldown = 0.6

# Lets one nearby food item claim the current peck. Keeping this state on the
# player prevents overlapping collectibles from all responding to the same input.
func start_player_peck() -> bool:
	if is_captured or is_pecking or peck_cooldown_timer > 0.0:
		return false
	is_pecking = true
	peck_time = 0.0
	_peck_consumed = false
	SoundManager.play_peck()
	peck_started.emit(global_position)
	return true

func play_food_snatch_reaction() -> void:
	if is_captured:
		return
	_snatch_reaction_timer = _snatch_reaction_duration
	food_snatch_count += 1
	food_snatch_started.emit()

func _update_food_snatch_reaction(delta: float) -> void:
	if _snatch_reaction_timer <= 0.0 or is_captured:
		return
	_snatch_reaction_timer = maxf(_snatch_reaction_timer - delta, 0.0)
	var progress := 1.0 - _snatch_reaction_timer / _snatch_reaction_duration
	var pop := sin(progress * PI)
	var flutter := sin(progress * PI * 4.0) * (1.0 - progress)
	body.scale = Vector3(
		_body_rest_scale.x * (1.0 + pop * 0.16),
		_body_rest_scale.y * (1.0 - pop * 0.12),
		_body_rest_scale.z * (1.0 + pop * 0.08)
	)
	left_wing.rotation.z = _left_wing_rest_rotation.z + pop * 0.95 + flutter * 0.14
	right_wing.rotation.z = _right_wing_rest_rotation.z - pop * 0.95 - flutter * 0.14
	if _snatch_reaction_timer <= 0.0:
		_reset_food_snatch_pose()
		food_snatch_completed.emit()

func _reset_food_snatch_pose() -> void:
	_snatch_reaction_timer = 0.0
	body.scale = _body_rest_scale
	left_wing.rotation = _left_wing_rest_rotation
	right_wing.rotation = _right_wing_rest_rotation

func _update_movement_animation(delta: float, is_sprint: bool) -> void:
	if is_captured:
		return
	var curr_xz := Vector2(velocity.x, velocity.z)
	var speed_curr := curr_xz.length()
	var speed_prev := _prev_velocity_xz.length()

	# Stop bounce: body squishes when the pigeon halts suddenly.
	if speed_prev > 0.5 and speed_curr < 0.1:
		_stop_bounce_timer = STOP_BOUNCE_DURATION

	# Turn roll: pigeon leans into sharp direction changes.
	if curr_xz.length() > 0.2 and _prev_velocity_xz.length() > 0.2:
		var turn_signal := _prev_velocity_xz.normalized().cross(curr_xz.normalized())
		_turn_roll = lerpf(_turn_roll, -turn_signal * TURN_ROLL_STRENGTH, minf(delta * 14.0, 1.0))
	else:
		_turn_roll = lerpf(_turn_roll, 0.0, minf(delta * 10.0, 1.0))
	pigeon_visual.rotation.z = _turn_roll

	# Acceleration lean: body tips forward when sprinting, back when braking.
	var speed_delta := (speed_curr - speed_prev) / maxf(delta, 0.001)
	var target_lean := clampf(-speed_delta / (run_speed * 14.0), -LEAN_STRENGTH, LEAN_STRENGTH * 0.5)
	_body_lean_x = lerpf(_body_lean_x, target_lean, minf(delta * 8.0, 1.0))
	pigeon_visual.rotation.x = _body_lean_x

	_prev_velocity_xz = curr_xz

	# Body scale: stop bounce > sprint strain > rest lerp.
	if _stop_bounce_timer > 0.0:
		_stop_bounce_timer = maxf(_stop_bounce_timer - delta, 0.0)
		var t := 1.0 - _stop_bounce_timer / STOP_BOUNCE_DURATION
		var bounce := sin(t * PI) * 0.12
		if _snatch_reaction_timer <= 0.0:
			body.scale = Vector3(
				_body_rest_scale.x * (1.0 + bounce),
				_body_rest_scale.y * (1.0 - bounce * 0.65),
				_body_rest_scale.z * (1.0 + bounce)
			)
	elif is_sprint and _stamina < STRAIN_STAMINA_THRESHOLD and _snatch_reaction_timer <= 0.0:
		_strain_time += delta
		var strain_t := 1.0 - (_stamina / STRAIN_STAMINA_THRESHOLD)
		var wobble := sin(_strain_time * STRAIN_WOBBLE_FREQ) * strain_t * 0.04
		body.scale = Vector3(
			_body_rest_scale.x * (1.0 + absf(wobble)),
			_body_rest_scale.y * (1.0 - absf(wobble) * 0.6),
			_body_rest_scale.z * (1.0 + absf(wobble))
		)
	else:
		_strain_time = 0.0
		if _snatch_reaction_timer <= 0.0:
			body.scale = body.scale.lerp(_body_rest_scale, minf(delta * 7.0, 1.0))

func try_consume_peck() -> bool:
	if is_captured or not is_pecking or _peck_consumed:
		return false
	_peck_consumed = true
	return true

func start_capture_reaction(ranger_position: Vector3) -> void:
	if is_captured:
		return
	is_captured = true
	is_pecking = false
	_reset_food_snatch_pose()
	_capture_reaction_time = 0.0
	velocity.x = 0.0
	velocity.z = 0.0
	var to_ranger := ranger_position - global_position
	to_ranger.y = 0.0
	if to_ranger.length_squared() > 0.001:
		pigeon_visual.rotation.y = atan2(to_ranger.x, to_ranger.z)
	SoundManager.play_capture_flap()

func _update_capture_reaction(delta: float) -> void:
	_capture_reaction_time += delta
	var struggle := sin(_capture_reaction_time * 24.0)
	var squash := absf(sin(_capture_reaction_time * 17.0))
	pigeon_visual.rotation.z = struggle * 0.24
	pigeon_visual.scale = Vector3(
		1.0 + squash * 0.16,
		1.0 - squash * 0.12,
		1.0 + squash * 0.16
	)
	head.position.y = head_y_rest + sin(_capture_reaction_time * 31.0) * 0.05
	beak.position.y = beak_y_rest + sin(_capture_reaction_time * 31.0) * 0.05

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
