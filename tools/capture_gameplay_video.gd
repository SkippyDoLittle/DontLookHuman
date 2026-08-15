extends SceneTree

const FPS: int = 30
const TRAILER_SECONDS: float = 33.0
const CAPTURE_SIZE: Vector2i = Vector2i(1280, 720)
const BRAND_IMAGE: String = "res://assets/branding/store_capsule.png"
const CARD_SCENE: PackedScene = preload("res://tools/trailer_card.tscn")
const SOUNDTRACK_SCRIPT: Script = preload("res://tools/trailer_soundtrack.gd")
const TEMP_SCORE_PATH: String = "user://phase10_trailer_scores.cfg"
const TEMP_LEGACY_SCORE_PATH: String = "user://phase10_trailer_legacy.dat"
const TEMP_PROGRESS_PATH: String = "user://phase10_trailer_progress.cfg"
const INPUT_ACTIONS: Array[StringName] = [
	&"move_forward",
	&"move_back",
	&"move_left",
	&"move_right",
	&"run",
	&"peck",
]
const SHOT_SPECS: Array[Dictionary] = [
	{
		"path": "res://scenes/levels/Level04_Festival.tscn",
		"kind": &"hook",
		"duration": 5.0,
		"seed": 40401,
	},
	{
		"path": "res://scenes/levels/Level03_Lakeside.tscn",
		"kind": &"blend",
		"duration": 5.0,
		"seed": 30302,
	},
	{
		"path": "res://scenes/levels/Level02_Playground.tscn",
		"kind": &"collision",
		"duration": 5.0,
		"seed": 20203,
	},
	{
		"path": "res://scenes/levels/Level05_BotanicalGardens.tscn",
		"kind": &"gauntlet",
		"duration": 14.0,
		"seed": 50504,
	},
]

var _failures: int = 0
var _active_level: Node = null
var _camera: Camera3D = null
var _overlay_layer: CanvasLayer = null
var _cut_rect: ColorRect = null
var _punch_label: Label = null
var _music_player: AudioStreamPlayer = null
var _capture_frame_index: int = 0
var _active_shot_seed: int = 0

func _initialize() -> void:
	call_deferred("_record_trailer")

func _record_trailer() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(CAPTURE_SIZE)
	_force_capture_quality()
	_force_capture_accessibility()
	_cleanup_temporary_saves()
	_install_overlay()
	_prepare_audio()

	var level := _load_level(SHOT_SPECS[0])
	await _capture_hook(level, float(SHOT_SPECS[0].duration))
	level = _load_level(SHOT_SPECS[1])
	await _capture_blend(level, float(SHOT_SPECS[1].duration))
	level = _load_level(SHOT_SPECS[2])
	await _capture_collision_comedy(level, float(SHOT_SPECS[2].duration))
	level = _load_level(SHOT_SPECS[3])
	await _capture_gauntlet(level, float(SHOT_SPECS[3].duration))
	await _show_final_hook(0.8)
	await _show_logo_reveal(3.2)

	_release_actions()
	if is_instance_valid(_active_level):
		_active_level.free()
	_active_level = null
	_cleanup_temporary_saves()

	if _failures == 0:
		print(
			"RELEASE_TRAILER_CAPTURE_OK|duration=%.1f|shots=%d|style=hook-first"
			% [TRAILER_SECONDS, SHOT_SPECS.size()]
		)
	quit(_failures)

func _load_level(spec: Dictionary) -> Node:
	_release_actions()
	paused = false
	if is_instance_valid(_active_level):
		_active_level.free()
	_active_shot_seed = int(spec.seed)
	_capture_frame_index = 0
	seed(_active_shot_seed)
	_force_capture_quality()
	_force_capture_accessibility()
	var path := String(spec.path)

	var packed := load(path) as PackedScene
	if packed == null:
		_fail("Could not load trailer level: %s" % path)
		return null

	_active_level = packed.instantiate()
	root.add_child(_active_level)
	_force_capture_quality()
	_stop_shipping_audio()
	for overlay_name in ["TitleScreen", "TransitionLayer", "PauseMenu", "HowToPlayScreen"]:
		var overlay := _active_level.get_node_or_null(overlay_name)
		if overlay != null:
			overlay.visible = false
	var hud_fade := _active_level.get_node_or_null("HUD/FadeOverlay")
	if hud_fade != null:
		hud_fade.visible = false

	var session := _active_level.get_node_or_null("GameTimer") as GameSession
	if session == null:
		_fail("Trailer level has no GameTimer: %s" % path)
		return _active_level
	session.set("_score_store", BestScoreStore.new(TEMP_SCORE_PATH, TEMP_LEGACY_SCORE_PATH))
	session.set("_progress_store", CampaignProgressStore.new(TEMP_PROGRESS_PATH))
	session.call("_set_state", GameSession.SessionState.ACTIVE)

	_configure_hud(_active_level)
	_camera = Camera3D.new()
	_camera.name = "TrailerCamera"
	_camera.fov = 58.0
	_active_level.add_child(_camera)
	_camera.make_current()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	return _active_level

