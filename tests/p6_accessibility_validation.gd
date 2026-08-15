extends SceneTree

# P6 reduced-motion persistence and presentation-contract validation.
# Run headless: --headless --path . --script res://tests/p6_accessibility_validation.gd

var _failures: int = 0
var _settings_path: String


func _initialize() -> void:
	call_deferred("_validate")


func _validate() -> void:
	Engine.time_scale = 1.0
	paused = false
	_settings_path = "user://p6_accessibility_%d.cfg" % Time.get_ticks_usec()
	_remove_test_settings()
	AccessibilitySettings.invalidate_cache(_settings_path)

	_test_lazy_persistence()
	await _test_camera_feedback()
	await _test_level_feedback()
	await _test_main_menu_control()

	Engine.time_scale = 1.0
	paused = false
	AccessibilitySettings.invalidate_cache(_settings_path)
	_remove_test_settings()
	if _failures == 0:
		print("P6_ACCESSIBILITY_VALIDATION_OK")
	quit(_failures)


func _test_lazy_persistence() -> void:
	_check(
		not ProjectSettings.has_setting("autoload/AccessibilitySettings"),
		"accessibility helper remains a lazy static utility, not an autoload"
	)
	_check(
		not AccessibilitySettings.is_reduced_motion_enabled(_settings_path),
		"missing injected settings file defaults reduced motion off"
	)

	var config := ConfigFile.new()
	config.set_value("audio", "music", 0.37)
	config.set_value("display", "quality_preset", "High")
	config.set_value("future_feature", "keep_me", "untouched")
	_check(config.save(_settings_path) == OK, "isolated settings fixture saves")
	AccessibilitySettings.invalidate_cache(_settings_path)
	_check(
		AccessibilitySettings.set_reduced_motion(true, _settings_path) == OK,
		"reduced motion persists through an injected settings path"
	)
	_check(
		AccessibilitySettings.is_reduced_motion_enabled(_settings_path),
		"persisted reduced-motion value is cached and readable"
	)

	var saved := ConfigFile.new()
	_check(saved.load(_settings_path) == OK, "updated settings remain readable")
	_check(
		is_equal_approx(float(saved.get_value("audio", "music", 0.0)), 0.37)
		and String(saved.get_value("display", "quality_preset", "")) == "High"
		and String(saved.get_value("future_feature", "keep_me", "")) == "untouched",
		"accessibility save preserves every unrelated ConfigFile key"
	)

	# An external edit remains hidden until explicit invalidation, proving the
	# runtime path uses one lightweight lazy cache instead of reading every frame.
	saved.set_value("accessibility", "reduced_motion", false)
	_check(saved.save(_settings_path) == OK, "external cache fixture edit saves")
	_check(
		AccessibilitySettings.is_reduced_motion_enabled(_settings_path),
		"cached value avoids repeated disk reads"
	)
	AccessibilitySettings.invalidate_cache(_settings_path)
	_check(
		not AccessibilitySettings.is_reduced_motion_enabled(_settings_path),
		"path-specific invalidation reloads an external settings change"
	)
	_check(
		AccessibilitySettings.set_reduced_motion(true, _settings_path) == OK,
		"fixture restores reduced motion for presentation checks"
	)


func _test_camera_feedback() -> void:
	var camera := Camera3D.new()
	root.add_child(camera)
	var feedback := CameraFeedbackController.new()
	feedback.settings_path = _settings_path
	feedback.configure(camera)

	AccessibilitySettings.set_reduced_motion(false, _settings_path)
	feedback.add_trauma(0.8, 0.5)
	feedback.update(0.016)
	_check(
		absf(camera.h_offset) > 0.00001 or absf(camera.v_offset) > 0.00001,
		"ordinary camera trauma still produces a bounded offset"
	)

	# Both updates deliberately happen in one process frame. Reduced motion must
	# reset before the shared-compositor frame guard can retain an old offset.
	AccessibilitySettings.set_reduced_motion(true, _settings_path)
	feedback.update(0.016)
	_check(
		is_zero_approx(camera.h_offset) and is_zero_approx(camera.v_offset),
		"live reduced-motion toggle immediately clears an active camera offset"
	)
	feedback.add_trauma(1.0, 1.0)
	_check(
		is_zero_approx(float(feedback.get("_trauma")))
		and is_zero_approx(camera.h_offset)
		and is_zero_approx(camera.v_offset),
		"new camera trauma is ignored while reduced motion is enabled"
	)

	camera.queue_free()
	await process_frame


