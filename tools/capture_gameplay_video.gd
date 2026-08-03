extends SceneTree

const LEVEL_PATH: String = "res://scenes/levels/Level04_Festival.tscn"
const CLIP_SECONDS: float = 10.0

func _initialize() -> void:
	call_deferred("_record_clip")

func _record_clip() -> void:
	var level := (load(LEVEL_PATH) as PackedScene).instantiate()
	root.add_child(level)
	await process_frame
	await process_frame

	for overlay_name in ["TitleScreen", "TransitionLayer", "PauseMenu", "HowToPlayScreen"]:
		var overlay := level.get_node_or_null(overlay_name)
		if overlay != null:
			overlay.visible = false
	var hud_fade := level.get_node_or_null("HUD/FadeOverlay")
	if hud_fade != null:
		hud_fade.visible = false

	var player := level.get_node("Player") as CharacterBody3D
	var ranger := level.get_node("Ranger") as CharacterBody3D
	player.global_position = ranger.global_position + Vector3(0.0, 0.5, 5.2)
	player.camera_yaw = 0.0
	var nearest_food: Node3D = null
	var nearest_distance: float = INF
	for collectible in get_nodes_in_group("collectibles"):
		if collectible is Node3D:
			var distance := player.global_position.distance_to(collectible.global_position)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest_food = collectible
	var session := level.get_node("GameTimer") as GameSession
	session.call("_set_state", GameSession.SessionState.ACTIVE)
	paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	var elapsed: float = 0.0
	var peck_started: bool = false
	var food_positioned: bool = false
	while elapsed < CLIP_SECONDS:
		var delta := 1.0 / 30.0
		for action in ["move_forward", "move_back", "move_left", "move_right", "run"]:
			Input.action_release(action)
		if elapsed < 2.6:
			Input.action_press("move_forward")
		if elapsed >= 0.8 and elapsed < 2.2:
			Input.action_press("run")
		if elapsed >= 2.6 and elapsed < 3.25:
			Input.action_press("move_forward")
			Input.action_press("move_left")
		if elapsed >= 4.5 and elapsed < 6.4:
			Input.action_press("move_back")
		if elapsed >= 6.4 and elapsed < 8.2:
			Input.action_press("move_forward")
			Input.action_press("move_right")
		if elapsed >= 3.25 and not food_positioned and nearest_food != null:
			nearest_food.global_position = player.global_position + Vector3(0.0, -0.5, -0.6)
			food_positioned = true
		if elapsed >= 3.35 and not peck_started:
			Input.action_press("peck")
			peck_started = true
		elif peck_started:
			Input.action_release("peck")
		await process_frame
		elapsed += delta

	for action in ["move_forward", "move_left", "move_right", "run", "peck"]:
		Input.action_release(action)
	print("PORTFOLIO_GAMEPLAY_CLIP_OK")
	quit()
