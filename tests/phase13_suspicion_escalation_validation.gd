extends SceneTree

var _failures: int = 0

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var level := (
		load("res://scenes/levels/Level02_Playground.tscn") as PackedScene
	).instantiate() as BaseLevel
	root.add_child(level)
	await process_frame
	await process_frame
	paused = false

	var controller := level.get_node("ParkChaosController") as ParkChaosController
	var hud := level.get_node("HUD") as RangerHUDController
	var player := level.get_node("Player") as CharacterBody3D
	var ranger := level.get_node("Ranger2")
	var pigeon := level.get_node("NPC_Animal")
	var visitor := get_nodes_in_group("visitors")[0]
	pigeon.global_position = player.global_position + Vector3(1.0, 0.0, 0.0)
	visitor.global_position = player.global_position + Vector3(2.0, -0.475, 0.0)
	var pigeon_reactions_before := int(pigeon.get("reaction_count"))
	var visitor_reactions_before := int(visitor.get("reaction_count"))
	var suspicion_before := float(ranger.get("suspicion"))

	ranger.emit_signal("state_changed", RangerStateMachine.State.CHASE)
	_check(controller.exposure_event_count == 1, "First chase starts one park-wide exposure cascade")
	_check(int(pigeon.get("reaction_count")) > pigeon_reactions_before, "The flock panics when the player is exposed")
	_check(int(visitor.get("reaction_count")) > visitor_reactions_before, "Visitors react when the player is exposed")
	_check(int(controller.exposure_reaction_counts.get("pigeons", 0)) > 0, "Exposure cascade reaches nearby pigeons")
	_check(int(controller.exposure_reaction_counts.get("visitors", 0)) > 0, "Exposure cascade reaches nearby visitors")
	_check(int(player.get("camera_shake_count")) == 1, "Exposure adds one controlled camera punch")
	_check(int(hud.get("exposure_feedback_count")) == 1, "Exposure flashes the HUD once")
	_check(hud.get_node("WarnLabel").text == "SPOTTED!", "Exposure clearly names the mistake")
	_check(hud.get_node("RangerStatus").text == "Rangers: Alert!", "Secondary detection never contradicts the global danger state")
	_check(int(hud.get("_highest_state")) == RangerStateMachine.State.CHASE, "A secondary ranger drives global danger feedback")
	_check(is_equal_approx(float(ranger.get("suspicion")), suspicion_before), "Feedback does not secretly increase difficulty")

	ranger.emit_signal("state_changed", RangerStateMachine.State.CHASE)
	_check(controller.exposure_event_count == 1, "Repeated chase signals cannot spam the cascade")

	for candidate in get_nodes_in_group("rangers"):
		candidate.set("suspicion", 0.0)
		(candidate.get("_suspicion_model") as RangerSuspicion).suspicion = 0.0
	ranger.emit_signal("suspicion_changed", 0.0)
	controller.call("_process", 5.0)
	ranger.emit_signal("state_changed", RangerStateMachine.State.CHASE)
	_check(controller.exposure_event_count == 2, "A genuinely calm park rearms a later exposure story")

	player.call("_update_camera_shake", 1.0)
	var camera := player.get_node("SpringArm3D/Camera3D") as Camera3D
	_check(absf(camera.h_offset) < 0.001 and absf(camera.v_offset) < 0.001, "Camera punch returns cleanly to rest")

	paused = false
	level.queue_free()
	await process_frame
	if _failures == 0:
		print("PHASE13_SUSPICION_ESCALATION_VALIDATION_OK")
	quit(_failures)

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("Phase 13 suspicion-escalation validation failed: %s" % message)
