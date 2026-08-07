extends SceneTree

const PARK_REACTIONS = preload("res://park_reaction_director.gd")
const OUTPUT := "user://signature_chaos_playtest/wrong_pigeon_grab.png"

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

	var stage := Vector3(0.0, 0.525, 0.0)
	var ranger := level.get_node("Ranger") as CharacterBody3D
	var teammate := level.get_node("Ranger2") as CharacterBody3D
	var player := level.get_node("Player") as CharacterBody3D
	ranger.global_position = stage
	ranger.set("capture_personality", "Hothead")
	player.global_position = stage + Vector3(2.25, 0.475, 1.25)
	ranger.look_at(player.global_position, Vector3.UP)
	teammate.global_position = stage + Vector3(-2.25, 0.0, 0.35)
	level.get_node("Ranger3").global_position = Vector3(30.0, 0.525, 30.0)

	var pigeons := get_nodes_in_group("pigeons")
	for index in pigeons.size():
		var pigeon := pigeons[index] as Node3D
		pigeon.set_process(false)
		pigeon.set_physics_process(false)
		pigeon.set("_reaction_mode", 0)
		pigeon.set("is_pecking", false)
		pigeon.global_position = Vector3(24.0 + index, 1.0, 24.0)
	var decoy := pigeons[0] as Node3D
	decoy.global_position = ranger.global_position + Vector3(0.28, 0.475, 0.0)
	decoy.call("react_to_park_event", PARK_REACTIONS.EVENT_GRAB_WINDUP, ranger.global_position)
	decoy.set_process(true)

	ranger.set_process(false)
	ranger.set_physics_process(false)
	teammate.set_process(false)
	teammate.set_physics_process(false)
	level.get_node("Ranger3").set_process(false)
	level.get_node("Ranger3").set_physics_process(false)

	var camera := Camera3D.new()
	camera.fov = 42.0
	level.add_child(camera)
	camera.global_position = stage + Vector3(4.1, 2.25, 4.75)
	camera.look_at(stage + Vector3(0.0, 0.25, 0.2), Vector3.UP)
	camera.make_current()

	ranger.call("_begin_miss_recovery")
	await create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	var output_directory := ProjectSettings.globalize_path(OUTPUT.get_base_dir())
	DirAccess.make_dir_recursive_absolute(output_directory)
	var save_error := root.get_texture().get_image().save_png(OUTPUT)
	if save_error == OK:
		print("MISTAKEN_IDENTITY_CAPTURE_OK|%s" % ProjectSettings.globalize_path(OUTPUT))
	else:
		push_error("Could not save mistaken-identity capture: %s" % error_string(save_error))
	level.queue_free()
	await process_frame
	quit(0 if save_error == OK else 1)
