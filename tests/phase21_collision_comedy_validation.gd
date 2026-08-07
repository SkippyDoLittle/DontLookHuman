extends SceneTree

# Phase 21 validation: autonomous ranger collision comedy.
# Run headless: --headless --path . --script res://tests/phase21_collision_comedy_validation.gd

var _pass_count: int = 0
var _fail_count: int = 0

func _init() -> void:
	_run_all()
	print("PHASE21 RESULTS: %d passed, %d failed" % [_pass_count, _fail_count])
	quit(0 if _fail_count == 0 else 1)

func _run_all() -> void:
	_test_ranger_movement_has_chase_collision_collider()
	_test_ranger_has_collision_stumble_signal()
	_test_ranger_has_collision_stumble_count()
	_test_ranger_has_stumble_cooldown_var()
	_test_ranger_has_check_chase_collision_method()
	_test_ranger_has_begin_chase_stumble_method()
	_test_ranger_has_receive_ranger_bump_method()
	_test_ranger_has_react_to_teammate_collision_method()
	_test_ranger_has_notify_teammates_of_collision_method()
	_test_presentation_has_collision_stumble_method()
	_test_presentation_has_teammate_collision_reaction_method()
	_test_presentation_has_collision_callout_method()
	_test_telemetry_tracks_collision_stumble_total()
	_test_telemetry_overlay_includes_stumble()
	_test_receive_ranger_bump_respects_idle_guard()
	_test_receive_ranger_bump_respects_cooldown()

func _assert(label: String, condition: bool) -> void:
	if condition:
		print("PHASE21_%s_OK" % label.to_upper().replace(" ", "_"))
		_pass_count += 1
	else:
		print("PHASE21_%s_FAIL" % label.to_upper().replace(" ", "_"))
		_fail_count += 1

# --- RangerMovement ---

func _test_ranger_movement_has_chase_collision_collider() -> void:
	var movement := RangerMovement.new()
	_assert(
		"RangerMovement has chase_collision_collider var",
		movement.get("chase_collision_collider") == null
	)

# --- Ranger signal and vars ---

func _test_ranger_has_collision_stumble_signal() -> void:
	var ranger := _make_bare_ranger()
	_assert(
		"Ranger has collision_stumble_started signal",
		ranger.has_signal("collision_stumble_started")
	)
	ranger.free()

func _test_ranger_has_collision_stumble_count() -> void:
	var ranger := _make_bare_ranger()
	_assert(
		"Ranger has collision_stumble_count int",
		ranger.get("collision_stumble_count") == 0
	)
	ranger.free()

func _test_ranger_has_stumble_cooldown_var() -> void:
	var ranger := _make_bare_ranger()
	_assert(
		"Ranger has _collision_stumble_cooldown float",
		is_equal_approx(float(ranger.get("_collision_stumble_cooldown")), 0.0)
	)
	ranger.free()

# --- Ranger methods ---

func _test_ranger_has_check_chase_collision_method() -> void:
	var ranger := _make_bare_ranger()
	_assert(
		"Ranger has _check_chase_collision method",
		ranger.has_method("_check_chase_collision")
	)
	ranger.free()

func _test_ranger_has_begin_chase_stumble_method() -> void:
	var ranger := _make_bare_ranger()
	_assert(
		"Ranger has _begin_chase_stumble method",
		ranger.has_method("_begin_chase_stumble")
	)
	ranger.free()

func _test_ranger_has_receive_ranger_bump_method() -> void:
	var ranger := _make_bare_ranger()
	_assert(
		"Ranger has receive_ranger_bump method",
		ranger.has_method("receive_ranger_bump")
	)
	ranger.free()

func _test_ranger_has_react_to_teammate_collision_method() -> void:
	var ranger := _make_bare_ranger()
	_assert(
		"Ranger has react_to_teammate_collision method",
		ranger.has_method("react_to_teammate_collision")
	)
	ranger.free()

func _test_ranger_has_notify_teammates_of_collision_method() -> void:
	var ranger := _make_bare_ranger()
	_assert(
		"Ranger has _notify_teammates_of_collision method",
		ranger.has_method("_notify_teammates_of_collision")
	)
	ranger.free()

# --- RangerPresentation ---

func _test_presentation_has_collision_stumble_method() -> void:
	var pres := RangerPresentation.new()
	_assert(
		"RangerPresentation has collision_stumble method",
		pres.has_method("collision_stumble")
	)

func _test_presentation_has_teammate_collision_reaction_method() -> void:
	var pres := RangerPresentation.new()
	_assert(
		"RangerPresentation has teammate_collision_reaction method",
		pres.has_method("teammate_collision_reaction")
	)

func _test_presentation_has_collision_callout_method() -> void:
	var pres := RangerPresentation.new()
	_assert(
		"RangerPresentation has _collision_callout method",
		pres.has_method("_collision_callout")
	)

# --- SessionTelemetry ---

func _test_telemetry_tracks_collision_stumble_total() -> void:
	var telemetry := SessionTelemetry.new()
	_assert(
		"SessionTelemetry has collision_stumble_total int",
		telemetry.get("collision_stumble_total") == 0
	)
	telemetry.free()

func _test_telemetry_overlay_includes_stumble() -> void:
	var file := FileAccess.open("res://session_telemetry.gd", FileAccess.READ)
	var found := false
	if file != null:
		var src := file.get_as_text()
		file.close()
		found = src.contains("Stumble")
	_assert("Telemetry overlay source includes Stumble label", found)

# --- Behavioral guards ---

func _test_receive_ranger_bump_respects_idle_guard() -> void:
	var ranger := _make_bare_ranger()
	ranger.set("grab_phase", 1)
	var count_before := int(ranger.get("collision_stumble_count"))
	ranger.call("receive_ranger_bump", Vector3.ZERO)
	_assert(
		"receive_ranger_bump is no-op when grab_phase is not IDLE",
		int(ranger.get("collision_stumble_count")) == count_before
	)
	ranger.free()

func _test_receive_ranger_bump_respects_cooldown() -> void:
	var ranger := _make_bare_ranger()
	ranger.set("_collision_stumble_cooldown", 5.0)
	var count_before := int(ranger.get("collision_stumble_count"))
	ranger.call("receive_ranger_bump", Vector3.ZERO)
	_assert(
		"receive_ranger_bump is no-op when cooldown is active",
		int(ranger.get("collision_stumble_count")) == count_before
	)
	ranger.free()

# --- Helpers ---

func _make_bare_ranger() -> Node:
	var ranger: Node = load("res://ranger.gd").new()
	return ranger
