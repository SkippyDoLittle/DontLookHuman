extends "res://tools/capture_gameplay_video.gd"

# Directed 52-second gameplay showcase for sharing with friends. It uses the
# real campaign scenes and gameplay presentation methods while staging the
# newest controlled-chaos systems so every beat is readable on video.

const SHOWCASE_SECONDS: float = 52.0
const PARK_REACTIONS = preload("res://park_reaction_director.gd")

func _initialize() -> void:
	call_deferred("_record_friends_showcase")

func _record_friends_showcase() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	_cleanup_temporary_saves()
	_install_overlay()
	_prepare_showcase_audio()

	var level := _load_level("res://scenes/levels/Level01_Park.tscn")
	await _capture_park_opening(level, 7.0)
	level = _load_level("res://scenes/levels/Level02_Playground.tscn")
	await _capture_playground_collision(level, 7.0)
	level = _load_level("res://scenes/levels/Level03_Lakeside.tscn")
	await _capture_lakeside_chain(level, 7.0)
	level = _load_level("res://scenes/levels/Level04_Festival.tscn")
	await _capture_festival_wrong_bird(level, 9.0)
	level = _load_level("res://scenes/levels/Level05_BotanicalGardens.tscn")
	await _capture_near_exit_failure(level, 6.0)
	level = _load_level("res://scenes/levels/Level05_BotanicalGardens.tscn")
	await _capture_botanical_escape(level, 12.0)
	await _show_friend_card(4.0)

	_release_actions()
	if is_instance_valid(_active_level):
		_active_level.free()
	_active_level = null
	_cleanup_temporary_saves()
	if _failures == 0:
		print("FRIENDS_SHOWCASE_CAPTURE_OK|duration=%.1f|levels=5|features=9" % SHOWCASE_SECONDS)
	quit(_failures)

func _capture_park_opening(level: Node, duration: float) -> void:
	if level == null:
		return
	var player := level.get_node("Player") as CharacterBody3D
	var food := level.get_node("PicnicFood") as Node3D
	var ranger := level.get_node("Ranger") as CharacterBody3D
	var stage := Vector3(0.0, 1.0, 4.5)
	_stage_pickup(player, food, stage, 0.0)
	ranger.global_position = stage + Vector3(3.5, -0.475, -0.3)
	ranger.look_at(player.global_position, Vector3.UP)
	_set_suspicion(ranger, 18.0)
	var pigeons := _pigeons(level)
	for index in mini(pigeons.size(), 6):
		var angle := float(index) / 6.0 * TAU
		pigeons[index].global_position = stage + Vector3(sin(angle), 0.0, cos(angle)) * 1.15

	var total_frames := ceili(duration * FPS)
	for frame in total_frames:
		var elapsed := float(frame) / float(FPS)
		_reset_frame_overlay()
		_show_punch("BLEND IN. STEAL EVERYTHING.", elapsed, 0.0, 1.15)
		if frame == 13:
			player.call("start_player_peck")
		if frame == 17 and is_instance_valid(food):
			food.call("_begin_collection")
		if elapsed >= 1.15 and elapsed < 3.4:
			_set_actions([&"move_forward"])
		elif elapsed >= 3.4:
			_set_actions([&"move_forward", &"move_left", &"run"])
		else:
			_set_actions([])
		if elapsed < 1.5:
			_set_camera(stage + Vector3(2.1, 1.05, 2.35), stage + Vector3(0.0, -0.45, -0.35), 48.0)
		elif elapsed < 4.0:
			_set_camera(player.global_position + Vector3(-2.0, 1.35, 2.25), player.global_position + Vector3.UP * -0.15, 58.0, 0.06)
		else:
			_set_camera(player.global_position + Vector3(2.7, 2.4, 2.8), player.global_position + Vector3.UP * -0.2, 64.0, 0.08)
		_apply_white_impact(frame, 17, 4)
		await process_frame

