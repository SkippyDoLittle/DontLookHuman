# escape_zone.gd — Attached to the reusable EscapeZone scene.
# Owns portal visibility, its Area3D trigger, and escape validation.

extends Node3D

signal player_escaped

@onready var player:          Node3D = get_node("../Player") as Node3D
@onready var objective_label: Label  = get_node("../HUD/ObjectiveStatus") as Label
@onready var exit_area:       Area3D = $ExitArea

var escaped:          bool = false
var _portal_revealed: bool = false   # guard so the reveal chime fires only once

func _ready() -> void:
	exit_area.body_entered.connect(_on_body_entered)

func _process(_delta: float) -> void:
	if escaped:
		return

	var items_remaining: int = get_tree().get_nodes_in_group("collectibles").size()

	# Show the portal only when all food is collected.
	visible = items_remaining == 0

	if visible and not _portal_revealed:
		_portal_revealed = true
		SoundManager.play_portal()


func _on_body_entered(body: Node3D) -> void:
	if escaped or body != player:
		return

	var items_remaining: int = get_tree().get_nodes_in_group("collectibles").size()
	if items_remaining > 0:
		objective_label.text = "%d item(s) still out there — steal them first!" % items_remaining
		return

	escaped = true
	objective_label.text = "YOU ESCAPED!"
	player_escaped.emit()
