class_name RangerHUDController
extends CanvasLayer

@onready var _status_label: Label = $RangerStatus
@onready var _suspicion_bar: ProgressBar = $SuspicionBar
@onready var _vignette_material: ShaderMaterial = $VignetteRect.material
@onready var _warning_label: Label = $WarnLabel
@onready var _sound_manager: Node = get_node("/root/SoundManager")

var _connected_rangers: Dictionary = {}
var _suspicion_by_ranger: Dictionary = {}
var _primary_ranger: Node
var _primary_state: int = RangerStateMachine.State.PATROL
var _pulse_time: float = 0.0
var _warning_timer: float = 0.0

func _ready() -> void:
	call_deferred("_connect_new_rangers")

func _process(delta: float) -> void:
	_connect_new_rangers()
	_update_bar_pulse(delta)
	_update_warning(delta)

func _connect_new_rangers() -> void:
	for ranger in get_tree().get_nodes_in_group("rangers"):
		var instance_id := ranger.get_instance_id()
		if _connected_rangers.has(instance_id):
			continue
		_connected_rangers[instance_id] = ranger
		_suspicion_by_ranger[instance_id] = float(ranger.get("suspicion"))
		ranger.connect("suspicion_changed", _on_suspicion_changed.bind(ranger))
		ranger.connect("state_changed", _on_state_changed.bind(ranger))
		ranger.connect("player_caught", _on_player_caught.bind(ranger))
		ranger.connect("observation_changed", _on_observation_changed.bind(ranger))
		if ranger.has_signal("grab_started"):
			ranger.connect("grab_started", _on_grab_started.bind(ranger))
		if ranger.has_signal("grab_missed"):
			ranger.connect("grab_missed", _on_grab_missed.bind(ranger))
		if ranger.has_signal("capture_started"):
			ranger.connect("capture_started", _on_capture_started.bind(ranger))
		if bool(ranger.get("is_primary")):
			_primary_ranger = ranger
			_primary_state = int(ranger.get("state"))
	_update_max_suspicion()

func _on_suspicion_changed(value: float, ranger: Node) -> void:
	_suspicion_by_ranger[ranger.get_instance_id()] = value
	_update_max_suspicion()

func _on_state_changed(new_state: int, ranger: Node) -> void:
	if ranger != _primary_ranger:
		return
	_primary_state = new_state
	if new_state == RangerStateMachine.State.CHASE:
		_show_warning("DANGER!", Color(1.0, 0.15, 0.15, 1.0), 1.8)
	elif new_state == RangerStateMachine.State.INVESTIGATE:
		_show_warning("!", Color(1.0, 0.8, 0.1, 1.0), 1.5)

func _on_player_caught(ranger: Node) -> void:
	_suspicion_by_ranger[ranger.get_instance_id()] = 100.0
	_update_max_suspicion()
	if ranger == _primary_ranger:
		_status_label.text = "CAUGHT!"

func _on_grab_started(_ranger: Node) -> void:
	_status_label.text = "Ranger: GRABBING!"
	_show_warning("DODGE!", Color(1.0, 0.18, 0.08, 1.0), 0.75)

func _on_grab_missed(_ranger: Node) -> void:
	_status_label.text = "Ranger: Stumbled!"
	_show_warning("CLOSE CALL!", Color(1.0, 0.82, 0.15, 1.0), 1.15)

func _on_capture_started(_ranger: Node) -> void:
	_status_label.text = "CAUGHT!"
	_show_warning("GOTCHA!", Color(1.0, 0.12, 0.08, 1.0), 0.8)

func _on_observation_changed(reason: String, is_nearby: bool, active_gain: float, ranger: Node) -> void:
	if ranger != _primary_ranger:
		return
	match int(ranger.get("state")):
		RangerStateMachine.State.CHASE:
			_status_label.text = "Ranger: Alert!"
		RangerStateMachine.State.INVESTIGATE:
			_status_label.text = (
				"Ranger: Suspicious — %s" % reason
				if active_gain > 0.0
				else "Ranger: Investigating..."
			)
		RangerStateMachine.State.PATROL:
			if active_gain > 0.0:
				_status_label.text = "Ranger: Suspicious — %s" % reason
			elif is_nearby:
				_status_label.text = "Ranger: Watching"
			else:
				_status_label.text = "Ranger: Calm"

func _update_max_suspicion() -> void:
	var maximum: float = 0.0
	for value in _suspicion_by_ranger.values():
		maximum = maxf(maximum, float(value))
	_suspicion_bar.value = maximum
	_vignette_material.set_shader_parameter("intensity", maximum / 100.0 * 0.65)
	_sound_manager.call("set_tension", maximum / 100.0)

func _update_bar_pulse(delta: float) -> void:
	match _primary_state:
		RangerStateMachine.State.PATROL:
			_pulse_time = 0.0
			_suspicion_bar.modulate = Color.WHITE
		RangerStateMachine.State.INVESTIGATE:
			_pulse_time += delta
			var pulse := sin(_pulse_time * TAU * 2.5) * 0.5 + 0.5
			_suspicion_bar.modulate = Color(1.0, lerp(0.35, 0.75, pulse), pulse * 0.1)
		RangerStateMachine.State.CHASE:
			_pulse_time += delta
			var pulse := sin(_pulse_time * TAU * 6.0) * 0.5 + 0.5
			_suspicion_bar.modulate = Color(1.0, lerp(0.0, 0.3, pulse), 0.0)

func _show_warning(text: String, color: Color, duration: float) -> void:
	_warning_label.text = text
	_warning_label.modulate = color
	_warning_label.visible = true
	_warning_timer = duration

func _update_warning(delta: float) -> void:
	if _warning_timer <= 0.0:
		return
	_warning_timer -= delta
	_warning_label.modulate.a = clampf(_warning_timer / 0.5, 0.0, 1.0)
	if _warning_timer <= 0.0:
		_warning_label.visible = false
