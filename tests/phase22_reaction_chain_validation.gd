extends SceneTree

# Phase 22 validation: bounded NPC-to-NPC reaction chains.
# Run headless: --headless --path . --script res://tests/phase22_reaction_chain_validation.gd

var _pass_count: int = 0
var _fail_count: int = 0

func _init() -> void:
	_run_all()
	print("PHASE22 RESULTS: %d passed, %d failed" % [_pass_count, _fail_count])
	quit(0 if _fail_count == 0 else 1)

func _run_all() -> void:
	_test_director_has_visitor_startled_event()
	_test_director_has_local_commotion_event()
	_test_director_has_broadcast_chain_method()
	_test_director_chain_depth_guard()
	_test_director_chain_actor_guard()
	_test_visitor_has_receive_pigeon_flyby()
	_test_visitor_has_startle_count()
	_test_visitor_has_visitor_startled_signal()
	_test_visitor_flyby_respects_cooldown()
	_test_visitor_flyby_respects_active_reaction()
	_test_ranger_has_react_to_chain_event()
	_test_ranger_has_react_to_commotion()
	_test_ranger_has_commotion_reaction_count()
	_test_ranger_commotion_requires_patrol_state()
	_test_ranger_commotion_no_suspicion_change()
	_test_ranger_commotion_respects_cooldown()
	_test_pigeon_has_react_to_chain_event()
	_test_pigeon_has_visitor_startle_count()
	_test_pigeon_local_commotion_triggers_watch()
	_test_telemetry_has_visitor_startle_total()
	_test_telemetry_overlay_includes_startle()

func _assert(label: String, condition: bool) -> void:
	if condition:
		print("PHASE22_%s_OK" % label.to_upper().replace(" ", "_"))
		_pass_count += 1
	else:
		print("PHASE22_%s_FAIL" % label.to_upper().replace(" ", "_"))
		_fail_count += 1

# --- ParkReactionDirector ---

func _test_director_has_visitor_startled_event() -> void:
	var d := ParkReactionDirector.new()
	_assert(
		"Director has EVENT_VISITOR_STARTLED constant",
		d.get("EVENT_VISITOR_STARTLED") == &"visitor_startled"
	)

func _test_director_has_local_commotion_event() -> void:
	var d := ParkReactionDirector.new()
	_assert(
		"Director has EVENT_LOCAL_COMMOTION constant",
		d.get("EVENT_LOCAL_COMMOTION") == &"local_commotion"
	)

func _test_director_has_broadcast_chain_method() -> void:
	var d := ParkReactionDirector.new()
	_assert("Director has broadcast_chain method", d.has_method("broadcast_chain"))

func _test_director_chain_depth_guard() -> void:
	var d := ParkReactionDirector.new()
	var max_depth: int = int(d.get("MAX_CHAIN_DEPTH"))
	var result: int = d.call("broadcast_chain", null, &"visitor_startled", Vector3.ZERO, max_depth, 0, null)
	_assert(
		"broadcast_chain returns early when depth >= MAX_CHAIN_DEPTH",
		result == 0
	)

func _test_director_chain_actor_guard() -> void:
	var d := ParkReactionDirector.new()
	var max_actors: int = int(d.get("MAX_CHAIN_ACTORS"))
	var result: int = d.call("broadcast_chain", null, &"visitor_startled", Vector3.ZERO, 0, max_actors, null)
	_assert(
		"broadcast_chain returns early when actors >= MAX_CHAIN_ACTORS",
		result == max_actors
	)

# --- ParkVisitor ---

func _test_visitor_has_receive_pigeon_flyby() -> void:
	var v: Node = load("res://park_visitor.gd").new()
	_assert("ParkVisitor has receive_pigeon_flyby method", v.has_method("receive_pigeon_flyby"))
	v.free()

func _test_visitor_has_startle_count() -> void:
	var v: Node = load("res://park_visitor.gd").new()
	_assert("ParkVisitor has startle_count int", v.get("startle_count") == 0)
	v.free()

func _test_visitor_has_visitor_startled_signal() -> void:
	var v: Node = load("res://park_visitor.gd").new()
	_assert("ParkVisitor has visitor_startled signal", v.has_signal("visitor_startled"))
	v.free()

func _test_visitor_flyby_respects_cooldown() -> void:
	var v: Node = load("res://park_visitor.gd").new()
	v.set("_startle_cooldown", 5.0)
	var result: bool = bool(v.call("receive_pigeon_flyby", null))
	_assert("receive_pigeon_flyby is no-op when startle cooldown active", not result)
	v.free()

