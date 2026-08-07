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

func configure(host: Node, alert_label: Label3D, sound_manager: Node) -> void:
	_host = host
	_alert_label = alert_label
	_sound_manager = sound_manager
	_alert_label.visible = false
	for node_name in [
		"RangerBody",
		"RangerLeftArm",
		"RangerRightArm",
		"RangerHead",
		"RangerHatBrim",
		"RangerHatCrown",
	]:
		var visual := _host.get_node_or_null(node_name) as Node3D
		if visual == null:
			continue
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
	match state:
		RangerStateMachine.State.PATROL:
			_pulse_time = 0.0
		RangerStateMachine.State.INVESTIGATE:
			_pulse_time += delta
			var pulse := sin(_pulse_time * TAU * 2.5) * 0.5 + 0.5
			_alert_label.modulate = Color(1.0, 0.85, 0.1, lerp(0.6, 1.0, pulse))
		RangerStateMachine.State.CHASE:
			_pulse_time += delta
			var pulse := sin(_pulse_time * TAU * 6.0) * 0.5 + 0.5
			_alert_label.modulate = Color(1.0, 0.2, 0.2, lerp(0.5, 1.0, pulse))

func grab_windup(duration: float, personality: String = "Steady") -> void:
	var callout := {
		"Rookie": "UH-OH!",
		"Hothead": "GOT YOU!",
		"Veteran": "HALT!",
	}.get(personality, "GRAB!") as String
	_show_alert(callout, Color(1.0, 0.15, 0.08, 1.0), 1.85, 0.06, 0.10)
	_kill_action_tween()
	_action_tween = _host.create_tween().set_parallel(true)
	_action_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_action_tween.tween_property(_host.get_node("RangerLeftArm"), "rotation:x", -1.1, duration)
	_action_tween.tween_property(_host.get_node("RangerRightArm"), "rotation:x", -1.1, duration)
	_action_tween.tween_property(_host.get_node("RangerBody"), "scale:y", 0.78, duration)
	_action_tween.tween_property(_host.get_node("RangerHatBrim"), "rotation:z", -0.12, duration)
	_action_tween.tween_property(_host.get_node("RangerHatCrown"), "rotation:z", -0.12, duration)

func grab_lunge() -> void:
	_kill_action_tween()
	_action_tween = _host.create_tween().set_parallel(true)
	_action_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_action_tween.tween_property(_host.get_node("RangerLeftArm"), "rotation:x", -1.6, 0.08)
	_action_tween.tween_property(_host.get_node("RangerRightArm"), "rotation:x", -1.6, 0.08)
	_action_tween.tween_property(_host.get_node("RangerBody"), "rotation:x", -0.32, 0.08)
	_action_tween.tween_property(_host.get_node("RangerBody"), "scale:y", 1.12, 0.08)

