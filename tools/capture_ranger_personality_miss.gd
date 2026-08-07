extends SceneTree

const OUTPUT := "user://signature_chaos_playtest/ranger_personality_miss.png"

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var level := (
		load("res://scenes/levels/Level05_BotanicalGardens.tscn") as PackedScene
	).instantiate() as BaseLevel
	root.add_child(level)
	paused = false
	await process_frame
	await process_frame
	for overlay_name in ["HUD", "TitleScreen", "TransitionLayer", "PauseMenu", "HowToPlayScreen"]:
		var overlay := level.get_node_or_null(overlay_name)
		if overlay != null:
			overlay.visible = false
	var hothead := level.get_node("Ranger2")
	var veteran := level.get_node("Ranger")
	var player := level.get_node("Player") as Node3D
	var stage := Vector3(0.0, 0.525, 0.0)
	hothead.global_position = stage
	veteran.global_position = stage + Vector3(2.7, 0.0, -0.2)
	player.global_position = stage + Vector3(-2.1, 0.475, -0.8)
	level.get_node("Ranger3").global_position = Vector3(30.0, 0.525, 30.0)
	level.get_node("Ranger4").global_position = Vector3(-30.0, 0.525, -30.0)

	var camera := Camera3D.new()
	camera.fov = 48.0
	level.add_child(camera)
	camera.global_position = stage + Vector3(6.2, 3.0, 6.4)
	camera.look_at(stage + Vector3(0.15, 0.35, -0.35), Vector3.UP)
	camera.make_current()

	for miss_index in 3:
		hothead.set("grab_phase", 0)
		hothead.call("_begin_miss_recovery")
	await create_timer(0.13).timeout
	await RenderingServer.frame_post_draw
	var output_directory := ProjectSettings.globalize_path(OUTPUT.get_base_dir())
	DirAccess.make_dir_recursive_absolute(output_directory)
	var save_error := root.get_texture().get_image().save_png(OUTPUT)
	if save_error == OK:
		print("RANGER_PERSONALITY_CAPTURE_OK|%s" % ProjectSettings.globalize_path(OUTPUT))
	else:
		push_error("Could not save ranger personality capture: %s" % error_string(save_error))
	paused = false
	level.queue_free()
	await process_frame
	quit(0 if save_error == OK else 1)
