# =============================================================================
# SCRIPT: park_visitor.gd
# ATTACHED TO: Each ParkVisitor node in Main.tscn
# =============================================================================
#
# OVERVIEW
# --------
# This script controls the human park visitors — ordinary people wandering
# around the park who have no idea a pigeon is stealing their food.
#
# Park visitors serve one purpose: making the park feel ALIVE. A park with only
# one ranger and three pigeons feels like an empty test level. Adding a few
# people sitting, strolling, and milling around turns it into a believable place.
#
# GAMEPLAY ROLE
# -------------
# Park visitors have NO interaction with the suspicion system. They don't notice
# the player, they don't affect the ranger, and the player can walk straight
# through them (they have no collision). They are purely visual background characters.
#
# BEHAVIOUR
# ---------
# Each visitor randomly alternates between two states:
#   WALK  — moving toward a random point within the park
#   PAUSE — standing still for a few seconds (like someone checking their phone
#            or watching the ducks)
# This creates an organic, unhurried feel — like real people in a park.
#
# HOW IT FITS INTO THE GAME
# -------------------------
# Park visitors are placed in Main.tscn as Node3D nodes with low-poly mesh
# children (same box/sphere style as the ranger). This script is attached to
# each one. Because each is a separate node with its own copy of these variables,
# they all wander independently and never synchronize.

# =============================================================================
# LINE 1 — INHERITANCE
# =============================================================================

# Extends CharacterBody3D so visitors have physics collision — they now bump
# into walls, benches, and boundary walls instead of phasing through them.
# Movement is handled via velocity + move_and_slide() in _physics_process(),
# with a _desired_move bridge variable set by the AI logic in _process().
extends CharacterBody3D


# =============================================================================
# EXPORTED VARIABLES: Tuning knobs visible in the Godot Inspector
# =============================================================================

@export var walk_speed: float = 0.9
# walk_speed — How fast (units per second) the visitor strolls.
# 0.9 is slightly slower than the pigeon's walk speed (1.2), giving humans a
# leisurely "afternoon in the park" pace. This also ensures the pigeon can
# easily weave around them.

@export var wander_radius: float = 7.5
# wander_radius — How far from the park centre the visitor is allowed to wander.
# 7.5 units keeps them within the visible park area without walking off the edge
# of the ground plane. Matches roughly with the ranger's patrol_radius (7.0)
# so visitors and ranger share the same general space.


# =============================================================================
# RUNTIME VARIABLES
# =============================================================================

var _target: Vector3 = Vector3.ZERO
# _target — The world position the visitor is currently walking toward.
# Updated each time the visitor picks a new destination.
# Vector3 holds three numbers: x (left/right), y (up/down), z (forward/back).
# The y is always kept at 0 so visitors walk on the ground, not into the air.

var _wait_timer: float = 0.0
# _wait_timer — Countdown timer (in seconds) for how long the visitor stands still.
# Counts down from a random value toward 0. When it hits 0, the visitor picks
# a new destination and starts walking again.

var _is_waiting: bool = false
# _is_waiting — True when the visitor is pausing; false when walking.
# This is a "state flag" — it determines which behaviour runs each frame.
# True = standing still and counting down the wait timer.
# False = walking toward _target.

var _desired_move: Vector3 = Vector3.ZERO
# _desired_move — Bridge between the AI logic (_process) and physics (_physics_process).
# Set to direction × speed while walking; left at zero while pausing.
# _physics_process applies it each physics tick via velocity + move_and_slide().


# =============================================================================
# _ready(): Runs once when this node enters the scene
# =============================================================================

func _ready() -> void:
	# Pick the very first destination immediately when the scene loads.
	# Without this, all visitors would stand at their spawn point until
	# the first wait timer expired.
	_pick_new_target()


# =============================================================================
# _process(delta): Runs every frame — drives the walk/pause behaviour
# =============================================================================

# "delta" is the time in seconds since the last frame (usually ~0.016 at 60fps).
# Multiplying distances and speeds by delta makes movement frame-rate independent:
# the visitor covers the same distance per second regardless of the game's fps.

