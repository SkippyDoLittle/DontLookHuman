extends SceneTree

# Phase 23 validation: personality capture variants and near-exit detection.
# Run headless: --headless --path . --script res://tests/phase23_capture_variants_validation.gd

var _pass_count: int = 0
var _fail_count: int = 0

func _init() -> void:
	_run_all()
	print("PHASE23 RESULTS: %d passed, %d failed" % [_pass_count, _fail_count])
	quit(0 if _fail_count == 0 else 1)

func _run_all() -> void:
	_test_ranger_has_capture_variant_signal()
	_test_ranger_has_capture_near_exit_count()
	_test_ranger_has_react_to_teammate_capture()
	_test_ranger_teammate_capture_blocked_when_caught()
	_test_ranger_teammate_capture_blocked_when_grabbing()
	_test_ranger_teammate_capture_blocked_by_cooldown()
	_test_ranger_has_is_near_exit_method()
	_test_ranger_is_near_exit_false_outside_tree()
	_test_presentation_player_captured_has_near_exit_param()
	_test_presentation_has_teammate_capture_reaction()
	_test_presentation_rookie_capture_uses_premature_overshoot()
	_test_visitor_has_capture_reaction_variant()
	_test_visitor_capture_event_sets_valid_variant()
	_test_visitor_has_captured_reaction_update_method()
	_test_pigeon_capture_uses_freeze_delay()
	_test_telemetry_has_capture_near_exit_total()
	_test_telemetry_overlay_includes_near_exit()
	_test_escape_zone_registers_escape_zones_group()

func _assert(label: String, condition: bool) -> void:
	if condition:
		print("PHASE23_%s_OK" % label.to_upper().replace(" ", "_"))
		_pass_count += 1
	else:
		print("PHASE23_%s_FAIL" % label.to_upper().replace(" ", "_"))
		_fail_count += 1

# --- Ranger ---

func _test_ranger_has_capture_variant_signal() -> void:
	var r: Node = load("res://ranger.gd").new()
	_assert("Ranger has capture_variant_started signal", r.has_signal("capture_variant_started"))
	r.free()

func _test_ranger_has_capture_near_exit_count() -> void:
	var r: Node = load("res://ranger.gd").new()
	_assert("Ranger has capture_near_exit_count int", r.get("capture_near_exit_count") == 0)
	r.free()

func _test_ranger_has_react_to_teammate_capture() -> void:
	var r: Node = load("res://ranger.gd").new()
	_assert("Ranger has react_to_teammate_capture method", r.has_method("react_to_teammate_capture"))
	r.free()

func _test_ranger_teammate_capture_blocked_when_caught() -> void:
	var r: Node = load("res://ranger.gd").new()
	r.set("caught", true)
	var result := bool(r.call("react_to_teammate_capture", Vector3.ZERO))
	_assert("react_to_teammate_capture blocked when caught", not result)
	r.free()

func _test_ranger_teammate_capture_blocked_when_grabbing() -> void:
	var r: Node = load("res://ranger.gd").new()
	r.set("grab_phase", 1)  # WINDUP
	var result := bool(r.call("react_to_teammate_capture", Vector3.ZERO))
	_assert("react_to_teammate_capture blocked when grab_phase not IDLE", not result)
	r.free()

func _test_ranger_teammate_capture_blocked_by_cooldown() -> void:
	var r: Node = load("res://ranger.gd").new()
	r.set("_teammate_reaction_cooldown", 5.0)
	var result := bool(r.call("react_to_teammate_capture", Vector3.ZERO))
	_assert("react_to_teammate_capture blocked when cooldown active", not result)
	r.free()

func _test_ranger_has_is_near_exit_method() -> void:
	var r: Node = load("res://ranger.gd").new()
	_assert("Ranger has _is_near_exit method", r.has_method("_is_near_exit"))
	r.free()

func _test_ranger_is_near_exit_false_outside_tree() -> void:
	var r: Node = load("res://ranger.gd").new()
	var result := bool(r.call("_is_near_exit"))
	_assert("_is_near_exit returns false when not in scene tree", not result)
	r.free()

