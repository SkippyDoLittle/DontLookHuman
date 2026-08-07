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

	# 1. Node presence
	var telemetry := level.get_node_or_null("SessionTelemetry")
	_check(telemetry != null, "SessionTelemetry node exists in the level scene tree")
	if telemetry == null:
		if _failures == 0:
			print("PHASE20_TELEMETRY_VALIDATION_OK")
		quit(_failures)
		return

	_check(telemetry.has_method("get_overlay_lines"), "Telemetry exposes get_overlay_lines for DebugOverlay")
	_check(telemetry.has_method("_on_notable_event"), "Telemetry exposes _on_notable_event for direct testing")

	# 2. Active flag in debug builds (headless validation always runs as debug)
	_check(bool(telemetry.get("_active")), "Telemetry is active in debug builds")
	_check(telemetry.is_in_group("session_telemetry"), "Telemetry registers in session_telemetry group")

	# 3. grab_attempts increments on grab_started signal
	var ranger := level.get_node_or_null("Ranger")
	_check(ranger != null, "Level supplies at least one Ranger")
	if ranger != null and ranger.has_signal("grab_started"):
		var before := int(telemetry.get("grab_attempts"))
		ranger.emit_signal("grab_started")
		await process_frame
		_check(int(telemetry.get("grab_attempts")) == before + 1,
			"grab_attempts increments on grab_started")
	else:
		_check(false, "Ranger has grab_started signal for telemetry to connect")

	# 4. Dead zone accumulates during ACTIVE state
	telemetry.set("_session_active", true)
	telemetry.set("_dead_zone_timer", 0.0)
	var dead_before := int(telemetry.get("dead_zone_count"))
	telemetry.call("_process", 31.0)
	_check(int(telemetry.get("dead_zone_count")) == dead_before + 1,
		"Dead zone counted after 30 s of silence during active session")

	# 5. Notable event resets the dead zone timer
	telemetry.set("_dead_zone_timer", 25.0)
	telemetry.call("_on_notable_event")
	_check(is_equal_approx(float(telemetry.get("_dead_zone_timer")), 0.0),
		"Notable event resets dead zone timer to zero")

	# 6. Dead zone does not accumulate while session is inactive
	telemetry.set("_session_active", false)
	telemetry.set("_dead_zone_timer", 0.0)
	var dead_inactive := int(telemetry.get("dead_zone_count"))
	telemetry.call("_process", 31.0)
	_check(int(telemetry.get("dead_zone_count")) == dead_inactive,
		"Dead zone does not accumulate while session is not active")
	telemetry.set("_session_active", true)

	# 7. Overlap detection: two events in quick succession produce an overlap
	telemetry.set("_recent_events", [])
	var overlap_before := int(telemetry.get("overlap_count"))
	telemetry.call("_on_notable_event")
	telemetry.call("_on_notable_event")
	_check(int(telemetry.get("overlap_count")) == overlap_before + 1,
		"Two clustered events register one overlap increment")

	# 8. A single isolated event does not produce an overlap
	telemetry.set("_recent_events", [])
	var overlap_solo := int(telemetry.get("overlap_count"))
	telemetry.call("_on_notable_event")
	_check(int(telemetry.get("overlap_count")) == overlap_solo,
		"A single isolated event does not falsely increment overlap count")

	# 9. get_overlay_lines returns content in debug build
	var lines: Array = telemetry.call("get_overlay_lines")
	_check(lines.size() > 0, "get_overlay_lines returns non-empty content in debug build")
	_check(lines[0] == "— Telemetry —", "First overlay line is the telemetry section header")

	# 10. Telemetry does not alter ranger grab timing
	if ranger != null:
		var recovery_before := float(ranger.get("grab_recovery_duration"))
		ranger.emit_signal("grab_started")
		await process_frame
		_check(is_equal_approx(float(ranger.get("grab_recovery_duration")), recovery_before),
			"Telemetry does not modify ranger grab_recovery_duration")

	# 11. Telemetry does not alter ranger suspicion
	if ranger != null:
		var suspicion_before := float(ranger.get("suspicion"))
		ranger.emit_signal("grab_started")
		await process_frame
		_check(is_equal_approx(float(ranger.get("suspicion")), suspicion_before),
			"Telemetry does not modify ranger suspicion")

	# 12. DebugOverlay can discover the telemetry node via group
	var found := get_nodes_in_group("session_telemetry")
	_check(found.size() == 1, "Exactly one session_telemetry node is registered in the group")
	_check(found[0] == telemetry, "The registered telemetry node is the SessionTelemetry child")

	paused = false
	level.queue_free()
	await process_frame

	if _failures == 0:
		print("PHASE20_TELEMETRY_VALIDATION_OK")
	quit(_failures)

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("Phase 20 telemetry validation failed: %s" % message)