func _capture_hook(level: Node, duration: float) -> void:
	if level == null:
		return
	var player := level.get_node("Player") as CharacterBody3D
	var ranger := level.get_node("Ranger") as CharacterBody3D
	var food := level.get_node("PicnicFood") as Node3D
	var stage := Vector3(0.0, 1.0, 7.2)
	_position_player(player, stage, 0.0)
	food.global_position = Vector3(stage.x, 0.13, stage.z - 0.72)
	ranger.global_position = Vector3(stage.x + 0.82, 0.525, stage.z - 0.40)
	ranger.look_at(player.global_position, Vector3.UP)
	_arrange_pigeons(level, stage, [
		Vector3(-1.35, 0.0, 0.38),
		Vector3(1.45, 0.0, 0.72),
		Vector3(-1.85, 0.0, -0.82),
	])
	_set_suspicion(ranger, 54.0)
	_script_ranger(ranger, "")
	_set_hud_detail(level, false)

	var total_frames := ceili(duration * FPS)
	for frame in total_frames:
		_capture_frame_index = frame
		var elapsed := float(frame) / float(FPS)
		_reset_frame_overlay()
		var actions: Array[StringName] = []
		if frame == 1:
			actions = [&"peck"]
		elif elapsed >= 1.08 and elapsed < 2.10:
			actions = [&"move_forward", &"run"]
		elif elapsed < 3.15 and elapsed >= 2.10:
			actions = [&"move_forward", &"move_left", &"run"]
		elif elapsed < 4.10 and elapsed >= 3.15:
			actions = [&"move_forward", &"move_right", &"run"]
		elif elapsed >= 4.10:
			actions = [&"move_forward", &"run"]

		if frame == 21:
			_set_suspicion(ranger, 91.0)
			_script_ranger(ranger, "!!")
		if frame == 5:
			_force_collect(food)
		if elapsed >= 0.70:
			_hold_suspicion([ranger], 91.0, 94.0)
			_sync_hud(level, 92.0, "Ranger: ALERT!")
		_set_hud_detail(level, elapsed >= 0.72)
		if elapsed >= 1.08:
			_drive_scripted_rangers([ranger], player, 3.15)

		if elapsed < 0.72:
			var orbit := elapsed / 0.72
			_set_camera(
				Vector3(stage.x + 2.40 - orbit * 0.30, 0.95, stage.z + 2.38 - orbit * 0.30),
				Vector3(stage.x, 0.18, stage.z - 0.25),
				lerpf(48.0, 43.0, orbit)
			)
		elif elapsed < 1.55:
			var push := (elapsed - 0.72) / 0.83
			_set_camera(
				ranger.global_position + Vector3(1.72 - push * 0.50, 1.12, 1.90 - push * 0.52),
				(ranger.global_position + player.global_position) * 0.5 + Vector3.UP * 0.15,
				lerpf(46.0, 55.0, push),
				0.25
			)
		elif elapsed < 3.15:
			_set_camera(
				player.global_position + Vector3(2.40, 1.05, 2.15),
				player.global_position + Vector3(0.0, -0.30, -0.45),
				64.0,
				0.14
			)
		else:
			_set_camera(
				player.global_position + Vector3(-1.70, 0.78, -2.55),
				player.global_position + Vector3(0.0, -0.25, 0.10),
				69.0,
				0.10
			)

		_apply_micro_cuts(frame, [46, 94])
		_apply_white_impact(frame, 5, 5)
		_set_actions(actions)
		await process_frame

