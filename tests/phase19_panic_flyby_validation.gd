extends SceneTree

const PARK_REACTIONS = preload("res://park_reaction_director.gd")

var _failures: int = 0

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	Engine.time_scale = 1.0
	var level := (
		load("res://scenes/levels/Level03_Lakeside.tscn") as PackedScene
	).instantiate() as BaseLevel
	root.add_child(level)
	await process_frame
	await process_frame
	paused = false

	var ranger := level.get_node("Ranger") as CharacterBody3D
	var pigeons := get_nodes_in_group("pigeons")
	var rangers := get_nodes_in_group("rangers")
	_check(pigeons.size() >= 2, "Lakeside supplies pigeons for flyby and regroup validation")
	for actor in rangers:
		actor.set_process(false)
		actor.set_physics_process(false)
	for pigeon in pigeons:
		pigeon.set_process(false)
		pigeon.set_physics_process(false)
		(pigeon as Node3D).global_position = Vector3(20.0, 1.0, 20.0)
	for index in range(1, rangers.size()):
		(rangers[index] as Node3D).global_position = Vector3(30.0 + index, 0.525, 30.0)

	var pigeon := pigeons[0] as CharacterBody3D
	pigeon.global_position = Vector3(0.0, 1.0, 0.0)
	ranger.global_position = Vector3(0.52, 0.525, 0.0)
	ranger.set("capture_personality", "Steady")
	ranger.set("suspicion", 78.0)
	ranger.set("grab_phase", 0)
	var suspicion_before := float(ranger.get("suspicion"))
	var ranger_position_before := ranger.global_position
	var movement := ranger.get("_movement") as RangerMovement
	movement.call("move_in_direction", Vector3.RIGHT, 1.7)
	var movement_before: Vector3 = movement.get("_desired_move")
	var ranger_events: Array[Node] = []
	var pigeon_events: Array[Node3D] = []
	ranger.connect("panic_pigeon_near_miss", func(actor: Node): ranger_events.append(actor))
	pigeon.connect("panic_ranger_near_miss", func(actor: Node3D): pigeon_events.append(actor))

	var panic_origin := Vector3(-1.0, 1.0, 0.0)
	_check(
		pigeon.call("react_to_park_event", PARK_REACTIONS.EVENT_PLAYER_EXPOSED, panic_origin),
		"Exposure starts a real pigeon panic"
	)
	pigeon.call("_process", 0.04)
	pigeon.call("_process", 0.02)
	_check(int(pigeon.get("panic_ranger_near_miss_count")) == 1, "One close panic path creates one accepted flyby")
	_check(int(ranger.get("panic_pigeon_reaction_count")) == 1, "Ranger reacts once to the incoming pigeon")
	_check(ranger_events.size() == 1 and ranger_events[0] == pigeon, "Ranger signal identifies the exact flyby pigeon")
	_check(pigeon_events.size() == 1 and pigeon_events[0] == ranger, "Pigeon signal identifies the exact startled ranger")
	_check(ranger.get_node("AlertLabel").text == "WHOA!", "Steady ranger uses its personality flyby callout")
	_check(level.has_node("PanicFlybyFeathers"), "Flyby throws a small readable feather burst")
	_check(is_equal_approx(float(ranger.get("suspicion")), suspicion_before), "Flyby never changes suspicion")
	_check(int(ranger.get("grab_phase")) == 0, "Flyby never enters or extends a grab phase")
	_check(is_equal_approx(float(ranger.get("_chaos_distraction_timer")), 0.0), "Flyby does not distract or stop ranger AI")
	_check(ranger.global_position == ranger_position_before, "Presentation does not teleport the ranger")
	var movement_after: Vector3 = movement.get("_desired_move")
	_check(movement_after.is_equal_approx(movement_before), "Presentation preserves the ranger's intended movement")

	pigeon.call("react_to_park_event", PARK_REACTIONS.EVENT_PLAYER_EXPOSED, panic_origin)
	pigeon.call("_process", 0.04)
	pigeon.call("_process", 0.02)
	_check(int(ranger.get("panic_pigeon_reaction_count")) == 1, "Ranger cooldown rejects an immediate second flyby")
	_check(bool(pigeon.get("_panic_ranger_near_miss_consumed")), "Rejected proximity is still consumed for the current panic")

	ranger.set("_panic_pigeon_reaction_cooldown", 0.0)
	pigeon.call("react_to_park_event", PARK_REACTIONS.EVENT_PLAYER_EXPOSED, panic_origin)
	pigeon.call("_process", 0.04)
	pigeon.call("_process", 0.02)
	_check(int(ranger.get("panic_pigeon_reaction_count")) == 2, "A later panic can rearm after the ranger cooldown")

	ranger.set("_panic_pigeon_reaction_cooldown", 0.0)
	ranger.set("grab_phase", 1)
	pigeon.call("react_to_park_event", PARK_REACTIONS.EVENT_PLAYER_EXPOSED, panic_origin)
	pigeon.call("_process", 0.04)
	pigeon.call("_process", 0.02)
	_check(int(ranger.get("panic_pigeon_reaction_count")) == 2, "Active grab animation always outranks a background flyby")
	_check(int(ranger.get("grab_phase")) == 1, "Rejected flyby leaves the grab phase untouched")
	_check(is_equal_approx(float(ranger.get("suspicion")), suspicion_before), "All flyby outcomes preserve suspicion math")

	for actor in rangers:
		(actor as Node3D).global_position = Vector3(30.0, 0.525, 30.0)
	var regroup_pigeon := pigeons[1] as CharacterBody3D
	var regroup_origin := Vector3(0.0, 1.0, 0.0)
	regroup_pigeon.global_position = Vector3(1.0, 1.0, 0.0)
	regroup_pigeon.set("_reaction_mode", 0)
	regroup_pigeon.call(
		"react_to_park_event",
		PARK_REACTIONS.EVENT_PLAYER_EXPOSED,
		regroup_origin
	)
	regroup_pigeon.call("_process", 0.04)
	regroup_pigeon.call("_process", 0.02)
	var maximum_event_distance := regroup_pigeon.global_position.distance_to(regroup_origin)
	var observed_inward_regroup := false
	for _step in 8:
		regroup_pigeon.call("_process", 0.1)
		var desired_move: Vector3 = regroup_pigeon.get("_desired_move")
		var rally_target: Vector3 = regroup_pigeon.get("_panic_rally_target")
		var toward_rally := rally_target - regroup_pigeon.global_position
		toward_rally.y = 0.0
		if bool(regroup_pigeon.get("_panic_regroup_started")) and desired_move.dot(toward_rally) > 0.0:
			observed_inward_regroup = true
		regroup_pigeon.global_position += desired_move * 0.1
		maximum_event_distance = maxf(
			maximum_event_distance,
			regroup_pigeon.global_position.distance_to(regroup_origin)
		)
	var rally_target: Vector3 = regroup_pigeon.get("_panic_rally_target")
	for _step in 8:
		regroup_pigeon.call("_process", 0.1)
		var desired_move: Vector3 = regroup_pigeon.get("_desired_move")
		var toward_rally := rally_target - regroup_pigeon.global_position
		toward_rally.y = 0.0
		if desired_move.dot(toward_rally) > 0.0:
			observed_inward_regroup = true
		regroup_pigeon.global_position += desired_move * 0.1
		maximum_event_distance = maxf(
			maximum_event_distance,
			regroup_pigeon.global_position.distance_to(regroup_origin)
		)
	_check(int(regroup_pigeon.get("panic_regroup_count")) == 1, "Panic switches from scatter to regroup exactly once")
	_check(observed_inward_regroup, "Regroup phase turns the pigeon back toward its nearby rally ring")
	_check(maximum_event_distance < 4.6, "Bounded panic cannot carry the pigeon to the map edge")
	_check(absf(rally_target.x) <= 7.2 and absf(rally_target.z) <= 7.2, "Rally target stays inside the normal roaming area")

	level.queue_free()
	await process_frame
	if _failures == 0:
		print("PHASE19_PANIC_FLYBY_VALIDATION_OK")
	quit(_failures)

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("Phase 19 panic-flyby validation failed: %s" % message)
