class_name RangerPresentation
extends RefCounted

var _host: Node
var _alert_label: Label3D
var _sound_manager: Node
var _alert_tween: Tween
var _action_tween: Tween
var _pulse_time: float = 0.0
var _visuals: Array[Node3D] = []
var _rest_transforms: Dictionary = {}
var _node_refs: Dictionary = {}
var _locomotion_time: float = 0.0
var _locomotion_blend: float = 0.0
var _personality: String = "Steady"
var _action_pose_active: bool = false
var settings_path: String = AccessibilitySettings.DEFAULT_SETTINGS_PATH

func configure(host: Node, alert_label: Label3D, sound_manager: Node) -> void:
	_host = host
	_alert_label = alert_label
	_sound_manager = sound_manager
	if not is_instance_valid(_host) or not is_instance_valid(_alert_label):
		return
	_personality = _host_personality()
	_alert_label.visible = false
	for node_name in [
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
	]:
		var visual := _host.get_node_or_null(node_name) as Node3D
		if visual == null:
			continue
		_node_refs[node_name] = visual
		_visuals.append(visual)
		_rest_transforms[visual] = visual.transform

func state_changed(new_state: int) -> void:
	if new_state in [RangerStateMachine.State.INVESTIGATE, RangerStateMachine.State.CHASE]:
		_sound_manager.call("play_alert")

	if _alert_tween:
		_alert_tween.kill()

	match new_state:
		RangerStateMachine.State.PATROL:
			_alert_label.visible = false
			_alert_label.text = ""
			_pulse_time = 0.0
		RangerStateMachine.State.INVESTIGATE:
			_show_alert("!", Color(1.0, 0.85, 0.1, 1.0), 1.3, 0.10, 0.12)
		RangerStateMachine.State.CHASE:
			_show_alert("!!", Color(1.0, 0.2, 0.2, 1.0), 1.6, 0.08, 0.14)

func update(delta: float, state: int) -> void:
	_update_locomotion(delta, state)
	var reduced_motion := AccessibilitySettings.is_reduced_motion_enabled(settings_path)
	match state:
		RangerStateMachine.State.PATROL:
			_pulse_time = 0.0
		RangerStateMachine.State.INVESTIGATE:
			if reduced_motion:
				_alert_label.modulate = Color(1.0, 0.85, 0.1, 1.0)
				return
			_pulse_time += delta
			var pulse := sin(_pulse_time * TAU * 2.5) * 0.5 + 0.5
			_alert_label.modulate = Color(1.0, 0.85, 0.1, lerp(0.6, 1.0, pulse))
		RangerStateMachine.State.CHASE:
			if reduced_motion:
				_alert_label.modulate = Color(1.0, 0.2, 0.2, 1.0)
				return
			_pulse_time += delta
			var pulse := sin(_pulse_time * TAU * 6.0) * 0.5 + 0.5
			_alert_label.modulate = Color(1.0, 0.2, 0.2, lerp(0.5, 1.0, pulse))