func _capture_blend(level: Node, duration: float) -> void:
	if level == null:
		return
	var player := level.get_node("Player") as CharacterBody3D
	var ranger := level.get_node("Ranger") as CharacterBody3D
	var food := level.get_node("PicnicFood4") as Node3D
	var stage := Vector3(4.0, 1.0, 4.2)
	_position_player(player, stage, 0.0)
	ranger.global_position = Vector3(stage.x, 0.525, stage.z - 2.25)
	ranger.look_at(player.global_position, Vector3.UP)
	_script_ranger(ranger, "!")
	food.global_position = Vector3(stage.x - 1.55, 0.10, stage.z - 2.20)
	_arrange_pigeons(level, stage, [
		Vector3(-0.65, 0.0, -0.10),
		Vector3(0.62, 0.0, 0.14),
		Vector3(-1.15, 0.0, 0.62),
		Vector3(1.12, 0.0, 0.70),
	])
	_set_suspicion(ranger, 68.0)

	var staged_pickup := false
	var total_frames := ceili(duration * FPS)
	for frame in total_frames:
		_capture_frame_index = frame
		var elapsed := float(frame) / float(FPS)
		_reset_frame_overlay()
		_show_punch("ACT NATURAL.", elapsed, 0.0, 0.92)
		var actions: Array[StringName] = []
		if frame == 25:
			actions = [&"peck"]
		elif elapsed >= 1.72 and elapsed < 2.70:
			actions = [&"move_left"]
		elif elapsed >= 2.70 and elapsed < 3.0:
			actions = [&"move_forward"]
		elif frame == 91:
			actions = [&"peck"]
		elif elapsed >= 3.45:
			actions = [&"move_forward", &"move_right", &"run"]

		if not staged_pickup and frame >= 84:
			staged_pickup = true
			food.global_position = player.global_position + Vector3(0.0, -0.87, -0.68)
		if frame == 94:
			_force_collect(food)
		if frame == 106:
			_script_ranger(ranger, "!!")
		_hold_suspicion([ranger], 68.0, 88.0)
		_sync_hud(level, 74.0 if frame < 106 else 91.0, "Ranger: Watching" if frame < 106 else "Ranger: ALERT!")
		_drive_scripted_rangers([ranger], player, 0.42 if frame < 106 else 2.60)

		if elapsed < 1.55:
			_set_camera(
				stage + Vector3(-2.75, 0.30, 2.20),
				stage + Vector3(0.0, -0.45, 0.0),
				48.0
			)
		elif elapsed < 2.72:
			_set_camera(
				ranger.global_position + Vector3(0.25, 1.35, -1.15),
				player.global_position + Vector3.UP * -0.20,
				55.0
			)
		elif elapsed < 3.55:
			_set_camera(
				player.global_position + Vector3(1.35, 0.58, 1.35),
				player.global_position + Vector3(0.0, -0.55, -0.35),
				44.0
			)
		else:
			_set_camera(
				player.global_position + Vector3(-2.20, 1.30, 2.75),
				player.global_position + Vector3(0.0, -0.20, -0.45),
				66.0,
				0.10
			)

		_apply_micro_cuts(frame, [47, 82, 106])
		_apply_white_impact(frame, 94, 4)
		_set_actions(actions)
		await process_frame

