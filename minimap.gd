# =============================================================================
# SCRIPT: minimap.gd
# ATTACHED TO: The "Minimap" Control node inside the HUD CanvasLayer
# =============================================================================
#
# OVERVIEW
# --------
# This script drives a small radar-style minimap in the top-right corner of
# the screen. It shows the player where the ranger and uncollected food items
# are at all times — the two most important pieces of information in the game.
#
# HOW IT WORKS
# ------------
# The minimap is a small square (120×120 pixels). Each thing in the world
# (ranger, food, player, exit) has a coloured dot on the minimap. Every frame
# we convert that thing's 3D world position to a 2D pixel position on the
# minimap using a simple scale formula, then move the dot there.
#
# WHAT THE DOTS MEAN
#   White  (10×10) — You (the pigeon)
#   Red    ( 8×8 ) — The ranger
#   Yellow ( 6×6 ) — Uncollected food items (disappear when stolen)
#   Green  ( 8×8 ) — The exit zone (only appears once all food is collected)
#
# WHY A CONTROL NODE?
# Control is Godot's base class for 2D UI elements. It understands anchors,
# offsets, and sizes in screen-space — perfect for a HUD element that must
# stay pinned to a corner regardless of screen resolution.

# =============================================================================
# INHERITANCE
# =============================================================================

# Extends Control because this is a 2D UI element living inside a CanvasLayer.
# Control gives us anchor/offset layout tools and a defined 2D size.
extends Control


# =============================================================================
# CONSTANTS — Tuning the minimap's scale and appearance
# =============================================================================

const MAP_RADIUS: float = 14.0
# MAP_RADIUS — How many Godot world units from the centre the minimap edge
# represents. Objects further than 14 units from the world origin will be
# clamped to the edge of the minimap. The park's playable area is roughly
# 14 units in every direction, so this fits the whole park on screen.

const MINIMAP_SIZE: float = 120.0
# MINIMAP_SIZE — The width and height of the minimap in pixels.
# Must match the size set on this node in the scene editor.


# =============================================================================
# @onready — Node references filled in when the scene is ready
# =============================================================================

# "../../" means: go up to HUD (parent), then up to Main (grandparent),
# then find the named child node. All game objects live directly under Main.

@onready var _player: Node3D = get_node("../../Player")
# _player — The pigeon the user controls. We read its global_position
# to place the white "you are here" dot on the minimap.

@onready var _ranger: Node3D = get_node("../../Ranger")
# _ranger — The park ranger. We read its global_position to place the red dot.

@onready var _escape_zone: Node3D = get_node("../../EscapeZone")
# _escape_zone — The exit portal. We check its "visible" property to know
# whether to show the green exit dot (only visible when all food is collected).

# ── Dot nodes (the coloured squares drawn on the minimap) ────────────────────

@onready var _player_dot: ColorRect = get_node("PlayerDot")
@onready var _ranger_dot: ColorRect = get_node("RangerDot")
@onready var _exit_dot:   ColorRect = get_node("ExitDot")

# Three separate food dots, one per collectible item in the scene.
@onready var _food_dots: Array = [
	get_node("FoodDot1"),
	get_node("FoodDot2"),
	get_node("FoodDot3"),
]


# =============================================================================
# RUNTIME VARIABLE
# =============================================================================

var _food_nodes: Array = []
# _food_nodes — Holds references to the three PicnicFood Node3D objects.
# We fill this in _ready() by searching the "collectibles" group.
# When a food item is collected it gets queue_free()'d. We check
# is_instance_valid() each frame to know whether to hide its dot.


# =============================================================================
# _ready(): One-time setup when the scene loads
# =============================================================================

func _ready() -> void:
	# Grab all nodes currently in the "collectibles" group.
	# picnic_food.gd adds each food item to this group in its own _ready().
	# get_nodes_in_group() returns an Array of matching nodes.
	var collectibles := get_tree().get_nodes_in_group("collectibles")

	# Store up to 3 food node references so we can track their positions.
	# "min()" prevents an out-of-bounds error if fewer than 3 exist.
	# We cast each to Node3D so we can read global_position later.
	for i in range(min(collectibles.size(), 3)):
		_food_nodes.append(collectibles[i] as Node3D)

	# The exit dot starts hidden — the escape zone isn't visible yet.
	_exit_dot.visible = false


