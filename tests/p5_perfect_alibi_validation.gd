extends SceneTree

# P5 Perfect Alibi integration and economy-contract validation.
# Run headless: --headless --path . --script res://tests/p5_perfect_alibi_validation.gd

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_validate")


func _validate() -> void:
	Engine.time_scale = 1.0
	paused = false
	var level := (
		load("res://scenes/levels/Level01_Park.tscn") as PackedScene
	).instantiate() as BaseLevel
	root.add_child(level)
	await process_frame
	await process_frame
	paused = false

	var session := level.get_node("GameTimer") as GameSession
	var controller := level.get_node("ParkChaosController") as ParkChaosController
	var player := level.get_node("Player") as CharacterBody3D
	var ranger_hud := level.get_node("HUD") as RangerHUDController
	var opportunity_card := level.get_node("HUD/ChaosWindowCallout") as PanelContainer
	var opportunity_label := level.get_node("HUD/ChaosWindowCallout/Label") as Label
	var rangers := _nodes_in_level_group(level, &"rangers")
	var pigeons := _nodes_in_level_group(level, &"pigeons")

	_check(rangers.size() >= 1, "campaign level supplies a ranger")
	_check(pigeons.size() >= 3, "campaign level supplies a readable flock")
	_check(controller.get_signal_connection_list("flock_sync_started").any(
		func(connection: Dictionary) -> bool:
			return connection.callable.get_object() == session
	), "GameSession connects the existing flock-sync signal")

	session.call("_set_state", GameSession.SessionState.ACTIVE)
	player.set_process(false)
	player.set_physics_process(false)
	player.global_position = Vector3(0.0, 1.0, 0.0)
	_stage_pigeons(pigeons, player.global_position)
	_stage_rangers(rangers, 0.0)
	_set_ranger_suspicion(rangers[0], 52.0)

	var timing_snapshot := _capture_timing_snapshot(rangers)
	var ready_events: Array[Dictionary] = []
	var pickup_events: Array[Dictionary] = []
	session.perfect_alibi_ready.connect(
		func(origin: Vector3, joiners: int, duration: float) -> void:
			ready_events.append({"origin": origin, "joiners": joiners, "duration": duration})
	)
	session.perfect_alibi_pickup_earned.connect(
		func(origin: Vector3, bonus: float) -> void:
			pickup_events.append({"origin": origin, "bonus": bonus})
	)

	# One accepted mimic wave at meaningful suspicion arms exactly one candidate.
	controller.emit_signal("flock_sync_started", 3, player.global_position)
	_check(is_equal_approx(float(session.get("_alibi_candidate_timer")), 2.6),
		"meaningful flock sync arms the 2.6 second candidate")
	controller.emit_signal("flock_sync_started", 6, Vector3(9.0, 1.0, 9.0))
	_check(is_equal_approx(float(session.get("_alibi_candidate_timer")), 2.6),
		"a second wave cannot refresh an active candidate")
	_check(int(session.get("_alibi_joiner_count")) == 3,
		"active candidate keeps the original earned joiner count")

	# Existing suspicion recovery is simulated here; Perfect Alibi only observes it.
	for ranger in rangers:
		_set_ranger_suspicion(ranger, 39.0)
	var suspicion_before_promotion := _suspicion_snapshot(rangers)
	session.call("_update_opportunity_windows", 0.1)
	_check(is_zero_approx(float(session.get("_alibi_candidate_timer"))),
		"existing blend predicate consumes the qualifying candidate")
	_check(is_equal_approx(float(session.get("_perfect_alibi_timer")), 3.2),
		"qualification starts one 3.2 second ready window")
	_check(int(session.get("perfect_alibi_ready_count")) == 1 and ready_events.size() == 1,
		"qualification emits one readable Perfect Alibi event")
	_check(ready_events[0].joiners == 3 and is_equal_approx(float(ready_events[0].duration), 3.2),
		"ready event preserves wave size and approved duration")
	_check(_same_suspicion(rangers, suspicion_before_promotion),
		"Perfect Alibi promotion never writes ranger suspicion")
	_check(opportunity_card.visible and opportunity_label.text.contains("PERFECT ALIBI"),
		"shared opportunity card switches to teal alibi mode")
	_check(opportunity_label.text.contains("STEAL NOW +5s") and opportunity_label.text.contains("3.2s"),
		"alibi card explains the unchanged reward and countdown")

	# The separate ranger-danger lane retains absolute precedence.
	ranger_hud.call("_show_warning", "DANGER!", Color.RED, 1.0)
	session.call("_refresh_opportunity_hud")
	_check(level.get_node("HUD/WarnLabel").text == "DANGER!",
		"opportunity feedback never overwrites danger text")
	_check(opportunity_card.visible and opportunity_label.text.contains("PERFECT ALIBI"),
		"danger and opportunity remain readable in separate HUD lanes")

	# Claiming the alibi reuses the existing +5 blend economy exactly.
	var timer := session.get("_timer") as SessionTimer
	var before_alibi_pickup := timer.time_remaining
	var dummy_food := Node3D.new()
	session.call("_on_food_collected_bonus", dummy_food, player.global_position)
	dummy_food.free()
	_check(is_equal_approx(timer.time_remaining - before_alibi_pickup, 5.0),
		"Perfect Alibi pickup adds exactly the existing +5 blend reward")
	_check(int(session.get("blend_bonus_count")) == 1 and int(session.get("chaos_bonus_count")) == 0,
		"alibi pickup records one blend and no phantom chaos reward")
	_check(int(session.get("perfect_alibi_pickup_count")) == 1 and pickup_events.size() == 1,
		"alibi pickup is consumed and reported exactly once")
	_check(is_equal_approx(float(pickup_events[0].bonus), 5.0),
		"Perfect Alibi signal reports the unchanged +5 amount")
	_check(is_zero_approx(float(session.get("_perfect_alibi_timer"))),
		"food pickup consumes the ready window")
	_check(_hud_has_text(level.get_node("HUD"), "PERFECT ALIBI!  +5s"),
		"earned pickup gets a concise clip-readable payoff")
	_check(_same_suspicion(rangers, suspicion_before_promotion),
		"claiming the reward still never writes suspicion")

	# The rearm lock prevents immediate farming even if suspicion rises again.
	_set_ranger_suspicion(rangers[0], 52.0)
	controller.emit_signal("flock_sync_started", 3, player.global_position)
	_check(is_zero_approx(float(session.get("_alibi_candidate_timer"))),
		"five-second rearm lock rejects immediate repeat farming")

	# Combined mode is one card and preserves the existing +5 +4 = +9 total.
	for ranger in rangers:
		_set_ranger_suspicion(ranger, 39.0)
	session.set("_perfect_alibi_timer", 3.0)
	session.call("_start_chaos_window")
	_check(opportunity_card.visible and opportunity_label.text.contains("PERFECT CHANCE: +9s"),
		"overlapping windows collapse into one gold +9 card")
	_check(opportunity_label.text.contains("3.0s"),
		"combined card uses the shorter actionable countdown")
	var before_combined_pickup := timer.time_remaining
	dummy_food = Node3D.new()
	session.call("_on_food_collected_bonus", dummy_food, player.global_position)
	dummy_food.free()
	_check(is_equal_approx(timer.time_remaining - before_combined_pickup, 9.0),
		"combined pickup remains exactly +9 seconds")
	_check(int(session.get("blend_bonus_count")) == 2 and int(session.get("chaos_bonus_count")) == 1,
		"combined claim records one existing blend and one existing chaos reward")
	_check(int(session.get("perfect_alibi_pickup_count")) == 2,
		"combined claim consumes one Perfect Alibi")

	# A broken alibi consumes the attempt without a reward or penalty.
	session.set("_chaos_window_timer", 0.0)
	session.set("_perfect_alibi_timer", 3.0)
	_move_pigeons_far(pigeons)
	var before_broken_pickup := timer.time_remaining
	dummy_food = Node3D.new()
	session.call("_on_food_collected_bonus", dummy_food, player.global_position)
	dummy_food.free()
	_check(is_equal_approx(timer.time_remaining, before_broken_pickup),
		"leaving the flock earns no alibi time and adds no penalty")
	_check(is_zero_approx(float(session.get("_perfect_alibi_timer"))),
		"unqualified food theft still consumes the alibi attempt")

	# Arming guards reject calm spam, undersized waves, chase, and active grabs.
	_stage_pigeons(pigeons, player.global_position)
	session.set("_alibi_rearm_timer", 0.0)
	for ranger in rangers:
		_set_ranger_suspicion(ranger, 20.0)
	controller.emit_signal("flock_sync_started", 3, player.global_position)
	_check(is_zero_approx(float(session.get("_alibi_candidate_timer"))),
		"already-safe suspicion cannot farm Perfect Alibi")
	_set_ranger_suspicion(rangers[0], 52.0)
	controller.emit_signal("flock_sync_started", 1, player.global_position)
	_check(is_zero_approx(float(session.get("_alibi_candidate_timer"))),
		"fewer than two mimic joiners cannot arm an alibi")
	rangers[0].set("state", RangerStateMachine.State.CHASE)
	controller.emit_signal("flock_sync_started", 3, player.global_position)
	_check(is_zero_approx(float(session.get("_alibi_candidate_timer"))),
		"chase rejects an alibi candidate")
	rangers[0].set("state", RangerStateMachine.State.PATROL)
	rangers[0].set("grab_phase", 1)
	controller.emit_signal("flock_sync_started", 3, player.global_position)
	_check(is_zero_approx(float(session.get("_alibi_candidate_timer"))),
		"active grab phase rejects an alibi candidate")
	rangers[0].set("grab_phase", 0)
	controller.emit_signal("flock_sync_started", 3, player.global_position)
	_check(float(session.get("_alibi_candidate_timer")) > 0.0,
		"safe meaningful wave can arm again after cooldown")
	session.call("_on_capture_started")
	_check(is_zero_approx(float(session.get("_alibi_candidate_timer")))
		and is_zero_approx(float(session.get("_perfect_alibi_timer"))),
		"capture cancels every alibi state immediately")
	_check(not opportunity_card.visible, "capture hides the opportunity lane")

	_check(_same_capture_timings(rangers, timing_snapshot),
		"Perfect Alibi never alters ranger capture or difficulty timings")
	for ranger in rangers:
		_check(is_zero_approx(float(ranger.get("_chaos_distraction_timer"))),
			"Perfect Alibi never invokes ranger distraction")

	paused = false
	level.queue_free()
	await process_frame
	if _failures == 0:
		print("P5_PERFECT_ALIBI_VALIDATION_OK")
	quit(_failures)


