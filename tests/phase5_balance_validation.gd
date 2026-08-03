extends SceneTree

const WALK_SPEED: float = 1.2
const SUSTAINED_MIXED_SPEED: float = 2.13
const PLAYABLE_RADIUS: float = 15.0

var _failures: int = 0

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var paths: Array[String] = [
		"res://scenes/levels/Level01_Park.tscn",
		"res://scenes/levels/Level02_Playground.tscn",
		"res://scenes/levels/Level03_Lakeside.tscn",
		"res://scenes/levels/Level04_Festival.tscn",
		"res://scenes/levels/Level05_BotanicalGardens.tscn",
	]

	var previous_pressure: float = -INF
	for path in paths:
		var pressure := await _measure_level(path)
		_check(
			pressure > previous_pressure,
			"%s increases the route pressure over the previous level" % path
		)
		previous_pressure = pressure

	if _failures == 0:
		print("PHASE5_BALANCE_VALIDATION_OK")
	quit(_failures)

func _measure_level(path: String) -> float:
	var level := (load(path) as PackedScene).instantiate()
	root.add_child(level)
	await process_frame
	await process_frame

	var player := level.get_node("Player") as Node3D
	var exit := level.get_node("EscapeZone") as Node3D
	var session := level.get_node("GameTimer") as GameSession
	var foods: Array[Node3D] = []
	var rangers: Array[Node3D] = []
	var pigeons: Array[Node3D] = []
	for node in get_nodes_in_group("collectibles"):
		if node is Node3D:
			foods.append(node)
	for node in get_nodes_in_group("rangers"):
		if node is Node3D:
			rangers.append(node)
	for node in get_nodes_in_group("pigeons"):
		if node is Node3D:
			pigeons.append(node)

	var route_distance := _shortest_route(player.global_position, foods, exit.global_position)
	var expert_estimate := route_distance / SUSTAINED_MIXED_SPEED * 1.35 + foods.size() * 0.85
	var first_attempt_estimate := route_distance / WALK_SPEED * 1.45 + foods.size() * 1.5
	var spawn_margin := _spawn_safety_margin(player, rangers)
	var exposed_food := _count_exposed_food(foods, rangers)
	var covered_food := _count_food_with_pigeon_cover(foods, pigeons)
	var pigeons_inside := _count_inside_playable_area(pigeons)
	var visitors := _get_visitors(level)
	var visitors_inside := _count_inside_playable_area(visitors)
	var route_pressure := _route_pressure_index(route_distance, rangers)

	print(
		(
			"BALANCE|%s|route=%.1f|timer=%.0f|expert=%.1f|first=%.1f|rangers=%d|"
			+ "pigeons=%d/%d|visitors=%d|spawn_margin=%.1f|exposed_food=%d|"
			+ "covered_food=%d|pressure=%.1f"
		)
		% [
			String(session.get_parent().get("level_config").level_id),
			route_distance,
			session.time_limit,
			expert_estimate,
			first_attempt_estimate,
			rangers.size(),
			pigeons_inside,
			pigeons.size(),
			visitors_inside,
			spawn_margin,
			exposed_food,
			covered_food,
			route_pressure,
		]
	)

	_check(foods.size() == 5, "%s keeps five collectibles" % path)
	_check(spawn_margin >= 0.5, "%s starts safely outside every ranger notice radius" % path)
	_check(session.time_limit >= expert_estimate + 10.0, "%s leaves expert recovery time" % path)
	_check(session.time_limit >= first_attempt_estimate, "%s supports the modeled first attempt" % path)
	_check(pigeons_inside == pigeons.size(), "%s keeps every pigeon inside the park" % path)
	_check(visitors_inside == visitors.size(), "%s keeps every visitor inside the park" % path)
	_check(covered_food >= 3, "%s provides pigeon cover near at least three foods" % path)

	paused = false
	level.queue_free()
	await process_frame
	return route_pressure

func _route_pressure_index(route_distance: float, rangers: Array[Node3D]) -> float:
	var total_notice: float = 0.0
	var total_active_gain: float = 0.0
	var total_recovery: float = 0.0
	for ranger in rangers:
		total_notice += float(ranger.get("notice_distance"))
		total_active_gain += (
			float(ranger.get("suspicion_gain_per_second"))
			+ float(ranger.get("separation_gain_per_second"))
		)
		total_recovery += float(ranger.get("suspicion_loss_per_second"))
	var ranger_count := float(rangers.size())
	var average_notice := total_notice / ranger_count
	var average_active_gain := total_active_gain / ranger_count
	var average_recovery := total_recovery / ranger_count
	return (
		ranger_count
		* average_notice
		* average_active_gain
		/ average_recovery
		* route_distance
		/ 50.0
	)

func _shortest_route(start: Vector3, foods: Array[Node3D], finish: Vector3) -> float:
	var indices: Array[int] = []
	for index in foods.size():
		indices.append(index)
	var best: float = INF
	for order in _permutations(indices):
		var distance: float = 0.0
		var current := start
		for index in order:
			distance += _flat_distance(current, foods[index].global_position)
			current = foods[index].global_position
		distance += _flat_distance(current, finish)
		best = minf(best, distance)
	return best

func _permutations(values: Array[int]) -> Array[Array]:
	if values.size() <= 1:
		return [values.duplicate()]
	var result: Array[Array] = []
	for index in values.size():
		var remaining := values.duplicate()
		var head: int = remaining.pop_at(index)
		for tail in _permutations(remaining):
			var order: Array = [head]
			order.append_array(tail)
			result.append(order)
	return result

func _spawn_safety_margin(player: Node3D, rangers: Array[Node3D]) -> float:
	var margin: float = INF
	for ranger in rangers:
		margin = minf(
			margin,
			_flat_distance(player.global_position, ranger.global_position)
			- float(ranger.get("notice_distance"))
		)
	return margin

func _count_exposed_food(foods: Array[Node3D], rangers: Array[Node3D]) -> int:
	var exposed: int = 0
	for food in foods:
		for ranger in rangers:
			if _flat_distance(food.global_position, ranger.global_position) <= float(ranger.get("notice_distance")):
				exposed += 1
				break
	return exposed

func _count_food_with_pigeon_cover(foods: Array[Node3D], pigeons: Array[Node3D]) -> int:
	var covered: int = 0
	for food in foods:
		for pigeon in pigeons:
			if _flat_distance(food.global_position, pigeon.global_position) <= 5.0:
				covered += 1
				break
	return covered

func _count_inside_playable_area(nodes: Array[Node3D]) -> int:
	var count: int = 0
	for node in nodes:
		if absf(node.global_position.x) <= PLAYABLE_RADIUS and absf(node.global_position.z) <= PLAYABLE_RADIUS:
			count += 1
	return count

func _get_visitors(level: Node) -> Array[Node3D]:
	var visitors: Array[Node3D] = []
	for child in level.get_children():
		if child is Node3D and (child.name.begins_with("ParkVisitor") or child.name.begins_with("Visitor_s")):
			visitors.append(child)
	return visitors

func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("Phase 5 balance validation failed: %s" % message)