func _capture_collision_comedy(level: Node, duration: float) -> void:
	if level == null:
		return
	var player := level.get_node("Player") as CharacterBody3D
	var rangers := _rangers(level)
	var food := level.get_node("PicnicFood") as Node3D
	var stage := Vector3(0.0, 1.0, -2.0)
	_stage_pickup(player, food, stage, 0.0)

	var ranger_a: CharacterBody3D = null
	var ranger_b: CharacterBody3D = null
	if not rangers.is_empty():
		ranger_a = rangers[0]
		ranger_a.process_mode = Node.PROCESS_MODE_DISABLED
		ranger_a.global_position = Vector3(stage.x, 0.525, stage.z - 3.4)
		ranger_a.look_at(player.global_position, Vector3.UP)
		_set_suspicion(ranger_a, 90.0)
		_script_ranger(ranger_a, "!!")
	if rangers.size() >= 2:
		ranger_b = rangers[1]
		ranger_b.process_mode = Node.PROCESS_MODE_DISABLED
		ranger_b.global_position = Vector3(stage.x + 2.6, 0.525, stage.z - 1.8)
		ranger_b.look_at(player.global_position, Vector3.UP)
		_set_suspicion(ranger_b, 82.0)
		_script_ranger(ranger_b, "!")
	_arrange_pigeons(level, stage, [
		Vector3(-0.95, 0.0, 0.70),
		Vector3(1.10, 0.0, 0.80),
	])
	_set_hud_detail(level, true)

	var stumble_done := false
	var body_a: Node3D = null
	if ranger_a != null:
		body_a = ranger_a.get_node_or_null("RangerBody")

	var total_frames := ceili(duration * FPS)
	for frame in total_frames:
		_capture_frame_index = frame
		var elapsed := float(frame) / float(FPS)
		_reset_frame_overlay()

		var actions: Array[StringName] = []
		if frame == 5:
			actions = [&"peck"]
		elif elapsed >= 0.48 and elapsed < 1.05:
			actions = [&"move_right", &"run"]
		elif elapsed >= 1.05:
			actions = [&"move_forward", &"run"]

		if frame == 8:
			_force_collect(food)

		if ranger_a != null:
			if frame < 42:
				_drive_scripted_rangers([ranger_a], player, 2.8)
				_hold_suspicion([ranger_a], 90.0, 94.0)
			elif frame == 42 and not stumble_done:
				stumble_done = true
				_script_ranger(ranger_a, "??")
				if body_a != null:
					body_a.rotation.x = 0.52
					body_a.rotation.z = 0.28
			elif frame > 42 and frame <= 90:
				var recover_t := float(frame - 42) / 48.0
				if body_a != null:
					body_a.rotation.x = lerpf(0.52, 0.0, recover_t)
					body_a.rotation.z = lerpf(0.28, 0.0, recover_t)
				_set_suspicion(ranger_a, lerpf(94.0, 78.0, recover_t))
			else:
				if body_a != null:
					body_a.rotation.x = 0.0
					body_a.rotation.z = 0.0
				_script_ranger(ranger_a, "!")
				_set_suspicion(ranger_a, 84.0)
				_drive_scripted_rangers([ranger_a], player, 2.0)

		if ranger_b != null:
			_drive_scripted_rangers([ranger_b], player, 1.8 if frame < 90 else 2.2)
			_hold_suspicion([ranger_b], 82.0, 94.0)

		var suspicion_val: float
		if frame < 42:
			suspicion_val = 90.0
		elif frame <= 90:
			suspicion_val = lerpf(94.0, 78.0, float(frame - 42) / 48.0)
		else:
			suspicion_val = 84.0
		_sync_hud(
			level,
			suspicion_val,
			"Rangers: CHASING!" if (frame < 42 or frame > 90) else "Ranger: Confused"
		)

		if frame < 15:
			_set_camera(
				stage + Vector3(3.2, 1.8, 3.5),
				stage + Vector3(0.0, -0.50, -0.20),
				46.0
			)
		elif frame < 48:
			_set_camera(
				stage + Vector3(-0.40, 1.0, 2.5),
				stage + Vector3(0.0, -0.50, -0.20),
				52.0,
				0.08
			)
		elif frame < 90 and ranger_a != null:
			_set_camera(
				ranger_a.global_position + Vector3(0.70, 1.10, 1.55),
				ranger_a.global_position + Vector3(0.0, -0.20, 0.0),
				50.0
			)
		else:
			_set_camera(
				player.global_position + Vector3(-2.20, 1.05, 2.40),
				player.global_position + Vector3(0.0, -0.32, -0.30),
				66.0,
				0.12
			)

		_apply_micro_cuts(frame, [42, 90])
		_apply_white_impact(frame, 8, 4)
		_apply_white_impact(frame, 42, 7)
		_set_actions(actions)
		await process_frame