func _nodes_in_level_group(level: Node, group_name: StringName) -> Array[Node]:
	var nodes: Array[Node] = []
	for node in get_nodes_in_group(group_name):
		if node == level or level.is_ancestor_of(node):
			nodes.append(node)
	return nodes


func _stage_pigeons(pigeons: Array[Node], origin: Vector3) -> void:
	for index in range(pigeons.size()):
		var pigeon := pigeons[index] as Node3D
		pigeon.set_process(false)
		pigeon.set_physics_process(false)
		if index < 3:
			var angle := float(index) / 3.0 * TAU
			pigeon.global_position = origin + Vector3(cos(angle), 0.0, sin(angle)) * (1.2 + index * 0.25)
		else:
			pigeon.global_position = Vector3(12.0 + index, 1.0, -12.0)


func _move_pigeons_far(pigeons: Array[Node]) -> void:
	for index in range(pigeons.size()):
		(pigeons[index] as Node3D).global_position = Vector3(12.0 + index, 1.0, -12.0)


func _stage_rangers(rangers: Array[Node], suspicion: float) -> void:
	for index in range(rangers.size()):
		var ranger := rangers[index] as Node3D
		ranger.set_process(false)
		ranger.set_physics_process(false)
		ranger.global_position = Vector3(11.0 + index * 2.0, 1.0, 11.0)
		ranger.set("caught", false)
		ranger.set("state", RangerStateMachine.State.PATROL)
		ranger.set("grab_phase", 0)
		ranger.set("_capture_signal_emitted", false)
		ranger.set("_session_capture_in_progress", false)
		_set_ranger_suspicion(ranger, suspicion)