func _capture_playground_collision(level: Node, duration: float) -> void:
	if level == null:
		return
	var player := level.get_node("Player") as CharacterBody3D
	var rangers := _rangers(level)
	var controller := level.get_node("ParkChaosController") as ParkChaosController
	var stage := Vector3(0.0, 1.0, -5.0)
	_position_player(player, stage + Vector3(0.0, 0.0, -2.2), 0.0)
	if rangers.size() < 2:
		_fail("Playground showcase needs two rangers")
		return
	rangers[0].global_position = stage + Vector3(-0.55, -0.475, 0.0)
	rangers[1].global_position = stage + Vector3(0.55, -0.475, 0.0)
	rangers[0].set("capture_personality", "Hothead")
	rangers[1].set("capture_personality", "Rookie")
	for ranger in rangers:
		_set_suspicion(ranger, 92.0)
		ranger.look_at(player.global_position, Vector3.UP)

	var total_frames := ceili(duration * FPS)
	for frame in total_frames:
		var elapsed := float(frame) / float(FPS)
		_reset_frame_overlay()
		_show_punch("PLAYGROUND PANIC", elapsed, 0.0, 0.95)
		if frame == 24:
			controller.call("_trigger_swing_chaos")
		if frame == 69:
			rangers[0].call("_begin_chase_stumble", rangers[1])
		if elapsed >= 0.9:
			_set_actions([&"move_forward", &"move_right", &"run"])
		if elapsed < 2.15:
			_set_camera(stage + Vector3(4.0, 3.1, 4.0), stage + Vector3.UP * 0.25, 56.0)
		elif elapsed < 4.5:
			_set_camera(stage + Vector3(1.7, 0.95, 2.0), stage + Vector3(0.0, 0.2, 0.0), 50.0, 0.15)
		else:
			_set_camera(player.global_position + Vector3(-2.4, 1.0, 2.7), player.global_position + Vector3.UP * -0.2, 67.0, 0.12)
		_apply_white_impact(frame, 24, 3)
		_apply_white_impact(frame, 69, 5)
		await process_frame

func _capture_lakeside_chain(level: Node, duration: float) -> void:
	if level == null:
		return
	var player := level.get_node("Player") as CharacterBody3D
	var controller := level.get_node("ParkChaosController") as ParkChaosController
	var water := level.get_node_or_null("Lake/WaterZone") as Node3D
	if water == null:
		_fail("Lakeside showcase could not find its water zone")
		return
	var stage := water.global_position + Vector3(0.0, 1.0, 0.0)
	_position_player(player, stage, -0.4)
	var pigeons := _pigeons(level)
	var visitors := _visitors(level)
	var rangers := _rangers(level)
	if pigeons.is_empty() or visitors.is_empty() or rangers.is_empty():
		_fail("Lakeside showcase needs a pigeon, visitor, and ranger")
		return
	var pigeon := pigeons[0]
	var visitor := visitors[0]
	var ranger := rangers[0]
	pigeon.global_position = stage + Vector3(-0.7, 0.0, 0.15)
	visitor.global_position = stage + Vector3(0.65, -0.475, 0.0)
	ranger.global_position = stage + Vector3(2.4, -0.475, 0.35)
	ranger.set("state", 0)
	_set_suspicion(ranger, 8.0)

	var total_frames := ceili(duration * FPS)
	for frame in total_frames:
		var elapsed := float(frame) / float(FPS)
		_reset_frame_overlay()
		_show_punch("ONE SPLASH. EVERYONE NOTICES.", elapsed, 0.0, 1.1)
		if frame == 25:
			controller.call("_on_player_splashed", stage)
		if frame == 78:
			pigeon.call("react_to_park_event", PARK_REACTIONS.EVENT_PLAYER_EXPOSED, stage - Vector3.RIGHT)
		if frame == 82:
			visitor.call("receive_pigeon_flyby", pigeon)
		if frame == 112:
			ranger.call("react_to_panic_pigeon", pigeon)
		if elapsed >= 1.1:
			_set_actions([&"move_forward", &"run"])
		if elapsed < 2.2:
			_set_camera(stage + Vector3(3.5, 2.65, 3.1), stage + Vector3.UP * -0.15, 57.0)
		elif elapsed < 4.6:
			_set_camera(visitor.global_position + Vector3(1.8, 1.05, 2.0), visitor.global_position + Vector3.UP * 0.35, 48.0, 0.1)
		else:
			_set_camera(ranger.global_position + Vector3(-1.7, 1.0, 1.8), ranger.global_position + Vector3.UP * 0.4, 49.0, 0.08)
		_apply_white_impact(frame, 25, 5)
		_apply_white_impact(frame, 82, 3)
		await process_frame

