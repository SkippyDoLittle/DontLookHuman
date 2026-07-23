# =============================================================================
# SCRIPT: escape_zone.gd
# ATTACHED TO: The "EscapeZone" Node3D in Main.tscn (the top-level portal node)
# =============================================================================
#
# OVERVIEW
# --------
# This script manages the escape zone — the glowing portal the player must reach
# after collecting all food items. It does two things:
#
#   1. Controls visibility: the portal is HIDDEN until all food is collected,
#      then shown as the destination the player needs to reach.
#
#   2. Detects escape: each frame, it checks if the player is close enough to
#      the portal's centre. If so, the "escaped" flag is set and the game ends.
#
# HOW IT FITS INTO THE GAME
# -------------------------
# This script is on the VISUAL node (the mesh/particles that form the exit portal).
# There is ALSO an exit_area.gd script on an Area3D node ("ExitArea") that uses
# Godot's physics area detection to check for the player. The two scripts overlap
# in purpose — this one uses distance math, that one uses physics triggers.
# game_timer.gd checks escape_zone.gd's "escaped" property, not exit_area.gd's.
#
# PATH NOTE:
# The "@onready" paths use "../" (ONE level up) because this script is attached
# directly to the EscapeZone node, which is a direct child of Main:
#   Main → EscapeZone   ← this script lives here
# So to reach Main's other children: go up one level (../) to reach Main.
# Setting "visible" on EscapeZone hides all its children at once —
# the portal mesh, the exit label, and the exit area all disappear together.

# =============================================================================
# LINE 1 — INHERITANCE
# =============================================================================

# Extends Node3D because this node has a 3D position in the world.
# We use global_position to detect when the player is close enough to escape.
extends Node3D


# =============================================================================
# LINE 3 — EXPORTED VARIABLE
# =============================================================================

@export var exit_distance: float = 2.5
# exit_distance — How close the player must be to the escape zone centre
# for the escape to trigger. 2.5 Godot units is approximately within the
# visual boundary of the portal — close enough to feel like stepping into it.


# =============================================================================
# LINES 5–6 — @onready NODE REFERENCES
# =============================================================================

@onready var player: Node3D = get_node("../Player") as Node3D
# player — Reference to the Player node, two levels up in the scene tree.
# "../../" = go up to EscapeZone, then up to Main, then find "Player".
# We need the player's position to measure distance to the escape zone.
# "as Node3D" casts it to Node3D so we can access global_position.

@onready var objective_label: Label = get_node("../HUD/ObjectiveStatus") as Label
# objective_label — The HUD text label showing the current objective.
# When the player escapes, we update this label to show the victory message.
# "../../HUD/ObjectiveStatus" = go up to Main, then find HUD → ObjectiveStatus.


# =============================================================================
# LINE 8 — RUNTIME VARIABLE
# =============================================================================

var escaped: bool = false
# escaped — Flag that records whether the player has successfully escaped.

var _portal_revealed: bool = false
# _portal_revealed — Set to true the first time the portal becomes visible.
# Guards the portal reveal sound so it only plays once, not every frame.
# Starts as false. Set to true the moment the player reaches the exit zone
# with all food collected.
# game_timer.gd reads this variable via exit_area.get("escaped") — wait, actually
# game_timer.gd reads it from "exit_area" (the ExitArea/exit_area.gd node).
# This node's "escaped" flag is the one tracked by escape_zone.gd internally
# to prevent running the escape logic again after the first trigger.


# =============================================================================
# LINES 10–24 — _process(): Main logic, runs every frame
# =============================================================================

# _delta is the time since the last frame, received but not used here.
# The underscore prefix is a GDScript convention for "intentionally unused parameter."
# We don't need delta because this script doesn't do anything time-based —
# it only checks conditions and sets flags.

