class_name RangerHUDController
extends CanvasLayer

@onready var _status_label: Label = $RangerStatus
@onready var _suspicion_bar: ProgressBar = $SuspicionBar
@onready var _vignette_material: ShaderMaterial = $VignetteRect.material
@onready var _warning_label: Label = $WarnLabel
@onready var _danger_flash: ColorRect = get_node_or_null("DangerFlash") as ColorRect
@onready var _sound_manager: Node = get_node("/root/SoundManager")

var _connected_rangers: Dictionary = {}
var _suspicion_by_ranger: Dictionary = {}
var _state_by_ranger: Dictionary = {}
var _primary_ranger: Node
var _primary_state: int = RangerStateMachine.State.PATROL
var _highest_state: int = RangerStateMachine.State.PATROL
var _pulse_time: float = 0.0
var _warning_timer: float = 0.0
var _danger_flash_tween: Tween
var exposure_feedback_count: int = 0
var close_call_feedback_count: int = 0
var _close_call_feedback_cooldown: float = 0.0
var flock_sync_feedback_count: int = 0
var wrong_pigeon_feedback_count: int = 0
var settings_path: String = AccessibilitySettings.DEFAULT_SETTINGS_PATH

func _ready() -> void:
	_ensure_danger_flash()
	call_deferred("_connect_new_rangers")

func _ensure_danger_flash() -> void:
	if _danger_flash != null:
		return
	_danger_flash = ColorRect.new()
	_danger_flash.name = "DangerFlash"
	_danger_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_danger_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_danger_flash.color = Color(0.82, 0.025, 0.01, 0.0)
	add_child(_danger_flash)
	move_child(_danger_flash, 0)

func _process(delta: float) -> void:
	_close_call_feedback_cooldown = maxf(_close_call_feedback_cooldown - delta, 0.0)
	if AccessibilitySettings.is_reduced_motion_enabled(settings_path):
		_suppress_danger_flash()
	_update_bar_pulse(delta)
	_update_warning(delta)

func _connect_new_rangers() -> void:
	for ranger in get_tree().get_nodes_in_group("rangers"):
		var instance_id := ranger.get_instance_id()
		if _connected_rangers.has(instance_id):
			continue
		_connected_rangers[instance_id] = ranger
		_suspicion_by_ranger[instance_id] = float(ranger.get("suspicion"))
		_state_by_ranger[instance_id] = int(ranger.get("state"))
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
		if ranger.has_signal("close_call"):
			ranger.connect("close_call", _on_close_call.bind(ranger))
		if ranger.has_signal("wrong_pigeon_grabbed"):
			ranger.connect("wrong_pigeon_grabbed", _on_wrong_pigeon_grabbed.bind(ranger))
		if bool(ranger.get("is_primary")):
			_primary_ranger = ranger
			_primary_state = int(ranger.get("state"))
	_update_max_suspicion()
	_update_highest_state()

func _on_suspicion_changed(value: float, ranger: Node) -> void:
	_suspicion_by_ranger[ranger.get_instance_id()] = value
	_update_max_suspicion()

func _on_state_changed(new_state: int, ranger: Node) -> void:
	_state_by_ranger[ranger.get_instance_id()] = new_state
	_update_highest_state()
	if new_state == RangerStateMachine.State.CHASE:
		_status_label.text = "Rangers: Alert!"
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
	_status_label.text = "CAUGHT!"

func _on_grab_started(_ranger: Node) -> void:
	_status_label.text = "Ranger: GRABBING!"
	_show_warning("DODGE!", Color(1.0, 0.18, 0.08, 1.0), 0.75)

func _on_grab_missed(_ranger: Node) -> void:
	_status_label.text = "Ranger: Stumbled!"
	_show_warning("CLOSE CALL!", Color(1.0, 0.82, 0.15, 1.0), 1.15)

func _on_close_call(_distance: float, _ranger: Node) -> void:
	if _close_call_feedback_cooldown > 0.0:
		return
	_close_call_feedback_cooldown = 0.75
	close_call_feedback_count += 1
	_status_label.text = "Rangers: Barely missed!"
	_show_warning("FEATHER'S WIDTH!", Color(1.0, 1.0, 0.62, 1.0), 1.25)

func _on_wrong_pigeon_grabbed(_pigeon: Node, _ranger: Node) -> void:
	wrong_pigeon_feedback_count += 1
	_status_label.text = "Ranger: Grabbed the wrong bird!"
	_show_warning("WRONG BIRD!", Color(0.5, 1.0, 0.92, 1.0), 1.25)

func _on_capture_started(_ranger: Node) -> void:
	_status_label.text = "CAUGHT!"
	# The ranger's world-space personality callout owns the capture punchline.
	# Clear DODGE rather than stacking a second large banner over it.
	_warning_timer = 0.0
	_warning_label.visible = false

func trigger_exposure_feedback() -> void:
	exposure_feedback_count += 1
	_status_label.text = "Rangers: Alert!"
	_show_warning("SPOTTED!", Color(1.0, 0.84, 0.12, 1.0), 1.35)
	if AccessibilitySettings.is_reduced_motion_enabled(settings_path):
		_suppress_danger_flash()
		return
	if _danger_flash_tween and _danger_flash_tween.is_valid():
		_danger_flash_tween.kill()
	_danger_flash.color = Color(0.82, 0.025, 0.01, 0.0)
	_danger_flash_tween = create_tween()
	_danger_flash_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_danger_flash_tween.tween_property(_danger_flash, "color:a", 0.24, 0.08)
	_danger_flash_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_danger_flash_tween.tween_property(_danger_flash, "color:a", 0.0, 0.48)

func trigger_flock_sync_feedback(joiner_count: int) -> bool:
	# Blending feedback yields to every danger banner and never changes suspicion.
	if _warning_timer > 0.0 or _highest_state != RangerStateMachine.State.PATROL:
		return false
	flock_sync_feedback_count += 1
	_show_warning("FLOCK SYNC x%d" % joiner_count, Color(0.52, 1.0, 0.84, 1.0), 0.8)
	return true

func _on_observation_changed(reason: String, is_nearby: bool, active_gain: float, ranger: Node) -> void:
	if ranger != _primary_ranger:
		return
	if _highest_state == RangerStateMachine.State.CHASE and int(ranger.get("state")) != RangerStateMachine.State.CHASE:
		_status_label.text = "Rangers: Alert!"
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
	_vignette_material.set_shader_parameter("intensity", maximum / 100.0 * 0.32)
	_sound_manager.call("set_tension", maximum / 100.0)

func _update_highest_state() -> void:
	_highest_state = RangerStateMachine.State.PATROL
	for ranger_state in _state_by_ranger.values():
		_highest_state = maxi(_highest_state, int(ranger_state))

func _update_bar_pulse(delta: float) -> void:
	if AccessibilitySettings.is_reduced_motion_enabled(settings_path):
		_pulse_time = 0.0
		match _highest_state:
			RangerStateMachine.State.PATROL:
				_suspicion_bar.modulate = Color.WHITE
			RangerStateMachine.State.INVESTIGATE:
				_suspicion_bar.modulate = Color(1.0, 0.62, 0.08, 1.0)
			RangerStateMachine.State.CHASE:
				_suspicion_bar.modulate = Color(1.0, 0.12, 0.04, 1.0)
		return
	match _highest_state:
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

func _suppress_danger_flash() -> void:
	if _danger_flash_tween and _danger_flash_tween.is_valid():
		_danger_flash_tween.kill()
	_danger_flash_tween = null
	if is_instance_valid(_danger_flash):
		_danger_flash.color = Color(0.82, 0.025, 0.01, 0.0)

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
