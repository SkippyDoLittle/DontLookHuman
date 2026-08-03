class_name SessionHUDController
extends RefCounted

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

func add_controls_hint() -> Label:
	_help_hint = Label.new()
	_help_hint.text = "H — controls"
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
	has_next_level: bool
) -> void:
	var flavor: String
	if headline == "ESCAPED!":
		flavor = "\"Just a pigeon. Nothing to see here.\""
	elif headline == "CAUGHT!":
		flavor = "Caught red-beaked by the ranger!"
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

	if success and has_next_level:
		_result_label.text += "\n\nSPACE — next level    R — restart"
	elif success:
		_result_label.text += "\n\n★  ALL LEVELS COMPLETE!  ★\nPress R to play again"
	else:
		_result_label.text += "\n\nPress R to retry"

	_result_label.modulate = Color(0.35, 1.0, 0.45) if success else Color(1.0, 0.35, 0.35)
	_result_bg.color = Color(0.03, 0.14, 0.06, 0.88) if success else Color(0.14, 0.03, 0.03, 0.88)
	_result_bg.visible = true
	_result_label.visible = true
	_timer_label.visible = false
	_status_label.visible = false
	_objective_label.visible = false
	_suspicion_bar.visible = false
	_stamina_bar.visible = false
