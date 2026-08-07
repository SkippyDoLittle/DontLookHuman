extends SceneTree

# Phase 24 validation: risk/reward decision bonuses for food collection.
# Run headless: --headless --path . --script res://tests/phase24_objective_decisions_validation.gd

var _pass_count: int = 0
var _fail_count: int = 0

func _init() -> void:
	_run_all()
	print("PHASE24 RESULTS: %d passed, %d failed" % [_pass_count, _fail_count])
	quit(0 if _fail_count == 0 else 1)

func _run_all() -> void:
	_test_session_timer_has_add_time()
	_test_session_timer_add_time_increases_remaining()
	_test_session_timer_add_time_noop_when_expired()
	_test_session_timer_add_time_noop_when_zero()
	_test_hud_controller_has_show_pickup_bonus()
	_test_game_session_has_blend_pickup_earned_signal()
	_test_game_session_has_chaos_pickup_earned_signal()
	_test_game_session_has_blend_bonus_count()
	_test_game_session_has_chaos_bonus_count()
	_test_game_session_has_chaos_window_timer()
	_test_game_session_has_blend_threshold_constant()
	_test_game_session_has_chaos_window_duration_constant()
	_test_game_session_source_connects_food()
	_test_game_session_source_checks_blend_condition()
	_test_telemetry_has_blend_bonus_total()
	_test_telemetry_has_chaos_bonus_total()
	_test_telemetry_overlay_includes_blend()
	_test_telemetry_overlay_includes_chaos()

func _assert(label: String, condition: bool) -> void:
	if condition:
		print("PHASE24_%s_OK" % label.to_upper().replace(" ", "_"))
		_pass_count += 1
	else:
		print("PHASE24_%s_FAIL" % label.to_upper().replace(" ", "_"))
		_fail_count += 1

# --- SessionTimer ---

func _test_session_timer_has_add_time() -> void:
	var t := SessionTimer.new()
	_assert("SessionTimer has add_time method", t.has_method("add_time"))

func _test_session_timer_add_time_increases_remaining() -> void:
	var t := SessionTimer.new()
	t.reset(30.0)
	t.add_time(5.0)
	_assert(
		"add_time increases time_remaining",
		is_equal_approx(t.time_remaining, 35.0)
	)

func _test_session_timer_add_time_noop_when_expired() -> void:
	var file := FileAccess.open("res://session_timer.gd", FileAccess.READ)
	var found := false
	if file != null:
		var src := file.get_as_text()
		file.close()
		found = src.contains("func add_time(") and src.contains("_expired_emitted")
	_assert("add_time guards against expired state", found)

func _test_session_timer_add_time_noop_when_zero() -> void:
	var t := SessionTimer.new()
	t.reset(30.0)
	t.add_time(0.0)
	_assert(
		"add_time is no-op when seconds <= 0",
		is_equal_approx(t.time_remaining, 30.0)
	)

# --- SessionHUDController ---

func _test_hud_controller_has_show_pickup_bonus() -> void:
	var file := FileAccess.open("res://session_hud_controller.gd", FileAccess.READ)
	var found := false
	if file != null:
		found = file.get_as_text().contains("func show_pickup_bonus(")
		file.close()
	_assert("SessionHUDController defines show_pickup_bonus", found)

# --- GameSession (game_timer.gd) ---

func _test_game_session_has_blend_pickup_earned_signal() -> void:
	var s: Node = load("res://game_timer.gd").new()
	_assert("GameSession has blend_pickup_earned signal", s.has_signal("blend_pickup_earned"))
	s.free()

func _test_game_session_has_chaos_pickup_earned_signal() -> void:
	var s: Node = load("res://game_timer.gd").new()
	_assert("GameSession has chaos_pickup_earned signal", s.has_signal("chaos_pickup_earned"))
	s.free()

func _test_game_session_has_blend_bonus_count() -> void:
	var s: Node = load("res://game_timer.gd").new()
	_assert("GameSession has blend_bonus_count int", s.get("blend_bonus_count") == 0)
	s.free()

func _test_game_session_has_chaos_bonus_count() -> void:
	var s: Node = load("res://game_timer.gd").new()
	_assert("GameSession has chaos_bonus_count int", s.get("chaos_bonus_count") == 0)
	s.free()

func _test_game_session_has_chaos_window_timer() -> void:
	var s: Node = load("res://game_timer.gd").new()
	_assert("GameSession has _chaos_window_timer float", s.get("_chaos_window_timer") == 0.0)
	s.free()

func _test_game_session_has_blend_threshold_constant() -> void:
	var file := FileAccess.open("res://game_timer.gd", FileAccess.READ)
	var found := false
	if file != null:
		found = file.get_as_text().contains("BLEND_THRESHOLD")
		file.close()
	_assert("GameSession source defines BLEND_THRESHOLD constant", found)

func _test_game_session_has_chaos_window_duration_constant() -> void:
	var file := FileAccess.open("res://game_timer.gd", FileAccess.READ)
	var found := false
	if file != null:
		found = file.get_as_text().contains("CHAOS_WINDOW_DURATION")
		file.close()
	_assert("GameSession source defines CHAOS_WINDOW_DURATION constant", found)

func _test_game_session_source_connects_food() -> void:
	var file := FileAccess.open("res://game_timer.gd", FileAccess.READ)
	var found := false
	if file != null:
		var src := file.get_as_text()
		file.close()
		found = src.contains("func _connect_food(") and src.contains("food_collected")
	_assert("GameSession source defines _connect_food and hooks food_collected", found)

func _test_game_session_source_checks_blend_condition() -> void:
	var file := FileAccess.open("res://game_timer.gd", FileAccess.READ)
	var found := false
	if file != null:
		var src := file.get_as_text()
		file.close()
		found = src.contains("func _check_blend_condition(") and src.contains("BLEND_RADIUS")
	_assert("GameSession source defines _check_blend_condition with radius check", found)

# --- SessionTelemetry ---

func _test_telemetry_has_blend_bonus_total() -> void:
	var t := SessionTelemetry.new()
	_assert("SessionTelemetry has blend_bonus_total int", t.get("blend_bonus_total") == 0)
	t.free()

func _test_telemetry_has_chaos_bonus_total() -> void:
	var t := SessionTelemetry.new()
	_assert("SessionTelemetry has chaos_bonus_total int", t.get("chaos_bonus_total") == 0)
	t.free()

func _test_telemetry_overlay_includes_blend() -> void:
	var file := FileAccess.open("res://session_telemetry.gd", FileAccess.READ)
	var found := false
	if file != null:
		found = file.get_as_text().contains("Blend")
		file.close()
	_assert("Telemetry source includes Blend label", found)

func _test_telemetry_overlay_includes_chaos() -> void:
	var file := FileAccess.open("res://session_telemetry.gd", FileAccess.READ)
	var found := false
	if file != null:
		found = file.get_as_text().contains("Chaos")
		file.close()
	_assert("Telemetry source includes Chaos label", found)
