# how_to_play.gd — Attach to a CanvasLayer node named "HowToPlayScreen" in Main.tscn.
# In the Inspector: set Layer = 15 so it renders above the HUD (layer 1) and TitleScreen (layer 10).
# Starts hidden; press H at any time (including title screen) to toggle.
extends CanvasLayer

const _CONTENT := """DON'T LOOK HUMAN

CONTROLS
  WASD        Move
  Shift       Sprint  (depletes stamina bar)
  Space       Peck    (reduces suspicion while stationary)
  Esc         Pause

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
  Stay near the NPC pigeons to blend in.

Press H to close"""

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
	panel.offset_left   = -270
	panel.offset_right  = 270
	panel.offset_top    = -280
	panel.offset_bottom = 280
	add_child(panel)

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	panel.add_child(margin)

	var lbl := Label.new()
	lbl.text = _CONTENT
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(0.92, 0.92, 0.92))
	lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	margin.add_child(lbl)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_H and event.pressed and not event.echo:
		visible = not visible
		get_viewport().set_input_as_handled()
