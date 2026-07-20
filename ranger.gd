extends Node3D

enum RangerState { PATROL, INVESTIGATE, CHASE }

@export var notice_distance: float = 4.0
@export var suspicious_speed: float = 2.0
@export var suspicion_gain_per_second: float = 35.0
@export var suspicion_loss_per_second: float = 15.0
@export var peck_loss_per_second: float = 20.0

@export var patrol_speed: float = 0.8
@export var patrol_radius: float = 7.0

@export var investigate_threshold: float = 65.0
@export var investigate_speed: float = 1.4
@export var chase_threshold: float = 90.0
@export var chase_speed: float = 2.8
@export var approach_stop_distance: float = 1.8

@export var food_aim_threshold: float = 0.9
@export var food_aim_delay: float = 0.8
@export var food_aim_gain_per_second: float = 25.0

@export var stare_threshold: float = 0.85
@export var stare_delay: float = 1.0
@export var stare_gain_per_second: float = 20.0

@export var separation_distance: float = 4.0
@export var separation_gain_per_second: float = 10.0

@onready var player: CharacterBody3D = get_node("../Player")
@onready var status_label: Label = get_node("../HUD/RangerStatus")
@onready var suspicion_bar: ProgressBar = get_node("../HUD/SuspicionBar")
@onready var pigeon_visual: Node3D = get_node("../Player/PigeonVisual")
@onready var _vignette_mat: ShaderMaterial = get_node("../HUD/VignetteRect").material
@onready var _warn_label: Label = get_node("../HUD/WarnLabel")

var suspicion: float = 0.0
var caught: bool = false
var state: RangerState = RangerState.PATROL
var _prev_state: RangerState = RangerState.PATROL
var _pulse_time: float = 0.0
var _warn_timer: float = 0.0
var _prev_suspicion: float = 0.0
var patrol_direction: Vector3 = Vector3.FORWARD
var time_until_turn: float = 0.0
var stare_time: float = 0.0
var food_aim_time: float = 0.0
var npc_animals: Array = []

func _ready() -> void:
	choose_new_patrol_direction()
	for npc_name in ["NPC_Animal", "NPC_Animal2", "NPC_Animal3"]:
		var npc := get_node_or_null("../" + npc_name)
		if npc:
			npc_animals.append(npc)

func _process(delta: float) -> void:
	if caught:
		suspicion_bar.value = 100.0
		status_label.text = "CAUGHT! Press R to retry"
		if Input.is_action_just_pressed("restart"):
			get_tree().reload_current_scene()
		return

	var distance_to_player: float = global_position.distance_to(player.global_position)
	var player_speed: float = Vector2(player.velocity.x, player.velocity.z).length()

	# Notice range widens when already alert — ranger keeps eyes on a known suspect
	var effective_notice: float
	if suspicion >= chase_threshold:
		effective_notice = 20.0
	elif suspicion >= investigate_threshold:
		effective_notice = notice_distance * 2.0
	else:
		effective_notice = notice_distance
	var is_nearby: bool = distance_to_player <= effective_notice

	var active_gain: float = 0.0
	var reason: String = ""

	# 1. Sprinting
	if is_nearby and player_speed > suspicious_speed:
		active_gain += suspicion_gain_per_second
		reason = "Too fast!"

	# 2. Moving directly toward food
	if is_nearby and _is_aiming_at_food(player_speed):
		food_aim_time += delta
		if food_aim_time >= food_aim_delay:
			active_gain += food_aim_gain_per_second
			if reason == "":
				reason = "Moving suspiciously"
	else:
		food_aim_time = maxf(food_aim_time - delta * 2.0, 0.0)

	# 3. Staring at the ranger (only while moving — pigeon holds last angle when still)
	if is_nearby and player_speed > 0.1 and _is_facing_ranger():
		stare_time += delta
		if stare_time >= stare_delay:
			active_gain += stare_gain_per_second
			if reason == "":
				reason = "Staring..."
	else:
		stare_time = maxf(stare_time - delta * 2.0, 0.0)

	# 4. Separated from all other animals
	if is_nearby and _is_isolated():
		active_gain += separation_gain_per_second
		if reason == "":
			reason = "Acting alone"

	# Update suspicion
	if active_gain > 0.0:
		suspicion = minf(suspicion + active_gain * delta, 100.0)
	else:
		var loss_rate := suspicion_loss_per_second
		if player.get("is_pecking"):
			loss_rate += peck_loss_per_second
		suspicion = maxf(suspicion - loss_rate * delta, 0.0)

	suspicion_bar.value = suspicion
	_vignette_mat.set_shader_parameter("intensity", suspicion / 100.0 * 0.65)

	if suspicion >= 100.0:
		caught = true
		return

	# Determine state from updated suspicion
	if suspicion >= chase_threshold:
		state = RangerState.CHASE
	elif suspicion >= investigate_threshold:
		state = RangerState.INVESTIGATE
	else:
		state = RangerState.PATROL

	if state != _prev_state:
		if state == RangerState.INVESTIGATE or state == RangerState.CHASE:
			SoundManager.play_alert()
		_prev_state = state

	# Move based on state
	match state:
		RangerState.PATROL:
			_do_patrol(delta)
		RangerState.INVESTIGATE:
			_move_toward_player(delta, investigate_speed)
		RangerState.CHASE:
			_move_toward_player(delta, chase_speed)

	# Pulse suspicion bar to signal urgency
	match state:
		RangerState.PATROL:
			_pulse_time = 0.0
			suspicion_bar.modulate = Color.WHITE
		RangerState.INVESTIGATE:
			_pulse_time += delta
			var p: float = sin(_pulse_time * TAU * 2.5) * 0.5 + 0.5
			suspicion_bar.modulate = Color(1.0, lerp(0.35, 0.75, p), p * 0.1)
		RangerState.CHASE:
			_pulse_time += delta
			var p: float = sin(_pulse_time * TAU * 6.0) * 0.5 + 0.5
			suspicion_bar.modulate = Color(1.0, lerp(0.0, 0.3, p), 0.0)

	# Threshold crossing warnings
	if suspicion >= chase_threshold and _prev_suspicion < chase_threshold:
		_warn_label.text = "DANGER!"
		_warn_label.modulate = Color(1.0, 0.15, 0.15, 1.0)
		_warn_label.visible = true
		_warn_timer = 1.8
	elif suspicion >= investigate_threshold and _prev_suspicion < investigate_threshold:
		_warn_label.text = "!"
		_warn_label.modulate = Color(1.0, 0.8, 0.1, 1.0)
		_warn_label.visible = true
		_warn_timer = 1.5

	if _warn_timer > 0.0:
		_warn_timer -= delta
		_warn_label.modulate.a = clampf(_warn_timer / 0.5, 0.0, 1.0)
		if _warn_timer <= 0.0:
			_warn_label.visible = false

	_prev_suspicion = suspicion

	# Status label
	match state:
		RangerState.CHASE:
			status_label.text = "Ranger: Alert!"
		RangerState.INVESTIGATE:
			if active_gain > 0.0:
				status_label.text = "Ranger: Suspicious — %s" % reason
			else:
				status_label.text = "Ranger: Investigating..."
		RangerState.PATROL:
			if active_gain > 0.0:
				status_label.text = "Ranger: Suspicious — %s" % reason
			elif is_nearby:
				status_label.text = "Ranger: Watching"
			else:
				status_label.text = "Ranger: Calm"

