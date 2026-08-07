extends SceneTree

const OUTPUT := "user://signature_chaos_playtest/feathers_width_close_call.png"

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
	var hud := level.get_node("HUD")
	for node_name in ["RangerStatus", "ObjectiveStatus", "SuspicionBar", "StaminaBar", "TimerLabel", "Minimap"]:
		var hud_item := hud.get_node_or_null(node_name)
		if hud_item != null:
			hud_item.visible = false
	(level.get_node("GameTimer") as GameSession).call("_set_state", GameSession.SessionState.ACTIVE)

	var player := level.get_node("Player") as Node3D
	var ranger := level.get_node("Ranger")
	var stage := Vector3(0.0, 1.0, -1.0)
	player.global_position = stage + Vector3(1.15, 0.0, 0.15)
	ranger.global_position = stage + Vector3(0.0, -0.475, 0.0)
	level.get_node("Ranger2").global_position = Vector3(30.0, 0.525, 30.0)
	level.get_node("Ranger3").global_position = Vector3(-30.0, 0.525, -30.0)

	var camera := Camera3D.new()
	camera.fov = 47.0
	level.add_child(camera)
	camera.global_position = stage + Vector3(5.0, 2.7, 5.3)
	camera.look_at(stage + Vector3(0.35, -0.2, -0.2), Vector3.UP)
	camera.make_current()

	var contact_distance := float(ranger.get("grab_contact_distance"))
	ranger.set("last_lunge_closest_distance", contact_distance + 0.18)
	ranger.call("_begin_miss_recovery")
	var controller := level.get_node("ParkChaosController") as ParkChaosController
	controller.call("_end_close_call_slowmo")
	await create_timer(0.13).timeout
	controller.set("_close_call_cooldown", 0.0)
	controller.call("_on_ranger_close_call", contact_distance + 0.18, ranger)
	await create_timer(0.03, true, false, true).timeout
	await RenderingServer.frame_post_draw
	var output_directory := ProjectSettings.globalize_path(OUTPUT.get_base_dir())
	DirAccess.make_dir_recursive_absolute(output_directory)
	var save_error := root.get_texture().get_image().save_png(OUTPUT)
	if save_error == OK:
		print("CLOSE_CALL_CAPTURE_OK|%s" % ProjectSettings.globalize_path(OUTPUT))
	else:
		push_error("Could not save close-call capture: %s" % error_string(save_error))
	controller.call("_end_close_call_slowmo")
	paused = false
	level.queue_free()
	await process_frame
	quit(0 if save_error == OK else 1)
