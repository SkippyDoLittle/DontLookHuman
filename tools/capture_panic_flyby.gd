extends SceneTree

const PARK_REACTIONS = preload("res://park_reaction_director.gd")
const OUTPUT := "user://signature_chaos_playtest/panic_pigeon_flyby.png"

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var level := (
		load("res://scenes/levels/Level03_Lakeside.tscn") as PackedScene
	).instantiate() as BaseLevel
	root.add_child(level)
	paused = false
	await process_frame
	await process_frame
	for overlay_name in ["TitleScreen", "TransitionLayer", "PauseMenu", "HowToPlayScreen"]:
		var overlay := level.get_node_or_null(overlay_name)
		if overlay != null:
			overlay.visible = false
	level.get_node("HUD").visible = false
	(level.get_node("GameTimer") as GameSession).call("_set_state", GameSession.SessionState.ACTIVE)

	var stage := Vector3(0.0, 0.525, 0.0)
	var ranger := level.get_node("Ranger") as CharacterBody3D
	var player := level.get_node("Player") as CharacterBody3D
	ranger.global_position = stage
	ranger.set("capture_personality", "Rookie")
	player.global_position = stage + Vector3(2.35, 0.475, 1.2)
	ranger.look_at(player.global_position, Vector3.UP)
	var rangers := get_nodes_in_group("rangers")
	for index in range(1, rangers.size()):
		(rangers[index] as Node3D).global_position = Vector3(30.0 + index, 0.525, 30.0)
	for actor in rangers:
		actor.set_process(false)
		actor.set_physics_process(false)

	var pigeons := get_nodes_in_group("pigeons")
	for index in pigeons.size():
		var pigeon := pigeons[index] as Node3D
		pigeon.set_process(false)
		pigeon.set_physics_process(false)
		pigeon.set("_reaction_mode", 0)
		pigeon.global_position = Vector3(24.0 + index, 1.0, 24.0)
	var flyby := pigeons[0] as CharacterBody3D
	flyby.global_position = stage + Vector3(0.48, 0.475, 0.05)

	var camera := Camera3D.new()
	camera.fov = 43.0
	level.add_child(camera)
	camera.global_position = stage + Vector3(4.2, 2.25, 5.0)
	camera.look_at(stage + Vector3(0.35, 0.2, 0.2), Vector3.UP)
	camera.make_current()

	flyby.call(
		"react_to_park_event",
		PARK_REACTIONS.EVENT_PLAYER_EXPOSED,
		stage + Vector3(-1.0, 0.475, 0.0)
	)
	flyby.call("_process", 0.04)
	flyby.call("_process", 0.02)
	flyby.call("_process", 0.02)
	await create_timer(0.11).timeout
	await RenderingServer.frame_post_draw
	var output_directory := ProjectSettings.globalize_path(OUTPUT.get_base_dir())
	DirAccess.make_dir_recursive_absolute(output_directory)
	var save_error := root.get_texture().get_image().save_png(OUTPUT)
	if save_error == OK:
		print("PANIC_FLYBY_CAPTURE_OK|%s" % ProjectSettings.globalize_path(OUTPUT))
	else:
		push_error("Could not save panic-flyby capture: %s" % error_string(save_error))
	level.queue_free()
	await process_frame
	quit(0 if save_error == OK else 1)
