extends Node3D

@export var exit_distance: float = 2.5

@onready var player: Node3D = get_node("../../Player") as Node3D
@onready var objective_label: Label = get_node("../../HUD/ObjectiveStatus") as Label

var escaped: bool = false

func _process(_delta: float) -> void:
	if escaped:
		return

	var items_remaining: int = get_tree().get_nodes_in_group("collectibles").size()
	visible = items_remaining == 0 
	if items_remaining > 0:
		return

	var player_flat := Vector2(player.global_position.x, player.global_position.z)
	var exit_flat := Vector2(global_position.x, global_position.z)
	if player_flat.distance_to(exit_flat) <= exit_distance:
		escaped = true
		objective_label.text = "YOU ESCAPED! City Park complete."
		print("You escaped the park!")
