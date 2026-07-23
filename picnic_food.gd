# =============================================================================
# SCRIPT: picnic_food.gd
# ATTACHED TO: Each PicnicFood node (PicnicFood, PicnicFood2, PicnicFood3) in Main.tscn
# =============================================================================
#
# OVERVIEW
# --------
# This script is attached to each food item in the park — the bread roll, the
# french fries, and the grape cluster. Each instance (copy) of this script runs
# independently, managing that specific piece of food.
#
# The script does three things:
#   1. Registers the food in the "collectibles" group so the rest of the game
#      can find all food items at once using get_nodes_in_group().
#   2. Detects when the player pigeon walks close enough to "collect" it.
#   3. On collection: plays a sound, spawns a particle burst, updates the
#      objective text, and removes the food node from the scene.
#
# HOW IT FITS INTO THE GAME
# -------------------------
# Food items are the primary objective. The player must collect all three.
# ranger.gd checks for remaining food items to know if the player is "aiming at food."
# escape_zone.gd checks for remaining food to unlock the exit.
# game_timer.gd checks for remaining food to pulse the exit marker and show results.
# All of these checks work by counting members of the "collectibles" group — this
# script's add_to_group("collectibles") call in _ready() is what makes that possible.
#
# WHAT IS AN "INSTANCE"?
# When you place multiple copies of the same scene (or use the same script on
# multiple nodes), each copy is called an "instance." Each instance has its OWN
# copy of all the variables in the script — so PicnicFood's "collected" variable
# is separate from PicnicFood2's "collected" variable. They run in parallel,
# independently, without interfering with each other.

# =============================================================================
# LINE 1 — INHERITANCE
# =============================================================================

# Extends Node3D — the base class for any 3D positioned object in Godot.
# Food items have positions in the 3D world (so we can measure distance to the player),
# but they don't need physics (no collision body, no gravity — they just sit there).
# Node3D provides the global_position property we use for distance measurement.
extends Node3D


# =============================================================================
# LINES 3 — EXPORTED VARIABLE
# =============================================================================

@export var collect_distance: float = 1.2
# collect_distance — How close (in Godot units) the player must be to collect this food.
# 1.2 units ≈ just about touching the food item. Close enough to feel intentional,
# far enough that the player doesn't have to be pixel-perfect.
# Exported so each food item could have a different collect radius if needed.


# =============================================================================
# LINES 5–6 — @onready NODE REFERENCES
# =============================================================================

@onready var player: Node3D = get_node("../Player") as Node3D
# player — Reference to the Player node. We need the player's position to measure
# the distance from food to player each frame.
# "as Node3D" is a type cast — it tells GDScript to treat the returned node as a Node3D.
# This unlocks the Node3D-specific properties (like global_position).
# "../Player" means "go up to Main, then find the child named Player."

@onready var objective_label: Label = get_node("../HUD/ObjectiveStatus") as Label
# objective_label — The on-screen text label showing what the player should do next.
# We update this text each time food is collected to tell the player how many remain.
# "../HUD/ObjectiveStatus" = go up to Main → find HUD → find ObjectiveStatus Label inside.


# =============================================================================
# LINE 8 — RUNTIME VARIABLE
# =============================================================================

var collected: bool = false
# collected — Flag: has this food item already been collected?
# Starts false. Set to true the moment the player picks it up.
# We need this flag because queue_free() (removing the node) doesn't happen
# instantly — there's one frame of delay. Without this flag, the collection logic
# could run twice in that gap, causing double sounds and incorrect item counts.


# =============================================================================
# LINES 10–11 — _ready(): Register in the collectibles group
# =============================================================================

func _ready() -> void:
	# add_to_group() registers this node as a member of the named group.
	# A GROUP is like a tag — you can later find all tagged nodes with:
	#   get_tree().get_nodes_in_group("collectibles")
	# This returns an Array of all nodes tagged "collectibles" that are currently
	# in the scene. When a food item is collected and queue_free() is called,
	# Godot removes it from all groups automatically.
	#
	# Every script that needs to count remaining food uses this group mechanism.
	# By adding ourselves here, we participate in that count automatically.
	add_to_group("collectibles")


# =============================================================================
# LINES 13–26 — _process(): Check collection distance every frame
# =============================================================================