func grab_windup(duration: float, personality: String = "Steady") -> void:
	_begin_action_pose(personality)
	var callout := {
		"Rookie": "UH-OH!",
		"Hothead": "GOT YOU!",
		"Veteran": "HALT!",
	}.get(personality, "GRAB!") as String
	_show_alert(callout, Color(1.0, 0.15, 0.08, 1.0), 1.85, 0.06, 0.10)
	_kill_action_tween()
	_action_tween = _host.create_tween().set_parallel(true)
	match personality:
		"Rookie":
			_action_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			_twp(_action_tween, "RangerLeftArm",  "rotation:x", -1.38, duration)
			_twp(_action_tween, "RangerRightArm", "rotation:x", -1.38, duration)
			_twp(_action_tween, "RangerBody",     "scale:y",     0.70, duration)
			_twp(_action_tween, "RangerHead",     "rotation:x",  0.16, duration)
			_twp(_action_tween, "RangerHatBrim",  "rotation:z", -0.20, duration)
			_twp(_action_tween, "RangerHatCrown", "rotation:z", -0.20, duration)
		"Hothead":
			_action_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			_twp(_action_tween, "RangerLeftArm",  "rotation:x", -1.22, duration * 0.65)
			_twp(_action_tween, "RangerRightArm", "rotation:x", -1.22, duration * 0.65)
			_twp(_action_tween, "RangerBody",     "scale:y",     0.74, duration)
			_twp(_action_tween, "RangerBody",     "rotation:x", -0.11, duration)
			_twp(_action_tween, "RangerHatBrim",  "rotation:z", -0.20, duration)
			_twp(_action_tween, "RangerHatCrown", "rotation:z", -0.20, duration)
		"Veteran":
			_action_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
			_twp(_action_tween, "RangerLeftArm",  "rotation:x", -0.82, duration)
			_twp(_action_tween, "RangerRightArm", "rotation:x", -1.18, duration)
			_twp(_action_tween, "RangerBody",     "scale:y",     0.82, duration)
			_twp(_action_tween, "RangerHead",     "rotation:x",  0.11, duration)
			_twp(_action_tween, "RangerHatBrim",  "rotation:z", -0.08, duration)
			_twp(_action_tween, "RangerHatCrown", "rotation:z", -0.08, duration)
		_:
			_action_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			_twp(_action_tween, "RangerLeftArm",  "rotation:x", -1.1,  duration)
			_twp(_action_tween, "RangerRightArm", "rotation:x", -1.1,  duration)
			_twp(_action_tween, "RangerBody",     "scale:y",     0.78, duration)
			_twp(_action_tween, "RangerHatBrim",  "rotation:z", -0.12, duration)
			_twp(_action_tween, "RangerHatCrown", "rotation:z", -0.12, duration)

func grab_lunge() -> void:
	_begin_action_pose(_personality)
	_kill_action_tween()
	_action_tween = _host.create_tween().set_parallel(true)
	_action_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_twp(_action_tween, "RangerLeftArm",  "rotation:x", -1.6, 0.08)
	_twp(_action_tween, "RangerRightArm", "rotation:x", -1.6, 0.08)
	_twp(_action_tween, "RangerBody",     "rotation:x", -0.32, 0.08)
	_twp(_action_tween, "RangerBody",     "scale:y",     1.12, 0.08)

func grab_missed(
	recovery_duration: float,
	personality: String = "Steady",
	miss_streak: int = 1
) -> String:
	_begin_action_pose(personality)
	var callout := _miss_callout(personality, miss_streak)
	_show_alert(callout, Color(1.0, 0.72, 0.15, 1.0), 1.55, 0.05, 0.10)
	_kill_action_tween()
	_action_tween = _host.create_tween().set_parallel(true)
	_action_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	match personality:
		"Rookie":
			_twp(_action_tween, "RangerBody",     "rotation:x", -1.18, 0.14)
			_twp(_action_tween, "RangerBody",     "position:y", -0.34, 0.14)
			_twp(_action_tween, "RangerLeftArm",  "rotation:z", -1.25, 0.14)
			_twp(_action_tween, "RangerRightArm", "rotation:z",  1.25, 0.14)
			_twp(_action_tween, "RangerHatBrim",  "rotation:z",  0.92, 0.14)
			_twp(_action_tween, "RangerHatCrown", "rotation:z",  0.92, 0.14)
		"Hothead":
			_twp(_action_tween, "RangerBody",     "rotation:z",  0.3,  0.14)
			_twp(_action_tween, "RangerBody",     "scale:y",     0.84, 0.14)
			_twp(_action_tween, "RangerLeftArm",  "rotation:x", -2.15, 0.14)
			_twp(_action_tween, "RangerRightArm", "rotation:x", -2.15, 0.14)
			_twp(_action_tween, "RangerHatBrim",  "rotation:z", -0.42, 0.14)
			_twp(_action_tween, "RangerHatCrown", "rotation:z", -0.42, 0.14)
		"Veteran":
			_twp(_action_tween, "RangerBody",     "rotation:x", -0.42, 0.14)
			_twp(_action_tween, "RangerBody",     "position:y", -0.1,  0.14)
			_twp(_action_tween, "RangerHead",     "rotation:y",  0.58, 0.14)
			_twp(_action_tween, "RangerLeftArm",  "rotation:z", -0.42, 0.14)
			_twp(_action_tween, "RangerRightArm", "rotation:z",  0.42, 0.14)
		_:
			_twp(_action_tween, "RangerBody",     "rotation:x", -0.95, 0.14)
			_twp(_action_tween, "RangerBody",     "position:y", -0.26, 0.14)
			_twp(_action_tween, "RangerLeftArm",  "rotation:z", -0.9,  0.14)
			_twp(_action_tween, "RangerRightArm", "rotation:z",  0.9,  0.14)
			_twp(_action_tween, "RangerHatBrim",  "rotation:z",  0.58, 0.14)
			_twp(_action_tween, "RangerHatCrown", "rotation:z",  0.58, 0.14)
	var reset_delay := maxf(recovery_duration - 0.42, 0.12)
	_host.get_tree().create_timer(reset_delay).timeout.connect(reset_grab_pose.bind(0.28))
	return callout