func _capture_gauntlet(level: Node, duration: float) -> void:
	if level == null:
		return
	var player := level.get_node("Player") as CharacterBody3D
	var final_food := level.get_node("PicnicFood5") as Node3D
	var escape_zone := level.get_node("EscapeZone") as Node3D
	var exit_area := escape_zone.get_node("ExitArea") as Area3D
	var portal_light := _build_trailer_portal(escape_zone)
	exit_area.set_deferred("monitoring", false)
	for collectible in _collectibles(level):
		if collectible != final_food:
			collectible.free()

	var rangers := _rangers(level)
	var start := Vector3(4.2, 1.0, 5.0)
	_stage_pickup(player, final_food, start, 0.78)
	_stage_rangers_around(rangers, start, 2.6)
	for ranger in rangers:
		_set_suspicion(ranger, 91.0)

	var escape_sound_played := false
	var total_frames := ceili(duration * FPS)
	for frame in total_frames:
		_capture_frame_index = frame
		var elapsed := float(frame) / float(FPS)
		_reset_frame_overlay()
		_show_punch("TOO LATE.", elapsed, 0.0, 0.78)

		if frame == 105:
			_position_player(player, Vector3(2.2, 1.0, 2.3), 0.78)
			_stage_rangers_around(rangers, player.global_position, 2.4)
		if frame == 210:
			_position_player(player, Vector3(-2.0, 1.0, -1.2), 0.70)
			_stage_rangers_around(rangers, player.global_position, 2.2)
		if frame == 300:
			_position_player(player, Vector3(-5.6, 1.0, -4.8), 0.66)
			_stage_rangers_around(rangers, player.global_position, 2.0)
		if frame == 375:
			_position_player(player, escape_zone.global_position + Vector3(0.0, 0.75, 2.0), 0.0)
			_stage_rangers_around(rangers, player.global_position, 1.75)

		var actions: Array[StringName] = []
		if frame == 18:
			actions = [&"peck"]
		elif elapsed >= 0.88 and frame < 375:
			if frame % 90 < 30:
				actions = [&"move_forward", &"move_left", &"run"]
			elif frame % 90 < 60:
				actions = [&"move_forward", &"move_right", &"run"]
			else:
				actions = [&"move_forward", &"run"]
		elif frame >= 375 and frame < 414:
			actions = [&"move_forward"]

		for ranger in rangers:
			_hold_suspicion([ranger], 91.0, 94.0)
		if frame == 21:
			_force_collect(final_food)
			escape_zone.visible = true
			for ranger in rangers:
				_script_ranger(ranger, "!!")
		if frame >= 21:
			_sync_hud(level, 94.0, "Rangers: CHASING!")
			if frame >= 375:
				var portal_target := escape_zone.global_position + Vector3(0.0, 0.75, 0.0)
				player.global_position = player.global_position.move_toward(portal_target, 0.085)
				var warning := level.get_node_or_null("HUD/WarnLabel") as Label
				if warning != null:
					warning.visible = false
			_drive_scripted_rangers(rangers, player, 3.05)
			_animate_trailer_portal(escape_zone, portal_light, elapsed)

		if elapsed < 1.15:
			_set_camera(start + Vector3(2.65, 3.15, 2.10), start + Vector3(0.0, -0.45, -0.35), 50.0)
		elif elapsed < 3.50:
			_set_camera(
				player.global_position + Vector3(-2.80, 2.65, 2.85),
				player.global_position + Vector3(0.0, -0.32, -0.30),
				62.0,
				0.13
			)
		elif elapsed < 7.0:
			var lead_ranger := rangers[0]
			_set_camera(
				lead_ranger.global_position + Vector3(-0.15, 1.35, 1.30),
				player.global_position + Vector3(0.0, -0.20, 0.0),
				68.0,
				0.16
			)
		elif elapsed < 10.0:
			_set_camera(
				player.global_position + Vector3(-2.0, 0.72, -2.55),
				player.global_position + Vector3(0.0, -0.38, 0.05),
				72.0,
				0.17
			)
		elif elapsed < 12.5:
			_set_camera(
				player.global_position + Vector3(3.75, 3.45, 4.35),
				player.global_position + Vector3(0.0, -0.25, -0.50),
				64.0,
				0.10
			)
		else:
			_set_camera(
				escape_zone.global_position + Vector3(4.20, 2.15, 0.35),
				escape_zone.global_position + Vector3(0.0, 0.72, 0.0),
				55.0,
				0.20
			)

		_apply_micro_cuts(frame, [105, 210, 300, 375])
		_apply_white_impact(frame, 21, 5)
		if frame >= 409:
			var escape_flash := clampf(float(frame - 409) / 10.0, 0.0, 1.0)
			_set_cut(Color.WHITE, escape_flash)
		if frame == 410 and not escape_sound_played:
			escape_sound_played = true
			var sound_manager := root.get_node_or_null("SoundManager")
			if sound_manager != null:
				sound_manager.call("play_escape")

		_set_actions(actions)
		await process_frame

func _build_trailer_portal(escape_zone: Node3D) -> OmniLight3D:
	var colors: Array[Color] = [
		Color(0.05, 0.95, 1.0),
		Color(0.64, 0.18, 1.0),
		Color(1.0, 0.86, 0.18),
	]
	var radii: Array[float] = [1.80, 1.20, 0.58]
	for index in radii.size():
		var disc := MeshInstance3D.new()
		disc.name = "TrailerPortalDisc%d" % index
		var mesh := CylinderMesh.new()
		mesh.top_radius = radii[index]
		mesh.bottom_radius = radii[index]
		mesh.height = 0.09 + float(index) * 0.025
		mesh.radial_segments = 48
		disc.mesh = mesh
		disc.position.y = 0.05 + float(index) * 0.055
		var material := StandardMaterial3D.new()
		material.albedo_color = colors[index]
		material.emission_enabled = true
		material.emission = colors[index]
		material.emission_energy_multiplier = 4.2 - float(index) * 0.65
		disc.material_override = material
		escape_zone.add_child(disc)

	var label := escape_zone.get_node("ExitLabel") as Label3D
	label.text = "ESCAPE!"
	label.position.y = 2.35
	label.font_size = 92
	label.outline_size = 18
	label.modulate = Color(0.30, 1.0, 1.0)

	var light := OmniLight3D.new()
	light.name = "TrailerPortalLight"
	light.position.y = 1.0
	light.light_color = Color(0.20, 0.90, 1.0)
	light.light_energy = 4.2
	light.omni_range = 7.0
	escape_zone.add_child(light)
	return light

