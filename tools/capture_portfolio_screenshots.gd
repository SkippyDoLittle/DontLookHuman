extends SceneTree

const CAPTURE_SIZE: Vector2i = Vector2i(1280, 720)
const SETTLE_FRAMES: int = 20
const FROZEN_HOLD_FRAMES: int = 3

const CAPTURES: Array[Dictionary] = [
	{
		"path": "res://scenes/levels/Level01_Park.tscn",
		"output": "res://docs/screenshots/level_01_park.png",
		"seed": 101,
		"landmark": "Pond",
		"player_position": Vector3(-1.1, 1.0, -4.25),
		"player_focus": Vector3(-0.15, 0.15, -3.65),
		"camera_position": Vector3(0.4, 2.35, 4.0),
		"camera_target": Vector3(-1.0, 0.62, -4.35),
		"camera_fov": 49.0,
		"ranger_name": "Ranger",
		"ranger_position": Vector3(1.25, 0.525, -4.9),
		"food_name": "PicnicFood",
		"food_position": Vector3(-0.15, 0.13, -3.65),
		"npc_positions": [
			Vector3(-2.15, 1.0, -4.7),
			Vector3(-2.65, 1.0, -5.65),
			Vector3(0.15, 1.0, -5.5),
		],
	},
	{
		"path": "res://scenes/levels/Level02_Playground.tscn",
		"output": "res://docs/screenshots/level_02_playground.png",
		"seed": 202,
		"landmark": "SwingBar",
		"player_position": Vector3(-1.15, 1.0, -4.15),
		"player_focus": Vector3(-0.15, 0.15, -4.65),
		"camera_position": Vector3(0.0, 2.15, 2.65),
		"camera_target": Vector3(0.0, 0.78, -5.15),
		"camera_fov": 49.0,
		"ranger_name": "Ranger",
		"ranger_position": Vector3(1.15, 0.525, -4.75),
		"food_name": "PicnicFood2",
		"food_position": Vector3(-0.15, 0.12, -4.65),
		"npc_positions": [
			Vector3(-2.15, 1.0, -5.15),
			Vector3(0.1, 1.0, -5.75),
			Vector3(2.15, 1.0, -5.75),
		],
	},
	{
		"path": "res://scenes/levels/Level03_Lakeside.tscn",
		"output": "res://docs/screenshots/level_03_lakeside.png",
		"seed": 303,
		"landmark": "Dock",
		"player_position": Vector3(-5.0, 1.18, -0.25),
		"player_focus": Vector3(-5.0, 0.4, -0.95),
		"camera_position": Vector3(-10.0, 2.55, 3.25),
		"camera_target": Vector3(-4.25, 0.62, -0.8),
		"camera_fov": 51.0,
		"ranger_name": "Ranger2",
		"ranger_position": Vector3(-5.05, 0.75, 1.65),
		"food_name": "PicnicFood5",
		"food_position": Vector3(-5.0, 0.4, -0.95),
		"npc_positions": [
			Vector3(-5.1, 1.18, -1.75),
			Vector3(-4.75, 1.18, -2.45),
		],
	},
	{
		"path": "res://scenes/levels/Level04_Festival.tscn",
		"output": "res://docs/screenshots/level_04_festival.png",
		"seed": 404,
		"landmark": "TentGreen",
		"player_position": Vector3(0.0, 1.0, 0.8),
		"player_focus": Vector3(0.45, 0.12, 0.45),
		"camera_position": Vector3(-10.0, 2.55, -1.0),
		"camera_target": Vector3(0.65, 0.78, 1.05),
		"camera_fov": 52.0,
		"ranger_name": "Ranger3",
		"ranger_position": Vector3(1.6, 0.525, 0.95),
		"food_name": "PicnicFood4",
		"food_position": Vector3(0.45, 0.12, 0.45),
		"npc_positions": [
			Vector3(-1.2, 1.0, 0.7),
			Vector3(-0.7, 1.0, 1.85),
		],
		"visitor_positions": [
			Vector3(-2.2, 0.85, 2.5),
			Vector3(2.6, 0.85, 2.6),
			Vector3(3.5, 0.85, 0.0),
			Vector3(-1.6, 0.85, -1.2),
		],
	},
	{
		"path": "res://scenes/levels/Level05_BotanicalGardens.tscn",
		"output": "res://docs/screenshots/level_05_botanical_gardens.png",
		"seed": 505,
		"landmark": "Fountain",
		"player_position": Vector3(-1.0, 1.0, 0.65),
		"player_focus": Vector3(-0.2, 0.15, 0.55),
		"camera_position": Vector3(4.5, 2.7, 4.4),
		"camera_target": Vector3(0.0, 0.7, -0.45),
		"camera_fov": 52.0,
		"ranger_name": "Ranger2",
		"ranger_position": Vector3(1.15, 0.525, -0.15),
		"food_name": "PicnicFood5",
		"food_position": Vector3(-0.2, 0.15, 0.55),
		"npc_positions": [
			Vector3(-1.85, 1.0, -0.1),
			Vector3(0.45, 1.0, -1.45),
		],
	},
]

