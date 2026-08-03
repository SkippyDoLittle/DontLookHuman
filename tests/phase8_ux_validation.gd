extends SceneTree

var _failures: int = 0
var _temporary_paths: Array[String] = []

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	await _validate_result_flow(
		"res://scenes/levels/Level01_Park.tscn",
		"NEXT LEVEL"
	)
	await _validate_result_flow(
		"res://scenes/levels/Level05_BotanicalGardens.tscn",
		"PLAY AGAIN"
	)
	await _validate_modal_controls()
	await _validate_obstacle_recovery()
	_cleanup_temporary_files()

	if _failures == 0:
		print("PHASE8_UX_VALIDATION_OK")
	quit(_failures)

func _validate_result_flow(level_path: String, expected_primary_text: String) -> void:
	var level := (load(level_path) as PackedScene).instantiate() as BaseLevel
	var session := level.get_node("GameTimer") as GameSession
	session.set("_progress_store", CampaignProgressStore.new(_temporary_path("progress")))
	session.set(
		"_score_store",
		BestScoreStore.new(_temporary_path("scores"), _temporary_path("legacy"))
	)
	root.add_child(level)
	await process_frame
	await process_frame

	paused = false
	session.call("_set_state", GameSession.SessionState.ACTIVE)
	session.call("_finish", true, "ESCAPED!")
	await process_frame

	var player := level.get_node("Player") as CharacterBody3D
	var actions := level.get_node("HUD/ResultActions") as HBoxContainer
	var primary := actions.get_node("PrimaryButton") as Button
	var retry := actions.get_node("RetryButton") as Button
	var menu := actions.get_node("MenuButton") as Button
	_check(paused, "%s freezes the scene tree on results" % level_path)
	_check(not player.can_process(), "%s stops player simulation behind results" % level_path)
	_check(actions.visible and actions.can_process(), "%s keeps result controls interactive while paused" % level_path)
	_check(primary.text == expected_primary_text, "%s presents the correct primary campaign action" % level_path)
	_check(retry.text == "REPLAY LEVEL", "%s offers a level replay" % level_path)
	_check(menu.visible, "%s offers a main-menu action" % level_path)
	_check(primary.has_focus(), "%s focuses its primary result action" % level_path)

	paused = false
	level.queue_free()
	await process_frame

func _validate_modal_controls() -> void:
	var level := (
		load("res://scenes/levels/Level01_Park.tscn") as PackedScene
	).instantiate() as BaseLevel
	root.add_child(level)
	await process_frame
	await process_frame
	var session := level.get_node("GameTimer") as GameSession
	var controls := level.get_node("HowToPlayScreen")
	var pause_menu := level.get_node("PauseMenu") as CanvasLayer

	paused = false
	pause_menu.visible = false
	session.call("_set_state", GameSession.SessionState.ACTIVE)
	controls.call("show_controls")
	_check(paused and session.state == GameSession.SessionState.PAUSED, "Opening controls during play pauses the session")
	_check(pause_menu.visible and controls.visible, "Controls remain modal above the pause menu")

	Input.action_press("pause_game")
	controls.call("close_controls")
	session.call("_process_paused_input")
	_check(paused and session.state == GameSession.SessionState.PAUSED, "The input that closes controls cannot also resume gameplay")
	Input.action_release("pause_game")
	await process_frame

	controls.call("show_controls")
	Input.action_press("pause_game")
	session.call("_process_paused_input")
	_check(not controls.visible, "Pause/Start closes an open controls overlay")
	_check(paused and session.state == GameSession.SessionState.PAUSED, "Pause/Start leaves the underlying pause menu paused")
	Input.action_release("pause_game")

	paused = false
	level.queue_free()
	await process_frame

func _validate_obstacle_recovery() -> void:
	var movement_test_root := Node3D.new()
	var ranger := CharacterBody3D.new()
	var player := CharacterBody3D.new()
	movement_test_root.add_child(ranger)
	movement_test_root.add_child(player)
	root.add_child(movement_test_root)
	ranger.position = Vector3.ZERO
	player.position = Vector3(5.0, 0.0, 0.0)
	await process_frame
	var movement := RangerMovement.new()
	movement.configure(
		ranger,
		player,
		{
			"patrol_speed": 1.1,
			"patrol_radius": 9.5,
			"investigate_speed": 1.8,
			"chase_speed": 3.5,
			"approach_stop_distance": 1.8,
		}
	)
	movement.update(0.1, RangerStateMachine.State.CHASE)
	movement.call("_begin_obstacle_recovery")
	movement.update(0.1, RangerStateMachine.State.CHASE)
	var recovery_move: Vector3 = movement.get("_desired_move")
	_check(movement.obstacle_recoveries == 1, "A blocked ranger records an obstacle recovery")
	_check(recovery_move.length() > 3.0, "A blocked ranger chooses a chase-speed sidestep")
	movement_test_root.queue_free()
	await process_frame

	var visitor := (
		load("res://scenes/actors/Visitor.tscn") as PackedScene
	).instantiate() as CharacterBody3D
	root.add_child(visitor)
	await process_frame
	visitor.call("_recover_from_obstacle")
	var visitor_move: Vector3 = visitor.get("_desired_move")
	_check(visitor.obstacle_recoveries == 1, "A blocked visitor records an obstacle recovery")
	_check(bool(visitor.get("_is_waiting")), "A blocked visitor stops pushing against the obstacle")
	_check(is_zero_approx(visitor_move.length()), "A blocked visitor clears its unreachable movement")
	visitor.queue_free()
	await process_frame

func _temporary_path(label: String) -> String:
	var path := "user://phase8_%s_%s.cfg" % [label, Time.get_ticks_usec()]
	_temporary_paths.append(path)
	return path

func _cleanup_temporary_files() -> void:
	for path in _temporary_paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("Phase 8 UX validation failed: %s" % message)
