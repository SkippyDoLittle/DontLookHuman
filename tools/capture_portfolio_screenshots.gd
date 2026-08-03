extends SceneTree

const CAPTURES: Array[Dictionary] = [
	{
		"path": "res://scenes/levels/Level01_Park.tscn",
		"output": "res://docs/screenshots/level_01_park.png",
		"yaw": 0.45,
	},
	{
		"path": "res://scenes/levels/Level02_Playground.tscn",
		"output": "res://docs/screenshots/level_02_playground.png",
		"yaw": -0.70,
	},
	{
		"path": "res://scenes/levels/Level03_Lakeside.tscn",
		"output": "res://docs/screenshots/level_03_lakeside.png",
		"yaw": 0.85,
	},
	{
		"path": "res://scenes/levels/Level04_Festival.tscn",
		"output": "res://docs/screenshots/level_04_festival.png",
		"yaw": -0.35,
	},
	{
		"path": "res://scenes/levels/Level05_BotanicalGardens.tscn",
		"output": "res://docs/screenshots/level_05_botanical_gardens.png",
		"yaw": 0.70,
	},
]

var _failures: int = 0

func _initialize() -> void:
	call_deferred("_capture_all")

func _capture_all() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	for spec in CAPTURES:
		await _capture_level(spec)
	if _failures == 0:
		print("PORTFOLIO_SCREENSHOTS_OK")
	quit(_failures)

func _capture_level(spec: Dictionary) -> void:
	var packed := load(String(spec.path)) as PackedScene
	if packed == null:
		_fail("Could not load %s" % spec.path)
		return

	var level := packed.instantiate()
	root.add_child(level)
	paused = false
	for overlay_name in ["HUD", "TitleScreen", "TransitionLayer", "PauseMenu", "HowToPlayScreen"]:
		var overlay := level.get_node_or_null(overlay_name)
		if overlay != null:
			overlay.visible = false
	var player := level.get_node_or_null("Player") as Node3D
	if player != null:
		player.rotation.y = float(spec.yaw)
	var sound_manager := root.get_node_or_null("SoundManager")
	if sound_manager != null:
		sound_manager.call("stop_ambient")

	for frame in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var save_error := image.save_png(String(spec.output))
	if save_error != OK:
		_fail("Could not save %s: %s" % [spec.output, error_string(save_error)])
	else:
		print("CAPTURED|%s" % spec.output)

	paused = false
	level.queue_free()
	await process_frame

func _fail(message: String) -> void:
	_failures += 1
	push_error("Portfolio capture failed: %s" % message)