# _process(delta) runs once per rendered frame (typically 60 times per second).
# The parameter "_delta" has a leading underscore to indicate we're receiving
# it but intentionally not using it in this function. GDScript doesn't allow
# unused parameter names without this convention (it would generate a warning).

func _process(_delta: float) -> void:
	# If already collected, do nothing. This prevents any logic from running
	# on frames between queue_free() being called and the node actually being removed.
	if collected:
		return   # Exit the function immediately.

	# Measure the straight-line distance from this food's world position to the player's.
	# global_position is the node's position in the WORLD (not relative to parent).
	# distance_to() computes: sqrt((dx)² + (dy)² + (dz)²)
	# This is the 3D equivalent of the Pythagorean theorem — the actual "as the crow flies"
	# distance between two points in 3D space.
	if global_position.distance_to(player.global_position) <= collect_distance:
		# Player is close enough! Mark as collected to prevent any double-triggers.
		collected = true

		# Play the collect sound (the three-note ascending chime).
		SoundManager.play_collect()

		# Spawn the particle burst effect at this food's position (explained below).
		_spawn_burst()

		# Count how many food items will remain AFTER this one is removed.
		# get_nodes_in_group("collectibles").size() counts nodes in the group RIGHT NOW.
		# This still includes "this" node (queue_free hasn't run yet), so we subtract 1
		# to get the count AFTER this collection.
		var remaining: int = get_tree().get_nodes_in_group("collectibles").size() - 1

		if remaining <= 0:
			# All food collected! Tell the player to head to the exit.
			# "<=" instead of "==" to handle edge case where size() somehow returns negative.
			objective_label.text = "All items stolen! Reach the exit!"
		else:
			# More food remains. Show how many.
			# "%d" is a format placeholder for an integer.
			# "item(s)" — the (s) covers both singular and plural without needing an if.
			objective_label.text = "%d item(s) left to steal!" % remaining

		# Remove this node from the scene. queue_free() doesn't destroy it instantly —
		# it schedules destruction at the end of the current frame. This is safe because
		# Godot doesn't allow modifications to the scene tree during _process().
		# IMPORTANT: queue_free() also automatically removes this node from all groups,
		# so future calls to get_nodes_in_group("collectibles") won't include this node.
		queue_free()


# =============================================================================
# LINES 28–55 — _spawn_burst(): Create a particle burst effect at collection
# =============================================================================

# Creates a CPUParticles3D node from scratch, configures it to spray small golden
# spheres outward, and places it at the food's current world position.
# The particles fade out and the node removes itself automatically.