func _animate_trailer_portal(
	escape_zone: Node3D,
	portal_light: OmniLight3D,
	elapsed: float
) -> void:
	var pulse := 1.0 + sin(elapsed * 9.0) * 0.07
	for index in 3:
		var disc := escape_zone.get_node_or_null("TrailerPortalDisc%d" % index) as MeshInstance3D
		if disc != null:
			disc.scale = Vector3(pulse, 1.0, pulse)
			disc.rotation.y = elapsed * (1.1 + float(index) * 0.45)
	if portal_light != null:
		portal_light.light_energy = 4.2 + sin(elapsed * 11.0) * 1.1

func _show_final_hook(duration: float) -> void:
	_release_actions()
	if is_instance_valid(_active_level):
		_active_level.free()
	_active_level = null
	var total_frames := ceili(duration * FPS)
	for frame in total_frames:
		var elapsed := float(frame) / float(FPS)
		_reset_frame_overlay()
		_set_cut(Color.BLACK, 1.0)
		_show_punch("JUST A PIGEON.", elapsed, 0.0, duration)
		await process_frame

func _show_logo_reveal(duration: float) -> void:
	var card := CARD_SCENE.instantiate() as Control
	card.process_mode = Node.PROCESS_MODE_ALWAYS
	card.pivot_offset = Vector2(640.0, 360.0)
	var tagline := card.get_node("Tagline") as Label
	tagline.text = "WISHLIST NOW"
	tagline.modulate.a = 0.0
	_overlay_layer.add_child(card)

	var total_frames := ceili(duration * FPS)
	for frame in total_frames:
		var elapsed := float(frame) / float(FPS)
		var progress := clampf(elapsed / duration, 0.0, 1.0)
		_reset_frame_overlay()
		_set_cut(Color.BLACK, 1.0)
		card.modulate.a = clampf(elapsed / 0.18, 0.0, 1.0)
		var zoom := lerpf(1.12, 1.0, 1.0 - pow(1.0 - progress, 3.0))
		card.scale = Vector2.ONE * zoom
		tagline.modulate.a = clampf((elapsed - 0.72) / 0.34, 0.0, 1.0)
		await process_frame

func _prepare_audio() -> void:
	_stop_shipping_audio()
	var music_bus := AudioServer.get_bus_index("Music")
	var sfx_bus := AudioServer.get_bus_index("SFX")
	if music_bus >= 0:
		AudioServer.set_bus_volume_db(music_bus, -5.0)
	if sfx_bus >= 0:
		AudioServer.set_bus_volume_db(sfx_bus, 1.5)
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "TrailerSoundtrack"
	_music_player.bus = "Music"
	_music_player.stream = SOUNDTRACK_SCRIPT.build(TRAILER_SECONDS)
	root.add_child(_music_player)
	_music_player.play()

func _install_overlay() -> void:
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.name = "TrailerOverlay"
	_overlay_layer.layer = 100
	root.add_child(_overlay_layer)

	_cut_rect = ColorRect.new()
	_cut_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cut_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cut_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	_overlay_layer.add_child(_cut_rect)

	_punch_label = Label.new()
	_punch_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_punch_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_punch_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_punch_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_punch_label.add_theme_font_size_override("font_size", 72)
	_punch_label.add_theme_color_override("font_color", Color(1.0, 0.93, 0.70))
	_punch_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.95))
	_punch_label.add_theme_constant_override("outline_size", 12)
	_punch_label.pivot_offset = Vector2(640.0, 360.0)
	_punch_label.visible = false
	_overlay_layer.add_child(_punch_label)

	for top_bar in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color(0.0, 0.0, 0.0, 0.86)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.anchor_left = 0.0
		bar.anchor_right = 1.0
		if top_bar:
			bar.anchor_top = 0.0
			bar.anchor_bottom = 0.0
			bar.offset_bottom = 24.0
		else:
			bar.anchor_top = 1.0
			bar.anchor_bottom = 1.0
			bar.offset_top = -24.0
		_overlay_layer.add_child(bar)

func _reset_frame_overlay() -> void:
	_cut_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	_punch_label.visible = false

func _show_punch(text: String, elapsed: float, start: float, duration: float) -> void:
	if elapsed < start or elapsed >= start + duration:
		return
	var progress := (elapsed - start) / duration
	var alpha := clampf(minf(progress / 0.12, (1.0 - progress) / 0.20), 0.0, 1.0)
	var eased := 1.0 - pow(1.0 - progress, 3.0)
	_punch_label.text = text
	_punch_label.visible = true
	_punch_label.modulate.a = alpha
	_punch_label.scale = Vector2.ONE * lerpf(1.30, 1.0, eased)
	_punch_label.rotation = lerpf(-0.025, 0.0, eased)

