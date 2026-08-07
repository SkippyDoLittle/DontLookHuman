extends SceneTree

const PARK_REACTIONS = preload("res://park_reaction_director.gd")

var _failures: int = 0

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	Engine.time_scale = 1.0
	var level := (
		load("res://scenes/levels/Level02_Playground.tscn") as PackedScene
	).instantiate() as BaseLevel
	root.add_child(level)
	await process_frame
	await process_frame
	paused = false

	var ranger := level.get_node("Ranger") as CharacterBody3D
	var player := level.get_node("Player") as CharacterBody3D
	var hud := level.get_node("HUD") as RangerHUDController
	var pigeons := get_nodes_in_group("pigeons")
	var rangers := get_nodes_in_group("rangers")
	_check(pigeons.size() >= 3, "Playground supplies enough pigeons for deterministic target selection")
	for actor in rangers:
		actor.set_process(false)
		actor.set_physics_process(false)
	for pigeon in pigeons:
		pigeon.set_process(false)
		pigeon.set_physics_process(false)

	var origin := Vector3(0.0, 1.0, 0.0)
	ranger.global_position = origin + Vector3(0.0, -0.475, 0.0)
	player.global_position = origin + Vector3(2.0, 0.0, 0.0)
	for index in pigeons.size():
		var pigeon := pigeons[index] as Node3D
		pigeon.set("_reaction_mode", 0)
		pigeon.set("is_pecking", false)
		pigeon.set("next_peck_timer", 10.0)
		pigeon.global_position = Vector3(20.0 + index, 1.0, 20.0)
	var target := pigeons[0] as Node3D
	var farther_candidate := pigeons[1] as Node3D
	target.global_position = ranger.global_position + Vector3(0.28, 0.475, 0.0)
	farther_candidate.global_position = ranger.global_position + Vector3(0.76, 0.475, 0.0)
	_check(
		target.call("react_to_park_event", PARK_REACTIONS.EVENT_GRAB_WINDUP, ranger.global_position),
		"A nearby pigeon watches the ranger wind-up before the mistake"
	)

	var teammate := rangers[1]
	(teammate as Node3D).global_position = ranger.global_position + Vector3(2.5, 0.0, 0.0)
	for index in range(2, rangers.size()):
		(rangers[index] as Node3D).global_position = Vector3(30.0 + index, 0.525, 30.0)

	var grabbed_targets: Array[Node] = []
	var released_targets: Array[Node] = []
	var player_caught_count := 0
	ranger.connect("wrong_pigeon_grabbed", func(pigeon: Node): grabbed_targets.append(pigeon))
	ranger.connect("wrong_pigeon_released", func(pigeon: Node): released_targets.append(pigeon))
	ranger.connect("player_caught", func(): player_caught_count += 1)
	var suspicion_before := float(ranger.get("suspicion"))
	var base_recovery := float(ranger.get("grab_recovery_duration"))
	ranger.set(
		"last_lunge_closest_distance",
		float(ranger.get("grab_contact_distance")) + 0.1
	)
	ranger.call("_begin_miss_recovery")

	_check(int(ranger.get("wrong_pigeon_grab_count")) == 1, "The closest eligible pigeon becomes the mistaken target")
	_check(grabbed_targets.size() == 1 and grabbed_targets[0] == target, "Ranger emits the exact decoy it grabbed")
	_check(bool(target.get("_mistaken_capture_active")), "The mistaken pigeon enters a dedicated held struggle")
	_check(not bool(farther_candidate.get("_mistaken_capture_active")), "Farther eligible pigeon remains free")
	_check(int(target.get("mistaken_capture_count")) == 1, "Pigeon records one mistaken capture")
	_check(is_equal_approx(float(ranger.get("_grab_timer")), base_recovery), "Mistaken identity preserves the approved first-miss recovery")
	_check(float(target.get("_mistaken_capture_timer")) <= base_recovery, "Pigeon releases before ranger recovery ends")
	_check(int(ranger.get("successful_grabs")) == 0 and not bool(ranger.get("caught")), "Wrong pigeon never counts as a successful player capture")
	_check(player_caught_count == 0 and not bool(player.get("is_captured")), "Player remains in control after the earned dodge")
	_check(int(ranger.get("close_call_count")) == 0, "Mistaken-identity payoff does not stack the close-call cinematic")
	_check(int(hud.get("wrong_pigeon_feedback_count")) == 1, "HUD announces the mistake once")
	_check(hud.get_node("WarnLabel").text == "WRONG BIRD!", "Dedicated mistake feedback replaces the generic miss banner")
	_check(int(teammate.get("teammate_reaction_count")) == 0, "Teammate correction waits for the grabbing ranger's first beat")
	_check(is_equal_approx(float(ranger.get("suspicion")), suspicion_before), "Mistaken identity does not reduce suspicion")
	_check(
		not target.call("react_to_park_event", PARK_REACTIONS.EVENT_PLAYER_EXPOSED, player.global_position),
		"Held pigeon cannot be interrupted by lower-priority park reactions"
	)
	await create_timer(0.52).timeout
	_check(int(teammate.get("teammate_reaction_count")) == 1, "One nearby ranger delivers the delayed correction")
	_check(not ranger.get_node("AlertLabel").visible, "Grabbing ranger's callout clears before the teammate speaks")
	_check(teammate.get_node("AlertLabel").text == "NOT THEM!", "Teammate correction stays short and readable")

	target.call("_process", 0.2)
	var expected_anchor: Vector3 = (
		ranger.global_position
		+ Vector3.UP * 0.92
		- ranger.global_transform.basis.z * 0.22
	)
	_check(target.global_position.distance_to(expected_anchor) < 0.02, "Struggling pigeon stays visibly anchored between the ranger's arms")
	_check(target.get_node("PigeonVisual/MistakenLeftWing").visible, "Left struggle wing becomes visible while held")
	_check(target.get_node("PigeonVisual/MistakenRightWing").visible, "Right struggle wing becomes visible while held")
	target.call("_process", 1.0)
	_check(not bool(target.get("_mistaken_capture_active")), "Pigeon is automatically released inside the recovery window")
	_check(released_targets.size() == 1 and released_targets[0] == target, "Ranger receives one release event from its decoy")
	_check(not target.get_node("PigeonVisual/MistakenLeftWing").visible, "Temporary struggle wings hide after release")
	_check(int(target.get("_reaction_mode")) == 2, "Released pigeon panics away from the ranger")

	ranger.set("grab_phase", 0)
	ranger.set("last_lunge_closest_distance", INF)
	farther_candidate.set("_reaction_mode", 0)
	farther_candidate.set("is_pecking", false)
	farther_candidate.global_position = ranger.global_position + Vector3(0.35, 0.475, 0.0)
	ranger.call("_begin_miss_recovery")
	_check(int(ranger.get("wrong_pigeon_grab_count")) == 1, "Six-second lockout prevents repeated wrong grabs")
	_check(not bool(farther_candidate.get("_mistaken_capture_active")), "Cooldown miss keeps the next pigeon free")

	ranger.set("_wrong_pigeon_cooldown", 0.0)
	ranger.set("grab_phase", 0)
	farther_candidate.set("_reaction_mode", 0)
	ranger.call("_begin_miss_recovery")
	_check(int(ranger.get("wrong_pigeon_grab_count")) == 2, "Mistaken identity can rearm after its cooldown")
	_check(is_equal_approx(float(ranger.get("suspicion")), suspicion_before), "Repeated presentation still leaves suspicion math untouched")

	level.queue_free()
	await process_frame
	await _validate_full_grab_timing()
	if _failures == 0:
		print("PHASE18_MISTAKEN_IDENTITY_VALIDATION_OK")
	quit(_failures)

