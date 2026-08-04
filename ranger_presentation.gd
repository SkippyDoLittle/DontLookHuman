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

func grab_missed(recovery_duration: float, personality: String = "Steady") -> void:
	var callout := {
		"Rookie": "OOPS!",
		"Hothead": "NO FAIR!",
		"Veteran": "MISSED.",
	}.get(personality, "WHIFF!") as String
	_show_alert(callout, Color(1.0, 0.72, 0.15, 1.0), 1.55, 0.05, 0.10)
	_kill_action_tween()
	_action_tween = _host.create_tween().set_parallel(true)
	_action_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_action_tween.tween_property(_host.get_node("RangerBody"), "rotation:x", -1.0, 0.14)
	_action_tween.tween_property(_host.get_node("RangerBody"), "position:y", -0.28, 0.14)
	_action_tween.tween_property(_host.get_node("RangerLeftArm"), "rotation:z", -1.0, 0.14)
	_action_tween.tween_property(_host.get_node("RangerRightArm"), "rotation:z", 1.0, 0.14)
	_action_tween.tween_property(_host.get_node("RangerHatBrim"), "rotation:z", 0.65, 0.14)
	_action_tween.tween_property(_host.get_node("RangerHatCrown"), "rotation:z", 0.65, 0.14)
	var reset_delay := maxf(recovery_duration - 0.42, 0.12)
	_host.get_tree().create_timer(reset_delay).timeout.connect(reset_grab_pose.bind(0.28))

func player_captured(personality: String = "Steady") -> void:
	var callout := {
		"Rookie": "I GOT ONE!",
		"Hothead": "YES!",
		"Veteran": "SECURED!",
	}.get(personality, "GOTCHA!") as String
	_show_alert(callout, Color(1.0, 0.85, 0.18, 1.0), 1.8, 0.05, 0.12)
	_kill_action_tween()
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

func _show_alert(
	text: String,
	color: Color,
	peak_scale: float,
	grow_duration: float,
	settle_duration: float
) -> void:
	_alert_label.text = text
	_alert_label.modulate = color
	_alert_label.scale = Vector3.ZERO
	_alert_label.visible = true
	_alert_tween = _host.create_tween()
	_alert_tween.tween_property(_alert_label, "scale", Vector3.ONE * peak_scale, grow_duration)
	_alert_tween.tween_property(_alert_label, "scale", Vector3.ONE, settle_duration)
