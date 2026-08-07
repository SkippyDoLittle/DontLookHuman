extends SceneTree

var _failures: int = 0

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var level := (
		load("res://scenes/levels/Level05_BotanicalGardens.tscn") as PackedScene
	).instantiate() as BaseLevel
	root.add_child(level)
	await process_frame
	await process_frame
	paused = false

	var hothead := level.get_node("Ranger2")
	var veteran := level.get_node("Ranger")
	hothead.global_position = Vector3(0.0, 0.525, 0.0)
	veteran.global_position = Vector3(2.5, 0.525, 0.0)
	level.get_node("Ranger3").global_position = Vector3(30.0, 0.525, 30.0)
	level.get_node("Ranger4").global_position = Vector3(-30.0, 0.525, -30.0)
	var base_recovery := float(hothead.get("grab_recovery_duration"))
	var windup_before := float(hothead.get("grab_windup_duration"))
	var lunge_speed_before := float(hothead.get("grab_lunge_speed"))
	var veteran_suspicion_before := float(veteran.get("suspicion"))
	var personality_callouts: Array[String] = []
	var teammate_callouts: Array[String] = []
	hothead.connect(
		"personality_reaction_started",
		func(_kind: StringName, callout: String): personality_callouts.append(callout)
	)
	veteran.connect(
		"teammate_reaction_started",
		func(callout: String): teammate_callouts.append(callout)
	)

	hothead.call("_begin_miss_recovery")
	_check(int(hothead.get("failed_grab_streak")) == 1, "First dodge starts the personality failure streak")
	_check(is_equal_approx(float(hothead.get("_grab_timer")), base_recovery), "First miss keeps the approved recovery timing")
	_check(String(hothead.get("last_personality_callout")) == "NO FAIR!", "Hothead has a distinct first-miss reaction")
	_check(personality_callouts == ["NO FAIR!"], "Personality reaction emits once per actual miss")
	_check(level.has_node("RangerStumbleDust"), "Missed grab kicks up visible stumble dust")
	_check(int(veteran.get("teammate_reaction_count")) == 1, "A nearby teammate notices the miss")
	_check(teammate_callouts == ["FOCUS."], "Veteran responds in character")
	_check(is_equal_approx(float(veteran.get("suspicion")), veteran_suspicion_before), "Social reaction does not increase detection pressure")
	_check(not bool(veteran.call("react_to_teammate_miss", hothead.global_position)), "Teammate response has an anti-spam cooldown")

	hothead.call("_update_grab", float(hothead.get("_grab_timer")) + 0.01)
	hothead.call("_begin_miss_recovery")
	_check(int(hothead.get("failed_grab_streak")) == 2, "Repeated dodge advances the failure story")
	_check(is_equal_approx(float(hothead.get("_grab_timer")), base_recovery + 0.14), "Second Hothead miss adds a small player-favoring recovery window")
	_check(String(hothead.get("last_personality_callout")) == "HOLD STILL!", "Hothead frustration escalates visibly")

	hothead.call("_update_grab", float(hothead.get("_grab_timer")) + 0.01)
	hothead.call("_begin_miss_recovery")
	_check(String(hothead.get("last_personality_callout")) == "I'M TRYING!", "Third Hothead miss reaches its punchline")
	_check(int(hothead.get("missed_grabs")) == 3, "Every real miss is still recorded")
	_check(float(hothead.get("_grab_timer")) > base_recovery, "Repeated misses become more forgiving")

	hothead.set("failed_grab_streak", 12)
	_check(float(hothead.call("_repeated_miss_recovery_bonus")) <= 0.4, "Anti-frustration recovery bonus remains capped")
	_check(is_equal_approx(float(hothead.get("grab_windup_duration")), windup_before), "Personality aftermath does not shorten the dodge telegraph")
	_check(is_equal_approx(float(hothead.get("grab_lunge_speed")), lunge_speed_before), "Personality aftermath does not speed up the lunge")

	paused = false
	level.queue_free()
	await process_frame
	if _failures == 0:
		print("PHASE15_RANGER_PERSONALITY_VALIDATION_OK")
	quit(_failures)

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("Phase 15 ranger-personality validation failed: %s" % message)