func _set_ranger_suspicion(ranger: Node, value: float) -> void:
	ranger.set("suspicion", value)
	var model := ranger.get("_suspicion_model") as RangerSuspicion
	if model != null:
		model.suspicion = value


func _suspicion_snapshot(rangers: Array[Node]) -> Array[float]:
	var values: Array[float] = []
	for ranger in rangers:
		values.append(float(ranger.get("suspicion")))
	return values


func _same_suspicion(rangers: Array[Node], expected: Array[float]) -> bool:
	if rangers.size() != expected.size():
		return false
	for index in range(rangers.size()):
		if not is_equal_approx(float(rangers[index].get("suspicion")), expected[index]):
			return false
	return true


func _capture_timing_snapshot(rangers: Array[Node]) -> Array[Dictionary]:
	var snapshots: Array[Dictionary] = []
	for ranger in rangers:
		snapshots.append({
			"gain": float(ranger.get("suspicion_gain_per_second")),
			"loss": float(ranger.get("suspicion_loss_per_second")),
			"peck_loss": float(ranger.get("peck_loss_per_second")),
			"windup": float(ranger.get("grab_windup_duration")),
			"lunge": float(ranger.get("grab_lunge_duration")),
			"lunge_speed": float(ranger.get("grab_lunge_speed")),
			"recovery": float(ranger.get("grab_recovery_duration")),
			"hold": float(ranger.get("capture_hold_duration")),
		})
	return snapshots


func _same_capture_timings(rangers: Array[Node], expected: Array[Dictionary]) -> bool:
	if rangers.size() != expected.size():
		return false
	var keys := ["gain", "loss", "peck_loss", "windup", "lunge", "lunge_speed", "recovery", "hold"]
	for index in range(rangers.size()):
		var current := _capture_timing_snapshot([rangers[index]])[0]
		for key in keys:
			if not is_equal_approx(float(current[key]), float(expected[index][key])):
				return false
	return true


func _hud_has_text(hud: Node, fragment: String) -> bool:
	for child in hud.get_children():
		if child is Label and (child as Label).text.contains(fragment):
			return true
	return false


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("P5 Perfect Alibi validation failed: %s" % message)