func _process(delta: float) -> void:
	# Clear desired movement each frame. Only set below when actively walking.
	_desired_move = Vector3.ZERO

	# ── WAITING (PAUSED) STATE ────────────────────────────────────────────────

	if _is_waiting:
		# Count down the wait timer.
		# "-=" subtracts delta from _wait_timer each frame (counts down in real time).
		_wait_timer -= delta

		# When the timer reaches zero, stop waiting and pick a new place to walk to.
		if _wait_timer <= 0.0:
			_is_waiting = false
			_pick_new_target()

		# "return" exits the function here — skip the walking code below
		# while the visitor is standing still.
		return

	# ── WALKING STATE ─────────────────────────────────────────────────────────

	# Calculate the direction from this visitor's current position to the target.
	# Subtracting the visitor's position from the target gives a vector that
	# points FROM here TO there.
	var to_target := _target - global_position

	# Zero out the Y component so the visitor only moves horizontally.
	# Without this, any tiny height difference between positions could cause
	# the visitor to angle upward or downward while walking.
	to_target.y = 0.0

	# If the visitor is close enough to the target (within 0.5 units),
	# consider them "arrived" and transition to the waiting state.
	if to_target.length() < 0.5:
		_is_waiting = true
		# Wait for a random duration between 2 and 6 seconds.
		# randf_range(min, max) returns a random float in that range.
		# Different visitors get different wait times so they don't all
		# move in sync with each other — keeps the park feeling natural.
		_wait_timer = randf_range(2.0, 6.0)
		return

	# Calculate the movement direction as a unit vector (length = 1.0, pure direction).
	# .normalized() divides the vector by its own length, giving a direction
	# without any distance information embedded in it.
	var dir := to_target.normalized()

	# Set the desired velocity for this frame. _physics_process() applies it.
	_desired_move = dir * walk_speed

	# Rotate the visitor to face the direction they are walking.
	# look_at(target, up) rotates this node so its -Z axis points at the target point.
	# We build a look target at the same Y as the visitor (global_position.y) to
	# prevent the visitor from tilting their body up or down — they always face flat.
	var look_target := Vector3(
		global_position.x + dir.x,  # A point in front of the visitor horizontally
		global_position.y,           # Same height as the visitor (no tilt)
		global_position.z + dir.z   # A point in front of the visitor depth-wise
	)
	look_at(look_target, Vector3.UP)
	# Vector3.UP is (0, 1, 0) — the "up" reference direction that keeps the
	# visitor standing upright and not rolling sideways.


# =============================================================================
# _physics_process(delta): Apply movement to the physics engine
# =============================================================================

# Runs at a fixed 60 Hz rate. The AI in _process() sets _desired_move each frame;
# this function applies it as velocity, adds gravity, then calls move_and_slide().
# Separating AI logic from physics ensures movement is consistent and collision works.

func _physics_process(delta: float) -> void:
	# Apply horizontal movement from the AI.
	velocity.x = _desired_move.x
	velocity.z = _desired_move.z
	# Add gravity when airborne; clear it when standing on the ground.
	# CharacterBody3D does NOT apply gravity automatically — we must do it here.
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	else:
		velocity.y = 0.0
	# move_and_slide() moves by velocity and handles collision response.
	# Visitors now stop at walls and benches instead of walking through them.
	move_and_slide()


# =============================================================================
# _pick_new_target(): Choose a random destination within the park
# =============================================================================

func _pick_new_target() -> void:
	# Pick a random angle anywhere in a full 360° circle.
	# TAU is 2 × PI ≈ 6.28 — the radian equivalent of a full circle.
	# randf_range(0.0, TAU) returns a random angle anywhere around that circle.
	var angle: float = randf_range(0.0, TAU)

	# Pick a random distance from the centre, between 1.5 and wander_radius.
	# The minimum of 1.5 keeps visitors from bunching up right at the origin.
	var dist: float = randf_range(1.5, wander_radius)

	# Convert the angle and distance into an X/Z position using trigonometry.
	# This is the same "point on a circle" formula used elsewhere in the project:
	#   X = sin(angle) × distance
	#   Z = cos(angle) × distance
	# The Y is 0 — always on the ground plane.
	_target = Vector3(sin(angle) * dist, 0.0, cos(angle) * dist)


# =============================================================================
# EXECUTION FLOW SUMMARY
# =============================================================================
#
# WHEN THE SCENE LOADS:
#   1. _ready() runs: picks the first random destination.
#
# EVERY FRAME:
#   If waiting:
#     - Count down _wait_timer.
#     - When it hits 0: stop waiting, pick a new destination.
#   If walking:
#     - Measure distance to _target.
#     - If arrived (< 0.5 units away): start waiting for 2–6 seconds.
#     - Otherwise: move toward _target and rotate to face it.
#
# RESULT:
#   Each visitor wanders independently to random spots in the park, pauses
#   briefly, then moves on. They never interfere with gameplay — they are
#   purely visual background characters.