func teammate_miss_reaction(personality: String = "Steady") -> String:
	var callout := {
		"Rookie": "YOU OK?!",
		"Hothead": "MY TURN!",
		"Veteran": "FOCUS.",
	}.get(personality, "NICE ONE.") as String
	_show_alert(callout, Color(0.55, 0.9, 1.0, 1.0), 1.35, 0.05, 0.1)
	return callout

func wrong_pigeon_grabbed(recovery_duration: float, personality: String = "Steady") -> String:
	_begin_action_pose(personality)
	var callout := {
		"Rookie": "I GOT—OH.",
		"Hothead": "NOT YOU?!",
		"Veteran": "...DECOY.",
	}.get(personality, "WAIT...") as String
	_show_alert(callout, Color(0.45, 1.0, 0.92, 1.0), 1.65, 0.05, 0.11)
	_kill_action_tween()
	_action_tween = _host.create_tween().set_parallel(true)
	_action_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_twp(_action_tween, "RangerBody",     "scale:y",     0.86, 0.13)
	_twp(_action_tween, "RangerHead",     "rotation:x",  0.42, 0.13)
	_twp(_action_tween, "RangerLeftArm",  "rotation:x", -1.72, 0.13)
	_twp(_action_tween, "RangerLeftArm",  "rotation:z", -0.5,  0.13)
	_twp(_action_tween, "RangerRightArm", "rotation:x", -1.72, 0.13)
	_twp(_action_tween, "RangerRightArm", "rotation:z",  0.5,  0.13)
	var reset_delay := maxf(recovery_duration - 0.3, 0.35)
	_host.get_tree().create_timer(reset_delay).timeout.connect(reset_grab_pose.bind(0.24))
	_host.get_tree().create_timer(0.42).timeout.connect(_clear_alert_if_matches.bind(callout))
	return callout

func teammate_wrong_pigeon_reaction(personality: String = "Steady") -> String:
	var callout := {
		"Rookie": "GARY?!",
		"Hothead": "WRONG ONE!",
		"Veteran": "FALSE TARGET.",
	}.get(personality, "NOT THEM!") as String
	_show_alert(callout, Color(0.62, 0.95, 1.0, 1.0), 1.4, 0.05, 0.1)
	_host.get_tree().create_timer(0.62).timeout.connect(_clear_alert_if_matches.bind(callout))
	return callout

func panic_pigeon_near_miss(personality: String = "Steady") -> String:
	_begin_action_pose(personality)
	var callout := {
		"Rookie": "BIRD!",
		"Hothead": "MOVE!",
		"Veteran": "DUCK.",
	}.get(personality, "WHOA!") as String
	_show_alert(callout, Color(0.75, 0.95, 1.0, 1.0), 1.45, 0.04, 0.09)
	_kill_action_tween()
	_action_tween = _host.create_tween().set_parallel(true)
	_action_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_twp(_action_tween, "RangerBody",     "rotation:z",  0.22, 0.1)
	_twp(_action_tween, "RangerHead",     "rotation:x", -0.35, 0.1)
	_twp(_action_tween, "RangerLeftArm",  "rotation:z", -1.15, 0.1)
	_twp(_action_tween, "RangerRightArm", "rotation:z",  1.15, 0.1)
	_host.get_tree().create_timer(0.28).timeout.connect(reset_grab_pose.bind(0.18))
	_host.get_tree().create_timer(0.46).timeout.connect(_clear_alert_if_matches.bind(callout))
	return callout