func _move_toward_player(delta: float, spd: float) -> void:
	var to_player := player.global_position - global_position
	to_player.y = 0.0
	if to_player.length() < 0.1:
		return
	var look_target := Vector3(player.global_position.x, global_position.y, player.global_position.z)
	look_at(look_target, Vector3.UP)
	if to_player.length() > approach_stop_distance:
		position += to_player.normalized() * spd * delta

func _get_nearest_food() -> Node3D:
	var nearest: Node3D = null
	var nearest_dist: float = INF
	for item in get_tree().get_nodes_in_group("collectibles"):
		var food_node := item as Node3D
		if food_node == null:
			continue
		var d: float = player.global_position.distance_to(food_node.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = food_node
	return nearest

func _is_aiming_at_food(player_speed: float) -> bool:
	if player_speed < 0.3:
		return false
	var food_item: Node3D = _get_nearest_food()
	if food_item == null:
		return false
	var to_food := food_item.global_position - player.global_position
	to_food.y = 0.0
	if to_food.length() < 0.5:
		return false
	var move_dir := Vector2(player.velocity.x, player.velocity.z).normalized()
	var food_dir := Vector2(to_food.x, to_food.z).normalized()
	return move_dir.dot(food_dir) >= food_aim_threshold

func _is_facing_ranger() -> bool:
	var to_ranger := global_position - player.global_position
	to_ranger.y = 0.0
	if to_ranger.length() < 0.5:
		return false
	var forward := pigeon_visual.global_transform.basis.z
	forward.y = 0.0
	return forward.normalized().dot(to_ranger.normalized()) >= stare_threshold

func _is_isolated() -> bool:
	for npc in npc_animals:
		if is_instance_valid(npc) and player.global_position.distance_to(npc.global_position) <= separation_distance:
			return false
	return true

func _do_patrol(delta: float) -> void:
	time_until_turn -= delta
	var is_outside_bounds: bool = (
		absf(position.x) > patrol_radius
		or absf(position.z) > patrol_radius
	)
	if is_outside_bounds:
		patrol_direction = Vector3(-position.x, 0.0, -position.z).normalized()
		time_until_turn = 1.0
	elif time_until_turn <= 0.0:
		choose_new_patrol_direction()
	if patrol_direction.length() > 0.001:
		look_at(global_position + patrol_direction, Vector3.UP)
	position += patrol_direction * patrol_speed * delta

func choose_new_patrol_direction() -> void:
	var angle: float = randf_range(0.0, TAU)
	patrol_direction = Vector3(sin(angle), 0.0, cos(angle))
	time_until_turn = randf_range(2.0, 4.0)
