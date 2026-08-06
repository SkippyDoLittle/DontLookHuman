extends SceneTree

var _failures: int = 0

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var level := (
		load("res://scenes/levels/Level01_Park.tscn") as PackedScene
	).instantiate() as BaseLevel
	root.add_child(level)
	await process_frame
	await process_frame
	paused = false
	var session := level.get_node("GameTimer") as GameSession
	session.call("_set_state", GameSession.SessionState.ACTIVE)
	var player := level.get_node("Player") as CharacterBody3D
	var food := level.get_node("PicnicFood") as Node3D
	player.global_position = food.global_position + Vector3.UP * 0.85
	player.set("is_pecking", true)
	player.set("_peck_consumed", false)

	var collected_events: Array[int] = [0]
	var animation_started_events: Array[int] = [0]
	var animation_completed_events: Array[int] = [0]
	food.connect("food_collected", func(_food: Node3D, _origin: Vector3): collected_events[0] += 1)
	food.connect("collection_animation_started", func(): animation_started_events[0] += 1)
	food.connect("collection_animation_completed", func(): animation_completed_events[0] += 1)
	var collectibles_before := get_nodes_in_group("collectibles").size()
	var start_position := food.global_position
	food.call("_process", 0.0)

	_check(bool(food.get("collected")), "A successful peck claims the food")
	_check(collected_events[0] == 1, "Food awards gameplay progress exactly once")
	_check(animation_started_events[0] == 1, "Food starts one visible snatch animation")
	_check(not food.is_queued_for_deletion(), "Collected food remains briefly as presentation")
	_check(get_nodes_in_group("collectibles").size() == collectibles_before - 1, "Objective count drops on the collection frame")
	_check(int(player.get("food_snatch_count")) == 1, "Player performs one successful-snatch reaction")
	_check(player.has_node("PigeonVisual/LeftWing") and player.has_node("PigeonVisual/RightWing"), "Player has readable flapping wings")
	_check(level.has_node("FoodSnatchTrail"), "Flying food leaves a readable golden trail")

	session.call("_refresh_collectible_count")
	_check(level.get_node("HUD/ObjectiveStatus").text == "4 item(s) left to steal!", "HUD updates before the visual flight finishes")

	player.call("_update_food_snatch_reaction", 0.2)
	var body := player.get_node("PigeonVisual/Body") as MeshInstance3D
	var left_wing := player.get_node("PigeonVisual/LeftWing") as MeshInstance3D
	_check(not body.scale.is_equal_approx(Vector3(1.0, 1.0, 1.4)), "Successful snatch visibly squashes the body")
	_check(absf(left_wing.rotation.z - 0.12) > 0.2, "Successful snatch visibly flaps a wing")

	food.call("_process", 0.17)
	_check(food.global_position.distance_to(start_position) > 0.08, "Food leaves its pickup position in a readable arc")
	var position_before_player_move := food.global_position
	player.global_position += Vector3(0.8, 0.0, 0.0)
	food.call("_process", 0.08)
	_check(food.global_position.x > position_before_player_move.x, "Flying food tracks a moving player")
	food.call("_process", 0.2)
	_check(animation_completed_events[0] == 1, "Food completes the snatch at the beak")
	await process_frame
	_check(not is_instance_valid(food), "Presentation node cleans itself up after impact")

	player.call("_update_food_snatch_reaction", 0.3)
	_check(body.scale.is_equal_approx(Vector3(1.0, 1.0, 1.4)), "Player body returns exactly to its rest pose")
	_check(is_equal_approx(left_wing.rotation.z, 0.12), "Player wing returns exactly to rest")

	player.call("add_camera_trauma", 0.17, 0.44)
	player.call("_update_camera_shake", 0.05)
	var camera := player.get_node("SpringArm3D/Camera3D") as Camera3D
	var player_shake_offset := Vector2(camera.h_offset, camera.v_offset)
	(session.get("_transition") as TransitionController).update_shake(0.05)
	_check(
		Vector2(camera.h_offset, camera.v_offset).is_equal_approx(player_shake_offset),
		"Idle transition controller preserves player-owned camera feedback"
	)

	paused = false
	level.queue_free()
	await process_frame
	if _failures == 0:
		print("PHASE14_FOOD_SNATCH_VALIDATION_OK")
	quit(_failures)

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("Phase 14 food-snatch validation failed: %s" % message)