func _capture_festival_wrong_bird(level: Node, duration: float) -> void:
	if level == null:
		return
	var player := level.get_node("Player") as CharacterBody3D
	var ranger := level.get_node("Ranger") as CharacterBody3D
	var controller := level.get_node("ParkChaosController") as ParkChaosController
	var pigeons := _pigeons(level)
	var rangers := _rangers(level)
	var stage := Vector3(1.5, 1.0, 2.0)
	_position_player(player, stage + Vector3(2.2, 0.0, 0.0), -0.7)
	ranger.global_position = stage + Vector3(0.0, -0.475, 0.0)
	ranger.set("capture_personality", "Hothead")
	_set_suspicion(ranger, 96.0)
	if pigeons.is_empty():
		_fail("Festival showcase needs a decoy pigeon")
		return
	for index in pigeons.size():
		pigeons[index].global_position = Vector3(18.0 + index, 1.0, 18.0)
	var decoy := pigeons[0]
	decoy.global_position = ranger.global_position + Vector3(0.3, 0.475, 0.0)
	decoy.call("react_to_park_event", PARK_REACTIONS.EVENT_GRAB_WINDUP, ranger.global_position)
	if rangers.size() > 1:
		rangers[1].global_position = ranger.global_position + Vector3(2.4, 0.0, 0.4)

	var total_frames := ceili(duration * FPS)
	for frame in total_frames:
		var elapsed := float(frame) / float(FPS)
		_reset_frame_overlay()
		_show_punch("THE PERFECT DECOY", elapsed, 0.0, 0.95)
		if frame == 23:
			ranger.set("last_lunge_closest_distance", float(ranger.get("grab_contact_distance")) + 0.1)
			ranger.call("_begin_miss_recovery")
		if frame == 118:
			controller.call("_trigger_food_frenzy", ranger.global_position, true)
		if elapsed >= 1.15 and elapsed < 4.6:
			player.global_position += Vector3.RIGHT * 2.8 / float(FPS)
			player.velocity = Vector3.RIGHT * 2.8
		else:
			player.velocity = Vector3.ZERO
		if elapsed < 4.0:
			_set_camera(ranger.global_position + Vector3(2.15, 1.05, 2.2), ranger.global_position + Vector3.UP * 0.45, 46.0, 0.08)
		elif elapsed < 6.2:
			_set_camera(player.global_position + Vector3(-2.7, 1.25, 2.4), player.global_position + Vector3.UP * -0.15, 61.0)
		else:
			_set_camera(ranger.global_position + Vector3(-3.8, 2.9, 3.7), ranger.global_position + Vector3.UP * 0.2, 62.0, 0.1)
		_apply_white_impact(frame, 23, 5)
		_apply_white_impact(frame, 118, 4)
		await process_frame

func _capture_near_exit_failure(level: Node, duration: float) -> void:
	if level == null:
		return
	var player := level.get_node("Player") as CharacterBody3D
	var ranger := level.get_node("Ranger") as CharacterBody3D
	var escape_zone := level.get_node("EscapeZone") as Node3D
	# Stay inside the 4.5-unit near-exit radius while filming from the open
	# garden interior instead of clipping the camera through the north hedge.
	var stage := escape_zone.global_position + Vector3(2.5, 0.75, 2.5)
	_position_player(player, stage, 0.0)
	ranger.global_position = stage + Vector3(0.35, -0.475, 0.0)
	ranger.set("capture_personality", "Rookie")
	ranger.set("capture_hold_duration", duration + 1.0)
	for visitor in _visitors(level).slice(0, 4):
		visitor.global_position = stage + Vector3(randf_range(-2.0, 2.0), -0.475, randf_range(1.2, 2.5))

	var total_frames := ceili(duration * FPS)
	for frame in total_frames:
		var elapsed := float(frame) / float(FPS)
		_reset_frame_overlay()
		_show_punch("SO CLOSE...", elapsed, 0.0, 0.9)
		if frame == 24:
			ranger.call("_complete_physical_capture")
		if elapsed < 1.0:
			_set_camera(stage + Vector3(2.8, 2.3, 2.6), stage + Vector3.UP * 0.25, 54.0)
		else:
			_set_camera(ranger.global_position + Vector3(2.2, 1.4, 2.3), ranger.global_position + Vector3.UP * 0.45, 47.0, 0.12)
		_apply_white_impact(frame, 24, 6)
		await process_frame

