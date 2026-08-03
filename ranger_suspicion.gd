class_name RangerSuspicion
extends RefCounted

var suspicion: float = 0.0
var caught: bool = false

var _ranger: CharacterBody3D
var _player: CharacterBody3D
var _pigeon_visual: Node3D
var _config: Dictionary

var _stare_time: float = 0.0
var _food_aim_time: float = 0.0
var _straight_time: float = 0.0
var _last_move_direction: Vector2 = Vector2.ZERO
var _still_time: float = 0.0

func configure(
	ranger: CharacterBody3D,
	player: CharacterBody3D,
	pigeon_visual: Node3D,
	config: Dictionary
) -> void:
	_ranger = ranger
	_player = player
	_pigeon_visual = pigeon_visual
	_config = config

func update(delta: float) -> Dictionary:
	if caught:
		return {"active_gain": 0.0, "reason": "", "is_nearby": true}

	var distance_to_player := _ranger.global_position.distance_to(_player.global_position)
	var player_speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	var effective_notice := _effective_notice_distance()
	var is_nearby := distance_to_player <= effective_notice
	var active_gain: float = 0.0
	var reason: String = ""

	if is_nearby and player_speed > float(_config.suspicious_speed):
		active_gain += float(_config.suspicion_gain_per_second)
		reason = "Too fast!"

	if is_nearby and _is_aiming_at_food(player_speed):
		_food_aim_time += delta
		if _food_aim_time >= float(_config.food_aim_delay):
			active_gain += float(_config.food_aim_gain_per_second)
			if reason.is_empty():
				reason = "Moving suspiciously"
	else:
		_food_aim_time = maxf(_food_aim_time - delta * 2.0, 0.0)

	if is_nearby and player_speed > 0.1 and _is_facing_ranger():
		_stare_time += delta
		if _stare_time >= float(_config.stare_delay):
			active_gain += float(_config.stare_gain_per_second)
			if reason.is_empty():
				reason = "Staring..."
	else:
		_stare_time = maxf(_stare_time - delta * 2.0, 0.0)

	if is_nearby and _is_isolated():
		active_gain += float(_config.separation_gain_per_second)
		if reason.is_empty():
			reason = "Acting alone"

	if is_nearby and bool(_player.get("in_water")):
		active_gain += 12.0
		if reason.is_empty():
			reason = "In the water!"

	active_gain = _apply_straight_line_detection(delta, is_nearby, player_speed, active_gain)
	if active_gain > 0.0 and reason.is_empty() and _straight_time >= float(_config.straight_line_threshold):
		reason = "Moving too straight"

	var still_gain := _apply_still_detection(delta, is_nearby, player_speed)
	active_gain += still_gain
	if still_gain > 0.0 and reason.is_empty():
		reason = "Standing still"

	if active_gain > 0.0:
		suspicion = minf(suspicion + active_gain * delta, 100.0)
	else:
		var loss_rate := float(_config.suspicion_loss_per_second)
		if bool(_player.get("is_pecking")):
			loss_rate += float(_config.peck_loss_per_second)
		suspicion = maxf(suspicion - loss_rate * delta, 0.0)

	if suspicion >= 100.0:
		caught = true

	return {"active_gain": active_gain, "reason": reason, "is_nearby": is_nearby}

func _effective_notice_distance() -> float:
	if suspicion >= float(_config.chase_threshold):
		return 20.0
	if suspicion >= float(_config.investigate_threshold):
		return float(_config.notice_distance) * 2.0
	return float(_config.notice_distance)

func _apply_straight_line_detection(
	delta: float,
	is_nearby: bool,
	player_speed: float,
	active_gain: float
) -> float:
	if is_nearby and player_speed > 0.3:
		var current_direction := Vector2(_player.velocity.x, _player.velocity.z).normalized()
		if _last_move_direction.length() > 0.5:
			var dot := current_direction.dot(_last_move_direction)
			if dot >= float(_config.straight_line_dot):
				_straight_time += delta
				if _straight_time >= float(_config.straight_line_threshold):
					active_gain += float(_config.straight_line_gain_per_second)
			else:
				_straight_time = maxf(_straight_time - delta * 2.0, 0.0)
		_last_move_direction = current_direction
	else:
		_straight_time = maxf(_straight_time - delta * 3.0, 0.0)
		if player_speed <= 0.1:
			_last_move_direction = Vector2.ZERO
	return active_gain

func _apply_still_detection(delta: float, is_nearby: bool, player_speed: float) -> float:
	if is_nearby and player_speed < 0.1 and not bool(_player.get("is_pecking")):
		_still_time += delta
		if _still_time >= float(_config.still_threshold):
			return float(_config.still_gain_per_second)
	else:
		_still_time = maxf(_still_time - delta * 1.5, 0.0)
	return 0.0

func _is_aiming_at_food(player_speed: float) -> bool:
	if player_speed < 0.3:
		return false
	var food_item := _get_nearest_food()
	if food_item == null:
		return false
	var to_food := food_item.global_position - _player.global_position
	to_food.y = 0.0
	if to_food.length() < 0.5:
		return false
	var move_direction := Vector2(_player.velocity.x, _player.velocity.z).normalized()
	var food_direction := Vector2(to_food.x, to_food.z).normalized()
	return move_direction.dot(food_direction) >= float(_config.food_aim_threshold)

func _get_nearest_food() -> Node3D:
	var nearest: Node3D = null
	var nearest_distance: float = INF
	for item in _ranger.get_tree().get_nodes_in_group("collectibles"):
		var food_node := item as Node3D
		if food_node == null:
			continue
		var distance := _player.global_position.distance_to(food_node.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = food_node
	return nearest

func _is_facing_ranger() -> bool:
	var to_ranger := _ranger.global_position - _player.global_position
	to_ranger.y = 0.0
	if to_ranger.length() < 0.5:
		return false
	var forward := _pigeon_visual.global_transform.basis.z
	forward.y = 0.0
	return forward.normalized().dot(to_ranger.normalized()) >= float(_config.stare_threshold)

func _is_isolated() -> bool:
	var separation_squared := pow(float(_config.separation_distance), 2.0)
	for npc in _ranger.get_tree().get_nodes_in_group("pigeons"):
		if (
			is_instance_valid(npc)
			and npc is Node3D
			and _player.global_position.distance_squared_to(npc.global_position) <= separation_squared
		):
			return false
	return true
