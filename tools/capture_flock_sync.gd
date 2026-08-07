extends SceneTree

const OUTPUT := "user://signature_chaos_playtest/flock_sync_blend.png"

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var level := (
		load("res://scenes/levels/Level01_Park.tscn") as PackedScene
	).instantiate() as BaseLevel
	root.add_child(level)
	paused = false
	await process_frame
	await process_frame
	for overlay_name in ["TitleScreen", "TransitionLayer", "PauseMenu", "HowToPlayScreen"]:
		var overlay := level.get_node_or_null(overlay_name)
		if overlay != null:
			overlay.visible = false
	var hud := level.get_node("HUD")
	for node_name in ["RangerStatus", "ObjectiveStatus", "SuspicionBar", "StaminaBar", "TimerLabel", "Minimap"]:
		var hud_item := hud.get_node_or_null(node_name)
		if hud_item != null:
			hud_item.visible = false
	(level.get_node("GameTimer") as GameSession).call("_set_state", GameSession.SessionState.ACTIVE)

	var stage := Vector3(0.0, 1.0, 0.0)
	var player := level.get_node("Player") as CharacterBody3D
	player.global_position = stage
	player.set("camera_yaw", PI)
	var rangers := get_nodes_in_group("rangers")
	for index in rangers.size():
		var ranger := rangers[index]
		ranger.call("halt_for_capture")
		(ranger as Node3D).global_position = (
			stage + Vector3(-2.15, -0.475, -0.5)
			if index == 0
			else Vector3(30.0 + index, 0.525, 30.0)
		)
	if not rangers.is_empty():
		(rangers[0] as Node3D).look_at(stage, Vector3.UP)

	var flock_positions := [
		Vector3(-1.35, 0.0, 0.55),
		Vector3(-0.65, 0.0, 1.45),
		Vector3(0.35, 0.0, 1.65),
		Vector3(1.25, 0.0, 1.0),
		Vector3(1.55, 0.0, -0.05),
		Vector3(0.65, 0.0, -1.15),
	]
	var pigeons := get_nodes_in_group("pigeons")
	for index in pigeons.size():
		var pigeon := pigeons[index] as Node3D
		pigeon.set("_reaction_mode", 0)
		pigeon.set("is_pecking", false)
		pigeon.set("next_peck_timer", 10.0)
		# Staging-only: keeps the observing ranger in the composition while the
		# capture demonstrates the lower-priority calm flock response.
		pigeon.set("flee_distance", 0.0)
		pigeon.global_position = (
			stage + flock_positions[index]
			if index < flock_positions.size()
			else Vector3(25.0 + index, 1.0, 25.0)
		)

	var camera := Camera3D.new()
	camera.fov = 48.0
	level.add_child(camera)
	camera.global_position = stage + Vector3(6.3, 3.5, 7.0)
	camera.look_at(stage + Vector3(0.0, -0.2, 0.25), Vector3.UP)
	camera.make_current()

	player.call("start_player_peck")
	await create_timer(0.27).timeout
	await RenderingServer.frame_post_draw
	var output_directory := ProjectSettings.globalize_path(OUTPUT.get_base_dir())
	DirAccess.make_dir_recursive_absolute(output_directory)
	var save_error := root.get_texture().get_image().save_png(OUTPUT)
	if save_error == OK:
		print("FLOCK_SYNC_CAPTURE_OK|%s" % ProjectSettings.globalize_path(OUTPUT))
	else:
		push_error("Could not save flock-sync capture: %s" % error_string(save_error))
	level.queue_free()
	await process_frame
	quit(0 if save_error == OK else 1)
