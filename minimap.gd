# minimap.gd — Attached to the Minimap Control node inside HUD
# Radar-style minimap: white=player, red=ranger, yellow=food, green=exit.

extends Control

const MAP_RADIUS:   float = 14.0    # world units from centre that map to the minimap edge
const MINIMAP_SIZE: float = 120.0   # pixel dimensions of the minimap square

@onready var _player:      Node3D   = get_node("../../Player")
@onready var _ranger:      Node3D   = get_node("../../Ranger")
@onready var _escape_zone: Node3D   = get_node("../../EscapeZone")

@onready var _player_dot: ColorRect = get_node("PlayerDot")
@onready var _ranger_dot: ColorRect = get_node("RangerDot")
@onready var _exit_dot:   ColorRect = get_node("ExitDot")
@onready var _food_dots:  Array     = [get_node("FoodDot1"), get_node("FoodDot2"), get_node("FoodDot3")]

var _food_nodes: Array = []   # references to PicnicFood nodes; checked each frame via is_instance_valid()

func _ready() -> void:
	var collectibles := get_tree().get_nodes_in_group("collectibles")
	for i in range(min(collectibles.size(), 3)):
		_food_nodes.append(collectibles[i] as Node3D)
	_exit_dot.visible = false

func _process(_delta: float) -> void:
	_place_dot(_player_dot, _player.global_position)
	_place_dot(_ranger_dot, _ranger.global_position)

	for i in range(_food_dots.size()):
		var dot: ColorRect = _food_dots[i]
		if i < _food_nodes.size() and is_instance_valid(_food_nodes[i]):
			_place_dot(dot, _food_nodes[i].global_position)
			dot.visible = true
		else:
			dot.visible = false   # food was collected

	# Mirror the escape zone's own visibility flag (set by escape_zone.gd when all food taken).
	_exit_dot.visible = _escape_zone.visible
	if _exit_dot.visible:
		_place_dot(_exit_dot, _escape_zone.global_position)

func _place_dot(dot: ColorRect, world_pos: Vector3) -> void:
	# Map world range [-MAP_RADIUS, +MAP_RADIUS] → pixel range [0, MINIMAP_SIZE].
	# Formula: (value / radius * 0.5 + 0.5) * size  (standard UV-remap)
	# World Z maps to screen Y; +Z (away from camera) = downward on the minimap.
	var px: float = (world_pos.x / MAP_RADIUS * 0.5 + 0.5) * MINIMAP_SIZE
	var py: float = (world_pos.z / MAP_RADIUS * 0.5 + 0.5) * MINIMAP_SIZE

	px = clamp(px, 0.0, MINIMAP_SIZE - dot.size.x)
	py = clamp(py, 0.0, MINIMAP_SIZE - dot.size.y)

	# Offset by half dot size so the dot is centred on the position, not corner-aligned.
	dot.position = Vector2(px - dot.size.x * 0.5, py - dot.size.y * 0.5)