var _failures: int = 0

func _initialize() -> void:
	call_deferred("_capture_all")

func _capture_all() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(CAPTURE_SIZE)
	# Pin presentation behavior in memory without overwriting the player's setting.
	AccessibilitySettings._reduced_motion_cache[
		AccessibilitySettings.DEFAULT_SETTINGS_PATH
	] = false
	_apply_capture_quality()
	for spec in CAPTURES:
		await _capture_level(spec)
	if _failures == 0:
		print("PORTFOLIO_SCREENSHOTS_OK")
	quit(_failures)

func _capture_level(spec: Dictionary) -> void:
	seed(int(spec.seed))
	_apply_capture_quality()
	var packed := load(String(spec.path)) as PackedScene
	if packed == null:
		_fail("Could not load %s" % spec.path)
		return

	var level := packed.instantiate()
	root.add_child(level)
	paused = false
	_apply_capture_quality()
	for overlay_name in ["HUD", "TitleScreen", "TransitionLayer", "PauseMenu", "HowToPlayScreen"]:
		var overlay := level.get_node_or_null(overlay_name)
		if overlay != null:
			overlay.visible = false
	_hide_chaos_window(level)
	_stage_level(level, spec)
	var sound_manager := root.get_node_or_null("SoundManager")
	if sound_manager != null:
		sound_manager.call("stop_music")
		sound_manager.call("stop_ambient")

	# Pause gameplay before shader/render warm-up so machine-specific frame deltas
	# cannot move AI or advance procedural actor poses before they are frozen.
	paused = true
	for frame in SETTLE_FRAMES:
		await process_frame
	# Reapply the complete composition after warm-up so process-always presentation
	# owners cannot introduce machine-specific camera or actor pose differences.
	_stage_level(level, spec)
	_freeze_capture_actors(level)
	for frame in FROZEN_HOLD_FRAMES:
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

func _apply_capture_quality() -> void:
	var quality_settings := root.get_node_or_null("QualitySettings")
	if quality_settings != null and quality_settings.has_method("apply_preset"):
		quality_settings.call("apply_preset", "High", false)

func _stage_level(level: Node, spec: Dictionary) -> void:
	var landmark := level.get_node_or_null(String(spec.landmark)) as Node3D
	if landmark == null:
		_fail("Missing capture landmark %s in %s" % [spec.landmark, level.name])

	var player := level.get_node_or_null("Player") as Node3D
	if player != null:
		player.global_position = spec.player_position
		_set_actor_velocity(player, Vector3.ZERO)
		_face_pigeon_visual(player, spec.player_focus)
		_pose_player(player)

	var food := level.get_node_or_null(String(spec.food_name)) as Node3D
	if food != null:
		food.global_position = spec.food_position

	var ranger := level.get_node_or_null(String(spec.ranger_name)) as Node3D
	if ranger != null:
		ranger.global_position = spec.ranger_position
		_set_actor_velocity(ranger, Vector3.ZERO)
		_face_standard_actor(ranger, spec.player_position)
		_pose_alert_ranger(ranger)

	_stage_named_pigeons(level, spec.get("npc_positions", []), spec.food_position)
	_stage_named_visitors(level, spec.get("visitor_positions", []), spec.player_position)
	_configure_capture_camera(level, spec)