func _set_cut(color: Color, alpha: float) -> void:
	if alpha < _cut_rect.color.a:
		return
	_cut_rect.color = Color(color.r, color.g, color.b, clampf(alpha, 0.0, 1.0))

func _apply_micro_cuts(frame: int, cut_frames: Array) -> void:
	for cut_frame_value in cut_frames:
		var cut_frame := int(cut_frame_value)
		var distance := absi(frame - cut_frame)
		if distance == 0:
			_set_cut(Color.BLACK, 0.92)
		elif distance == 1:
			_set_cut(Color.BLACK, 0.38)

func _apply_white_impact(frame: int, impact_frame: int, radius: int) -> void:
	var distance := absi(frame - impact_frame)
	if distance > radius:
		return
	var alpha := (1.0 - float(distance) / float(radius + 1)) * 0.56
	_set_cut(Color(1.0, 0.92, 0.70), alpha)

func _set_camera(position: Vector3, target: Vector3, fov: float, shake: float = 0.0) -> void:
	if not is_instance_valid(_camera):
		return
	var deterministic_phase := (
		float(_capture_frame_index) / float(FPS)
		+ float(_active_shot_seed % 997) * 0.001
	)
	var shake_offset := Vector3(
		sin(deterministic_phase * 61.0) * shake,
		cos(deterministic_phase * 73.0) * shake * 0.55,
		sin(deterministic_phase * 47.0) * shake * 0.35
	)
	_camera.global_position = position + shake_offset
	_camera.fov = fov
	_camera.look_at(target, Vector3.UP)

func _position_player(player: CharacterBody3D, position: Vector3, yaw: float) -> void:
	player.global_position = position
	player.velocity = Vector3.ZERO
	player.set("camera_yaw", yaw)
	player.set("camera_pitch", -0.12)
	var spring_arm := player.get_node("SpringArm3D") as SpringArm3D
	spring_arm.rotation = Vector3(-0.12, yaw, 0.0)
	var visual := player.get_node("PigeonVisual") as Node3D
	visual.rotation.y = yaw + PI

func _stage_pickup(
	player: CharacterBody3D,
	food: Node3D,
	position: Vector3,
	yaw: float
) -> void:
	_position_player(player, position, yaw)
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	food.global_position = position + forward * 0.70 + Vector3.DOWN * 0.87

func _stage_rangers_around(rangers: Array[CharacterBody3D], origin: Vector3, distance: float) -> void:
	var offsets: Array[Vector3] = [
		Vector3(distance, -0.475, distance * 0.25),
		Vector3(-distance * 0.80, -0.475, distance * 0.50),
		Vector3(distance * 0.20, -0.475, distance),
		Vector3(-distance * 0.20, -0.475, -distance),
	]
	for index in mini(rangers.size(), offsets.size()):
		var ranger := rangers[index]
		ranger.process_mode = Node.PROCESS_MODE_DISABLED
		ranger.global_position = origin + offsets[index]
		ranger.velocity = Vector3.ZERO
		ranger.look_at(origin, Vector3.UP)

func _arrange_pigeons(level: Node, origin: Vector3, offsets: Array[Vector3]) -> void:
	var pigeons := _pigeons(level)
	for index in mini(pigeons.size(), offsets.size()):
		var pigeon := pigeons[index]
		pigeon.global_position = origin + offsets[index]
		pigeon.process_mode = Node.PROCESS_MODE_DISABLED

func _force_collect(food: Node3D) -> void:
	if not is_instance_valid(food) or food.is_queued_for_deletion():
		return
	# Use the shipping collection path so signals, objective state, sound, particles,
	# and the beak-flight animation remain honest and cannot drift from gameplay.
	food.call("_begin_collection")

func _script_ranger(ranger: CharacterBody3D, alert_text: String) -> void:
	ranger.process_mode = Node.PROCESS_MODE_DISABLED
	var alert := ranger.get_node("AlertLabel") as Label3D
	alert.visible = not alert_text.is_empty()
	alert.text = alert_text
	alert.scale = Vector3.ONE * (1.45 if alert_text == "!!" else 1.18)
	alert.modulate = Color(1.0, 0.20, 0.16) if alert_text == "!!" else Color(1.0, 0.86, 0.12)

func _drive_scripted_rangers(
	rangers: Array[CharacterBody3D],
	player: CharacterBody3D,
	speed: float
) -> void:
	for ranger in rangers:
		var to_player := player.global_position - ranger.global_position
		to_player.y = 0.0
		if to_player.length() <= 0.72:
			continue
		var direction := to_player.normalized()
		ranger.global_position += direction * speed / float(FPS)
		ranger.look_at(
			Vector3(player.global_position.x, ranger.global_position.y, player.global_position.z),
			Vector3.UP
		)

