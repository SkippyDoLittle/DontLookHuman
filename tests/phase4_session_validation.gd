extends SceneTree

var _failures: int = 0

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	_validate_timer_component()
	_validate_score_component()
	await _validate_level_sessions()

	if _failures == 0:
		print("PHASE4_SESSION_VALIDATION_OK")
	quit(_failures)

func _validate_timer_component() -> void:
	var timer := SessionTimer.new()
	var countdown_values: Array[int] = []
	var countdown_finished_count: Array[int] = [0]
	var expired_count: Array[int] = [0]
	timer.countdown_changed.connect(func(value: int): countdown_values.append(value))
	timer.countdown_finished.connect(func(): countdown_finished_count[0] += 1)
	timer.expired.connect(func(): expired_count[0] += 1)

	timer.reset(5.0)
	timer.advance(1.25)
	_check(is_equal_approx(timer.time_remaining, 3.75), "SessionTimer subtracts active time")
	timer.advance(10.0)
	timer.advance(1.0)
	_check(is_zero_approx(timer.time_remaining), "SessionTimer clamps at zero")
	_check(expired_count[0] == 1, "SessionTimer expires exactly once")

	timer.start_countdown(3)
	timer.advance_countdown(1.0)
	timer.advance_countdown(2.0)
	_check(countdown_values == [3, 2, 1], "SessionTimer emits countdown sequence")
	_check(countdown_finished_count[0] == 1, "SessionTimer finishes countdown exactly once")

func _validate_score_component() -> void:
	var scorer := ScoreManager.new()
	var lightning := scorer.calculate(true, 90.0, 71.0, 5, 0)
	var great := scorer.calculate(true, 90.0, 60.0, 5, 0)
	var nice := scorer.calculate(true, 90.0, 45.0, 5, 0)
	var completed := scorer.calculate(true, 90.0, 20.0, 5, 0)
	var failed := scorer.calculate(false, 90.0, 70.0, 5, 3)

	_check(lightning.score == 1000, "Lightning score preserved")
	_check(great.score == 750, "Great score preserved")
	_check(nice.score == 500, "Nice score preserved")
	_check(completed.score == 250, "Completion score preserved")
	_check(failed.score == 0, "Failure score remains zero")
	_check(failed.collected == 2, "Collected item count is calculated")

func _validate_level_sessions() -> void:
	var paths: Array[String] = [
		"res://scenes/levels/Level01_Park.tscn",
		"res://scenes/levels/Level02_Playground.tscn",
		"res://scenes/levels/Level03_Lakeside.tscn",
		"res://scenes/levels/Level04_Festival.tscn",
		"res://scenes/levels/Level05_BotanicalGardens.tscn",
	]

	for path in paths:
		var packed := load(path) as PackedScene
		_check(packed != null, "%s loads" % path)
		if packed == null:
			continue

		var level := packed.instantiate()
		root.add_child(level)
		await process_frame

		var session := level.get_node_or_null("GameTimer") as GameSession
		_check(session != null, "%s uses GameSession" % path)
		if session != null:
			_check(session.state == GameSession.SessionState.TITLE, "%s starts at title" % path)
			_check(not session.game_started, "%s has not started before countdown" % path)
			_check(not session.game_over, "%s is not over on load" % path)
			_check(is_equal_approx(session.time_remaining, session.time_limit), "%s initializes its timer" % path)
			_check(session.has_signal("session_state_changed"), "%s exposes state changes" % path)
			_check(session.has_signal("collectible_count_changed"), "%s exposes collectible changes" % path)
			_check(session.has_signal("level_finished"), "%s exposes completion" % path)

		if path.ends_with("Level01_Park.tscn") and session != null:
			_check(
				level.get_node("HUD/ObjectiveStatus").text == "Steal all 5 items, then reach the exit!",
				"Session HUD owns the initial objective"
			)
			level.get_node("EscapeZone").emit_signal("escape_blocked", 3)
			_check(
				level.get_node("HUD/ObjectiveStatus").text == "3 item(s) still out there — steal them first!",
				"Escape rejection reaches the session HUD"
			)
			get_nodes_in_group("collectibles")[0].queue_free()
			await process_frame
			session.call("_refresh_collectible_count")
			_check(
				level.get_node("HUD/ObjectiveStatus").text == "4 item(s) left to steal!",
				"Collectible changes reach the session HUD"
			)
			session.call("_set_state", GameSession.SessionState.ACTIVE)
			paused = false
			session.call("_pause_session")
			_check(session.state == GameSession.SessionState.PAUSED, "Session enters paused state")
			_check(level.get_node("PauseMenu").visible, "Pause state shows pause menu")
			level.get_node("PauseMenu").call("_on_resume_pressed")
			_check(session.state == GameSession.SessionState.ACTIVE, "Session resumes to active state")
			_check(not paused, "Resume unpauses the scene tree")

		paused = false
		level.queue_free()
		await process_frame

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("Phase 4 session validation failed: %s" % message)