# --- RangerPresentation (source checks) ---

func _test_presentation_player_captured_has_near_exit_param() -> void:
	var file := FileAccess.open("res://ranger_presentation.gd", FileAccess.READ)
	var found := false
	if file != null:
		var src := file.get_as_text()
		file.close()
		found = src.contains("func player_captured(") and src.contains("near_exit")
	_assert("RangerPresentation player_captured accepts near_exit parameter", found)

func _test_presentation_has_teammate_capture_reaction() -> void:
	var file := FileAccess.open("res://ranger_presentation.gd", FileAccess.READ)
	var found := false
	if file != null:
		found = file.get_as_text().contains("func teammate_capture_reaction(")
		file.close()
	_assert("RangerPresentation defines teammate_capture_reaction", found)

func _test_presentation_rookie_capture_uses_premature_overshoot() -> void:
	var file := FileAccess.open("res://ranger_presentation.gd", FileAccess.READ)
	var found := false
	if file != null:
		var src := file.get_as_text()
		file.close()
		# -2.3 is the Rookie arm overshoot angle unique to the premature celebration phase
		found = src.contains("-2.3") and src.contains("\"Rookie\":")
	_assert("RangerPresentation Rookie capture uses premature overshoot angle", found)

# --- ParkVisitor ---

func _test_visitor_has_capture_reaction_variant() -> void:
	var v: Node = load("res://park_visitor.gd").new()
	_assert("ParkVisitor has _capture_reaction_variant int", v.get("_capture_reaction_variant") == 0)
	v.free()

func _test_visitor_capture_event_sets_valid_variant() -> void:
	var v: Node = load("res://park_visitor.gd").new()
	var d := ParkReactionDirector.new()
	v.call("react_to_park_event", d.get("EVENT_PLAYER_CAUGHT"), Vector3.ZERO)
	var variant := int(v.get("_capture_reaction_variant"))
	_assert(
		"Visitor capture event sets valid reaction variant (0-2)",
		variant >= 0 and variant <= 2
	)
	v.free()

func _test_visitor_has_captured_reaction_update_method() -> void:
	var file := FileAccess.open("res://park_visitor.gd", FileAccess.READ)
	var found := false
	if file != null:
		found = file.get_as_text().contains("func _update_captured_reaction(")
		file.close()
	_assert("ParkVisitor defines _update_captured_reaction method", found)

# --- NpcAnimal (pigeon) ---

func _test_pigeon_capture_uses_freeze_delay() -> void:
	var file := FileAccess.open("res://npc_animal.gd", FileAccess.READ)
	var found := false
	if file != null:
		var src := file.get_as_text()
		file.close()
		found = (
			src.contains("EVENT_PLAYER_CAUGHT")
			and src.contains("maxf(_reaction_delay, 0.45)")
		)
	_assert("NpcAnimal enforces minimum freeze delay for EVENT_PLAYER_CAUGHT", found)

# --- SessionTelemetry ---

func _test_telemetry_has_capture_near_exit_total() -> void:
	var t := SessionTelemetry.new()
	_assert("SessionTelemetry has capture_near_exit_total int", t.get("capture_near_exit_total") == 0)
	t.free()

func _test_telemetry_overlay_includes_near_exit() -> void:
	var file := FileAccess.open("res://session_telemetry.gd", FileAccess.READ)
	var found := false
	if file != null:
		var src := file.get_as_text()
		file.close()
		found = src.contains("Near-exit")
	_assert("Telemetry source includes Near-exit label", found)

# --- EscapeZone ---

func _test_escape_zone_registers_escape_zones_group() -> void:
	var file := FileAccess.open("res://escape_zone.gd", FileAccess.READ)
	var found := false
	if file != null:
		var src := file.get_as_text()
		file.close()
		found = src.contains("escape_zones")
	_assert("EscapeZone registers itself in escape_zones group", found)
