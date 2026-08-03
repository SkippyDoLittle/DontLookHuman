# minimap.gd — Attached to the Minimap Control node inside HUD.
# Compass-style minimap: the player stays centered while entity dots rotate
# around them so the camera's forward direction always points up.

extends Control

const MINIMAP_SIZE: float = 120.0

@export_range(1.0, 100.0, 0.5) var map_radius: float = 14.0

@onready var _player:      Node3D = get_node("../../Player")
@onready var _spring_arm:  Node3D = get_node("../../Player/SpringArm3D")
@onready var _escape_zone: Node3D = get_node("../../EscapeZone")

@onready var _player_dot: ColorRect = get_node("PlayerDot")
@onready var _exit_dot:   ColorRect = get_node("ExitDot")

var _ranger_dots: Array[ColorRect] = []
var _food_dots:   Array[ColorRect] = []

func _ready() -> void:
	# Reuse the existing scene-authored dots first, then grow these pools when a
	# level contains more entities than the original two-ranger/five-food layout.
	_ranger_dots = _find_existing_dots("RangerDot")
	_food_dots = _find_existing_dots("FoodDot")
	_exit_dot.visible = false

func _process(_delta: float) -> void:
	_pin_to_centre(_player_dot)

	var rangers := get_tree().get_nodes_in_group("rangers")
	_ensure_dot_pool(
		_ranger_dots,
		rangers.size(),
		"RangerDot",
		Vector2(8.0, 8.0),
		Color(1.0, 0.2, 0.2)
	)
	for i in rangers.size():
		var ranger := rangers[i] as Node3D
		_place_dot(_ranger_dots[i], ranger.global_position)

	var collectibles := get_tree().get_nodes_in_group("collectibles")
	_ensure_dot_pool(
		_food_dots,
		collectibles.size(),
		"FoodDot",
		Vector2(9.0, 9.0),
		Color(1.0, 0.9, 0.2)
	)
	for i in collectibles.size():
		var collectible := collectibles[i] as Node3D
		_place_dot(_food_dots[i], collectible.global_position)

	# Mirror the escape zone's own visibility flag, which changes when all food
	# has been collected.
	_exit_dot.visible = _escape_zone.visible
	if _exit_dot.visible:
		_place_dot(_exit_dot, _escape_zone.global_position)

func _find_existing_dots(prefix: String) -> Array[ColorRect]:
	var dots: Array[ColorRect] = []
	for child in get_children():
		if child is ColorRect and String(child.name).begins_with(prefix):
			dots.append(child as ColorRect)
	return dots

func _ensure_dot_pool(
	dots: Array[ColorRect],
	required: int,
	prefix: String,
	dot_size: Vector2,
	dot_color: Color
) -> void:
	while dots.size() < required:
		var dot := ColorRect.new()
		dot.name = "%s%d" % [prefix, dots.size() + 1]
		dot.size = dot_size
		dot.color = dot_color
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(dot)
		dots.append(dot)

	for i in dots.size():
		dots[i].visible = i < required

func _pin_to_centre(dot: ColorRect) -> void:
	dot.position = Vector2(
		MINIMAP_SIZE * 0.5 - dot.size.x * 0.5,
		MINIMAP_SIZE * 0.5 - dot.size.y * 0.5
	)

func _place_dot(dot: ColorRect, world_pos: Vector3) -> void:
	var dx: float = world_pos.x - _player.global_position.x
	var dz: float = world_pos.z - _player.global_position.z

	# Rotate offsets around the player so camera-forward appears at the top.
	var angle: float = -_spring_arm.rotation.y
	var rotated_x: float = dx * cos(angle) - dz * sin(angle)
	var rotated_z: float = dx * sin(angle) + dz * cos(angle)

	var px: float = MINIMAP_SIZE * 0.5 + rotated_x / map_radius * (MINIMAP_SIZE * 0.5)
	var py: float = MINIMAP_SIZE * 0.5 + rotated_z / map_radius * (MINIMAP_SIZE * 0.5)

	px = clamp(px, 0.0, MINIMAP_SIZE - dot.size.x)
	py = clamp(py, 0.0, MINIMAP_SIZE - dot.size.y)
	dot.position = Vector2(px - dot.size.x * 0.5, py - dot.size.y * 0.5)
