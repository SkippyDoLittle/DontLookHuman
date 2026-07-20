extends CharacterBody3D

@export var walk_speed: float = 1.2
@export var run_speed: float = 4.0
@export var turn_speed: float = 10.0
@export var peck_duration: float = 0.55
@export var peck_cooldown: float = 0.3

const PECK_FORWARD: float = 0.12
const PECK_DROP: float = 0.13
const PECK_STRIKE_FRAC: float = 0.40
const HEAD_BOB_Z: float = 0.06

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var is_pecking: bool = false
var peck_time: float = 0.0
var peck_cooldown_timer: float = 0.0
var head_y_rest: float = 0.0
var beak_y_rest: float = 0.0
var head_z_rest: float = 0.0
var beak_z_rest: float = 0.0
var bob_time: float = 0.0
var _prev_sin: float = 0.0

@onready var pigeon_visual: Node3D = $PigeonVisual
@onready var head: MeshInstance3D = $PigeonVisual/Head
@onready var beak: MeshInstance3D = $PigeonVisual/Beak

func _ready() -> void:
	head_y_rest = head.position.y
	beak_y_rest = beak.position.y
	head_z_rest = head.position.z
	beak_z_rest = beak.position.z

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = -0.1

	var input_vector: Vector2 = Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_back"
	)

	var sprinting: bool = Input.is_action_pressed("run")
	var current_speed: float = run_speed if sprinting else walk_speed

	velocity.x = input_vector.x * current_speed
	velocity.z = input_vector.y * current_speed

	if input_vector.length() > 0.1:
		var direction := Vector3(input_vector.x, 0, input_vector.y)
		var target_angle := atan2(direction.x, direction.z)
		pigeon_visual.rotation.y = lerp_angle(pigeon_visual.rotation.y, target_angle, delta * turn_speed)

	if not is_pecking:
		if input_vector.length() > 0.1:
			bob_time += delta * current_speed * 5.0
			var bob_sin: float = sin(bob_time)
			var bob := bob_sin * HEAD_BOB_Z
			head.position.z = head_z_rest + bob
			beak.position.z = beak_z_rest + bob
			if _prev_sin <= 0.0 and bob_sin > 0.0:
				SoundManager.play_step(sprinting)
			_prev_sin = bob_sin
		else:
			head.position.z = lerp(head.position.z, head_z_rest, delta * 10.0)
			beak.position.z = lerp(beak.position.z, beak_z_rest, delta * 10.0)
			_prev_sin = 0.0

	if peck_cooldown_timer > 0.0:
		peck_cooldown_timer -= delta

	if Input.is_action_just_pressed("peck") and not is_pecking and peck_cooldown_timer <= 0.0 and not sprinting:
		is_pecking = true
		peck_time = 0.0
		SoundManager.play_peck()

	if is_pecking:
		peck_time += delta
		var t: float = peck_time / peck_duration
		var z_off: float
		var y_off: float
		if t < PECK_STRIKE_FRAC:
			var st: float = t / PECK_STRIKE_FRAC
			z_off = sin(st * PI * 0.5) * PECK_FORWARD
			var yst: float = clampf((st - 0.2) / 0.8, 0.0, 1.0)
			y_off = sin(yst * PI * 0.5) * PECK_DROP
		else:
			var rt: float = (t - PECK_STRIKE_FRAC) / (1.0 - PECK_STRIKE_FRAC)
			@warning_ignore("shadowed_global_identifier")
			var recovery_weight: float = 1.0 - sin(rt * PI * 0.5)
			z_off = recovery_weight * PECK_FORWARD
			y_off = recovery_weight * PECK_DROP
		head.position.z = head_z_rest + z_off
		head.position.y = head_y_rest - y_off
		beak.position.z = beak_z_rest + z_off
		beak.position.y = beak_y_rest - y_off
		if peck_time >= peck_duration:
			is_pecking = false
			peck_cooldown_timer = peck_cooldown
			head.position.z = head_z_rest
			head.position.y = head_y_rest
			beak.position.z = beak_z_rest
			beak.position.y = beak_y_rest

	move_and_slide()