func _spawn_burst() -> void:

	# ── CREATE THE PARTICLE MATERIAL ─────────────────────────────────────────

	# StandardMaterial3D is the default Godot material — controls how a surface
	# looks: its color, whether it's shiny, whether it's lit by lights, etc.
	var mat := StandardMaterial3D.new()

	# vertex_color_use_as_albedo = true means: use the color set on the PARTICLES
	# (p.color below) as the material color, instead of albedo_color on the material.
	# Without this, the particle color setting would have no visual effect.
	mat.vertex_color_use_as_albedo = true

	# SHADING_MODE_UNSHADED means this material doesn't receive lighting.
	# Lit materials look darker or lighter based on where lights are in the scene.
	# Unshaded = always the same flat color regardless of lighting.
	# For brief particles, unshaded looks cleaner and more "game-like."
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# ── CREATE THE PARTICLE MESH ──────────────────────────────────────────────

	# The mesh defines the SHAPE of each particle — what each one looks like.
	# SphereMesh creates a 3D sphere.
	var mesh := SphereMesh.new()
	mesh.radius = 0.06           # Sphere radius: 0.06 units. Small, pea-sized.
	mesh.height = 0.12           # Sphere height (should be 2×radius for a true sphere).
	mesh.radial_segments = 4     # Number of horizontal polygons around the sphere.
	mesh.rings = 2               # Number of vertical rings. Low values = low-poly (diamond-like shape).
	# Low radial_segments (4) and rings (2) = a very simple, angular gem shape —
	# fits the low-poly art style of the game.

	# Apply the material to this mesh (surface index 0 = the first/only surface).
	mesh.surface_set_material(0, mat)

	# ── CREATE AND CONFIGURE THE PARTICLE SYSTEM ──────────────────────────────

	# CPUParticles3D is a Godot node that simulates particles on the CPU (processor)
	# rather than the GPU (graphics card). CPU particles work in every environment
	# and don't require special GPU features. For a small burst of 14 particles,
	# CPU particles are perfectly fast enough.
	var p := CPUParticles3D.new()

	p.emitting = true
	# emitting = true means the particles start emitting immediately when the node enters
	# the scene. Combined with one_shot = true, they burst once and stop.

	p.one_shot = true
	# one_shot = true: emit one burst then stop. (If false, it would loop continuously.)

	p.amount = 14
	# amount = how many particles are in the system total. 14 small spheres burst out.

	p.lifetime = 0.55
	# lifetime = how long each particle lives (in seconds) before disappearing.
	# 0.55 seconds = just over half a second. The burst is quick and punchy.

	p.explosiveness = 1.0
	# explosiveness = how quickly particles are emitted. 1.0 = ALL particles are
	# released simultaneously at the very start (a true explosion/burst effect).
	# 0.0 would emit them evenly spread over the lifetime.

	p.direction = Vector3.UP
	# direction = the central direction particles travel. UP = (0, 1, 0).
	# Combined with spread = 180, particles spray in ALL directions (full sphere).

	p.spread = 180.0
	# spread = the half-angle cone of possible directions from "direction" (in degrees).
	# 180 degrees = particles can go anywhere in a full sphere around the emit point.

	p.gravity = Vector3(0.0, -6.0, 0.0)
	# gravity = a constant force applied to particles each second (in units/sec²).
	# -6.0 on Y = pulls particles downward at 6 units per second² (like weak gravity).
	# This makes them arc upward then fall, like a fountain.

	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 4.5
	# Each particle gets a random initial speed between 2.5 and 4.5 units/second.
	# This variation makes the burst look natural rather than uniform.

	p.color = Color(1.0, 0.85, 0.2)
	# The color of the particles: R=1.0 (full red), G=0.85 (high green), B=0.2 (low blue).
	# This produces a golden-yellow color — like crumbs or seeds scattering from food.

	p.mesh = mesh
	# Assign our low-poly sphere mesh as the shape of each particle.
	# (On CPUParticles3D, the shape is set via the .mesh property, not .draw_pass_1
	# which belongs to GPUParticles3D — an important distinction.)

	# ── ADD TO THE SCENE AND POSITION ─────────────────────────────────────────

	# Add the particle node as a child of the PARENT of this food item (Main scene).
	# WHY the PARENT and not this node itself?
	# Because we're about to call queue_free() on this food node, which would destroy
	# all its children too — including the particles, before they finish playing.
	# By adding to the parent, the particles outlive the food node's destruction.
	get_parent().add_child(p)

	# Set the particle emitter's world position to match the food's current position.
	# This must be done AFTER add_child(), because global_position is only meaningful
	# when a node is part of the scene tree.
	p.global_position = global_position

	# ── AUTO-CLEANUP ──────────────────────────────────────────────────────────

	# Connect the "finished" signal to queue_free() to auto-destroy the particle node.
	# A SIGNAL is like a notification system — when something happens (the particles
	# finish playing), Godot "emits" the "finished" signal.
	# .connect(callable) means: "When 'finished' is emitted, call this function."
	# p.queue_free is the function to call — it destroys the particle node.
	# Result: the particle node deletes itself when its animation is complete.
	# Without this, the node would remain in the scene forever doing nothing.
	p.finished.connect(p.queue_free)


# =============================================================================
# EXECUTION FLOW SUMMARY
# =============================================================================
#
# WHEN THE SCENE LOADS (for each food item):
#   1. _ready() runs: this food registers in the "collectibles" group.
#
# EVERY FRAME:
#   1. If already collected: do nothing.
#   2. Measure distance from this food to the player.
#   3. If distance <= collect_distance:
#      a. Mark as collected (set flag to prevent double-triggering).
#      b. Play the collect chime sound.
#      c. Spawn the golden particle burst at this position.
#      d. Count remaining food and update the objective label.
#      e. Remove this node from the scene (queue_free).
#
# THE PARTICLE BURST (one-time, after collection):
#   - 14 golden low-poly spheres burst outward in all directions.
#   - They arc and fall due to gravity.
#   - After 0.55 seconds, each particle disappears.
#   - When the system finishes, the CPUParticles3D node removes itself.
