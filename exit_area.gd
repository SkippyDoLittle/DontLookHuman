# exit_area.gd — Attached to the ExitArea Area3D inside EscapeZone
# Physics-based escape trigger. game_timer.gd reads THIS node's "escaped" flag to end the game.

extends Area3D

@onready var objective_label: Label = get_node("../../HUD/ObjectiveStatus") as Label

var escaped: bool = false

func _ready() -> void:
	# body_entered fires when any physics body enters the Area3D collision shape.
	# Event-driven: more reliable than checking distance every frame.
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if escaped:
		return
	if body.name != "Player":
		return

	var items_remaining: int = get_tree().get_nodes_in_group("collectibles").size()
	if items_remaining > 0:
		objective_label.text = "%d item(s) still out there — steal them first!" % items_remaining
		return

	escaped = true
	objective_label.text = "YOU ESCAPED! Press R to play again."
	print("You escaped the park!")
