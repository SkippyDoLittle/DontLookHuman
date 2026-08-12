class_name CameraFeedbackController
extends RefCounted

# One owner composes every camera feedback channel. Gameplay systems only add
# trauma; they never write Camera3D offsets directly and therefore cannot erase
# each other when food, danger, and capture feedback overlap.
const CAMERA_META_KEY: StringName = &"dont_look_human_camera_feedback"

var _camera: Camera3D
var _trauma: float = 0.0
var _decay_per_second: float = 1.8
var _maximum_offset: float = 0.06
var _time: float = 0.0
var _owns_offsets: bool = false
var _last_update_frame: int = -1

static func shared_for_camera(camera: Camera3D) -> CameraFeedbackController:
	if not is_instance_valid(camera):
		return CameraFeedbackController.new()
	if camera.has_meta(CAMERA_META_KEY):
		var existing := camera.get_meta(CAMERA_META_KEY) as CameraFeedbackController
		if existing != null:
			return existing
	var controller := CameraFeedbackController.new()
	controller.configure(camera)
	camera.set_meta(CAMERA_META_KEY, controller)
	return controller

func configure(camera: Camera3D) -> void:
	_camera = camera

func add_trauma(strength: float, duration: float = 0.42) -> void:
	_trauma = maxf(_trauma, clampf(strength, 0.0, 1.0))
	_decay_per_second = 1.0 / maxf(duration, 0.05)
	_owns_offsets = true

func update(delta: float) -> void:
	if not is_instance_valid(_camera):
		return
	# Player and level presentation both reference this shared compositor. Only
	# advance it once per rendered frame when both systems call update().
	var current_frame := Engine.get_process_frames()
	if _last_update_frame == current_frame:
		return
	_last_update_frame = current_frame
	if _trauma <= 0.0 and not _owns_offsets:
		return
	if _trauma <= 0.0:
		_camera.h_offset = move_toward(_camera.h_offset, 0.0, delta * 0.4)
		_camera.v_offset = move_toward(_camera.v_offset, 0.0, delta * 0.4)
		if is_zero_approx(_camera.h_offset) and is_zero_approx(_camera.v_offset):
			_owns_offsets = false
		return
	_time += delta
	_trauma = maxf(_trauma - delta * _decay_per_second, 0.0)
	var magnitude := _trauma * _trauma * _maximum_offset
	_camera.h_offset = sin(_time * 61.0) * magnitude
	_camera.v_offset = sin(_time * 47.0 + 1.7) * magnitude * 0.62

func reset() -> void:
	_trauma = 0.0
	_owns_offsets = false
	if is_instance_valid(_camera):
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0