func _miss_callout(personality: String, miss_streak: int) -> String:
	var callouts: Dictionary = {
		"Rookie":  ["OOPS!", "SORRY!", "NOT AGAIN!"],
		"Hothead": ["NO FAIR!", "HOLD STILL!", "I'M TRYING!"],
		"Veteran": ["MISSED.", "ADJUSTING.", "CALCULATED."],
		"Steady":  ["WHIFF!", "CLOSE!", "OKAY..."],
	}
	var choices := callouts.get(personality, callouts["Steady"]) as Array
	return String(choices[mini(maxi(miss_streak - 1, 0), choices.size() - 1)])

func collision_stumble(recovery_duration: float, personality: String = "Steady", contact_type: StringName = &"obstacle") -> void:
	_begin_action_pose(personality)
	var callout := _collision_callout(personality, contact_type)
	_show_alert(callout, Color(1.0, 0.65, 0.15, 1.0), 1.55, 0.05, 0.09)
	_kill_action_tween()
	_action_tween = _host.create_tween().set_parallel(true)
	_action_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_twp(_action_tween, "RangerBody",     "rotation:x",  0.45, 0.11)
	_twp(_action_tween, "RangerBody",     "position:y", -0.18, 0.11)
	_twp(_action_tween, "RangerLeftArm",  "rotation:x",  1.05, 0.11)
	_twp(_action_tween, "RangerLeftArm",  "rotation:z", -0.65, 0.11)
	_twp(_action_tween, "RangerRightArm", "rotation:x",  1.05, 0.11)
	_twp(_action_tween, "RangerRightArm", "rotation:z",  0.65, 0.11)
	_twp(_action_tween, "RangerHatBrim",  "rotation:x",  0.35, 0.11)
	_twp(_action_tween, "RangerHatCrown", "rotation:x",  0.35, 0.11)
	var reset_delay := maxf(recovery_duration - 0.45, 0.18)
	_host.get_tree().create_timer(reset_delay).timeout.connect(reset_grab_pose.bind(0.28))

func teammate_collision_reaction(personality: String = "Steady") -> String:
	var callout := {
		"Rookie": "WATCH OUT!",
		"Hothead": "WATCH IT!",
		"Veteran": "STAY SHARP.",
	}.get(personality, "HEADS UP!") as String
	_show_alert(callout, Color(0.85, 0.78, 1.0, 1.0), 1.35, 0.05, 0.1)
	_host.get_tree().create_timer(0.6).timeout.connect(_clear_alert_if_matches.bind(callout))
	return callout

func teammate_capture_reaction(personality: String = "Steady") -> String:
	var callout := {
		"Rookie": "FINALLY!!",
		"Hothead": "NICE!",
		"Veteran": "Hm.",
	}.get(personality, "GOOD CATCH.") as String
	_show_alert(callout, Color(0.55, 1.0, 0.65, 1.0), 1.4, 0.05, 0.10)
	_host.get_tree().create_timer(0.65).timeout.connect(_clear_alert_if_matches.bind(callout))
	return callout

func _collision_callout(personality: String, contact_type: StringName) -> String:
	if contact_type == &"ranger":
		return {
			"Rookie": "OW!",
			"Hothead": "WATCH IT!",
			"Veteran": "...FOCUS.",
		}.get(personality, "HEY!") as String
	elif contact_type == &"bumper":
		return {
			"Rookie": "WHOA!",
			"Hothead": "BACK OFF!",
			"Veteran": "HMPH.",
		}.get(personality, "WHOA!") as String
	else:
		return {
			"Rookie": "OOF!",
			"Hothead": "MOVE!",
			"Veteran": "OBSTACLE.",
		}.get(personality, "UGH!") as String

func commotion_lookover(personality: String = "Steady") -> void:
	if not _can_animate():
		return
	_begin_action_pose(personality)
	var callout := {
		"Rookie": "HM?",
		"Hothead": "HEY!",
		"Veteran": "?",
	}.get(personality, "HM?") as String
	_show_alert(callout, Color(0.92, 0.92, 0.92, 1.0), 1.2, 0.06, 0.10)
	_kill_action_tween()
	_action_tween = _host.create_tween().set_parallel(true)
	_action_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_twp(_action_tween, "RangerHead", "rotation:y", 0.28, 0.12)
	_twp(_action_tween, "RangerBody", "rotation:z", 0.06, 0.12)
	_host.get_tree().create_timer(0.5).timeout.connect(reset_grab_pose.bind(0.22))
	_host.get_tree().create_timer(0.65).timeout.connect(_clear_alert_if_matches.bind(callout))