func grab_missed(
	recovery_duration: float,
	personality: String = "Steady",
	miss_streak: int = 1
) -> String:
	var callout := _miss_callout(personality, miss_streak)
	_show_alert(callout, Color(1.0, 0.72, 0.15, 1.0), 1.55, 0.05, 0.10)
	_kill_action_tween()
	_action_tween = _host.create_tween().set_parallel(true)
	_action_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	match personality:
		"Rookie":
			_action_tween.tween_property(_host.get_node("RangerBody"), "rotation:x", -1.18, 0.14)
			_action_tween.tween_property(_host.get_node("RangerBody"), "position:y", -0.34, 0.14)
			_action_tween.tween_property(_host.get_node("RangerLeftArm"), "rotation:z", -1.25, 0.14)
			_action_tween.tween_property(_host.get_node("RangerRightArm"), "rotation:z", 1.25, 0.14)
			_action_tween.tween_property(_host.get_node("RangerHatBrim"), "rotation:z", 0.92, 0.14)
			_action_tween.tween_property(_host.get_node("RangerHatCrown"), "rotation:z", 0.92, 0.14)
		"Hothead":
			_action_tween.tween_property(_host.get_node("RangerBody"), "rotation:z", 0.3, 0.14)
			_action_tween.tween_property(_host.get_node("RangerBody"), "scale:y", 0.84, 0.14)
			_action_tween.tween_property(_host.get_node("RangerLeftArm"), "rotation:x", -2.15, 0.14)
			_action_tween.tween_property(_host.get_node("RangerRightArm"), "rotation:x", -2.15, 0.14)
			_action_tween.tween_property(_host.get_node("RangerHatBrim"), "rotation:z", -0.42, 0.14)
			_action_tween.tween_property(_host.get_node("RangerHatCrown"), "rotation:z", -0.42, 0.14)
		"Veteran":
			_action_tween.tween_property(_host.get_node("RangerBody"), "rotation:x", -0.42, 0.14)
			_action_tween.tween_property(_host.get_node("RangerBody"), "position:y", -0.1, 0.14)
			_action_tween.tween_property(_host.get_node("RangerHead"), "rotation:y", 0.58, 0.14)
			_action_tween.tween_property(_host.get_node("RangerLeftArm"), "rotation:z", -0.42, 0.14)
			_action_tween.tween_property(_host.get_node("RangerRightArm"), "rotation:z", 0.42, 0.14)
		_:
			_action_tween.tween_property(_host.get_node("RangerBody"), "rotation:x", -0.95, 0.14)
			_action_tween.tween_property(_host.get_node("RangerBody"), "position:y", -0.26, 0.14)
			_action_tween.tween_property(_host.get_node("RangerLeftArm"), "rotation:z", -0.9, 0.14)
			_action_tween.tween_property(_host.get_node("RangerRightArm"), "rotation:z", 0.9, 0.14)
			_action_tween.tween_property(_host.get_node("RangerHatBrim"), "rotation:z", 0.58, 0.14)
			_action_tween.tween_property(_host.get_node("RangerHatCrown"), "rotation:z", 0.58, 0.14)
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
	var callout := {
		"Rookie": "I GOT—OH.",
		"Hothead": "NOT YOU?!",
		"Veteran": "...DECOY.",
	}.get(personality, "WAIT...") as String
	_show_alert(callout, Color(0.45, 1.0, 0.92, 1.0), 1.65, 0.05, 0.11)
	_kill_action_tween()
	_action_tween = _host.create_tween().set_parallel(true)
	_action_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_action_tween.tween_property(_host.get_node("RangerBody"), "scale:y", 0.86, 0.13)
	_action_tween.tween_property(_host.get_node("RangerHead"), "rotation:x", 0.42, 0.13)
	_action_tween.tween_property(_host.get_node("RangerLeftArm"), "rotation:x", -1.72, 0.13)
	_action_tween.tween_property(_host.get_node("RangerLeftArm"), "rotation:z", -0.5, 0.13)
	_action_tween.tween_property(_host.get_node("RangerRightArm"), "rotation:x", -1.72, 0.13)
	_action_tween.tween_property(_host.get_node("RangerRightArm"), "rotation:z", 0.5, 0.13)
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
	var callout := {
		"Rookie": "BIRD!",
		"Hothead": "MOVE!",
		"Veteran": "DUCK.",
	}.get(personality, "WHOA!") as String
	_show_alert(callout, Color(0.75, 0.95, 1.0, 1.0), 1.45, 0.04, 0.09)
	_kill_action_tween()
	_action_tween = _host.create_tween().set_parallel(true)
	_action_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_action_tween.tween_property(_host.get_node("RangerBody"), "rotation:z", 0.22, 0.1)
	_action_tween.tween_property(_host.get_node("RangerHead"), "rotation:x", -0.35, 0.1)
	_action_tween.tween_property(_host.get_node("RangerLeftArm"), "rotation:z", -1.15, 0.1)
	_action_tween.tween_property(_host.get_node("RangerRightArm"), "rotation:z", 1.15, 0.1)
	_host.get_tree().create_timer(0.28).timeout.connect(reset_grab_pose.bind(0.18))
	_host.get_tree().create_timer(0.46).timeout.connect(_clear_alert_if_matches.bind(callout))
	return callout

