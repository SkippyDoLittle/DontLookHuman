extends SceneTree

# P2.2 validation: ranger locomotion is visual-only and action poses take priority.

const REQUIRED_VISUALS: Array[String] = [
	"RangerBody",
	"RangerLeftArm",
	"RangerRightArm",
	"RangerBelt",
	"RangerBadge",
	"RangerLeftLeg",
	"RangerRightLeg",
	"RangerLeftBoot",
	"RangerRightBoot",
	"RangerHead",
	"RangerHatBrim",
	"RangerHatCrown",
]

var _pass_count: int = 0
var _fail_count: int = 0
var _host: Node3D
var _presentation: RangerPresentation
var _sound_stub: Node
var _rest_transforms: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run_all")

func _run_all() -> void:
	_setup_ranger()
	_test_required_direct_child_contract()
	_test_patrol_gait_is_visual_only()
	_test_state_profiles_escalate()
	_test_personality_cadence()
	await _test_action_tween_precedence_and_exact_recovery()
	_cleanup()
	print("P2 RANGER PRESENTATION RESULTS: %d passed, %d failed" % [_pass_count, _fail_count])
	quit(0 if _fail_count == 0 else 1)

func _setup_ranger() -> void:
	_host = (load("res://scenes/actors/Ranger.tscn") as PackedScene).instantiate() as Node3D
	# The scene script expects level siblings, so presentation is configured manually
	# before the host enters the tree.
	_host.set_script(null)
	root.add_child(_host)
	_presentation = RangerPresentation.new()
	_sound_stub = Node.new()
	_presentation.configure(_host, _host.get_node("AlertLabel") as Label3D, _sound_stub)
	for node_name in REQUIRED_VISUALS:
		var visual := _host.get_node(node_name) as Node3D
		_rest_transforms[node_name] = visual.transform

func _test_required_direct_child_contract() -> void:
	var all_present := true
	for node_name in REQUIRED_VISUALS:
		if _host.get_node_or_null(node_name) == null:
			all_present = false
			break
	_assert("Ranger keeps all presentation children at exact paths", all_present)

func _test_patrol_gait_is_visual_only() -> void:
	var root_before := _host.transform
	_presentation.update(0.22, RangerStateMachine.State.PATROL)
	var left_leg := _host.get_node("RangerLeftLeg") as Node3D
	var right_leg := _host.get_node("RangerRightLeg") as Node3D
	_assert("Patrol gait leaves ranger root transform unchanged", _host.transform.is_equal_approx(root_before))
	_assert("Patrol gait moves opposing legs", not left_leg.transform.is_equal_approx(right_leg.transform))

func _test_state_profiles_escalate() -> void:
	var patrol := _presentation.call("_locomotion_profile", RangerStateMachine.State.PATROL, "Steady") as Dictionary
	var investigate := _presentation.call("_locomotion_profile", RangerStateMachine.State.INVESTIGATE, "Steady") as Dictionary
	var chase := _presentation.call("_locomotion_profile", RangerStateMachine.State.CHASE, "Steady") as Dictionary
	_assert("Investigate cadence exceeds patrol cadence", float(investigate["cadence"]) > float(patrol["cadence"]))
	_assert("Chase cadence exceeds investigate cadence", float(chase["cadence"]) > float(investigate["cadence"]))
	_assert("Chase stride exceeds patrol stride", float(chase["stride"]) > float(patrol["stride"]))
	_assert("Investigate head scan exceeds chase scan", float(investigate["head_scan"]) > float(chase["head_scan"]))

func _test_personality_cadence() -> void:
	var rookie := _presentation.call("_locomotion_profile", RangerStateMachine.State.PATROL, "Rookie") as Dictionary
	var steady := _presentation.call("_locomotion_profile", RangerStateMachine.State.PATROL, "Steady") as Dictionary
	var veteran := _presentation.call("_locomotion_profile", RangerStateMachine.State.PATROL, "Veteran") as Dictionary
	var hothead := _presentation.call("_locomotion_profile", RangerStateMachine.State.CHASE, "Hothead") as Dictionary
	var steady_chase := _presentation.call("_locomotion_profile", RangerStateMachine.State.CHASE, "Steady") as Dictionary
	_assert("Rookie patrol cadence is quicker than Steady", float(rookie["cadence"]) > float(steady["cadence"]))
	_assert("Veteran patrol cadence is calmer than Steady", float(veteran["cadence"]) < float(steady["cadence"]))
	_assert("Hothead chase leans farther forward", float(hothead["forward_lean"]) < float(steady_chase["forward_lean"]))
	var personality_host := (load("res://scenes/actors/Ranger.tscn") as PackedScene).instantiate()
	personality_host.set("capture_personality", "Rookie")
	var personality_presentation := RangerPresentation.new()
	personality_presentation.configure(
		personality_host,
		personality_host.get_node("AlertLabel") as Label3D,
		_sound_stub
	)
	_assert("Presentation reads personality from ranger host", String(personality_presentation.get("_personality")) == "Rookie")
	personality_host.free()

func _test_action_tween_precedence_and_exact_recovery() -> void:
	_presentation.update(0.2, RangerStateMachine.State.CHASE)
	_presentation.grab_lunge()
	var body := _host.get_node("RangerBody") as Node3D
	await create_timer(0.04).timeout
	var action_pose := body.transform
	_presentation.update(0.05, RangerStateMachine.State.PATROL)
	_assert("Active grab tween takes precedence over gait", body.transform.is_equal_approx(action_pose))
	await create_timer(0.08).timeout
	var completed_action_pose := body.transform
	_presentation.update(0.12, RangerStateMachine.State.CHASE)
	_assert("Completed action pose stays locked until reset", body.transform.is_equal_approx(completed_action_pose))

	_presentation.reset_grab_pose(0.0)
	await process_frame
	var all_exact := true
	for node_name in REQUIRED_VISUALS:
		var visual := _host.get_node(node_name) as Node3D
		if not visual.transform.is_equal_approx(_rest_transforms[node_name] as Transform3D):
			all_exact = false
			break
	_assert("Reset restores every animated visual to exact rest transform", all_exact)

func _cleanup() -> void:
	if is_instance_valid(_host):
		_host.free()
	if is_instance_valid(_sound_stub):
		_sound_stub.free()

func _assert(label: String, condition: bool) -> void:
	if condition:
		print("P2_RANGER_%s_OK" % label.to_upper().replace(" ", "_"))
		_pass_count += 1
	else:
		push_error("P2_RANGER_%s_FAIL" % label.to_upper().replace(" ", "_"))
		_fail_count += 1
