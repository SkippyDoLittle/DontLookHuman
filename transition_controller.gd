class_name TransitionController
extends RefCounted

var _host: Node
var _fade_overlay: ColorRect
var _transition_rect: ColorRect
var _camera: Camera3D
var _shake_trauma: float = 0.0

func configure(host: Node, level_root: Node) -> void:
	_host = host
	_fade_overlay = level_root.get_node("HUD/FadeOverlay") as ColorRect
	_transition_rect = level_root.get_node("TransitionLayer/FadeRect") as ColorRect
	_camera = level_root.get_node("Player/SpringArm3D/Camera3D") as Camera3D

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
	_shake_trauma = maxf(_shake_trauma, clampf(strength, 0.0, 1.0))

func update_shake(delta: float) -> void:
	if _shake_trauma > 0.0:
		_shake_trauma = maxf(_shake_trauma - delta * 1.8, 0.0)
		var magnitude := _shake_trauma * _shake_trauma * 0.04
		_camera.h_offset = randf_range(-magnitude, magnitude)
		_camera.v_offset = randf_range(-magnitude, magnitude)
	else:
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0