# =============================================================================
# _process(delta): Runs every frame — updates all dot positions
# =============================================================================

# "delta" is the time since the last frame but we don't use it here —
# we're just reading current positions and repositioning dots, not animating.

func _process(_delta: float) -> void:
	# Update the player and ranger dots every frame unconditionally.
	_place_dot(_player_dot, _player.global_position)
	_place_dot(_ranger_dot, _ranger.global_position)

	# ── Food dots ────────────────────────────────────────────────────────────
	# Each food item has its own dot. When food is collected, its Node3D is
	# deleted (queue_free). We use is_instance_valid() to detect this —
	# if the node no longer exists, we hide that dot.
	for i in range(_food_dots.size()):
		var dot: ColorRect = _food_dots[i]
		# Check whether we have a reference AND the node is still alive.
		if i < _food_nodes.size() and is_instance_valid(_food_nodes[i]):
			_place_dot(dot, _food_nodes[i].global_position)
			dot.visible = true
		else:
			# Food was collected — hide the dot.
			dot.visible = false

	# ── Exit dot ─────────────────────────────────────────────────────────────
	# The escape zone's "visible" property is toggled by escape_zone.gd:
	# true when all food is collected, false otherwise. Mirror that here.
	_exit_dot.visible = _escape_zone.visible
	if _exit_dot.visible:
		_place_dot(_exit_dot, _escape_zone.global_position)


# =============================================================================
# _place_dot(): Convert a 3D world position to a 2D minimap pixel position
# =============================================================================

func _place_dot(dot: ColorRect, world_pos: Vector3) -> void:
	# COORDINATE MAPPING
	# ------------------
	# The world uses X (left/right) and Z (forward/back) for horizontal movement.
	# The minimap is a 2D square where X = left/right and Y = up/down on screen.
	#
	# FORMULA: (world_component / MAP_RADIUS) remaps the world range [-14, +14]
	# to the range [-1, +1]. Multiplying by 0.5 and adding 0.5 shifts that to
	# [0, 1]. Multiplying by MINIMAP_SIZE gives a pixel position in [0, 120].
	#
	# This is identical to the standard UV-mapping formula used in shaders:
	#   pixel = (value_normalized * 0.5 + 0.5) * size
	#
	# WORLD Z → SCREEN Y
	# In the 3D world, Z points "into the screen" (away from the camera).
	# On the minimap, we map +Z (further into the world) to lower Y on screen
	# (visually downward). This matches how most top-down maps are oriented.

	var px: float = (world_pos.x / MAP_RADIUS * 0.5 + 0.5) * MINIMAP_SIZE
	var py: float = (world_pos.z / MAP_RADIUS * 0.5 + 0.5) * MINIMAP_SIZE

	# Clamp so dots never appear outside the minimap rectangle.
	# "clamp(value, min, max)" returns value clamped between min and max.
	# We subtract dot.size so a dot exactly at the edge doesn't overflow.
	px = clamp(px, 0.0, MINIMAP_SIZE - dot.size.x)
	py = clamp(py, 0.0, MINIMAP_SIZE - dot.size.y)

	# Subtract half the dot's size to centre the dot on the position,
	# rather than placing the top-left corner of the dot on the position.
	# dot.size is a Vector2 (width, height). ".x" and ".y" access each component.
	dot.position = Vector2(px - dot.size.x * 0.5, py - dot.size.y * 0.5)


# =============================================================================
# EXECUTION FLOW SUMMARY
# =============================================================================
#
# WHEN THE SCENE LOADS:
#   1. _ready() finds the 3 PicnicFood nodes via the "collectibles" group.
#   2. Exit dot is hidden (no food collected yet, exit isn't open yet).
#
# EVERY FRAME:
#   1. Player dot and ranger dot are repositioned using current world positions.
#   2. Each food dot: if the food still exists → show dot at its position.
#                     if the food was collected → hide the dot.
#   3. Exit dot: mirrors _escape_zone.visible — appears when all food is taken.
#
# COORDINATE FORMULA (for any dot):
#   minimap_x = (world_x / 14.0 * 0.5 + 0.5) * 120
#   minimap_y = (world_z / 14.0 * 0.5 + 0.5) * 120
#   dot.position = Vector2(minimap_x, minimap_y) - dot.size / 2
