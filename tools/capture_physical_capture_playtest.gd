extends SceneTree

const OUTPUT_DIRECTORY: String = "user://physical_capture_playtest"
const SPECS: Array[Dictionary] = [
	{"path": "res://scenes/levels/Level01_Park.tscn", "name": "level_01_windup", "moment": &"windup", "camera_side": -1.0},
	{"path": "res://scenes/levels/Level02_Playground.tscn", "name": "level_02_miss", "moment": &"miss"},
	{"path": "res://scenes/levels/Level03_Lakeside.tscn", "name": "level_03_caught", "moment": &"caught"},
	{"path": "res://scenes/levels/Level04_Festival.tscn", "name": "level_04_hothead_miss", "moment": &"miss"},
	{"path": "res://scenes/levels/Level05_BotanicalGardens.tscn", "name": "level_05_veteran_windup", "moment": &"windup"},
]

var _failures: int = 0

func _initialize() -> void:
	call_deferred("_capture_all")

func _capture_all() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var absolute_directory := ProjectSettings.globalize_path(OUTPUT_DIRECTORY)
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_directory)
	if directory_error != OK:
		_fail("Could not create %s: %s" % [absolute_directory, error_string(directory_error)])
		quit(_failures)
		return

	for spec in SPECS:
		await _capture_moment(spec)
	if _failures == 0:
		print("PHYSICAL_CAPTURE_PLAYTEST_CAPTURES_OK|directory=%s" % absolute_directory)
	quit(_failures)

func _capture_moment(spec: Dictionary) -> void:
	var packed := load(String(spec.path)) as PackedScene
	if packed == null:
		_fail("Could not load %s" % spec.path)
		return

	var level := packed.instantiate() as BaseLevel
	root.add_child(level)
	paused = false
	await process_frame
	for overlay_name in ["TitleScreen", "TransitionLayer", "PauseMenu", "HowToPlayScreen"]:
		var overlay := level.get_node_or_null(overlay_name)
		if overlay != null:
			overlay.visible = false
	var fade_overlay := level.get_node_or_null("HUD/FadeOverlay")
	if fade_overlay != null:
		fade_overlay.visible = false
	var result_label := level.get_node_or_null("HUD/ResultLabel")
	if result_label != null:
		result_label.visible = false

	var session := level.get_node("GameTimer") as GameSession
	session.call("_set_state", GameSession.SessionState.ACTIVE)
	var player := level.get_node("Player") as CharacterBody3D
	var ranger := level.get_node("Ranger") as CharacterBody3D
	ranger.set("capture_hold_duration", 5.0)
	for other_ranger in get_nodes_in_group("rangers"):
		if other_ranger != ranger:
			other_ranger.call("halt_for_capture")

	var stage := player.global_position
	stage.y = 1.0
	player.global_position = stage
	player.velocity = Vector3.ZERO
	ranger.global_position = stage + Vector3(0.0, -0.475, -2.4)
	ranger.velocity = Vector3.ZERO
	_arrange_reactors(level, stage)
	_install_camera(level, stage, float(spec.get("camera_side", 1.0)))

	var suspicion_model := ranger.get("_suspicion_model") as RangerSuspicion
	suspicion_model.suspicion = 100.0
	ranger.call("_process", 0.0)
	var moment := StringName(spec.moment)
	match moment:
		&"windup":
			await create_timer(minf(float(ranger.get("grab_windup_duration")) * 0.55, 0.24)).timeout
		&"miss":
			ranger.call("_begin_lunge")
			player.global_position += Vector3(3.2, 0.0, 0.0)
			ranger.call("_update_grab", float(ranger.get("grab_lunge_duration")) + 0.01)
			await create_timer(0.16).timeout
		&"caught":
			ranger.call("_begin_lunge")
			player.global_position = ranger.global_position + Vector3(0.0, 0.475, -0.55)
			ranger.call("_update_grab", 0.0)
			await create_timer(0.2).timeout

	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var output := "%s/%s.png" % [OUTPUT_DIRECTORY, String(spec.name)]
	var save_error := image.save_png(output)
	if save_error != OK:
		_fail("Could not save %s: %s" % [output, error_string(save_error)])
	else:
		print("PLAYTEST_CAPTURE|%s" % ProjectSettings.globalize_path(output))

	paused = false
	level.queue_free()
	await process_frame

func _arrange_reactors(level: Node, stage: Vector3) -> void:
	var pigeon_offsets := [
		Vector3(-1.3, 0.0, -1.4),
		Vector3(1.25, 0.0, -1.7),
		Vector3(-2.0, 0.0, -2.7),
		Vector3(2.0, 0.0, -2.8),
	]
	var pigeons := get_nodes_in_group("pigeons")
	for index in mini(pigeons.size(), pigeon_offsets.size()):
		var pigeon := pigeons[index] as Node3D
		pigeon.global_position = stage + pigeon_offsets[index]
		pigeon.set("flee_distance", 0.0)

	var visitor_offsets := [
		Vector3(-3.0, -0.475, -1.8),
		Vector3(3.0, -0.475, -2.1),
		Vector3(-3.8, -0.475, -3.5),
	]
	var visitors := get_nodes_in_group("visitors")
	for index in mini(visitors.size(), visitor_offsets.size()):
		var visitor := visitors[index] as Node3D
		visitor.global_position = stage + visitor_offsets[index]

func _install_camera(level: Node, stage: Vector3, camera_side: float) -> void:
	var camera := Camera3D.new()
	camera.name = "CapturePlaytestCamera"
	camera.fov = 52.0
	level.add_child(camera)
	camera.global_position = stage + Vector3(4.8 * camera_side, 2.7, 5.4)
	camera.look_at(stage + Vector3(0.0, -0.3, -1.55), Vector3.UP)
	camera.make_current()

func _fail(message: String) -> void:
	_failures += 1
	push_error("Physical-capture playtest capture failed: %s" % message)
