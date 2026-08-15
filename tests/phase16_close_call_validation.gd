extends SceneTree

var _failures: int = 0

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	Engine.time_scale = 1.0
	var level := (
		load("res://scenes/levels/Level02_Playground.tscn") as PackedScene
	).instantiate() as BaseLevel
	root.add_child(level)
	await process_frame
	await process_frame
	paused = false
	var controller := level.get_node("ParkChaosController") as ParkChaosController
	var accessibility_path := "user://phase16_accessibility_%s.cfg" % Time.get_ticks_usec()
	controller.settings_path = accessibility_path
	AccessibilitySettings.invalidate_cache(accessibility_path)
	var hud := level.get_node("HUD") as RangerHUDController
	var ranger := level.get_node("Ranger")
	var player := level.get_node("Player") as CharacterBody3D
	var base_recovery := float(ranger.get("grab_recovery_duration"))
	var contact_distance := float(ranger.get("grab_contact_distance"))
	var close_margin := float(ranger.get("close_call_margin"))
	var cinematic_events: Array[float] = []
	controller.connect(
		"close_call_cinematic_started",
		func(distance: float, _origin: Vector3): cinematic_events.append(distance)
	)

	ranger.set("last_lunge_closest_distance", contact_distance + 0.2)
	ranger.call("_begin_miss_recovery")
	_check(int(ranger.get("close_call_count")) == 1, "A genuinely narrow miss is recognized")
	_check(int(controller.get("close_call_event_count")) == 1, "Narrow miss starts one cinematic payoff")
	_check(cinematic_events.size() == 1, "Close-call cinematic exposes a deterministic event")
	_check(int(hud.get("close_call_feedback_count")) == 1, "HUD celebrates the narrow dodge once")
	_check(hud.get_node("WarnLabel").text == "FEATHER'S WIDTH!", "HUD distinguishes a narrow dodge from an ordinary miss")
	_check(int(player.get("camera_shake_count")) == 1, "Narrow dodge adds a controlled camera punch")
	_check(level.has_node("CloseCallFeathers"), "Narrow dodge throws a visible feather burst")
	_check(Engine.time_scale < 0.5, "Narrow dodge enters bounded cinematic slow motion")
	_check(is_equal_approx(float(ranger.get("_grab_timer")), base_recovery), "Cinematic does not alter the first approved recovery window")

	await create_timer(0.18, true, false, true).timeout
	_check(is_equal_approx(Engine.time_scale, 1.0), "Unscaled safety timer restores normal speed automatically")

	ranger.set("grab_phase", 0)
	ranger.set("last_lunge_closest_distance", contact_distance + close_margin + 0.4)
	var close_count_before_far_miss := int(ranger.get("close_call_count"))
	ranger.call("_begin_miss_recovery")
	_check(int(ranger.get("close_call_count")) == close_count_before_far_miss, "Comfortable dodge remains an ordinary miss")
	_check(int(controller.get("close_call_event_count")) == 1, "Far miss does not start another cinematic")

	controller.set("_close_call_cooldown", 0.0)
	ranger.set("grab_phase", 0)
	ranger.set("last_lunge_closest_distance", contact_distance + 0.1)
	ranger.call("_begin_miss_recovery")
	_check(Engine.time_scale < 0.5, "Later close call can rearm after its cooldown")
	paused = false
	level.queue_free()
	await process_frame
	AccessibilitySettings.invalidate_cache(accessibility_path)
	if FileAccess.file_exists(accessibility_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(accessibility_path))
	_check(is_equal_approx(Engine.time_scale, 1.0), "Leaving the level mid-effect always restores normal speed")

	if _failures == 0:
		print("PHASE16_CLOSE_CALL_VALIDATION_OK")
	quit(_failures)

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("Phase 16 close-call validation failed: %s" % message)