func _test_level_feedback() -> void:
	AccessibilitySettings.set_reduced_motion(true, _settings_path)
	var level := (
		load("res://scenes/levels/Level01_Park.tscn") as PackedScene
	).instantiate() as BaseLevel
	var hud := level.get_node("HUD") as RangerHUDController
	var chaos := level.get_node("ParkChaosController") as ParkChaosController
	var pause_menu := level.get_node("PauseMenu")
	hud.settings_path = _settings_path
	chaos.settings_path = _settings_path
	pause_menu.set("settings_path", _settings_path)
	root.add_child(level)
	await process_frame
	await process_frame
	paused = false

	var pause_check := pause_menu.get_node_or_null(
		"VBoxContainer/AudioPanel/ReducedMotionCheck"
	) as CheckButton
	# Legacy Main.tscn intentionally has no authored accessibility row. The
	# nullable script lookup must still boot and apply the persisted preference.
	if is_instance_valid(pause_check):
		_check(pause_check.button_pressed, "pause control loads the injected persisted value")
		pause_menu.visible = true
		pause_menu.call("_on_audio_pressed")
		var audio_panel := pause_menu.get_node("VBoxContainer/AudioPanel") as VBoxContainer
		var music_slider := audio_panel.get_node("MusicSlider") as HSlider
		var audio_button := pause_menu.get_node("VBoxContainer/AudioButton") as Button
		var controls_button := pause_menu.get_node("VBoxContainer/ControlsButton") as Button
		_check(
			audio_panel.visible
			and music_slider.has_focus()
			and audio_button.focus_neighbor_bottom == NodePath("../AudioPanel/MusicSlider")
			and controls_button.focus_neighbor_top == NodePath("../AudioPanel/ReducedMotionCheck"),
			"expanded pause settings enters and reverses through its controller focus chain"
		)
		pause_menu.call("_on_audio_pressed")
		_check(
			not audio_panel.visible and audio_button.has_focus(),
			"collapsed pause settings restores focus to the disclosure button"
		)
		pause_menu.visible = false
	else:
		_check(
			AccessibilitySettings.is_reduced_motion_enabled(_settings_path),
			"legacy pause scene boots safely without an authored accessibility control"
		)
		pause_menu.visible = true
		pause_menu.call("_on_audio_pressed")
		var legacy_controls := pause_menu.get_node("VBoxContainer/ControlsButton") as Button
		_check(
			legacy_controls.focus_neighbor_top == NodePath("../AudioPanel/SFXSlider"),
			"legacy expanded settings retains a valid reverse focus target"
		)
		pause_menu.call("_on_audio_pressed")
		pause_menu.visible = false

	var suspicion_bar := hud.get_node("SuspicionBar") as ProgressBar
	hud.set("_highest_state", RangerStateMachine.State.INVESTIGATE)
	hud.call("_update_bar_pulse", 0.03)
	var amber := suspicion_bar.modulate
	hud.call("_update_bar_pulse", 0.31)
	_check(
		_colors_close(suspicion_bar.modulate, amber)
		and amber.r > 0.9
		and amber.g > 0.45
		and amber.b < 0.2,
		"investigate pulse becomes one stable semantic amber tint"
	)
	hud.set("_highest_state", RangerStateMachine.State.CHASE)
	hud.call("_update_bar_pulse", 0.04)
	var red := suspicion_bar.modulate
	hud.call("_update_bar_pulse", 0.27)
	_check(
		_colors_close(suspicion_bar.modulate, red)
		and red.r > 0.9
		and red.g < 0.2,
		"chase pulse becomes one stable semantic red tint"
	)
	var presentation_ranger := get_first_node_in_group("rangers")
	var ranger_presentation := presentation_ranger.get("_presentation") as RangerPresentation
	ranger_presentation.settings_path = _settings_path
	var alert_label := presentation_ranger.get_node("AlertLabel") as Label3D
	ranger_presentation.call("state_changed", RangerStateMachine.State.CHASE)
	ranger_presentation.call("update", 0.03, RangerStateMachine.State.CHASE)
	var steady_alert := alert_label.modulate
	ranger_presentation.call("update", 0.21, RangerStateMachine.State.CHASE)
	_check(
		_colors_close(alert_label.modulate, steady_alert)
		and is_equal_approx(steady_alert.a, 1.0),
		"reduced motion keeps the ranger world alert solid instead of flashing"
	)

	var exposure_before := hud.exposure_feedback_count
	hud.trigger_exposure_feedback()
	var danger_flash := hud.get_node("DangerFlash") as ColorRect
	_check(
		hud.exposure_feedback_count == exposure_before + 1
		and hud.get_node("WarnLabel").visible
		and hud.get_node("WarnLabel").text == "SPOTTED!",
		"reduced motion retains semantic exposure status and warning feedback"
	)
	_check(
		is_zero_approx(danger_flash.color.a)
		and hud.get("_danger_flash_tween") == null,
		"reduced motion suppresses the danger flash and its tween"
	)

	var player := level.get_node("Player")
	var ranger := get_first_node_in_group("rangers")
	var close_events: Array[float] = []
	chaos.close_call_cinematic_started.connect(
		func(distance: float, _origin: Vector3) -> void:
			close_events.append(distance)
	)
	chaos.set("_close_call_cooldown", 0.0)
	var close_count_before := chaos.close_call_event_count
	var shake_attempts_before := int(player.get("camera_shake_count"))
	Engine.time_scale = 1.0
	chaos.call("_on_ranger_close_call", 0.42, ranger)
	_check(
		is_equal_approx(float(chaos.get("_close_call_cooldown")), 2.8)
		and chaos.close_call_event_count == close_count_before + 1,
		"reduced close call retains cooldown and event accounting"
	)
	_check(
		is_equal_approx(Engine.time_scale, 1.0)
		and not bool(chaos.get("_close_call_active")),
		"reduced close call skips only time-scale slowdown state"
	)
	_check(
		close_events.size() == 1
		and int(player.get("camera_shake_count")) == shake_attempts_before + 1
		and level.has_node("CloseCallFeathers"),
		"reduced close call retains its signal, feedback call, and feather burst"
	)
	chaos.call("_on_ranger_close_call", 0.31, ranger)
	_check(
		chaos.close_call_event_count == close_count_before + 1,
		"retained cooldown still rejects immediate close-call repetition"
	)

	# Default behavior remains available when the preference is disabled.
	AccessibilitySettings.set_reduced_motion(false, _settings_path)
	chaos.set("_close_call_cooldown", 0.0)
	Engine.time_scale = 1.0
	chaos.call("_on_ranger_close_call", 0.36, ranger)
	_check(
		Engine.time_scale < 0.5 and bool(chaos.get("_close_call_active")),
		"disabling reduced motion preserves the existing close-call slowdown"
	)
	chaos.call("_end_close_call_slowmo")
	_check(is_equal_approx(Engine.time_scale, 1.0), "normal close-call scale restores cleanly")

	if is_instance_valid(pause_check):
		pause_check.button_pressed = false
		pause_check.button_pressed = true
		_check(
			AccessibilitySettings.is_reduced_motion_enabled(_settings_path),
			"pause control persists and updates the shared lazy cache"
		)

	level.queue_free()
	await process_frame
	Engine.time_scale = 1.0
	paused = false


