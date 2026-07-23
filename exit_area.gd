# =============================================================================
# SCRIPT: exit_area.gd
# ATTACHED TO: The "ExitArea" node (an Area3D) inside EscapeZone in Main.tscn
# =============================================================================
#
# OVERVIEW
# --------
# This script handles the PHYSICS-BASED escape detection — when the player's
# collision shape enters the exit area's collision shape, the game knows the
# player has physically stepped into the exit zone.
#
# This is the DEFINITIVE escape check: game_timer.gd reads THIS node's "escaped"
# variable (not escape_zone.gd's "escaped") to decide whether to call _finish(true).
#
# HOW IT DIFFERS FROM escape_zone.gd:
# - escape_zone.gd: Controls the VISUAL portal. Checks every frame using distance math.
#   Its "escaped" flag is internal — used to stop its own repeated checks.
# - exit_area.gd: Controls the PHYSICS TRIGGER. Uses Godot's Area3D collision system.
#   Its "escaped" flag is what game_timer.gd actually reads to end the game.
#
# WHY HAVE TWO SCRIPTS FOR THE SAME ZONE?
# This is a design overlap that emerged during development. Having both provides
# redundancy — if one method misses the trigger (e.g., the player moves very fast),
# the other catches it. The physics-based Area3D method (this script) is generally
# more reliable for precise collision detection.
#
# WHAT IS AN Area3D?
# Area3D is a special Godot node that defines a 3D region (using a CollisionShape3D
# child node). It doesn't physically block movement — it's "invisible" to physics.
# Instead, it detects when other physics bodies ENTER or EXIT it and emits signals.
# Think of it like a motion-sensor beam: it doesn't stop you, but it knows when you cross it.
#
# WHAT IS A SIGNAL?
# A signal is Godot's event notification system. When something happens — like a body
# entering an Area3D — the node "emits" a signal. Other code can "connect" to that
# signal to run a function when the event occurs.
# Signals are like setting up a tripwire alarm: you connect the alarm (signal) to an
# action (a function), and it automatically triggers when the wire is tripped.

# =============================================================================
# LINE 1 — INHERITANCE
# =============================================================================

# Extends Area3D — Godot's built-in node for a 3D trigger region.
# By extending Area3D, this script inherits all the area's built-in signals,
# including "body_entered" — emitted when a physics body (like CharacterBody3D)
# enters the area's collision shape.
extends Area3D


# =============================================================================
# LINE 3 — @onready NODE REFERENCE
# =============================================================================

@onready var objective_label: Label = get_node("../../HUD/ObjectiveStatus") as Label
# objective_label — Reference to the HUD label showing the current objective.
# "../../" goes up two levels: from ExitArea up to EscapeZone, then up to Main.
# Then digs down to find HUD → ObjectiveStatus.
# We update this label when the player escapes (to show a victory message)
# or when they enter early (to remind them they still need to steal food).


# =============================================================================
# LINE 5 — RUNTIME VARIABLE
# =============================================================================

var escaped: bool = false
# escaped — The definitive escape flag. Set to true when the player steps into
# this Area3D with all food collected. game_timer.gd reads this every frame via:
#   bool(exit_area.get("escaped"))
# Once true, game_timer.gd calls _finish(true, "ESCAPED!") to end the game.


# =============================================================================
# LINES 7–8 — _ready(): Connect the physics signal
# =============================================================================

func _ready() -> void:
	# Connect the "body_entered" SIGNAL to our handler function "_on_body_entered".
	# "body_entered" is a built-in signal from Area3D. It fires whenever a physics
	# body (CharacterBody3D, RigidBody3D, etc.) enters this area's collision region.
	#
	# THE SIGNAL/CONNECT PATTERN:
	# Instead of checking distance every frame (like escape_zone.gd does),
	# we use event-driven programming: "when X happens, call Y."
	# This is more efficient — Godot's physics engine handles the detection,
	# and our function only runs when a body actually enters.
	#
	# body_entered.connect(callable) registers our _on_body_entered function
	# to be called automatically whenever the signal fires.
	body_entered.connect(_on_body_entered)


# =============================================================================
# LINES 10–12 — _process(): Listen for restart after escaping
# =============================================================================

func _process(_delta: float) -> void:
	# After a successful escape, listen for the restart key.
	# "escaped and" means "only check restart input if we've already escaped."
	# Without this, pressing R could reload the scene even before the game ends.
	if escaped and Input.is_action_just_pressed("restart"):
		# Reload the scene to start a new game.
		get_tree().reload_current_scene()

	# WHY HANDLE RESTART HERE?
	# This is somewhat redundant with game_timer.gd (which also handles restart
	# when game_over is true). Having it here as well ensures the player can always
	# restart even if there's a timing issue between these scripts.


# =============================================================================
# LINES 14–28 — _on_body_entered(): Called when something enters the Area3D
# =============================================================================

# This function is called automatically by Godot when the "body_entered" signal fires.
# The "body" parameter is the Node3D that entered the area — could be the player,
# an NPC, or anything else with a physics body.

func _on_body_entered(body: Node3D) -> void:
	# Guard: if already escaped, ignore any further entries.
	# This prevents the escape from triggering twice if the player steps
	# in and out of the area while game_timer.gd is processing the win.
	if escaped:
		return

	# Check if the entering body is the Player.
	# "body.name" is the node's name as set in the Godot editor.
	# "!=" means "not equal to" (the opposite of ==).
	# If anything OTHER than the Player enters (e.g., an NPC pigeon wanders in),
	# we ignore it entirely.
	if body.name != "Player":
		return

	# The Player entered the area. Now check if all food has been collected.
	# get_nodes_in_group("collectibles") returns all nodes currently in the group.
	# .size() returns the count. If > 0, food items still exist.
	var items_remaining: int = get_tree().get_nodes_in_group("collectibles").size()

	if items_remaining > 0:
		# Player entered the exit zone but hasn't stolen everything yet.
		# Show a reminder message without triggering the escape.
		# "%d" formats the integer items_remaining into the string.
		objective_label.text = "%d item(s) still out there — steal them first!" % items_remaining
		return   # Don't set escaped — let the player go back and steal more food.

	# All food has been collected AND the player just entered the exit area.
	# Trigger the successful escape!
	escaped = true

	# Show the victory message on the objective label.
	objective_label.text = "YOU ESCAPED! Press R to play again."

	# Print a debug message to the Godot editor's console/output.
	print("You escaped the park!")


# =============================================================================
# EXECUTION FLOW SUMMARY
# =============================================================================
#
# WHEN THE SCENE LOADS:
#   1. @onready fills in objective_label reference.
#   2. _ready() runs: connects the body_entered signal to _on_body_entered.
#      From this point, Godot's physics engine automatically monitors this area.
#
# DURING GAMEPLAY:
#   _process() runs every frame but does almost nothing until escaped = true.
#   The real work happens in _on_body_entered(), which fires by physics event (not per-frame).
#
# WHEN THE PLAYER ENTERS THE EXIT AREA:
#   1. body_entered signal fires — Godot calls _on_body_entered(player).
#   2. Guard check: is this the Player? Is escaped already true? Skip if so.
#   3. Count remaining food items.
#   4. If food remains: show a "steal first!" reminder, return.
#   5. If no food remains:
#      a. Set escaped = true.
#      b. Update objective label with victory message.
#      c. Print debug message.
#   6. game_timer.gd, reading escaped each frame, detects "escaped = true"
#      and calls _finish(true, "ESCAPED!") to officially end the game.
#
# AFTER ESCAPE:
#   _process() detects the restart key (R) and reloads the scene.