func chaos_reaction(callout: String, duration: float) -> void:
	_begin_action_pose(_personality)
	_show_alert(callout, Color(0.35, 0.9, 1.0, 1.0), 1.45, 0.06, 0.12)
	_kill_action_tween()
	_action_tween = _host.create_tween().set_parallel(true)
	_action_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_twp(_action_tween, "RangerBody", "rotation:z", 0.18, 0.12)
	_twp(_action_tween, "RangerHead", "rotation:y", 0.65, 0.12)
	var reset_delay := maxf(duration - 0.28, 0.18)
	_host.get_tree().create_timer(reset_delay).timeout.connect(reset_grab_pose.bind(0.22))

func player_captured(personality: String = "Steady", near_exit: bool = false) -> void:
	_begin_action_pose(personality)
	var callout := {
		"Rookie": "I GOT ONE!",
		"Hothead": "YES!",
		"Veteran": "SECURED.",
	}.get(personality, "GOTCHA!") as String
	var alert_scale := 2.1 if near_exit else 1.8
	var alert_color := Color(1.0, 0.58, 0.0, 1.0) if near_exit else Color(1.0, 0.85, 0.18, 1.0)
	_show_alert(callout, alert_color, alert_scale, 0.05, 0.12)
	_kill_action_tween()
	match personality:
		"Rookie":
			_action_tween = _host.create_tween().set_parallel(true)
			_action_tween.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
			_twp(_action_tween, "RangerLeftArm",  "rotation:x", -2.3, 0.18)
			_twp(_action_tween, "RangerRightArm", "rotation:x", -2.3, 0.18)
			_twp(_action_tween, "RangerBody",     "scale:y",     0.82, 0.18)
			_twp(_action_tween, "RangerHatBrim",  "rotation:z",  0.38, 0.18)
			_twp(_action_tween, "RangerHatCrown", "rotation:z",  0.38, 0.18)
			_host.get_tree().create_timer(0.32).timeout.connect(func() -> void:
				if not is_instance_valid(_host):
					return
				_kill_action_tween()
				_action_tween = _host.create_tween().set_parallel(true)
				_action_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
				_twp(_action_tween, "RangerLeftArm",  "rotation:x", -1.75, 0.22)
				_twp(_action_tween, "RangerRightArm", "rotation:x", -1.75, 0.22)
				_twp(_action_tween, "RangerHatBrim",  "rotation:z",  0.0,  0.22)
				_twp(_action_tween, "RangerHatCrown", "rotation:z",  0.0,  0.22)
			)
		"Hothead":
			_action_tween = _host.create_tween().set_parallel(true)
			_action_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			_twp(_action_tween, "RangerBody",     "rotation:x", -0.28, 0.12)
			_twp(_action_tween, "RangerBody",     "scale:y",     1.15, 0.12)
			_twp(_action_tween, "RangerBody",     "rotation:z",  0.14, 0.12)
			_twp(_action_tween, "RangerLeftArm",  "rotation:x", -2.05, 0.12)
			_twp(_action_tween, "RangerRightArm", "rotation:x", -2.05, 0.12)
			_host.get_tree().create_timer(0.2).timeout.connect(func() -> void:
				if not is_instance_valid(_host):
					return
				_kill_action_tween()
				_action_tween = _host.create_tween().set_parallel(true)
				_action_tween.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
				_twp(_action_tween, "RangerBody", "rotation:z", 0.0,  0.18)
				_twp(_action_tween, "RangerBody", "scale:y",    1.0,  0.18)
				_twp(_action_tween, "RangerBody", "scale:x",    1.12, 0.18)
				_twp(_action_tween, "RangerBody", "scale:z",    1.12, 0.18)
			)
		"Veteran":
			_action_tween = _host.create_tween().set_parallel(true)
			_action_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			_twp(_action_tween, "RangerRightArm", "rotation:x", -1.75, 0.3)
			_twp(_action_tween, "RangerLeftArm",  "rotation:x", -1.45, 0.3)
			_twp(_action_tween, "RangerBody",     "scale",      Vector3(1.04, 0.97, 1.04), 0.3)
			_twp(_action_tween, "RangerHead",     "rotation:x",  0.1,  0.3)
		_:
			_action_tween = _host.create_tween().set_parallel(true)
			_action_tween.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
			_twp(_action_tween, "RangerLeftArm",  "rotation:x", -1.9,  0.22)
			_twp(_action_tween, "RangerRightArm", "rotation:x", -1.9,  0.22)
			_twp(_action_tween, "RangerBody",     "scale", Vector3(1.12, 0.9, 1.12), 0.22)

