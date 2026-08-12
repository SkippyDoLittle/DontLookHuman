class_name SessionHUDController
extends RefCounted

signal result_action_requested(action: StringName)

const ACTION_NEXT: StringName = &"next"
const ACTION_RETRY: StringName = &"retry"
const ACTION_REPLAY_CAMPAIGN: StringName = &"replay_campaign"
const ACTION_MENU: StringName = &"menu"

var _hud: CanvasLayer
var _timer_label: Label
var _result_bg: ColorRect
var _result_label: Label
var _status_label: Label
var _objective_label: Label
var _suspicion_bar: ProgressBar
var _stamina_bar: ProgressBar
var _countdown_label: Label
var _help_hint: Label
var _chaos_window_callout: PanelContainer
var _chaos_window_label: Label
var _opportunity_background: StyleBoxFlat
var _result_actions: HBoxContainer
var _primary_button: Button
var _retry_button: Button
var _menu_button: Button
var _primary_action: StringName = ACTION_NEXT

func configure(level_root: Node) -> void:
	_hud = level_root.get_node("HUD") as CanvasLayer
	_timer_label = _hud.get_node("TimerLabel") as Label
	_result_bg = _hud.get_node("ResultBackground") as ColorRect
	_result_label = _hud.get_node("ResultLabel") as Label
	_status_label = _hud.get_node("RangerStatus") as Label
	_objective_label = _hud.get_node("ObjectiveStatus") as Label
	_suspicion_bar = _hud.get_node("SuspicionBar") as ProgressBar
	_stamina_bar = _hud.get_node("StaminaBar") as ProgressBar
	_countdown_label = _hud.get_node("CountdownLabel") as Label
	_chaos_window_callout = _hud.get_node_or_null("ChaosWindowCallout") as PanelContainer
	if _chaos_window_callout == null:
		_chaos_window_callout = _create_chaos_window_callout()
	_chaos_window_label = _chaos_window_callout.get_node("Label") as Label
	_opportunity_background = _chaos_window_callout.get_theme_stylebox("panel") as StyleBoxFlat
	_result_actions = _hud.get_node_or_null("ResultActions") as HBoxContainer
	if _result_actions == null:
		_result_actions = _create_result_actions()
	_primary_button = _result_actions.get_node("PrimaryButton") as Button
	_retry_button = _result_actions.get_node("RetryButton") as Button
	_menu_button = _result_actions.get_node("MenuButton") as Button
	_primary_button.pressed.connect(_on_primary_pressed)
	_retry_button.pressed.connect(func(): result_action_requested.emit(ACTION_RETRY))
	_menu_button.pressed.connect(func(): result_action_requested.emit(ACTION_MENU))

func _create_chaos_window_callout() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "ChaosWindowCallout"
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.z_index = 12
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.offset_left = -190.0
	panel.offset_top = 38.0
	panel.offset_right = 190.0
	panel.offset_bottom = 76.0

	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.12, 0.065, 0.01, 0.92)
	background.border_color = Color(1.0, 0.58, 0.10, 0.95)
	background.set_border_width_all(2)
	background.set_corner_radius_all(8)
	background.content_margin_left = 12.0
	background.content_margin_right = 12.0
	background.content_margin_top = 6.0
	background.content_margin_bottom = 6.0
	panel.add_theme_stylebox_override("panel", background)

	var label := Label.new()
	label.name = "Label"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.34))
	label.add_theme_color_override("font_shadow_color", Color(0.02, 0.01, 0.0, 0.95))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	panel.add_child(label)
	_hud.add_child(panel)
	return panel

func _create_result_actions() -> HBoxContainer:
	var actions := HBoxContainer.new()
	actions.name = "ResultActions"
	actions.process_mode = Node.PROCESS_MODE_ALWAYS
	actions.visible = false
	actions.set_anchors_preset(Control.PRESET_CENTER)
	actions.position = Vector2(-238.0, 115.0)
	actions.size = Vector2(476.0, 55.0)
	actions.add_theme_constant_override("separation", 10)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	_hud.add_child(actions)

	for spec in [
		{"name": "PrimaryButton", "text": "NEXT LEVEL"},
		{"name": "RetryButton", "text": "RETRY"},
		{"name": "MenuButton", "text": "MAIN MENU"},
	]:
		var button := Button.new()
		button.name = String(spec.name)
		button.text = String(spec.text)
		button.custom_minimum_size = Vector2(145.0, 52.0)
		button.add_theme_font_size_override("font_size", 16)
		actions.add_child(button)
	return actions

func add_controls_hint() -> Label:
	_help_hint = Label.new()
	_help_hint.text = "H / Pause menu - controls"
	_help_hint.add_theme_font_size_override("font_size", 13)
	_help_hint.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 0.60))
	_help_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_help_hint.offset_bottom = -10
	_help_hint.offset_left = 12
	_hud.add_child(_help_hint)
	return _help_hint

func hide_controls_hint() -> void:
	if is_instance_valid(_help_hint):
		_help_hint.visible = false

func show_countdown(value: int) -> void:
	_countdown_label.text = str(value)
	_countdown_label.visible = true

func show_go() -> void:
	_countdown_label.text = "GO!"

func hide_countdown() -> void:
	_countdown_label.visible = false

func show_chaos_window(remaining: float, bonus_seconds: float) -> void:
	var clamped_remaining := maxf(remaining, 0.0)
	if clamped_remaining <= 0.0:
		hide_chaos_window()
		return
	_show_opportunity_window(
		"STEAL FOOD: +%.0fs  |  CHAOS %.1fs" % [bonus_seconds, clamped_remaining],
		Color(1.0, 0.84, 0.34),
		Color(0.12, 0.065, 0.01, 0.92),
		Color(1.0, 0.58, 0.10, 0.95)
	)