func _test_main_menu_control() -> void:
	AccessibilitySettings.set_reduced_motion(true, _settings_path)
	var menu := (load("res://MainMenu.tscn") as PackedScene).instantiate()
	menu.set("settings_path", _settings_path)
	menu.set(
		"_score_store",
		BestScoreStore.new(
			"user://p6_accessibility_menu_scores.cfg",
			"user://p6_accessibility_menu_legacy.dat"
		)
	)
	menu.set("_progress_store", CampaignProgressStore.new("user://p6_accessibility_menu_progress.cfg"))
	root.add_child(menu)
	await process_frame

	var check := menu.get_node_or_null(
		"CanvasLayer/SettingsPanel/VBoxContainer/ReducedMotionCheck"
	) as CheckButton
	_check(is_instance_valid(check), "main settings panel exposes reduced motion")
	if is_instance_valid(check):
		_check(check.button_pressed, "main-menu control loads injected persisted state")
		check.button_pressed = false
		_check(
			not AccessibilitySettings.is_reduced_motion_enabled(_settings_path),
			"main-menu toggle immediately updates shared reduced-motion state"
		)

	var saved := ConfigFile.new()
	_check(saved.load(_settings_path) == OK, "menu-updated settings remain readable")
	_check(
		String(saved.get_value("display", "quality_preset", "")) == "High"
		and String(saved.get_value("future_feature", "keep_me", "")) == "untouched",
		"menu accessibility toggle preserves unrelated stored preferences"
	)

	menu.queue_free()
	await process_frame


func _colors_close(a: Color, b: Color) -> bool:
	return (
		is_equal_approx(a.r, b.r)
		and is_equal_approx(a.g, b.g)
		and is_equal_approx(a.b, b.b)
		and is_equal_approx(a.a, b.a)
	)


func _remove_test_settings() -> void:
	var absolute_path := ProjectSettings.globalize_path(_settings_path)
	if FileAccess.file_exists(_settings_path):
		DirAccess.remove_absolute(absolute_path)
	for path in [
		"user://p6_accessibility_menu_scores.cfg",
		"user://p6_accessibility_menu_legacy.dat",
		"user://p6_accessibility_menu_progress.cfg",
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("P6 accessibility validation failed: %s" % message)
