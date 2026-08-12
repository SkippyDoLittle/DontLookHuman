extends SceneTree

# P5 opportunity-readability regression checks.
# Run headless: --headless --path . --script res://tests/p5_chaos_window_hud_validation.gd

var _pass_count: int = 0
var _fail_count: int = 0

func _initialize() -> void:
	call_deferred("_run_all")

func _run_all() -> void:
	Engine.time_scale = 1.0
	paused = false
	await _test_runtime_window_lifecycle()
	await _test_legacy_main_runtime_compatibility()
	print("P5_CHAOS_WINDOW_HUD RESULTS: %d passed, %d failed" % [_pass_count, _fail_count])
	quit(0 if _fail_count == 0 else 1)

func _test_runtime_window_lifecycle() -> void:
	var level := (
		load("res://scenes/levels/Level01_Park.tscn") as PackedScene
	).instantiate() as BaseLevel
	root.add_child(level)
	await process_frame
	await process_frame
	paused = false

	var session := level.get_node("GameTimer") as GameSession
	var callout := level.get_node_or_null("HUD/ChaosWindowCallout") as PanelContainer
	var label := level.get_node_or_null("HUD/ChaosWindowCallout/Label") as Label
	_assert("runtime callout is created", is_instance_valid(callout))
	_assert("runtime callout has readable label", is_instance_valid(label))
	_assert("callout begins hidden", is_instance_valid(callout) and not callout.visible)

	session.call("_set_state", GameSession.SessionState.ACTIVE)
	session.call("_connect_new_rangers")
	var ranger := get_first_node_in_group("rangers")
	_assert("test ranger exists", is_instance_valid(ranger))
	if is_instance_valid(ranger):
		ranger.emit_signal("grab_missed")
	_assert("miss starts existing six second window", is_equal_approx(float(session.get("_chaos_window_timer")), 6.0))
	_assert("miss immediately reveals callout", is_instance_valid(callout) and callout.visible)
	_assert("callout explains food reward", is_instance_valid(label) and label.text.contains("STEAL FOOD: +4s"))
	_assert("callout begins at six seconds", is_instance_valid(label) and label.text.contains("6.0s"))

	session.call("_update_chaos_window", 1.25)
	_assert("window ticks without changing duration rules", is_equal_approx(float(session.get("_chaos_window_timer")), 4.75))
	_assert("visible countdown text ticks", is_instance_valid(label) and label.text.contains("4.8s"))
	session.call("_update_chaos_window", 5.0)
	_assert("window expires at zero", is_zero_approx(float(session.get("_chaos_window_timer"))))
	_assert("expired window hides callout", is_instance_valid(callout) and not callout.visible)

	if is_instance_valid(ranger):
		ranger.emit_signal("collision_stumble_started", &"ranger", Vector3.ZERO)
	_assert("collision routes to same six second window", is_equal_approx(float(session.get("_chaos_window_timer")), 6.0))
	_assert("collision reveals same callout", is_instance_valid(callout) and callout.visible)

	session.call("_set_state", GameSession.SessionState.PAUSED)
	_assert("paused state hides opportunity callout", is_instance_valid(callout) and not callout.visible)
	_assert("pause does not consume gameplay opportunity time", is_equal_approx(float(session.get("_chaos_window_timer")), 6.0))
	session.call("_set_state", GameSession.SessionState.ACTIVE)
	_assert("resume restores active opportunity callout", is_instance_valid(callout) and callout.visible)

	session.call("_update_chaos_window", 2.0)
	if is_instance_valid(ranger):
		ranger.emit_signal("grab_missed")
	_assert("later miss refreshes the existing window", is_equal_approx(float(session.get("_chaos_window_timer")), 6.0))
	session.call("_finish", false, "TIME'S UP!")
	_assert("result cleanup clears gameplay window", is_zero_approx(float(session.get("_chaos_window_timer"))))
	_assert("result takes precedence over callout", is_instance_valid(callout) and not callout.visible)
	_assert("result remains visible", level.get_node("HUD/ResultLabel").visible)

	paused = false
	level.queue_free()
	await process_frame

func _test_legacy_main_runtime_compatibility() -> void:
	var legacy_level := (load("res://Main.tscn") as PackedScene).instantiate()
	root.add_child(legacy_level)
	await process_frame
	await process_frame
	var callout := legacy_level.get_node_or_null("HUD/ChaosWindowCallout") as PanelContainer
	var label := legacy_level.get_node_or_null("HUD/ChaosWindowCallout/Label") as Label
	_assert("legacy Main creates runtime callout", is_instance_valid(callout))
	_assert("legacy Main callout has label", is_instance_valid(label))
	paused = false
	legacy_level.queue_free()
	await process_frame

func _assert(label: String, condition: bool) -> void:
	if condition:
		print("P5_CHAOS_WINDOW_HUD_%s_OK" % label.to_upper().replace(" ", "_"))
		_pass_count += 1
	else:
		print("P5_CHAOS_WINDOW_HUD_%s_FAIL" % label.to_upper().replace(" ", "_"))
		_fail_count += 1
