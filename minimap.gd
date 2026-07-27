# minimap.gd — Attached to the Minimap Control node inside HUD
# Compass-style minimap: the container stays fixed (no spinning box).
# Instead, each dot's position is manually rotated around the minimap centre
# based on the camera yaw, so the direction the player faces always points up.
# white=player (centre), red=ranger, yellow=food, green=exit.

extends Control

const MAP_RADIUS:   float = 14.0    # world units that map to the minimap edge
const MINIMAP_SIZE: float = 120.0   # pixel size of the minimap square

@onready var _player:      Node3D   = get_node("../../Player")
@onready var _spring_arm:  Node3D   = get_node("../../Player/SpringArm3D")
@onready var _ranger:      Node3D   = get_node("../../Ranger")
@onready var _ranger2:     Node3D   = get_node_or_null("../../Ranger2")
@onready var _escape_zone: Node3D   = get_node("../../EscapeZone")

@onready var _player_dot:  ColorRect = get_node("PlayerDot")
@onready var _ranger_dot:  ColorRect = get_node("RangerDot")
@onready var _ranger2_dot: ColorRect = get_node_or_null("RangerDot2")
@onready var _exit_dot:    ColorRect = get_node("ExitDot")
@onready var _food_dots:  Array     = [get_node("FoodDot1"), get_node("FoodDot2"), get_node("FoodDot3"), get_node("FoodDot4"), get_node("FoodDot5")]

var _food_nodes: Array = []        # PicnicFood node refs; checked each frame via is_instance_valid()
var _food_nodes_ready: bool = false  # stays false until first _process, so lookup runs after all _ready() calls

func _ready() -> void:
	_exit_dot.visible = false

func _process(_delta: float) -> void:
	# Populate food nodes on the very first frame — by then all nodes have run _ready()
	# and added themselves to the "collectibles" group. Doing this in _ready() is too early.
	if not _food_nodes_ready:
		_food_nodes_ready = true
		var collectibles := get_tree().get_nodes_in_group("collectibles")
		for i in range(min(collectibles.size(), 5)):
			_food_nodes.append(collectibles[i] as Node3D)

	# The container no longer spins — dots move instead.
	# Player stays pinned to centre.
	_pin_to_centre(_player_dot)

	_place_dot(_ranger_dot, _ranger.global_position)

	if _ranger2 != null and _ranger2_dot != null:
		_ranger2_dot.visible = true
		_place_dot(_ranger2_dot, _ranger2.global_position)
	elif _ranger2_dot != null:
		_ranger2_dot.visible = false

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

func _pin_to_centre(dot: ColorRect) -> void:
	dot.position = Vector2(
		MINIMAP_SIZE * 0.5 - dot.size.x * 0.5,
		MINIMAP_SIZE * 0.5 - dot.size.y * 0.5
	)

func _place_dot(dot: ColorRect, world_pos: Vector3) -> void:
	# Offset of this object from the player in world space.
	var dx: float = world_pos.x - _player.global_position.x
	var dz: float = world_pos.z - _player.global_position.z

	# Rotate the offset so the camera's forward direction always points up on the minimap.
	# SpringArm3D rotation.y is the camera yaw; negating it gives the angle we need to spin
	# the dots so that "what's ahead of the player" appears at the top.
	var a: float = -_spring_arm.rotation.y
	var rdx: float = dx * cos(a) - dz * sin(a)
	var rdz: float = dx * sin(a) + dz * cos(a)

	# Convert rotated world offset to minimap pixel position.
	var px: float = MINIMAP_SIZE * 0.5 + rdx / MAP_RADIUS * (MINIMAP_SIZE * 0.5)
	var py: float = MINIMAP_SIZE * 0.5 + rdz / MAP_RADIUS * (MINIMAP_SIZE * 0.5)

	px = clamp(px, 0.0, MINIMAP_SIZE - dot.size.x)
	py = clamp(py, 0.0, MINIMAP_SIZE - dot.size.y)

	dot.position = Vector2(px - dot.size.x * 0.5, py - dot.size.y * 0.5)