func _miss_callout(personality: String, miss_streak: int) -> String:
	var callouts: Dictionary = {
		"Rookie": ["OOPS!", "SORRY!", "NOT AGAIN!"],
		"Hothead": ["NO FAIR!", "HOLD STILL!", "I'M TRYING!"],
		"Veteran": ["MISSED.", "ADJUSTING.", "CALCULATED."],
		"Steady": ["WHIFF!", "CLOSE!", "OKAY..."],
	}
	var choices := callouts.get(personality, callouts["Steady"]) as Array
	return String(choices[mini(maxi(miss_streak - 1, 0), choices.size() - 1)])

func collision_stumble(recovery_duration: float, personality: String = "Steady", contact_type: StringName = &"obstacle") -> void:
	var callout := _collision_callout(personality, contact_type)
	_show_alert(callout, Color(1.0, 0.65, 0.15, 1.0), 1.55, 0.05, 0.09)
	_kill_action_tween()
	_action_tween = _host.create_tween().set_parallel(true)
	_action_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_action_tween.tween_property(_host.get_node("RangerBody"), "rotation:x", 0.45, 0.11)
	_action_tween.tween_property(_host.get_node("RangerBody"), "position:y", -0.18, 0.11)
	_action_tween.tween_property(_host.get_node("RangerLeftArm"), "rotation:x", 1.05, 0.11)
	_action_tween.tween_property(_host.get_node("RangerLeftArm"), "rotation:z", -0.65, 0.11)
	_action_tween.tween_property(_host.get_node("RangerRightArm"), "rotation:x", 1.05, 0.11)
	_action_tween.tween_property(_host.get_node("RangerRightArm"), "rotation:z", 0.65, 0.11)
	_action_tween.tween_property(_host.get_node("RangerHatBrim"), "rotation:x", 0.35, 0.11)
	_action_tween.tween_property(_host.get_node("RangerHatCrown"), "rotation:x", 0.35, 0.11)
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
	var callout := {
		"Rookie": "HM?",
		"Hothead": "HEY!",
		"Veteran": "?",
	}.get(personality, "HM?") as String
	_show_alert(callout, Color(0.92, 0.92, 0.92, 1.0), 1.2, 0.06, 0.10)
	_kill_action_tween()
	_action_tween = _host.create_tween().set_parallel(true)
	_action_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_action_tween.tween_property(_host.get_node("RangerHead"), "rotation:y", 0.28, 0.12)
	_action_tween.tween_property(_host.get_node("RangerBody"), "rotation:z", 0.06, 0.12)
	_host.get_tree().create_timer(0.5).timeout.connect(reset_grab_pose.bind(0.22))
	_host.get_tree().create_timer(0.65).timeout.connect(_clear_alert_if_matches.bind(callout))

func chaos_reaction(callout: String, duration: float) -> void:
	_show_alert(callout, Color(0.35, 0.9, 1.0, 1.0), 1.45, 0.06, 0.12)
	_kill_action_tween()
	_action_tween = _host.create_tween().set_parallel(true)
	_action_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_action_tween.tween_property(_host.get_node("RangerBody"), "rotation:z", 0.18, 0.12)
	_action_tween.tween_property(_host.get_node("RangerHead"), "rotation:y", 0.65, 0.12)
	var reset_delay := maxf(duration - 0.28, 0.18)
	_host.get_tree().create_timer(reset_delay).timeout.connect(reset_grab_pose.bind(0.22))

