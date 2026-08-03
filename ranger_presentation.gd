class_name RangerPresentation
extends RefCounted

var _host: Node
var _alert_label: Label3D
var _sound_manager: Node
var _alert_tween: Tween
var _pulse_time: float = 0.0

func configure(host: Node, alert_label: Label3D, sound_manager: Node) -> void:
	_host = host
	_alert_label = alert_label
	_sound_manager = sound_manager
	_alert_label.visible = false

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