func reset_grab_pose(duration: float = 0.2) -> void:
	if not is_instance_valid(_host) or _rest_transforms.is_empty():
		return
	_kill_action_tween()
	_action_tween = _host.create_tween().set_parallel(true)
	_action_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_locomotion_blend = 0.0
	for visual in _visuals:
		if is_instance_valid(visual):
			_action_tween.tween_property(visual, "transform", _rest_transforms[visual], duration)
	_action_tween.finished.connect(_finish_action_pose)

func _kill_action_tween() -> void:
	if _action_tween and _action_tween.is_valid():
		_action_tween.kill()

func _begin_action_pose(personality: String) -> void:
	_personality = personality
	_action_pose_active = true
	_locomotion_blend = 0.0
	_restore_rest_transforms_immediately()

func _finish_action_pose() -> void:
	_action_pose_active = false
	_locomotion_blend = 0.0

func _update_locomotion(delta: float, state: int) -> void:
	if not _can_animate() or _action_pose_active or _action_tween_is_active():
		return
	var profile := _locomotion_profile(state, _personality)
	_locomotion_time = fmod(_locomotion_time + delta * float(profile["cadence"]), TAU)
	_locomotion_blend = move_toward(_locomotion_blend, 1.0, delta * 7.0)
	var step_wave := sin(_locomotion_time)
	var bounce := absf(sin(_locomotion_time))
	var stride := float(profile["stride"])
	var body_bob := float(profile["body_bob"])
	var forward_lean := float(profile["forward_lean"])
	var arm_swing := float(profile["arm_swing"])
	var hat_sway := float(profile["hat_sway"])

	_pose_from_rest("RangerLeftLeg", Vector3(step_wave * stride, 0.0, 0.0), Vector3.ZERO)
	_pose_from_rest("RangerRightLeg", Vector3(-step_wave * stride, 0.0, 0.0), Vector3.ZERO)
	_pose_from_rest("RangerLeftBoot", Vector3(step_wave * stride * 0.65, 0.0, 0.0), Vector3(0.0, 0.0, step_wave * 0.012))
	_pose_from_rest("RangerRightBoot", Vector3(-step_wave * stride * 0.65, 0.0, 0.0), Vector3(0.0, 0.0, -step_wave * 0.012))
	var upper_body_bob := Vector3(0.0, bounce * body_bob, 0.0)
	_pose_from_rest("RangerLeftArm", Vector3(-step_wave * arm_swing, 0.0, 0.0), upper_body_bob)
	_pose_from_rest("RangerRightArm", Vector3(step_wave * arm_swing, 0.0, 0.0), upper_body_bob)
	var body_rotation := Vector3(forward_lean, 0.0, step_wave * float(profile["body_sway"]))
	_pose_from_rest("RangerBody", body_rotation, upper_body_bob)
	_pose_from_rest("RangerBelt", body_rotation, upper_body_bob)
	_pose_from_rest("RangerBadge", body_rotation, upper_body_bob)
	_pose_from_rest("RangerHead", Vector3(-forward_lean * 0.35, step_wave * float(profile["head_scan"]), 0.0), upper_body_bob)
	_pose_from_rest("RangerHatBrim", Vector3(0.0, 0.0, -step_wave * hat_sway), upper_body_bob)
	_pose_from_rest("RangerHatCrown", Vector3(0.0, 0.0, -step_wave * hat_sway), upper_body_bob)