func _test_visitor_flyby_respects_active_reaction() -> void:
	var v: Node = load("res://park_visitor.gd").new()
	v.set("_reaction_event", &"some_event")
	var result: bool = bool(v.call("receive_pigeon_flyby", null))
	_assert("receive_pigeon_flyby is no-op when visitor already reacting", not result)
	v.free()

# --- Ranger ---

func _test_ranger_has_react_to_chain_event() -> void:
	var r: Node = load("res://ranger.gd").new()
	_assert("Ranger has react_to_chain_event method", r.has_method("react_to_chain_event"))
	r.free()

func _test_ranger_has_react_to_commotion() -> void:
	var r: Node = load("res://ranger.gd").new()
	_assert("Ranger has react_to_commotion method", r.has_method("react_to_commotion"))
	r.free()

func _test_ranger_has_commotion_reaction_count() -> void:
	var r: Node = load("res://ranger.gd").new()
	_assert("Ranger has commotion_reaction_count int", r.get("commotion_reaction_count") == 0)
	r.free()

func _test_ranger_commotion_requires_patrol_state() -> void:
	var r: Node = load("res://ranger.gd").new()
	r.set("state", 2)  # CHASE
	var count_before: int = int(r.get("commotion_reaction_count"))
	r.call("react_to_commotion", Vector3.ZERO, 0, 0)
	_assert(
		"react_to_commotion is no-op when ranger is not in PATROL state",
		int(r.get("commotion_reaction_count")) == count_before
	)
	r.free()

func _test_ranger_commotion_no_suspicion_change() -> void:
	var r: Node = load("res://ranger.gd").new()
	r.set("suspicion", 42.0)
	r.set("state", 0)  # PATROL
	r.set("grab_phase", 0)  # IDLE
	var suspicion_before: float = float(r.get("suspicion"))
	r.call("react_to_commotion", Vector3.ZERO, 0, 0)
	_assert(
		"react_to_commotion does not modify suspicion",
		is_equal_approx(float(r.get("suspicion")), suspicion_before)
	)
	r.free()

func _test_ranger_commotion_respects_cooldown() -> void:
	var r: Node = load("res://ranger.gd").new()
	r.set("_commotion_react_cooldown", 5.0)
	var count_before: int = int(r.get("commotion_reaction_count"))
	r.call("react_to_commotion", Vector3.ZERO, 0, 0)
	_assert(
		"react_to_commotion is no-op when cooldown active",
		int(r.get("commotion_reaction_count")) == count_before
	)
	r.free()

# --- NpcAnimal (pigeon) ---

func _test_pigeon_has_react_to_chain_event() -> void:
	var file := FileAccess.open("res://npc_animal.gd", FileAccess.READ)
	var found := false
	if file != null:
		found = file.get_as_text().contains("func react_to_chain_event(")
		file.close()
	_assert("NpcAnimal source defines react_to_chain_event", found)

func _test_pigeon_has_visitor_startle_count() -> void:
	var file := FileAccess.open("res://npc_animal.gd", FileAccess.READ)
	var found := false
	if file != null:
		found = file.get_as_text().contains("var visitor_startle_count")
		file.close()
	_assert("NpcAnimal source defines visitor_startle_count", found)

func _test_pigeon_local_commotion_triggers_watch() -> void:
	var file := FileAccess.open("res://npc_animal.gd", FileAccess.READ)
	var found := false
	if file != null:
		var src := file.get_as_text()
		file.close()
		found = src.contains("EVENT_LOCAL_COMMOTION") and src.contains("ReactionMode.WATCH")
	_assert("NpcAnimal routes EVENT_LOCAL_COMMOTION into WATCH mode", found)

# --- SessionTelemetry ---

func _test_telemetry_has_visitor_startle_total() -> void:
	var t := SessionTelemetry.new()
	_assert("SessionTelemetry has visitor_startle_total int", t.get("visitor_startle_total") == 0)
	t.free()

func _test_telemetry_overlay_includes_startle() -> void:
	var file := FileAccess.open("res://session_telemetry.gd", FileAccess.READ)
	var found := false
	if file != null:
		var src := file.get_as_text()
		file.close()
		found = src.contains("Startle")
	_assert("Telemetry overlay source includes Startle label", found)
