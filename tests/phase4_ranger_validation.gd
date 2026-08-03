extends SceneTree

var _failures: int = 0

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	_validate_state_machine()
	await _validate_all_level_rangers()
	await _validate_signal_flow()

	if _failures == 0:
		print("PHASE4_RANGER_VALIDATION_OK")
	quit(_failures)

func _validate_state_machine() -> void:
	var state_machine := RangerStateMachine.new()
	_check(
		state_machine.update(20.0, 65.0, 90.0) == RangerStateMachine.State.PATROL,
		"Low suspicion selects patrol"
	)
	_check(
		state_machine.update(70.0, 65.0, 90.0) == RangerStateMachine.State.INVESTIGATE,
		"Mid suspicion selects investigate"
	)
	_check(
		state_machine.update(95.0, 65.0, 90.0) == RangerStateMachine.State.CHASE,
		"High suspicion selects chase"
	)

func _validate_all_level_rangers() -> void:
	var specs: Array[Dictionary] = [
		{"path": "res://Main.tscn", "count": 2},
		{"path": "res://scenes/levels/Level01_Park.tscn", "count": 2},
		{"path": "res://scenes/levels/Level02_Playground.tscn", "count": 3},
		{"path": "res://scenes/levels/Level03_Lakeside.tscn", "count": 3},
		{"path": "res://scenes/levels/Level04_Festival.tscn", "count": 3},
		{"path": "res://scenes/levels/Level05_BotanicalGardens.tscn", "count": 4},
	]

	for spec in specs:
		var level := (load(spec.path) as PackedScene).instantiate()
		root.add_child(level)
		await process_frame

		var rangers := get_nodes_in_group("rangers")
		_check(rangers.size() == spec.count, "%s keeps all rangers" % spec.path)
		var primary_count: int = 0
		for ranger in rangers:
			if bool(ranger.get("is_primary")):
				primary_count += 1
			_check(ranger.has_signal("suspicion_changed"), "%s exposes suspicion changes" % ranger.name)
			_check(ranger.has_signal("state_changed"), "%s exposes state changes" % ranger.name)
			_check(ranger.has_signal("player_caught"), "%s exposes catch events" % ranger.name)
			_check(ranger.has_signal("observation_changed"), "%s exposes observations" % ranger.name)
			_check(ranger.get("_suspicion_model") is RangerSuspicion, "%s has suspicion component" % ranger.name)
			_check(ranger.get("_movement") is RangerMovement, "%s has movement component" % ranger.name)
			_check(ranger.get("_presentation") is RangerPresentation, "%s has presentation component" % ranger.name)
		_check(primary_count == 1, "%s keeps one primary ranger" % spec.path)
		_check(level.get_node("HUD") is RangerHUDController, "%s uses signal-driven ranger HUD" % spec.path)

		var session := level.get_node("GameTimer") as GameSession
		session.call("_set_state", GameSession.SessionState.ACTIVE)
		paused = false
		for frame in 5:
			await physics_frame
		for ranger in rangers:
			_check(ranger.position.is_finite(), "%s movement remains finite" % ranger.name)

		level.queue_free()
		await process_frame

func _validate_signal_flow() -> void:
	var level := (load("res://scenes/levels/Level01_Park.tscn") as PackedScene).instantiate()
	root.add_child(level)
	await process_frame

	var ranger := level.get_node("Ranger")
	var hud := level.get_node("HUD") as RangerHUDController
	var session := level.get_node("GameTimer") as GameSession
	hud.call("_connect_new_rangers")
	session.call("_connect_new_rangers")

	var state_events: Array[int] = []
	var caught_events: Array[int] = [0]
	_connect_state_events(ranger, state_events)
	ranger.connect("player_caught", func(): caught_events[0] += 1)

	var suspicion_model := ranger.get("_suspicion_model") as RangerSuspicion
	suspicion_model.suspicion = 80.0
	ranger.call("_process", 0.0)
	_check(ranger.state == RangerStateMachine.State.INVESTIGATE, "Ranger enters investigate state")
	_check(ranger.get_node("AlertLabel").visible, "Investigate alert is presented")
	_check(is_equal_approx(hud.get_node("SuspicionBar").value, 80.0), "HUD receives suspicion signal")
	_check(is_equal_approx(session.peak_suspicion, 80.0), "GameSession receives suspicion signal")

	suspicion_model.suspicion = 97.0
	ranger.call("_process", 0.0)
	_check(ranger.state == RangerStateMachine.State.CHASE, "Ranger enters chase state")
	_check(ranger.get_node("AlertLabel").text == "!!", "Chase alert is presented")

	var player := level.get_node("Player") as CharacterBody3D
	player.global_position = ranger.global_position + Vector3(1.0, 0.0, 0.0)
	player.velocity = Vector3(3.0, 0.0, 0.0)
	suspicion_model.suspicion = 100.0
	ranger.call("_process", 0.0)
	_check(ranger.caught, "Ranger catch state is preserved")
	_check(caught_events[0] == 1, "Catch signal emits exactly once")
	_check(session.state == GameSession.SessionState.FINISHED, "Catch signal finishes GameSession")
	_check(level.get_node("HUD/ResultLabel").visible, "Catch signal displays results")
	_check(
		"The ranger noticed: Too fast!" in level.get_node("HUD/ResultLabel").text,
		"Catch result explains the suspicious behavior"
	)
	_check(state_events == [RangerStateMachine.State.INVESTIGATE, RangerStateMachine.State.CHASE], "State signals preserve transition order")

	paused = false
	level.queue_free()
	await process_frame

func _connect_state_events(ranger: Node, events: Array[int]) -> void:
	ranger.connect("state_changed", func(new_state: int): events.append(new_state))

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("Phase 4 ranger validation failed: %s" % message)