func _sync_hud(level: Node, suspicion: float, status: String) -> void:
	var bar := level.get_node_or_null("HUD/SuspicionBar") as ProgressBar
	if bar != null:
		bar.value = suspicion
	var ranger_status := level.get_node_or_null("HUD/RangerStatus") as Label
	if ranger_status != null:
		ranger_status.text = status
	var warning := level.get_node_or_null("HUD/WarnLabel") as Label
	if warning != null:
		warning.visible = suspicion >= 90.0
		warning.text = "DANGER!" if suspicion >= 90.0 else ""

func _set_suspicion(ranger: CharacterBody3D, value: float) -> void:
	var model := ranger.get("_suspicion_model") as RangerSuspicion
	if model != null:
		model.suspicion = value

func _hold_suspicion(
	rangers: Array[CharacterBody3D],
	minimum: float,
	maximum: float
) -> void:
	for ranger in rangers:
		var model := ranger.get("_suspicion_model") as RangerSuspicion
		if model != null:
			model.suspicion = clampf(model.suspicion, minimum, maximum)

func _rangers(level: Node) -> Array[CharacterBody3D]:
	var result: Array[CharacterBody3D] = []
	for child in level.get_children():
		if child is CharacterBody3D and String(child.name).begins_with("Ranger"):
			result.append(child as CharacterBody3D)
	return result

func _pigeons(level: Node) -> Array[Node3D]:
	var result: Array[Node3D] = []
	for node in get_nodes_in_group("pigeons"):
		if node is Node3D and level.is_ancestor_of(node):
			result.append(node as Node3D)
	return result

func _collectibles(level: Node) -> Array[Node3D]:
	var result: Array[Node3D] = []
	for node in get_nodes_in_group("collectibles"):
		if node is Node3D and level.is_ancestor_of(node):
			result.append(node as Node3D)
	return result

func _configure_hud(level: Node) -> void:
	for node_path in [
		"HUD/TimerLabel",
		"HUD/Minimap",
		"HUD/CountdownLabel",
		"HUD/ResultBackground",
		"HUD/ResultLabel",
		"HUD/ResultActions",
		"HUD/DebugOverlay",
		"HUD/ChaosWindowCallout",
		"HUD/HelpHint",
	]:
		var control := level.get_node_or_null(node_path) as CanvasItem
		if control != null:
			control.visible = false

func _set_hud_detail(level: Node, visible: bool) -> void:
	for node_path in ["HUD/RangerStatus", "HUD/SuspicionBar", "HUD/ObjectiveStatus"]:
		var control := level.get_node_or_null(node_path) as CanvasItem
		if control != null:
			control.visible = visible

func _set_actions(actions: Array[StringName]) -> void:
	_release_actions()
	for action in actions:
		Input.action_press(action)

func _release_actions() -> void:
	for action in INPUT_ACTIONS:
		Input.action_release(action)

func _cleanup_temporary_saves() -> void:
	for path in [TEMP_SCORE_PATH, TEMP_LEGACY_SCORE_PATH, TEMP_PROGRESS_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _force_capture_quality() -> void:
	var quality_settings := root.get_node_or_null("QualitySettings")
	if quality_settings != null and quality_settings.has_method("apply_preset"):
		quality_settings.call("apply_preset", "High", false)

func _force_capture_accessibility() -> void:
	# Capture is a separate process. Override the lazy cache only; never write the
	# player's user://settings.cfg or change their persisted reduced-motion choice.
	AccessibilitySettings._reduced_motion_cache[
		AccessibilitySettings.DEFAULT_SETTINGS_PATH
	] = false

func _stop_shipping_audio() -> void:
	var sound_manager := root.get_node_or_null("SoundManager")
	if sound_manager == null:
		return
	sound_manager.call("stop_music")
	sound_manager.call("stop_ambient")
	# stop_music intentionally fades during gameplay. Capture needs zero adaptive
	# bleed on the very first frame, so stop only its known layer players now. The
	# separately-owned TrailerSoundtrack player remains untouched and audible.
	if sound_manager.has_method("adaptive_music_director"):
		var music_director: Node = sound_manager.call("adaptive_music_director") as Node
		if is_instance_valid(music_director):
			var layer_names: Array[StringName] = music_director.call("layer_names")
			for layer_name in layer_names:
				var layer_player := music_director.call("layer_player", layer_name) as AudioStreamPlayer
				if is_instance_valid(layer_player):
					layer_player.stop()
					layer_player.volume_db = -80.0

func _fail(message: String) -> void:
	_failures += 1
	push_error("Release trailer capture failed: %s" % message)