func show_alibi_window(remaining: float, bonus_seconds: float) -> void:
	var clamped_remaining := maxf(remaining, 0.0)
	if clamped_remaining <= 0.0:
		hide_chaos_window()
		return
	_show_opportunity_window(
		"PERFECT ALIBI: STEAL NOW +%.0fs  |  %.1fs" % [bonus_seconds, clamped_remaining],
		Color(0.52, 1.0, 0.88),
		Color(0.025, 0.13, 0.105, 0.94),
		Color(0.20, 0.92, 0.70, 0.98)
	)

func show_combined_window(remaining: float, total_bonus_seconds: float) -> void:
	var clamped_remaining := maxf(remaining, 0.0)
	if clamped_remaining <= 0.0:
		hide_chaos_window()
		return
	_show_opportunity_window(
		"PERFECT CHANCE: +%.0fs  |  %.1fs" % [total_bonus_seconds, clamped_remaining],
		Color(1.0, 0.96, 0.46),
		Color(0.15, 0.11, 0.015, 0.95),
		Color(1.0, 0.80, 0.18, 1.0)
	)

func _show_opportunity_window(
	text: String,
	text_color: Color,
	background_color: Color,
	border_color: Color
) -> void:
	if not is_instance_valid(_chaos_window_callout) or not is_instance_valid(_chaos_window_label):
		return
	_chaos_window_label.text = text
	_chaos_window_label.add_theme_color_override("font_color", text_color)
	if is_instance_valid(_opportunity_background):
		_opportunity_background.bg_color = background_color
		_opportunity_background.border_color = border_color
	_chaos_window_callout.visible = true

func hide_chaos_window() -> void:
	if is_instance_valid(_chaos_window_callout):
		_chaos_window_callout.visible = false

func update_timer(remaining: float) -> void:
	var seconds := ceili(remaining)
	_timer_label.text = "%d:%02d" % [seconds / 60.0, seconds % 60]
	if remaining <= 20.0:
		_timer_label.modulate = Color(1.0, 0.3, 0.3)
	elif remaining <= 40.0:
		_timer_label.modulate = Color(1.0, 0.75, 0.2)
	else:
		_timer_label.modulate = Color.WHITE

func update_objective(remaining: int, total: int) -> void:
	if remaining <= 0:
		_objective_label.text = "All items stolen! Reach the exit!"
	elif remaining == total:
		_objective_label.text = "Steal all %d items, then reach the exit!" % total
	else:
		_objective_label.text = "%d item(s) left to steal!" % remaining

func show_escape_blocked(remaining: int) -> void:
	_objective_label.text = "%d item(s) still out there — steal them first!" % remaining

func show_result(
	headline: String,
	success: bool,
	summary: Dictionary,
	best_score: int,
	is_new_best: bool,
	has_next_level: bool,
	caught_reason: String
) -> void:
	var flavor: String
	if headline == "ESCAPED!":
		flavor = "\"Just a pigeon. Nothing to see here.\""
	elif headline == "CAUGHT!":
		flavor = (
			"The ranger noticed: %s" % caught_reason
			if not caught_reason.is_empty()
			else "Caught red-beaked by the ranger!"
		)
	else:
		flavor = "The picnic packed up before you could escape."

	_result_label.text = (
		headline
		+ "\n" + flavor
		+ "\n\n──────────────────"
		+ "\nScore:          %d pts"
		+ (("\n                " + summary.tier) if summary.tier != "" else "")
		+ "\nTime:           %d:%02d"
		+ "\nItems stolen:   %d / %d"
		+ "\n──────────────────"
	) % [summary.score, summary.minutes, summary.seconds, summary.collected, summary.total]

	if is_new_best:
		_result_label.text += "\n★  New best score!"
	elif best_score > 0:
		_result_label.text += "\nBest score: %d pts" % best_score

	if success and not has_next_level:
		_result_label.text += "\n\n★  ALL LEVELS COMPLETE!  ★"

	_result_label.modulate = Color(0.35, 1.0, 0.45) if success else Color(1.0, 0.35, 0.35)
	_result_bg.color = Color(0.03, 0.14, 0.06, 0.88) if success else Color(0.14, 0.03, 0.03, 0.88)
	_result_bg.visible = true
	_result_label.visible = true
	_timer_label.visible = false
	_status_label.visible = false
	_objective_label.visible = false
	_suspicion_bar.visible = false
	_stamina_bar.visible = false
	hide_chaos_window()

	_primary_button.visible = success
	if success and has_next_level:
		_primary_action = ACTION_NEXT
		_primary_button.text = "NEXT LEVEL"
	elif success:
		_primary_action = ACTION_REPLAY_CAMPAIGN
		_primary_button.text = "PLAY AGAIN"
	_retry_button.text = "REPLAY LEVEL" if success else "RETRY"
	_result_actions.visible = true
	var focus_target := _primary_button if _primary_button.visible else _retry_button
	focus_target.call_deferred("grab_focus")

func show_pickup_bonus(text: String, color: Color = Color.WHITE) -> void:
	if not is_instance_valid(_hud):
		return
	hide_chaos_window()
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	label.offset_left = -200.0
	label.offset_right = -8.0
	label.offset_top = 46.0
	label.offset_bottom = 76.0
	_hud.add_child(label)
	var tween := label.create_tween().set_parallel(true)
	tween.tween_property(label, "offset_top", 14.0, 1.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 1.4)
	tween.finished.connect(label.queue_free)

func disable_result_actions() -> void:
	_primary_button.disabled = true
	_retry_button.disabled = true
	_menu_button.disabled = true

func _on_primary_pressed() -> void:
	result_action_requested.emit(_primary_action)