func _process(_delta: float) -> void:

	# If the player has already escaped, skip all logic.
	# Once escaped, we don't need to check anything further.
	if escaped:
		return   # Exit the function immediately.

	# Count how many food items remain in the "collectibles" group.
	# get_tree() returns the SceneTree — Godot's manager for the scene.
	# get_nodes_in_group("collectibles") returns an Array of all nodes tagged "collectibles."
	# .size() returns the number of elements in that Array.
	# When all food is collected and queue_free()'d, this returns 0.
	var items_remaining: int = get_tree().get_nodes_in_group("collectibles").size()

	# Show or hide this visual node based on whether all food is collected.
	# "visible" is a built-in property of every Node3D (and CanvasItem) in Godot.
	# Setting it to true makes the node (and all its children) visible.
	# Setting it to false hides everything.
	#
	# "items_remaining == 0" is a boolean expression:
	#   == means "equal to." If items_remaining IS zero, this evaluates to true.
	#   If not zero, it evaluates to false.
	# So: visible = true when all food is gone. visible = false while food remains.
	# The exit portal is invisible until all food is stolen — then it appears!
	visible = items_remaining == 0

	# Play the portal reveal chime the FIRST time the portal becomes visible.
	# Without the _portal_revealed guard this would fire every frame once all
	# food is collected, playing the chime thousands of times per second.
	if visible and not _portal_revealed:
		_portal_revealed = true
		SoundManager.play_portal()

	# If food remains, don't check for escape. The player can't escape early.
	if items_remaining > 0:
		return   # Stop here — nothing more to do this frame.

	# All food has been collected. Now check if the player is at the exit.
	#
	# WHY USE 2D DISTANCE INSTEAD OF 3D DISTANCE?
	# The player and the portal are both on the ground (Y ≈ 0), but floating-point
	# precision means their Y values might not be exactly equal. If we used 3D
	# distance_to(), a tiny Y difference could make the player appear farther away
	# than they really are in horizontal terms.
	# Using Vector2 with only X and Z (ignoring Y) measures pure horizontal distance —
	# which is what actually matters for "did the player step into the exit zone?"

	# Create a 2D vector from the player's X and Z world positions.
	var player_flat := Vector2(player.global_position.x, player.global_position.z)

	# Create a 2D vector from this zone's X and Z world positions.
	var exit_flat := Vector2(global_position.x, global_position.z)

	# Check if the horizontal distance between player and exit is within the threshold.
	# distance_to() on Vector2 computes: sqrt((x2-x1)² + (y2-y1)²)
	# (In 2D space, "y" here maps to the 3D "z" — it's just the Vector2's second component.)
	if player_flat.distance_to(exit_flat) <= exit_distance:
		# Player has reached the exit with all food! Trigger the escape.
		escaped = true

		# Update the objective label with the victory message.
		objective_label.text = "YOU ESCAPED! City Park complete."

		# Print to Godot's debug output console (not visible in the game itself).
		# Useful during development for quickly confirming the escape triggered.
		# print() outputs to the Output panel in the Godot editor.
		print("You escaped the park!")


# =============================================================================
# EXECUTION FLOW SUMMARY
# =============================================================================
#
# WHEN THE SCENE LOADS:
#   1. @onready references are filled in (player, objective_label).
#   2. No other setup is needed — the node starts invisible (Godot's default
#      depends on what was set in the editor, but escape_zone.gd controls it
#      dynamically via "visible = items_remaining == 0" every frame).
#
# EVERY FRAME:
#   1. If already escaped: do nothing.
#   2. Count remaining food in the "collectibles" group.
#   3. Set this node's visibility: show if all food collected, hide if food remains.
#   4. If food still remains: stop here.
#   5. Measure the 2D (horizontal) distance from player to this zone.
#   6. If player is within exit_distance:
#      a. Set escaped = true (prevents this triggering again).
#      b. Update objective label with victory text.
#      c. Print debug message to console.
#
# IMPORTANT NOTE:
# escape_zone.gd sets its own "escaped" flag but does NOT directly end the game.
# game_timer.gd reads "escaped" from exit_area (exit_area.gd, the Area3D node),
# not from this script. This script is primarily responsible for SHOWING/HIDING
# the visual portal and tracking escape for its own purposes. The definitive
# game-ending escape check comes from exit_area.gd (see that file for details).
