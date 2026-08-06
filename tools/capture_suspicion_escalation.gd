extends SceneTree

const OUTPUT := "user://signature_chaos_playtest/suspicion_exposure_cascade.png"

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var level := (
		load("res://scenes/levels/Level02_Playground.tscn") as PackedScene
	).instantiate() as BaseLevel
	root.add_child(level)
	paused = false
	await process_frame
	await process_frame
	for overlay_name in ["TitleScreen", "TransitionLayer", "PauseMenu", "HowToPlayScreen"]:
		var overlay := level.get_node_or_null(overlay_name)
		if overlay != null:
			overlay.visible = false
	(level.get_node("GameTimer") as GameSession).call(
		"_set_state",
		GameSession.SessionState.ACTIVE
	)

	var player := level.get_node("Player") as Node3D
	var stage := Vector3(0.0, 1.0, 0.0)
	player.global_position = stage
	var pigeon_offsets := [
		Vector3(-2.1, 0.0, -1.0), Vector3(2.1, 0.0, -1.1),
		Vector3(-1.2, 0.0, -2.5), Vector3(1.25, 0.0, -2.6),
		Vector3(0.0, 0.0, -3.6),
	]
	var pigeons := get_nodes_in_group("pigeons")
	for index in mini(pigeons.size(), pigeon_offsets.size()):
		var pigeon := pigeons[index] as Node3D
		pigeon.global_position = stage + pigeon_offsets[index]
		pigeon.set("flee_distance", 0.0)
	var ranger := level.get_node("Ranger2")
	ranger.global_position = stage + Vector3(0.0, -0.475, -4.8)
	for other_ranger in get_nodes_in_group("rangers"):
		if other_ranger != ranger:
			other_ranger.call("halt_for_capture")

	var camera := Camera3D.new()
	camera.fov = 52.0
	level.add_child(camera)
	camera.global_position = stage + Vector3(5.6, 3.2, 6.2)
	camera.look_at(stage + Vector3(0.0, -0.1, -1.9), Vector3.UP)
	camera.make_current()

	var suspicion_model := ranger.get("_suspicion_model") as RangerSuspicion
	suspicion_model.suspicion = 94.0
	ranger.set("suspicion", 94.0)
	ranger.emit_signal("suspicion_changed", 94.0)
	ranger.emit_signal("state_changed", RangerStateMachine.State.CHASE)
	await create_timer(0.16).timeout
	await RenderingServer.frame_post_draw
	var output_directory := ProjectSettings.globalize_path(OUTPUT.get_base_dir())
	DirAccess.make_dir_recursive_absolute(output_directory)
	var save_error := root.get_texture().get_image().save_png(OUTPUT)
	if save_error == OK:
		print("SUSPICION_ESCALATION_CAPTURE_OK|%s" % ProjectSettings.globalize_path(OUTPUT))
	else:
		push_error("Could not save suspicion escalation capture: %s" % error_string(save_error))
	paused = false
	level.queue_free()
	await process_frame
	quit(0 if save_error == OK else 1)