func _capture_botanical_escape(level: Node, duration: float) -> void:
	if level == null:
		return
	var player := level.get_node("Player") as CharacterBody3D
	var controller := level.get_node("ParkChaosController") as ParkChaosController
	var escape_zone := level.get_node("EscapeZone") as Node3D
	var exit_area := escape_zone.get_node("ExitArea") as Area3D
	exit_area.set_deferred("monitoring", false)
	var portal_light := _build_trailer_portal(escape_zone)
	var foods := _collectibles(level)
	if foods.is_empty():
		_fail("Botanical showcase needs collectibles")
		return
	var final_food := foods.back() as Node3D
	for food in foods:
		if food != final_food:
			food.free()
	var start := escape_zone.global_position + Vector3(0.0, 0.75, 6.2)
	_stage_pickup(player, final_food, start, 0.0)
	var rangers := _rangers(level)
	_stage_rangers_around(rangers, start, 2.8)
	for ranger in rangers:
		_set_suspicion(ranger, 94.0)

	var total_frames := ceili(duration * FPS)
	for frame in total_frames:
		var elapsed := float(frame) / float(FPS)
		_reset_frame_overlay()
		_show_punch("FOUR RANGERS. ONE WAY OUT.", elapsed, 0.0, 1.05)
		if frame == 18:
			player.call("start_player_peck")
		if frame == 22 and is_instance_valid(final_food):
			final_food.call("_begin_collection")
			controller.call_deferred("_trigger_sprinkler_finale")
		if frame >= 34:
			var target := escape_zone.global_position + Vector3(0.0, 0.75, 0.0)
			player.global_position = player.global_position.move_toward(target, 4.15 / float(FPS))
			player.velocity = (target - player.global_position).normalized() * 4.15
			_drive_scripted_rangers(rangers, player, 3.25)
			_animate_trailer_portal(escape_zone, portal_light, elapsed)
		if elapsed < 3.2:
			_set_camera(start + Vector3(4.1, 3.4, 4.2), start + Vector3.UP * -0.2, 58.0, 0.08)
		elif elapsed < 8.4:
			_set_camera(player.global_position + Vector3(-2.8, 1.15, 3.0), player.global_position + Vector3.UP * -0.2, 69.0, 0.16)
		else:
			_set_camera(escape_zone.global_position + Vector3(4.1, 2.0, 1.0), escape_zone.global_position + Vector3.UP * 0.7, 54.0, 0.18)
		_apply_white_impact(frame, 22, 5)
		if frame >= total_frames - 13:
			_set_cut(Color.WHITE, clampf(float(frame - (total_frames - 13)) / 12.0, 0.0, 1.0))
		await process_frame

func _show_friend_card(duration: float) -> void:
	_release_actions()
	if is_instance_valid(_active_level):
		_active_level.free()
	_active_level = null
	var card := CARD_SCENE.instantiate() as Control
	card.process_mode = Node.PROCESS_MODE_ALWAYS
	card.pivot_offset = Vector2(640.0, 360.0)
	var tagline := card.get_node("Tagline") as Label
	tagline.text = "PLAYTEST SHOWCASE"
	tagline.modulate.a = 0.0
	_overlay_layer.add_child(card)
	var total_frames := ceili(duration * FPS)
	for frame in total_frames:
		var elapsed := float(frame) / float(FPS)
		var progress := clampf(elapsed / duration, 0.0, 1.0)
		_reset_frame_overlay()
		_set_cut(Color.BLACK, 1.0)
		card.modulate.a = clampf(elapsed / 0.2, 0.0, 1.0)
		card.scale = Vector2.ONE * lerpf(1.12, 1.0, 1.0 - pow(1.0 - progress, 3.0))
		tagline.modulate.a = clampf((elapsed - 0.75) / 0.35, 0.0, 1.0)
		await process_frame

func _prepare_showcase_audio() -> void:
	var sound_manager := root.get_node_or_null("SoundManager")
	if sound_manager != null:
		sound_manager.call("stop_ambient")
	var music_bus := AudioServer.get_bus_index("Music")
	var sfx_bus := AudioServer.get_bus_index("SFX")
	if music_bus >= 0:
		AudioServer.set_bus_volume_db(music_bus, -6.0)
	if sfx_bus >= 0:
		AudioServer.set_bus_volume_db(sfx_bus, 2.0)
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "FriendsShowcaseSoundtrack"
	_music_player.bus = "Music"
	_music_player.stream = SOUNDTRACK_SCRIPT.build(SHOWCASE_SECONDS)
	root.add_child(_music_player)
	_music_player.play()

func _visitors(level: Node) -> Array[Node3D]:
	var result: Array[Node3D] = []
	for node in get_nodes_in_group("visitors"):
		if node is Node3D and level.is_ancestor_of(node):
			result.append(node as Node3D)
	return result
