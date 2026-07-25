# escape_zone.gd — Attached to the EscapeZone Node3D in Main.tscn
# Controls portal visibility (hidden until all food collected) and distance-based escape detection.
# Note: game_timer.gd reads "escaped" from exit_area.gd (the Area3D), not this script.

extends Node3D

@export var exit_distance: float = 2.5

@onready var player:          Node3D = get_node("../Player") as Node3D
@onready var objective_label: Label  = get_node("../HUD/ObjectiveStatus") as Label

var escaped:          bool = false
var _portal_revealed: bool = false   # guard so the reveal chime fires only once

func _process(_delta: float) -> void:
	if escaped:
		return

	var items_remaining: int = get_tree().get_nodes_in_group("collectibles").size()

	# Show the portal only when all food is collected.
	visible = items_remaining == 0

	if visible and not _portal_revealed:
		_portal_revealed = true
		SoundManager.play_portal()

	if items_remaining > 0:
		return

	# Use 2D (XZ) distance to ignore any tiny Y-axis differences between player and portal.
	var player_flat := Vector2(player.global_position.x, player.global_position.z)
	var exit_flat   := Vector2(global_position.x, global_position.z)

	if player_flat.distance_to(exit_flat) <= exit_distance:
		escaped = true
		objective_label.text = "YOU ESCAPED! City Park complete."
		print("You escaped the park!")
