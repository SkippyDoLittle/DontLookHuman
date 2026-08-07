extends SceneTree

const PARK_REACTIONS = preload("res://park_reaction_director.gd")

var _failures: int = 0

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	Engine.time_scale = 1.0
	var level := (
		load("res://scenes/levels/Level01_Park.tscn") as PackedScene
	).instantiate() as BaseLevel
	root.add_child(level)
	await process_frame
	await process_frame
	paused = false

	var controller := level.get_node("ParkChaosController") as ParkChaosController
	var hud := level.get_node("HUD") as RangerHUDController
	var player := level.get_node("Player") as CharacterBody3D
	var pigeons := get_nodes_in_group("pigeons")
	var rangers := get_nodes_in_group("rangers")
	_check(pigeons.size() >= 5, "Level 1 supplies enough pigeons for a readable wave")
	for ranger in rangers:
		ranger.call("halt_for_capture")
		(ranger as Node3D).global_position = Vector3(30.0, 1.0, 30.0)

	var origin := Vector3(0.0, 1.0, 0.0)
	player.global_position = origin
	for index in pigeons.size():
		var pigeon := pigeons[index] as Node3D
		pigeon.set("_reaction_mode", 0)
		pigeon.set("is_pecking", false)
		pigeon.set("next_peck_timer", 10.0)
		if index < 4:
			var angle := float(index) / 4.0 * TAU
			pigeon.global_position = origin + Vector3(sin(angle), 0.0, cos(angle)) * (1.35 + index * 0.35)
		else:
			pigeon.global_position = Vector3(18.0 + index, 1.0, 18.0)

	var sync_joiners: Array[int] = []
	controller.connect(
		"flock_sync_started",
		func(joiner_count: int, _origin: Vector3): sync_joiners.append(joiner_count)
	)
	var suspicion_before: Array[float] = []
	for ranger in rangers:
		suspicion_before.append(float(ranger.get("suspicion")))

	_check(player.call("start_player_peck"), "A calm player can start the existing peck action")
	_check(int(controller.get("flock_sync_event_count")) == 1, "One player peck starts one flock-sync wave")
	_check(sync_joiners.size() == 1 and sync_joiners[0] == 4, "Only the four nearby calm pigeons join")
	_check(int(hud.get("flock_sync_feedback_count")) == 1, "HUD acknowledges the successful blend once")
	_check(hud.get_node("WarnLabel").text == "FLOCK SYNC x4", "HUD makes the size of the flock response readable")
	_check(not player.call("start_player_peck"), "The public peck start preserves the existing active-peck guard")
	_check(int(controller.get("flock_sync_event_count")) == 1, "Rejected repeated input cannot duplicate the wave")
	for index in 4:
		_check(bool(pigeons[index].get("_mimic_pending")), "Nearby pigeon %d waits for its distance beat" % index)
	for index in range(4, pigeons.size()):
		_check(not bool(pigeons[index].get("_mimic_pending")), "Distant pigeon %d ignores the player peck" % index)
	for index in rangers.size():
		_check(
			is_equal_approx(float(rangers[index].get("suspicion")), suspicion_before[index]),
			"Flock sync does not change ranger %d suspicion" % index
		)

	for index in 4:
		pigeons[index].call("_process", 0.5)
		_check(int(pigeons[index].get("mimic_peck_count")) == 1, "Nearby pigeon %d completes one delayed mimic" % index)

	var interrupted := pigeons[0]
	_check(
		interrupted.call("react_to_park_event", PARK_REACTIONS.EVENT_PLAYER_EXPOSED, origin),
		"Exposure panic reaches a synchronized pigeon"
	)
	_check(not bool(interrupted.get("_mimic_active")), "Panic immediately cancels a mimic peck")
	_check(
		not interrupted.call("request_mimic_peck", origin, 0.0),
		"A reacting pigeon cannot be pulled back into the cosmetic wave"
	)

	controller.call("_on_player_peck_started", origin)
	_check(int(controller.get("flock_sync_event_count")) == 1, "Wave cooldown suppresses immediate repetition")
	hud.call("_show_warning", "DANGER!", Color.RED, 1.0)
	_check(not hud.call("trigger_flock_sync_feedback", 4), "Blend feedback yields to an active danger warning")
	_check(hud.get_node("WarnLabel").text == "DANGER!", "Danger text remains visible when flock feedback is rejected")

	controller.call("_process", 1.0)
	for index in range(1, 4):
		var pigeon := pigeons[index]
		pigeon.call("_cancel_mimic_peck")
		pigeon.set("is_pecking", false)
		pigeon.set("_reaction_mode", 0)
		pigeon.set("next_peck_timer", 10.0)
	controller.call("_on_player_peck_started", origin)
	_check(int(controller.get("flock_sync_event_count")) == 2, "A later calm peck can start another bounded wave")

	level.queue_free()
	await process_frame
	if _failures == 0:
		print("PHASE17_FLOCK_SYNC_VALIDATION_OK")
	quit(_failures)

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("Phase 17 flock-sync validation failed: %s" % message)