func _configure_capture_camera(level: Node, spec: Dictionary) -> void:
	var camera := level.get_node_or_null("PortfolioCamera") as Camera3D
	if camera == null:
		camera = Camera3D.new()
		camera.name = "PortfolioCamera"
		camera.near = 0.08
		camera.far = 80.0
		level.add_child(camera)
	camera.global_position = spec.camera_position
	camera.fov = float(spec.camera_fov)
	camera.look_at(spec.camera_target, Vector3.UP)
	camera.make_current()

func _stage_named_pigeons(level: Node, positions: Array, focus: Vector3) -> void:
	for index in positions.size():
		var node_name := "NPC_Animal" if index == 0 else "NPC_Animal%d" % (index + 1)
		var pigeon := level.get_node_or_null(node_name) as Node3D
		if pigeon == null:
			continue
		pigeon.global_position = positions[index]
		_set_actor_velocity(pigeon, Vector3.ZERO)
		_face_pigeon_root(pigeon, focus)

func _stage_named_visitors(level: Node, positions: Array, focus: Vector3) -> void:
	for index in positions.size():
		var visitor := level.get_node_or_null("ParkVisitor%d" % (index + 1)) as Node3D
		if visitor == null:
			continue
		visitor.global_position = positions[index]
		_set_actor_velocity(visitor, Vector3.ZERO)
		_face_standard_actor(visitor, focus)

func _set_actor_velocity(actor: Node3D, value: Vector3) -> void:
	if actor is CharacterBody3D:
		(actor as CharacterBody3D).velocity = value

func _face_pigeon_visual(actor: Node3D, target: Vector3) -> void:
	var visual := actor.get_node_or_null("PigeonVisual") as Node3D
	if visual == null:
		return
	var direction := target - actor.global_position
	direction.y = 0.0
	if direction.length_squared() > 0.0001:
		visual.rotation.y = atan2(direction.x, direction.z)

func _face_pigeon_root(actor: Node3D, target: Vector3) -> void:
	var direction := target - actor.global_position
	direction.y = 0.0
	if direction.length_squared() > 0.0001:
		actor.look_at(actor.global_position - direction, Vector3.UP)

func _face_standard_actor(actor: Node3D, target: Vector3) -> void:
	var flat_target := Vector3(target.x, actor.global_position.y, target.z)
	if actor.global_position.distance_squared_to(flat_target) > 0.0001:
		actor.look_at(flat_target, Vector3.UP)

func _pose_player(player: Node3D) -> void:
	var left_wing := player.get_node_or_null("PigeonVisual/LeftWing") as Node3D
	var right_wing := player.get_node_or_null("PigeonVisual/RightWing") as Node3D
	var head := player.get_node_or_null("PigeonVisual/Head") as Node3D
	if left_wing != null:
		left_wing.rotation.z = 0.58
	if right_wing != null:
		right_wing.rotation.z = -0.32
	if head != null:
		head.rotation.z = -0.08

func _pose_alert_ranger(ranger: Node3D) -> void:
	var label := ranger.get_node_or_null("AlertLabel") as Label3D
	if label != null:
		label.text = "!"
		label.visible = true
	for limb_name in ["RangerLeftArm", "RangerRightArm"]:
		var arm := ranger.get_node_or_null(limb_name) as Node3D
		if arm != null:
			arm.rotation.x = -0.72

func _hide_chaos_window(level: Node) -> void:
	var chaos_window := level.get_node_or_null("HUD/ChaosWindowCallout") as CanvasItem
	if chaos_window != null:
		chaos_window.visible = false

func _freeze_capture_actors(level: Node) -> void:
	var player := level.get_node_or_null("Player")
	var descendants := level.find_children("*", "", true, false)
	for actor in descendants:
		var is_player := actor == player
		var is_capture_actor := (
			actor.is_in_group(&"rangers")
			or actor.is_in_group(&"pigeons")
			or actor.is_in_group(&"visitors")
		)
		if is_player or is_capture_actor:
			actor.process_mode = Node.PROCESS_MODE_DISABLED

func _fail(message: String) -> void:
	_failures += 1
	push_error("Portfolio capture failed: %s" % message)
