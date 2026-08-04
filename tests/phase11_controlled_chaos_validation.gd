extends SceneTree

const RANGER_SCRIPT = preload("res://ranger.gd")

var _failures: int = 0

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	await _validate_campaign_rollout()

	var level := (
		load("res://scenes/levels/Level02_Playground.tscn") as PackedScene
	).instantiate() as BaseLevel
	root.add_child(level)
	await process_frame
	await process_frame

	paused = false
	var session := level.get_node("GameTimer") as GameSession
	session.call("_set_state", GameSession.SessionState.ACTIVE)
	var playground_rangers := get_nodes_in_group("rangers")
	_check(playground_rangers.size() == 3, "Playground retains all three rangers")
	for candidate in playground_rangers:
		_check(bool(candidate.get("physical_capture_enabled")), "%s opts into physical capture" % candidate.name)

	var ranger := level.get_node("Ranger")
	var player := level.get_node("Player") as CharacterBody3D
	var suspicion_model := ranger.get("_suspicion_model") as RangerSuspicion
	var caught_events: Array[int] = [0]
	var capture_started_events: Array[int] = [0]
	ranger.player_caught.connect(func(): caught_events[0] += 1)
	ranger.capture_started.connect(func(): capture_started_events[0] += 1)
	ranger.set("capture_hold_duration", 0.03)

	var nearby_pigeon := level.get_node("NPC_Animal3")
	var nearby_visitor := level.get_node("ParkVisitor2")
	var pigeon_reactions_before := int(nearby_pigeon.get("reaction_count"))
	var visitor_reactions_before := int(nearby_visitor.get("reaction_count"))

	player.global_position = ranger.global_position + Vector3(2.2, 0.0, 0.0)
	player.velocity = Vector3.ZERO
	suspicion_model.suspicion = 100.0
	ranger.call("_process", 0.0)
	_check(not ranger.caught, "Full suspicion exposes the player without an automatic catch")
	_check(ranger.grab_phase == RANGER_SCRIPT.GrabPhase.WINDUP, "An exposed nearby player starts a telegraphed grab")
	_check(caught_events[0] == 0, "The wind-up does not end the run")
	_check(
		int(nearby_pigeon.get("reaction_count")) > pigeon_reactions_before,
		"Nearby pigeons notice the grab wind-up"
	)
	_check(
		int(nearby_visitor.get("reaction_count")) > visitor_reactions_before,
		"Nearby visitors notice the grab wind-up"
	)

	player.global_position = ranger.global_position + Vector3(8.0, 0.0, 0.0)
	ranger.call("_begin_lunge")
	ranger.call("_update_grab", float(ranger.get("grab_lunge_duration")) + 0.01)
	_check(ranger.grab_phase == RANGER_SCRIPT.GrabPhase.RECOVERY, "A dodged lunge enters miss recovery")
	_check(int(ranger.get("missed_grabs")) == 1, "A missed grab is recorded once")
	_check(not ranger.caught, "A missed grab keeps the run alive")
	ranger.call("_update_grab", float(ranger.get("grab_recovery_duration")) + 0.01)
	_check(ranger.grab_phase == RANGER_SCRIPT.GrabPhase.IDLE, "The ranger recovers and can resume chasing")

	player.global_position = ranger.global_position + Vector3(0.55, 0.0, 0.0)
	ranger.call("_begin_grab")
	ranger.call("_begin_lunge")
	ranger.call("_update_grab", 0.0)
	_check(ranger.caught, "Physical contact completes the catch")
	_check(bool(player.get("is_captured")), "The player visibly struggles after contact")
	_check(capture_started_events[0] == 1, "Capture tableau starts exactly once")
	_check(caught_events[0] == 0, "Results wait until the capture tableau finishes")
	_check(bool(session.get("_capture_sequence_active")), "The timer pauses during the capture tableau")

	await create_timer(0.08).timeout
	_check(caught_events[0] == 1, "The catch result emits after the tableau")
	_check(session.state == GameSession.SessionState.FINISHED, "Physical capture finishes the session")
	_check(level.get_node("HUD/ResultLabel").visible, "Physical capture displays the result UI")

	paused = false
	level.queue_free()
	await process_frame

	if _failures == 0:
		print("PHASE11_CONTROLLED_CHAOS_VALIDATION_OK")
	quit(_failures)

func _validate_campaign_rollout() -> void:
	var specs: Array[Dictionary] = [
		{"path": "res://scenes/levels/Level01_Park.tscn", "count": 2, "min_windup": 0.55, "max_lunge": 6.4},
		{"path": "res://scenes/levels/Level02_Playground.tscn", "count": 3, "min_windup": 0.42, "max_lunge": 7.2},
		{"path": "res://scenes/levels/Level03_Lakeside.tscn", "count": 3, "min_windup": 0.4, "max_lunge": 7.15},
		{"path": "res://scenes/levels/Level04_Festival.tscn", "count": 3, "min_windup": 0.4, "max_lunge": 7.2},
		{"path": "res://scenes/levels/Level05_BotanicalGardens.tscn", "count": 4, "min_windup": 0.42, "max_lunge": 7.1},
	]
	var personalities: Dictionary = {}
	for spec in specs:
		var level := (load(spec.path) as PackedScene).instantiate() as BaseLevel
		root.add_child(level)
		await process_frame
		var rangers := get_nodes_in_group("rangers")
		_check(rangers.size() == int(spec.count), "%s retains its ranger count" % spec.path)
		for ranger in rangers:
			var windup := float(ranger.get("grab_windup_duration"))
			var lunge_speed := float(ranger.get("grab_lunge_speed"))
			var start_distance := float(ranger.get("grab_start_distance"))
			var contact_distance := float(ranger.get("grab_contact_distance"))
			var recovery := float(ranger.get("grab_recovery_duration"))
			var personality := String(ranger.get("capture_personality"))
			personalities[personality] = true
			_check(bool(ranger.get("physical_capture_enabled")), "%s enables physical capture" % ranger.name)
			_check(windup >= float(spec.min_windup), "%s keeps a readable wind-up" % ranger.name)
			_check(lunge_speed <= float(spec.max_lunge), "%s respects the level speed cap" % ranger.name)
			_check(start_distance - contact_distance >= 1.5, "%s leaves meaningful dodge distance" % ranger.name)
			_check(recovery >= 0.95, "%s gives a useful miss-recovery opening" % ranger.name)
		paused = false
		level.queue_free()
		await process_frame
	for personality in ["Rookie", "Steady", "Hothead", "Veteran"]:
		_check(personalities.has(personality), "Campaign includes the %s ranger personality" % personality)

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("Phase 11 controlled-chaos validation failed: %s" % message)
