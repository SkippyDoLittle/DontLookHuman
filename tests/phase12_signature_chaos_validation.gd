extends SceneTree

const PARK_REACTIONS = preload("res://park_reaction_director.gd")

var _failures: int = 0

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	await _validate_food_frenzy()
	await _validate_swing_surprise()
	await _validate_lakeside_splash()
	await _validate_festival_frenzy()
	await _validate_sprinkler_finale()
	if _failures == 0:
		print("PHASE12_SIGNATURE_CHAOS_VALIDATION_OK")
	quit(_failures)

func _validate_food_frenzy() -> void:
	var level := await _load_level("res://scenes/levels/Level01_Park.tscn")
	var controller := level.get_node("ParkChaosController") as ParkChaosController
	var food := level.get_node("PicnicFood") as Node3D
	var pigeon := level.get_node("NPC_Animal") as Node3D
	pigeon.global_position = food.global_position + Vector3(1.0, 0.0, 0.0)
	var reactions_before := int(pigeon.get("reaction_count"))
	food.emit_signal("food_collected", food, food.global_position)
	await process_frame
	_check(controller.signature_event_count == 1, "Park triggers exactly one signature event")
	_check(controller.last_event_name == PARK_REACTIONS.EVENT_FOOD_FRENZY, "Park uses a feeding frenzy")
	_check(int(pigeon.get("reaction_count")) > reactions_before, "Park pigeons swarm the stolen food")
	food.emit_signal("food_collected", food, food.global_position)
	_check(controller.signature_event_count == 1, "Park frenzy cannot spam")
	await _unload_level(level)

func _validate_swing_surprise() -> void:
	var level := await _load_level("res://scenes/levels/Level02_Playground.tscn")
	var controller := level.get_node("ParkChaosController") as ParkChaosController
	var food := level.get_node("PicnicFood2") as Node3D
	var swing := level.get_node("SwingSeatR") as Node3D
	var start_rotation := swing.rotation.x
	food.emit_signal("food_collected", food, food.global_position)
	await create_timer(0.12).timeout
	_check(controller.last_event_name == PARK_REACTIONS.EVENT_SWING_CHAOS, "Playground food wakes the swings")
	_check(not is_equal_approx(swing.rotation.x, start_rotation), "Playground swing visibly moves")
	_check(controller.signature_event_count == 1, "Playground surprise triggers once")
	await _unload_level(level)

func _validate_lakeside_splash() -> void:
	var level := await _load_level("res://scenes/levels/Level03_Lakeside.tscn")
	var controller := level.get_node("ParkChaosController") as ParkChaosController
	var water := level.get_node("Lake/WaterZone") as Area3D
	var origin := water.global_position
	water.emit_signal("player_splashed", origin)
	await process_frame
	_check(controller.last_event_name == PARK_REACTIONS.EVENT_WATER_SPLASH, "Lakeside reacts to the first splash")
	_check(controller.signature_event_count == 1, "Lakeside splash event triggers once")
	water.emit_signal("player_splashed", origin)
	_check(controller.signature_event_count == 1, "Repeated lake entry does not spam the event")
	await _unload_level(level)

func _validate_festival_frenzy() -> void:
	var level := await _load_level("res://scenes/levels/Level04_Festival.tscn")
	var controller := level.get_node("ParkChaosController") as ParkChaosController
	var popcorn := level.get_node("PicnicFood4") as Node3D
	var pigeon := level.get_node("NPC_Animal") as Node3D
	pigeon.global_position = popcorn.global_position + Vector3(1.0, 0.0, 0.0)
	var reactions_before := int(pigeon.get("reaction_count"))
	popcorn.emit_signal("food_collected", popcorn, popcorn.global_position)
	await process_frame
	_check(controller.last_event_name == PARK_REACTIONS.EVENT_FESTIVAL_FRENZY, "Festival popcorn starts its larger frenzy")
	_check(int(pigeon.get("reaction_count")) > reactions_before, "Festival flock joins the popcorn panic")
	_check(controller.signature_event_count == 1, "Festival frenzy triggers once")
	await _unload_level(level)

func _validate_sprinkler_finale() -> void:
	var level := await _load_level("res://scenes/levels/Level05_BotanicalGardens.tscn")
	var controller := level.get_node("ParkChaosController") as ParkChaosController
	var foods: Array[Node] = []
	for index in range(1, 6):
		var node_name := "PicnicFood" if index == 1 else "PicnicFood%d" % index
		foods.append(level.get_node(node_name))
	for index in range(foods.size()):
		var food := foods[index] as Node3D
		food.emit_signal("food_collected", food, food.global_position)
		if index < foods.size() - 1:
			_check(controller.signature_event_count == 0, "Botanical finale waits for all food")
	await process_frame
	_check(controller.last_event_name == PARK_REACTIONS.EVENT_SPRINKLER_BURST, "Botanical finale activates the fountain sprinklers")
	_check(controller.signature_event_count == 1, "Botanical sprinkler finale triggers once")
	_check(level.has_node("SprinklerChaosRig"), "Botanical finale creates visible sweeping water")
	await _unload_level(level)

func _load_level(path: String) -> BaseLevel:
	var level := (load(path) as PackedScene).instantiate() as BaseLevel
	root.add_child(level)
	await process_frame
	await process_frame
	paused = false
	var controller := level.get_node_or_null("ParkChaosController")
	_check(controller is ParkChaosController, "%s has the shared chaos controller" % path.get_file())
	_check(level.get_node("HUD").has_node("ChaosEventLabel"), "%s has event feedback" % path.get_file())
	return level

func _unload_level(level: BaseLevel) -> void:
	paused = false
	level.queue_free()
	await process_frame

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("Phase 12 signature-chaos validation failed: %s" % message)