func _validate_full_grab_timing() -> void:
	var level := (
		load("res://scenes/levels/Level01_Park.tscn") as PackedScene
	).instantiate() as BaseLevel
	root.add_child(level)
	await process_frame
	await process_frame
	paused = false
	var ranger := level.get_node("Ranger2") as CharacterBody3D
	var player := level.get_node("Player") as CharacterBody3D
	var pigeons := get_nodes_in_group("pigeons")
	var rangers := get_nodes_in_group("rangers")
	for actor in rangers:
		actor.set_process(false)
		actor.set_physics_process(false)
	for pigeon in pigeons:
		pigeon.set_process(false)
		pigeon.set_physics_process(false)
		pigeon.set("_reaction_mode", 0)
		pigeon.set("is_pecking", false)

	var start := Vector3(0.0, 0.525, 0.0)
	ranger.global_position = start
	player.global_position = Vector3(2.0, 1.0, 0.0)
	for index in pigeons.size():
		(pigeons[index] as Node3D).global_position = Vector3(24.0 + index, 1.0, 24.0)
	var target := pigeons[0] as Node3D
	var lunge_distance := float(ranger.get("grab_lunge_speed")) * float(ranger.get("grab_lunge_duration"))
	target.global_position = start + Vector3(lunge_distance, 0.475, 0.0)

	ranger.call("_begin_grab")
	_check(int(target.get("_reaction_mode")) == 1, "Potential decoy watches the real ranger wind-up")
	var windup_duration := float(ranger.get("grab_windup_duration"))
	target.call("_process", windup_duration)
	ranger.call("_update_grab", windup_duration)
	_check(int(ranger.get("grab_phase")) == 2, "Slowest campaign wind-up advances into its real lunge")
	player.global_position = Vector3(6.0, 1.0, 0.0)
	var lunge_direction: Vector3 = ranger.get("_grab_direction")
	var remaining := float(ranger.get("grab_lunge_duration"))
	while remaining > 0.0001:
		var step := minf(remaining, 0.04)
		target.call("_process", step)
		_check(int(target.get("_reaction_mode")) == 1, "Decoy stays put for the entire lunge instead of fleeing early")
		ranger.global_position += lunge_direction * float(ranger.get("grab_lunge_speed")) * step
		ranger.call("_update_grab", step)
		remaining -= step
	_check(int(ranger.get("wrong_pigeon_grab_count")) == 1, "Full wind-up and lunge can produce the intended wrong-pigeon grab")
	_check(bool(target.get("_mistaken_capture_active")), "Live-timing decoy enters the held struggle at the miss endpoint")
	level.queue_free()
	await process_frame

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("Phase 18 mistaken-identity validation failed: %s" % message)
