extends SceneTree

const OUTPUT_DIRECTORY := "user://signature_chaos_playtest"
const SPECS: Array[Dictionary] = [
	{"path": "res://scenes/levels/Level01_Park.tscn", "name": "level_01_feeding_frenzy", "event": &"food", "food": "PicnicFood"},
	{"path": "res://scenes/levels/Level02_Playground.tscn", "name": "level_02_swing_out", "event": &"food", "food": "PicnicFood2", "focus": "SwingBar"},
	{"path": "res://scenes/levels/Level03_Lakeside.tscn", "name": "level_03_splash", "event": &"water", "focus": "Lake/WaterZone"},
	{"path": "res://scenes/levels/Level04_Festival.tscn", "name": "level_04_popcorn_panic", "event": &"food", "food": "PicnicFood4"},
	{"path": "res://scenes/levels/Level05_BotanicalGardens.tscn", "name": "level_05_sprinklers", "event": &"finale", "focus": "Fountain"},
]

var _failures := 0

func _initialize() -> void:
	call_deferred("_capture_all")

func _capture_all() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var absolute_directory := ProjectSettings.globalize_path(OUTPUT_DIRECTORY)
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_directory)
	if directory_error != OK:
		_fail("Could not create %s" % absolute_directory)
		quit(_failures)
		return
	for spec in SPECS:
		await _capture_event(spec)
	if _failures == 0:
		print("SIGNATURE_CHAOS_CAPTURES_OK|directory=%s" % absolute_directory)
	quit(_failures)

func _capture_event(spec: Dictionary) -> void:
	var level := (load(String(spec.path)) as PackedScene).instantiate() as BaseLevel
	root.add_child(level)
	paused = false
	await process_frame
	await process_frame
	for overlay_name in ["TitleScreen", "TransitionLayer", "PauseMenu", "HowToPlayScreen"]:
		var overlay := level.get_node_or_null(overlay_name)
		if overlay != null:
			overlay.visible = false
	var session := level.get_node("GameTimer") as GameSession
	session.call("_set_state", GameSession.SessionState.ACTIVE)
	var focus := _event_focus(level, spec)
	_arrange_actors(focus)
	_install_camera(level, focus, StringName(spec.event))
	_trigger(level, spec, focus)
	await create_timer(0.34 if StringName(spec.event) != &"finale" else 0.5).timeout
	await RenderingServer.frame_post_draw
	var output := "%s/%s.png" % [OUTPUT_DIRECTORY, String(spec.name)]
	var save_error := root.get_texture().get_image().save_png(output)
	if save_error != OK:
		_fail("Could not save %s" % output)
	else:
		print("CHAOS_CAPTURE|%s" % ProjectSettings.globalize_path(output))
	paused = false
	level.queue_free()
	await process_frame

func _event_focus(level: BaseLevel, spec: Dictionary) -> Vector3:
	if spec.has("focus"):
		var focus_node := level.get_node_or_null(String(spec.focus)) as Node3D
		if focus_node != null:
			return focus_node.global_position
	var food := level.get_node(String(spec.food)) as Node3D
	return food.global_position

func _arrange_actors(focus: Vector3) -> void:
	var pigeon_offsets := [
		Vector3(-2.2, 0.0, 0.7), Vector3(2.2, 0.0, 0.8),
		Vector3(-1.2, 0.0, -2.0), Vector3(1.2, 0.0, -2.2),
	]
	var pigeons := get_nodes_in_group("pigeons")
	for index in mini(pigeons.size(), pigeon_offsets.size()):
		var pigeon := pigeons[index] as Node3D
		pigeon.global_position = focus + pigeon_offsets[index] + Vector3.UP
		pigeon.set("flee_distance", 0.0)
	var ranger_offsets := [Vector3(-3.4, -0.48, -1.2), Vector3(3.5, -0.48, -1.5)]
	var rangers := get_nodes_in_group("rangers")
	for index in mini(rangers.size(), ranger_offsets.size()):
		var ranger := rangers[index] as Node3D
		ranger.global_position = focus + ranger_offsets[index]

func _install_camera(level: BaseLevel, focus: Vector3, event_name: StringName) -> void:
	var camera := Camera3D.new()
	camera.fov = 54.0
	level.add_child(camera)
	var camera_offset := Vector3(6.5, 3.8, 7.2)
	if event_name == &"water":
		camera_offset = Vector3(7.5, 4.5, 8.0)
	elif event_name == &"finale":
		camera_offset = Vector3(8.0, 4.4, 7.2)
	camera.global_position = focus + camera_offset
	camera.look_at(focus + Vector3.UP * 0.65, Vector3.UP)
	camera.make_current()

func _trigger(level: BaseLevel, spec: Dictionary, focus: Vector3) -> void:
	match StringName(spec.event):
		&"food":
			var food := level.get_node(String(spec.food)) as Node3D
			food.emit_signal("food_collected", food, food.global_position)
		&"water":
			level.get_node("Lake/WaterZone").emit_signal("player_splashed", focus)
		&"finale":
			for index in range(1, 6):
				var food_name := "PicnicFood" if index == 1 else "PicnicFood%d" % index
				var food := level.get_node(food_name) as Node3D
				food.emit_signal("food_collected", food, food.global_position)

func _fail(message: String) -> void:
	_failures += 1
	push_error("Signature-chaos capture failed: %s" % message)