func _locomotion_profile(state: int, personality: String) -> Dictionary:
	var profile: Dictionary
	match state:
		RangerStateMachine.State.INVESTIGATE:
			profile = {
				"cadence": 5.1, "stride": 0.28, "body_bob": 0.014,
				"forward_lean": -0.045, "arm_swing": 0.18,
				"body_sway": 0.018, "head_scan": 0.12, "hat_sway": 0.025,
			}
		RangerStateMachine.State.CHASE:
			profile = {
				"cadence": 8.6, "stride": 0.52, "body_bob": 0.035,
				"forward_lean": -0.14, "arm_swing": 0.46,
				"body_sway": 0.035, "head_scan": 0.02, "hat_sway": 0.055,
			}
		_:
			profile = {
				"cadence": 3.35, "stride": 0.20, "body_bob": 0.009,
				"forward_lean": 0.0, "arm_swing": 0.13,
				"body_sway": 0.012, "head_scan": 0.035, "hat_sway": 0.016,
			}

	match personality:
		"Rookie":
			profile["cadence"] = float(profile["cadence"]) * 1.12
			profile["body_bob"] = float(profile["body_bob"]) * 1.3
			profile["hat_sway"] = float(profile["hat_sway"]) * 1.45
		"Hothead":
			profile["cadence"] = float(profile["cadence"]) * 1.08
			profile["stride"] = float(profile["stride"]) * 1.12
			profile["forward_lean"] = float(profile["forward_lean"]) - 0.035
		"Veteran":
			profile["cadence"] = float(profile["cadence"]) * 0.88
			profile["body_bob"] = float(profile["body_bob"]) * 0.62
			profile["hat_sway"] = float(profile["hat_sway"]) * 0.55
	return profile

func _pose_from_rest(node_name: String, rotation_offset: Vector3, position_offset: Vector3) -> void:
	var visual := _node_refs.get(node_name) as Node3D
	if not is_instance_valid(visual) or not _rest_transforms.has(visual):
		return
	var rest: Transform3D = _rest_transforms[visual]
	var target := rest
	target.basis = Basis.from_euler(rest.basis.get_euler() + rotation_offset).scaled(rest.basis.get_scale())
	target.origin = rest.origin + position_offset
	visual.transform = visual.transform.interpolate_with(target, _locomotion_blend)

func _action_tween_is_active() -> bool:
	return _action_tween != null and _action_tween.is_valid() and _action_tween.is_running()

func _restore_rest_transforms_immediately() -> void:
	for visual in _visuals:
		if is_instance_valid(visual) and _rest_transforms.has(visual):
			visual.transform = _rest_transforms[visual]

func _host_personality() -> String:
	for property in _host.get_property_list():
		if StringName(property.name) == &"capture_personality":
			return String(_host.get("capture_personality"))
	return "Steady"

func _clear_alert_if_matches(callout: String) -> void:
	if not is_instance_valid(_alert_label) or _alert_label.text != callout:
		return
	_alert_label.text = ""
	_alert_label.visible = false

func _show_alert(
	text: String,
	color: Color,
	peak_scale: float,
	grow_duration: float,
	settle_duration: float
) -> void:
	if not _can_animate():
		return
	if _alert_tween and _alert_tween.is_valid():
		_alert_tween.kill()
	_alert_label.text = text
	_alert_label.modulate = color
	_alert_label.scale = Vector3.ZERO
	_alert_label.visible = true
	_alert_tween = _host.create_tween()
	_alert_tween.tween_property(_alert_label, "scale", Vector3.ONE * peak_scale, grow_duration)
	_alert_tween.tween_property(_alert_label, "scale", Vector3.ONE, settle_duration)

func _can_animate() -> bool:
	return (
		is_instance_valid(_host)
		and _host.is_inside_tree()
		and is_instance_valid(_alert_label)
		and _alert_label.is_inside_tree()
	)

# Safely tween a property on a cached visual node — no-op if the node was absent from Ranger.tscn.
func _twp(tw: Tween, node_name: String, prop: String, val: Variant, dur: float) -> void:
	var node: Object = _node_refs.get(node_name)
	if node != null:
		tw.tween_property(node, prop, val, dur)
