class_name TransitionController
extends RefCounted

var _host: Node
var _fade_overlay: ColorRect
var _transition_rect: ColorRect
var _camera_feedback: CameraFeedbackController

func configure(host: Node, level_root: Node) -> void:
	_host = host
	_fade_overlay = level_root.get_node("HUD/FadeOverlay") as ColorRect
	_transition_rect = level_root.get_node("TransitionLayer/FadeRect") as ColorRect
	var camera := level_root.get_node("Player/SpringArm3D/Camera3D") as Camera3D
	_camera_feedback = CameraFeedbackController.shared_for_camera(camera)

func fade_in() -> void:
	var tween := _host.create_tween()
	tween.tween_property(_fade_overlay, "modulate:a", 0.0, 0.8)
	tween.tween_callback(func(): _fade_overlay.visible = false)

func fade_to_black(duration: float, completion: Callable) -> void:
	var tween := _host.create_tween()
	tween.tween_property(_transition_rect, "color:a", 1.0, duration)
	tween.tween_callback(completion)

func clear_transition() -> void:
	_transition_rect.color.a = 0.0

func start_shake(strength: float = 1.0) -> void:
	_camera_feedback.add_trauma(strength, 0.55)

func update_shake(delta: float) -> void:
	_camera_feedback.update(delta)
