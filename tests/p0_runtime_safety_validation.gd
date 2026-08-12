extends SceneTree

# P0 stabilization validation: reaction methods must be safe without a scene tree.
# Run headless: --headless --path . --script res://tests/p0_runtime_safety_validation.gd

var _pass_count: int = 0
var _fail_count: int = 0

func _init() -> void:
	_test_ranger_commotion_is_safe_outside_tree()
	_test_visitor_capture_reaction_is_safe_outside_tree()
	_test_visitor_flyby_is_safe_outside_tree()
	_test_unconfigured_presentation_reaction_is_safe()
	print("P0 RUNTIME SAFETY RESULTS: %d passed, %d failed" % [_pass_count, _fail_count])
	quit(0 if _fail_count == 0 else 1)

func _assert(label: String, condition: bool) -> void:
	if condition:
		print("P0_RUNTIME_%s_OK" % label.to_upper().replace(" ", "_"))
		_pass_count += 1
	else:
		print("P0_RUNTIME_%s_FAIL" % label.to_upper().replace(" ", "_"))
		_fail_count += 1

func _test_ranger_commotion_is_safe_outside_tree() -> void:
	var ranger := load("res://ranger.gd").new() as Node3D
	ranger.set("suspicion", 42.0)
	ranger.set("state", 0) # PATROL
	ranger.set("grab_phase", 0) # IDLE
	var reacted := bool(ranger.call("react_to_commotion", Vector3(3.0, 0.0, 2.0), 0, 0))
	_assert(
		"Ranger commotion is safe outside tree",
		reacted
		and int(ranger.get("commotion_reaction_count")) == 1
		and is_equal_approx(float(ranger.get("suspicion")), 42.0)
	)
	ranger.free()

func _test_visitor_capture_reaction_is_safe_outside_tree() -> void:
	var visitor := load("res://park_visitor.gd").new() as Node3D
	var director := ParkReactionDirector.new()
	var reacted := bool(visitor.call(
		"react_to_park_event",
		director.get("EVENT_PLAYER_CAUGHT"),
		Vector3.ZERO
	))
	var variant := int(visitor.get("_capture_reaction_variant"))
	_assert(
		"Visitor capture reaction is safe outside tree",
		reacted and variant >= 0 and variant <= 2
	)
	visitor.free()

func _test_visitor_flyby_is_safe_outside_tree() -> void:
	var visitor := load("res://park_visitor.gd").new() as Node3D
	var pigeon := Node3D.new()
	pigeon.position = Vector3(0.5, 0.0, 0.0)
	var reacted := bool(visitor.call("receive_pigeon_flyby", pigeon))
	_assert(
		"Visitor flyby is safe outside tree",
		reacted and int(visitor.get("startle_count")) == 1
	)
	pigeon.free()
	visitor.free()

func _test_unconfigured_presentation_reaction_is_safe() -> void:
	var presentation := RangerPresentation.new()
	presentation.configure(null, null, null)
	presentation.commotion_lookover("Steady")
	_assert("Unconfigured presentation reaction is a safe no-op", true)
