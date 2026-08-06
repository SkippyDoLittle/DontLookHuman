extends SceneTree

const OUTPUT := "user://signature_chaos_playtest/food_snatch_closeup.png"

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
	for overlay_name in ["HUD", "TitleScreen", "TransitionLayer", "PauseMenu", "HowToPlayScreen"]:
		var overlay := level.get_node_or_null(overlay_name)
		if overlay != null:
			overlay.visible = false
	var food := level.get_node("PicnicFood") as Node3D
	var player := level.get_node("Player") as CharacterBody3D
	var chaos_controller := level.get_node("ParkChaosController") as ParkChaosController
	chaos_controller.set("_signature_triggered", true)
	for ranger in get_nodes_in_group("rangers"):
		ranger.call("halt_for_capture")
	var focus := food.global_position + Vector3.UP * 0.28
	player.global_position = food.global_position + Vector3(0.0, 0.87, 0.62)
	player.get_node("PigeonVisual").rotation.y = PI
	player.set("is_pecking", true)
	player.set("_peck_consumed", false)

	var camera := Camera3D.new()
	camera.fov = 43.0
	level.add_child(camera)
	camera.global_position = focus + Vector3(1.8, 1.0, -2.15)
	camera.look_at(focus + Vector3(0.0, 0.08, -0.18), Vector3.UP)
	camera.make_current()

	food.call("_process", 0.0)
	player.call("_update_food_snatch_reaction", 0.2)
	food.call("_process", 0.14)
	await process_frame
	await RenderingServer.frame_post_draw
	var output_directory := ProjectSettings.globalize_path(OUTPUT.get_base_dir())
	DirAccess.make_dir_recursive_absolute(output_directory)
	var save_error := root.get_texture().get_image().save_png(OUTPUT)
	if save_error == OK:
		print("FOOD_SNATCH_CAPTURE_OK|%s" % ProjectSettings.globalize_path(OUTPUT))
	else:
		push_error("Could not save food snatch capture: %s" % error_string(save_error))
	paused = false
	level.queue_free()
	await process_frame
	quit(0 if save_error == OK else 1)