func player_captured(personality: String = "Steady", near_exit: bool = false) -> void:
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
			# Premature celebration: arms overshoot high, then correct to hold position
			_action_tween = _host.create_tween().set_parallel(true)
			_action_tween.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
			_action_tween.tween_property(_host.get_node("RangerLeftArm"), "rotation:x", -2.3, 0.18)
			_action_tween.tween_property(_host.get_node("RangerRightArm"), "rotation:x", -2.3, 0.18)
			_action_tween.tween_property(_host.get_node("RangerBody"), "scale:y", 0.82, 0.18)
			_action_tween.tween_property(_host.get_node("RangerHatBrim"), "rotation:z", 0.38, 0.18)
			_action_tween.tween_property(_host.get_node("RangerHatCrown"), "rotation:z", 0.38, 0.18)
			_host.get_tree().create_timer(0.32).timeout.connect(func() -> void:
				if not is_instance_valid(_host):
					return
				_kill_action_tween()
				_action_tween = _host.create_tween().set_parallel(true)
				_action_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
				_action_tween.tween_property(_host.get_node("RangerLeftArm"), "rotation:x", -1.75, 0.22)
				_action_tween.tween_property(_host.get_node("RangerRightArm"), "rotation:x", -1.75, 0.22)
				_action_tween.tween_property(_host.get_node("RangerHatBrim"), "rotation:z", 0.0, 0.22)
				_action_tween.tween_property(_host.get_node("RangerHatCrown"), "rotation:z", 0.0, 0.22)
			)
		"Hothead":
			# Overcommit: hard forward lunge then snap back to aggressive triumph pose
			_action_tween = _host.create_tween().set_parallel(true)
			_action_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			_action_tween.tween_property(_host.get_node("RangerBody"), "rotation:x", -0.28, 0.12)
			_action_tween.tween_property(_host.get_node("RangerBody"), "scale:y", 1.15, 0.12)
			_action_tween.tween_property(_host.get_node("RangerBody"), "rotation:z", 0.14, 0.12)
			_action_tween.tween_property(_host.get_node("RangerLeftArm"), "rotation:x", -2.05, 0.12)
			_action_tween.tween_property(_host.get_node("RangerRightArm"), "rotation:x", -2.05, 0.12)
			_host.get_tree().create_timer(0.2).timeout.connect(func() -> void:
				if not is_instance_valid(_host):
					return
				_kill_action_tween()
				_action_tween = _host.create_tween().set_parallel(true)
				_action_tween.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
				_action_tween.tween_property(_host.get_node("RangerBody"), "rotation:z", 0.0, 0.18)
				_action_tween.tween_property(_host.get_node("RangerBody"), "scale:y", 1.0, 0.18)
				_action_tween.tween_property(_host.get_node("RangerBody"), "scale:x", 1.12, 0.18)
				_action_tween.tween_property(_host.get_node("RangerBody"), "scale:z", 1.12, 0.18)
			)
		"Veteran":
			# Calm, controlled: smooth single-arm hold, body barely moves
			_action_tween = _host.create_tween().set_parallel(true)
			_action_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			_action_tween.tween_property(_host.get_node("RangerRightArm"), "rotation:x", -1.75, 0.3)
			_action_tween.tween_property(_host.get_node("RangerLeftArm"), "rotation:x", -1.45, 0.3)
			_action_tween.tween_property(_host.get_node("RangerBody"), "scale", Vector3(1.04, 0.97, 1.04), 0.3)
			_action_tween.tween_property(_host.get_node("RangerHead"), "rotation:x", 0.1, 0.3)
		_:
			# Steady: original elastic arms-up with body squish
			_action_tween = _host.create_tween().set_parallel(true)
			_action_tween.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
			_action_tween.tween_property(_host.get_node("RangerLeftArm"), "rotation:x", -1.9, 0.22)
			_action_tween.tween_property(_host.get_node("RangerRightArm"), "rotation:x", -1.9, 0.22)
			_action_tween.tween_property(_host.get_node("RangerBody"), "scale", Vector3(1.12, 0.9, 1.12), 0.22)

func reset_grab_pose(duration: float = 0.2) -> void:
	if not is_instance_valid(_host) or _rest_transforms.is_empty():
		return
	_kill_action_tween()
	_action_tween = _host.create_tween().set_parallel(true)
	_action_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	for visual in _visuals:
		if is_instance_valid(visual):
			_action_tween.tween_property(visual, "transform", _rest_transforms[visual], duration)

func _kill_action_tween() -> void:
	if _action_tween and _action_tween.is_valid():
		_action_tween.kill()

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
	if _alert_tween and _alert_tween.is_valid():
		_alert_tween.kill()
	_alert_label.text = text
	_alert_label.modulate = color
	_alert_label.scale = Vector3.ZERO
	_alert_label.visible = true
	_alert_tween = _host.create_tween()
	_alert_tween.tween_property(_alert_label, "scale", Vector3.ONE * peak_scale, grow_duration)
	_alert_tween.tween_property(_alert_label, "scale", Vector3.ONE, settle_duration)
