# escape_zone.gd — Attached to the reusable EscapeZone scene.
# Owns portal visibility, its Area3D trigger, and escape validation.

extends Node3D

signal player_escaped
signal escape_blocked(remaining: int)

@onready var player: Node3D = get_node("../Player") as Node3D
@onready var exit_area: Area3D = $ExitArea

var escaped:          bool = false
var _portal_revealed: bool = false   # guard so the reveal chime fires only once

func _ready() -> void:
	add_to_group("escape_zones")
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
		escape_blocked.emit(items_remaining)
		return

	escaped = true
	player_escaped.emit()
