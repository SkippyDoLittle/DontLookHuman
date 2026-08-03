# how_to_play.gd — Attach to a CanvasLayer node named "HowToPlayScreen" in Main.tscn.
# In the Inspector: set Layer = 15 so it renders above the HUD (layer 1) and TitleScreen (layer 10).
# Starts hidden; press H at any time (including title screen) to toggle.
extends CanvasLayer

var _close_button: Button

const _CONTENT := """DON'T LOOK HUMAN

CONTROLS
  WASD / Left Stick       Move
  Shift / Left Shoulder   Sprint  (depletes stamina bar)
  E / A                   Peck food
  Esc / Start             Pause / resume
  R / Y                   Retry current level
  Space / A               Start or continue
  Mouse / Right Stick     Rotate camera
  Scroll / D-pad Up/Down  Zoom camera
  H / B                   Close this screen

OBJECTIVE
  Steal all 5 food items scattered around the park,
  then reach the glowing green exit portal.

THE RANGER GETS SUSPICIOUS IF YOU:
  •  Sprint near them
  •  Walk in a straight line for too long
  •  Stare directly at them while moving
  •  Head straight toward food
  •  Stand alone, far from the other pigeons
  •  Wade in the pond
  •  Stand completely still in the open

TIPS
  Peck often while resting — it looks natural and lowers suspicion.
  Weave as you walk; pigeons don’t march in straight lines.
  Stay near the NPC pigeons to blend in."""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	# Dark overlay covers the whole screen so background content doesn't distract.
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.84)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Centered panel
	var panel := PanelContainer.new()
	panel.anchor_left   = 0.5
	panel.anchor_right  = 0.5
	panel.anchor_top    = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left   = -300
	panel.offset_right  = 300
	panel.offset_top    = -340
	panel.offset_bottom = 340
	add_child(panel)

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	panel.add_child(margin)

	# VBoxContainer holds the text label and the close button stacked vertically.
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	margin.add_child(vbox)

	var lbl := Label.new()
	lbl.text = _CONTENT
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(0.92, 0.92, 0.92))
	lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	vbox.add_child(lbl)

	# Close button — styled to match the main menu green button theme.
	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color          = Color(0.06, 0.13, 0.06, 0.88)
	style_normal.border_color       = Color(0.22, 0.52, 0.22, 1.0)
	for s in ["border_width_left", "border_width_top", "border_width_right", "border_width_bottom"]:
		style_normal.set(s, 1)
	for s in ["corner_radius_top_left", "corner_radius_top_right", "corner_radius_bottom_right", "corner_radius_bottom_left"]:
		style_normal.set(s, 4)

	var style_hover := StyleBoxFlat.new()
	style_hover.bg_color           = Color(0.11, 0.24, 0.11, 0.95)
	style_hover.border_color        = Color(0.35, 0.70, 0.35, 1.0)
	for s in ["border_width_left", "border_width_top", "border_width_right", "border_width_bottom"]:
		style_hover.set(s, 1)
	for s in ["corner_radius_top_left", "corner_radius_top_right", "corner_radius_bottom_right", "corner_radius_bottom_left"]:
		style_hover.set(s, 4)

	_close_button = Button.new()
	_close_button.text = "CLOSE"
	_close_button.custom_minimum_size = Vector2(0, 44)
	_close_button.add_theme_font_size_override("font_size", 16)
	_close_button.add_theme_color_override("font_color", Color(0.85, 0.98, 0.85, 1.0))
	_close_button.add_theme_stylebox_override("normal",  style_normal)
	_close_button.add_theme_stylebox_override("hover",   style_hover)
	_close_button.add_theme_stylebox_override("pressed", style_normal)
	_close_button.pressed.connect(_close_controls)
	vbox.add_child(_close_button)

func show_controls() -> void:
	visible = true
	_close_button.call_deferred("grab_focus")

func _close_controls() -> void:
	visible = false
	var controls_button := get_node_or_null("../PauseMenu/VBoxContainer/ControlsButton") as Button
	if controls_button != null and controls_button.is_visible_in_tree():
		controls_button.call_deferred("grab_focus")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_H and event.pressed and not event.echo:
		if visible:
			_close_controls()
		else:
			show_controls()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("ui_cancel"):
		_close_controls()
		get_viewport().set_input_as_handled()
