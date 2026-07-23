# =============================================================================
# SCRIPT: npc_animal.gd
# ATTACHED TO: NPC_Animal, NPC_Animal2, NPC_Animal3 nodes in Main.tscn
# =============================================================================
#
# OVERVIEW
# --------
# This script controls the background NPC (Non-Player Character) pigeons —
# the other birds wandering the park that are NOT controlled by the player.
#
# NPC PIGEONS SERVE TWO GAMEPLAY PURPOSES:
#   1. They help the player "blend in." ranger.gd checks whether NPC pigeons
#      are near the player — if none are, the player looks suspicious (isolated).
#      Staying close to the flock reduces the "Acting alone" suspicion source.
#
#   2. They make the park feel alive. A world with only the player and the ranger
#      would feel empty. Background characters add believability.
#
# WHAT THE NPCs DO:
# Each NPC alternates randomly between two behaviours:
#   WANDER — Walking in a random direction for 1–3 seconds.
#   PAUSE  — Standing still for 0.7–2 seconds, pecking at the ground.
# When the park ranger gets too close, NPCs FLEE — running away from the ranger.
#
# HOW IT FITS INTO THE GAME
# -------------------------
# The NPC pigeons look and move like the player's pigeon (same animation system:
# head-bob while walking, peck animation while paused). This visual consistency
# helps the player blend in — they look like "just another pigeon."
# ranger.gd uses the npc_animals array to check separation distance.

# =============================================================================
# LINE 1 — INHERITANCE
# =============================================================================

# Extends CharacterBody3D — the same physics class as the player and ranger.
# CharacterBody3D understands gravity and collision: NPCs now stay on the
# ground and bump into walls, benches, and boundary walls rather than
# phasing through them. Movement uses velocity + move_and_slide() in
# _physics_process(), with a _desired_move bridge set by the AI logic in _process().
extends CharacterBody3D


# =============================================================================
# LINES 3–11 — EXPORTED VARIABLES
# =============================================================================

@export var speed: float = 1.2
# speed — Walking speed (units/second) during normal wander behaviour.
# Matches the player's walk_speed so NPCs look like the same kind of bird.

@export var flee_speed: float = 2.2
# flee_speed — Running speed when fleeing from the ranger.
# Faster than normal walking but slower than the player's run speed (4.0).
# NPCs flee at a moderate pace — they're scared but not panicking.

@export var wander_radius: float = 8.0
# wander_radius — The area (±8 units from centre) within which NPCs wander.
# If an NPC reaches the boundary, it turns back toward the centre.
# A slightly larger radius than the ranger's patrol_radius (7.0) ensures NPCs
# spread around the full park area.

@export var flee_distance: float = 4.5
# flee_distance — How close the ranger must be (in units) for an NPC to start fleeing.
# 4.5 units is close enough that the NPC is "spooked" by the ranger's approach,
# triggering a realistic bird-fleeing reaction.


# =============================================================================
# LINES 8–11 — CONSTANTS: Peck animation parameters
# =============================================================================

# These constants mirror the same values in player.gd to make the NPC peck
# animation look identical to the player's. See player.gd for full explanations.
const PECK_FORWARD: float = 0.12
# How far forward the head moves during a peck.

const PECK_DROP: float = 0.13
# How far down the head drops during a peck.

const PECK_DURATION: float = 0.55
# How long one peck animation cycle takes in seconds.

const PECK_STRIKE_FRAC: float = 0.40
# What fraction (40%) of the peck is the strike phase; the rest is recovery.

const HEAD_BOB_Z: float = 0.05
# Maximum forward/backward displacement of head during walk bob.
# Slightly less than the player's (0.06) — subtly different to distinguish NPCs.


# =============================================================================
# LINES 14–16 — @onready NODE REFERENCES
# =============================================================================

@onready var head: MeshInstance3D = $PigeonVisual/Head
# head — The NPC pigeon's head mesh. Animated during peck and walk-bob.
# "$PigeonVisual/Head" = find child "PigeonVisual", then its child "Head".

@onready var beak: MeshInstance3D = $PigeonVisual/Beak
# beak — The NPC pigeon's beak mesh. Moves in sync with the head.

@onready var ranger: Node3D = get_node_or_null("../Ranger")
# ranger — Reference to the Ranger node, found one level up in the scene.
# get_node_or_null() returns null if "Ranger" doesn't exist — safer than get_node()
# which would crash. The null case is handled in _process() with is_instance_valid().
# We need the ranger's position to know whether to flee.


# =============================================================================
# LINES 18–30 — RUNTIME VARIABLES
# =============================================================================

var direction: Vector3 = Vector3.FORWARD
# direction — The NPC's current movement direction vector.
# Starts pointing forward (0, 0, -1). Randomly reassigned by choose_new_behavior().
# Updated each frame to point away from the ranger during fleeing.

var time_until_change: float = 0.0
# time_until_change — Countdown timer (seconds). When it reaches 0, the NPC
# picks a new wander behaviour (start walking in a new direction or start pausing).

var is_pausing: bool = false
# is_pausing — True while the NPC is standing still (pecking). False while wandering.
# Controls whether the NPC moves or stands still in _do_wander().

var is_fleeing: bool = false
# is_fleeing — True when the ranger is within flee_distance. When true, normal
# wandering is suspended and the NPC runs away from the ranger.

var head_y_rest: float = 0.0
var beak_y_rest: float = 0.0
var head_z_rest: float = 0.0
var beak_z_rest: float = 0.0
# These four variables store the head and beak's resting positions (the positions
# set in the Godot scene editor), recorded in _ready(). The peck and bob animations
# offset from these baseline positions. See player.gd for a full explanation.

var is_pecking: bool = false
# is_pecking — True while the peck animation is playing. Prevents walk-bob from
# interfering with the peck, and blocks new pecks from starting mid-animation.

var peck_time: float = 0.0
# peck_time — Timer counting up during a peck animation (0 → PECK_DURATION).
# Resets to 0 at the start of each new peck.

var next_peck_timer: float = 0.0
# next_peck_timer — Countdown to the next automatic peck while the NPC is paused.
# The NPC randomly pecks at the ground while standing still, simulating foraging.

var bob_time: float = 0.0
# bob_time — Ever-increasing value used as input to sin() for the walk-bob animation.
# See player.gd's bob_time for a full explanation.

var _prev_sin: float = 0.0
# _prev_sin — The sin(bob_time) value from the previous frame.
# Used for zero-crossing detection: when the sine wave crosses from negative to
# positive we know one full bob "step" has occurred. Same technique as player.gd.

var _desired_move: Vector3 = Vector3.ZERO
# _desired_move — Bridge between AI logic (_process) and the physics engine
# (_physics_process). The AI sets a direction × speed here each frame; the
# physics function converts it to velocity and calls move_and_slide().

var _peck_sfx: AudioStreamPlayer3D
# _peck_sfx — A 3D audio player attached to THIS NPC's body.
# AudioStreamPlayer3D is different from the global AudioStreamPlayer used in
# SoundManager: it has a position in the 3D world, and Godot automatically
# reduces its volume as the listener (camera/player) moves further away.
# This means the peck sound is only audible when you're standing close to
# this specific pigeon — exactly like real bird sounds in a park.

var _step_sfx: AudioStreamPlayer3D
# _step_sfx — Same idea as _peck_sfx but for footsteps.
# Each NPC gets its own 3D footstep player so the clopping sound fades with
# distance — you only hear nearby pigeons walking, not every bird on the map.


# =============================================================================
# LINES 33–39 — _ready(): Initialize positions and choose first behaviour
# =============================================================================

func _ready() -> void:
	# Record the starting positions of head and beak so peck/bob animations
	# know where "rest" is. Must happen after @onready fills in the references.
	head_y_rest = head.position.y
	beak_y_rest = beak.position.y
	head_z_rest = head.position.z
	beak_z_rest = beak.position.z

	# Set the timer for the first peck while pausing.
	# randf_range(0.5, 1.5) returns a random float between 0.5 and 1.5 seconds.
	# This randomizes the timing between NPCs so they don't all peck simultaneously.
	next_peck_timer = randf_range(0.5, 1.5)

	# Pick the initial wander behaviour (random direction + duration, or start pausing).
	choose_new_behavior()

	# Create a 3D audio player for this NPC's peck sound.
	# AudioStreamPlayer3D must be a child of a node in the scene tree to work.
	# Adding it here (as a child of this NPC) means it moves with the pigeon
	# and its volume is automatically calculated from the player's distance to IT.
	_peck_sfx = AudioStreamPlayer3D.new()
	_peck_sfx.stream       = SoundManager.npc_peck_stream()
	_peck_sfx.volume_db    = 4.0   # Audible when nearby.
	_peck_sfx.unit_size    = 2.0   # Full volume within 2 units; fades gradually beyond that.
	_peck_sfx.max_distance = 7.0   # Completely silent beyond 7 units.
	_peck_sfx.bus          = "SFX" # Route through SFX bus so the SFX volume slider controls it.
	add_child(_peck_sfx)

	# Create a 3D audio player for this NPC's footstep sound.
	# Same distance-falloff approach as _peck_sfx — steps fade with distance so
	# you only hear nearby birds walking, not every pigeon on the whole map.
	_step_sfx = AudioStreamPlayer3D.new()
	_step_sfx.stream       = SoundManager.npc_step_stream()
	_step_sfx.volume_db    = 2.0   # Slightly quieter than peck — steps are more continuous.
	_step_sfx.unit_size    = 2.0   # Same fade curve as peck.
	_step_sfx.max_distance = 6.0   # Audible range slightly shorter than peck.
	_step_sfx.bus          = "SFX" # Route through SFX bus so the SFX volume slider controls it.
	add_child(_step_sfx)


# =============================================================================
# LINES 41–54 — _process(delta): Main behaviour loop, runs every frame
# =============================================================================

func _process(delta: float) -> void:
	# Clear desired movement at the start of each frame.
	# The AI functions below set it if the NPC should move this frame.
	_desired_move = Vector3.ZERO

	# ── STEP 1: UPDATE PECK ANIMATION ─────────────────────────────────────────

	# Always update the peck animation first, regardless of fleeing or wandering.
	# The peck can happen during any state; it runs independently of movement logic.
	_update_peck(delta)

	# ── STEP 2: CHECK FOR FLEE TRIGGER ────────────────────────────────────────

	# is_instance_valid() confirms the ranger node still exists in the scene.
	# Nodes can be deleted at runtime; accessing a deleted node causes a crash.
	if is_instance_valid(ranger):
		# Measure the distance from THIS NPC to the ranger.
		# If within flee_distance (4.5 units), start fleeing.
		is_fleeing = global_position.distance_to(ranger.global_position) < flee_distance
	else:
		# Ranger doesn't exist (e.g., hasn't spawned yet, or was removed).
		# Can't flee from something that doesn't exist.
		is_fleeing = false

	# ── STEP 3: CHOOSE MOVEMENT BEHAVIOUR ─────────────────────────────────────

	if is_fleeing:
		_do_flee(delta)    # Run away from the ranger.
	else:
		_do_wander(delta)  # Normal random wandering/pausing.

	# ── STEP 4: UPDATE WALK-BOB ANIMATION ────────────────────────────────────

	# Update head-bob based on whether the NPC is moving or standing still.
	_update_walk_bob(delta)


# =============================================================================
# _physics_process(delta): Apply movement to the physics engine
# =============================================================================

# Runs at a fixed 60 Hz rate. The AI in _process() sets _desired_move;
# this function applies it as velocity, adds gravity, and calls move_and_slide().

func _physics_process(delta: float) -> void:
	velocity.x = _desired_move.x
	velocity.z = _desired_move.z
	# Gravity: pull down when airborne; clear vertical speed when on the ground.
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	else:
		velocity.y = 0.0
	# move_and_slide() moves by velocity and handles collision response.
	# NPC pigeons now bump into walls and benches instead of phasing through them.
	move_and_slide()


# =============================================================================
# LINES 56–75 — _do_wander(delta): Normal random wandering behaviour
# =============================================================================

func _do_wander(delta: float) -> void:

	# Check if the NPC has wandered outside the allowed radius (±8 units from centre).
	# absf() returns the absolute value: absf(-9) = 9, absf(3) = 3.
	# "or" = trigger if EITHER X OR Z is out of bounds.
	var is_outside_bounds: bool = (
		absf(position.x) > wander_radius
		or absf(position.z) > wander_radius
	)

	if is_outside_bounds:
		# Out of bounds — force the NPC to turn back toward centre.
		# Negate the current position to get a vector pointing toward origin (0, 0, 0).
		# .normalized() converts to a unit vector (length = 1) for direction only.
		direction = Vector3(-position.x, 0.0, -position.z).normalized()

		# Stop pausing (if it was) so the NPC actually moves toward the centre.
		is_pausing = false

		# Rotate to face the movement direction.
		# look_at(target, up) rotates the node so its -Z axis faces the target.
		# "global_position - direction" is a point BEHIND the NPC.
		# WHY SUBTRACT? In Godot, look_at() makes the node's -Z face the target.
		# For a node moving in "direction", its -Z should face opposite to direction.
		# So: target = position - direction (the point the NPC is "leaving behind").
		# This is counterintuitive but correct for Godot's axis convention.
		if direction.length() > 0.001:
			look_at(global_position - direction, Vector3.UP)
	else:
		# Within bounds — count down the behaviour timer.
		time_until_change -= delta
		if time_until_change <= 0.0:
			# Timer expired — pick a new random behaviour.
			choose_new_behavior()

	if is_pausing:
		# Standing still — trigger idle pecking animation.
		_idle_peck(delta)
	else:
		# Moving — set the desired velocity for this frame.
		# _physics_process() will apply this via move_and_slide() with gravity.
		_desired_move = direction * speed


# =============================================================================
# LINES 76–86 — _do_flee(delta): Run away from the ranger
# =============================================================================

func _do_flee(_delta: float) -> void:
	# Safety check: only flee if the ranger still exists.
	if not is_instance_valid(ranger):
		return

	# Calculate the direction AWAY from the ranger.
	# "global_position - ranger.global_position" = vector FROM ranger TO this NPC.
	# (Subtracting the ranger's position from ours gives a vector pointing away from it.)
	var flee_dir := (global_position - ranger.global_position)

	# Zero out the vertical component — flee on the ground plane only.
	flee_dir.y = 0.0

	if flee_dir.length() > 0.001:
		# Normalize to get a unit direction vector (just direction, no distance info).
		flee_dir = flee_dir.normalized()

		# Set the desired velocity to move away from the ranger at flee_speed.
		_desired_move = flee_dir * flee_speed

		# Rotate the NPC to face AWAY from the ranger.
		# Same "subtract direction" trick as in _do_wander (see explanation above).
		look_at(global_position - flee_dir, Vector3.UP)

		# Update the stored direction so walk-bob knows the NPC is moving.
		direction = flee_dir

	# Stop any pausing behaviour while fleeing — the NPC is running, not foraging.
	is_pausing = false


# =============================================================================
# LINES 88–95 — _idle_peck(delta): Schedule random pecks while standing still
# =============================================================================

# Called each frame while the NPC is paused (standing still).
# Randomly triggers peck animations as if the bird is pecking at the ground.

func _idle_peck(delta: float) -> void:
	# Don't start a new peck if one is already playing.
	if is_pecking:
		return

	# Count down the timer to the next peck.
	next_peck_timer -= delta

	if next_peck_timer <= 0.0:
		# Timer expired — start a new peck!
		is_pecking = true
		peck_time = 0.0   # Reset the animation timer.

		# Play this NPC's 3D peck sound from its own body position.
		# Because _peck_sfx is an AudioStreamPlayer3D attached to this bird,
		# Godot automatically fades the volume based on how far the player is.
		# Stand next to this pigeon → clearly audible. Five meters away → silent.
		_peck_sfx.play()

		# Set a random delay until the NEXT peck after this one finishes.
		# randf_range(0.8, 2.5) = 0.8 to 2.5 seconds between pecks.
		# Each NPC picks its own random interval, so they don't peck in sync.
		next_peck_timer = randf_range(0.8, 2.5)


# =============================================================================
# LINES 97–123 — _update_peck(delta): Run the peck animation frame by frame
# =============================================================================

# This function runs the identical peck animation logic as player.gd.
# See player.gd lines 82–108 for a detailed line-by-line explanation.
# The logic is identical; only the constant names are different (PECK_DURATION
# instead of the exported peck_duration, since NPCs use fixed values).

func _update_peck(delta: float) -> void:
	# Do nothing if no peck is happening.
	if not is_pecking:
		return

	# Advance the peck timer.
	peck_time += delta

	# Normalize to 0.0–1.0 progress fraction.
	var t: float = peck_time / PECK_DURATION

	var z_off: float   # Forward/backward offset to apply to head and beak.
	var y_off: float   # Up/down offset to apply to head and beak.

	if t < PECK_STRIKE_FRAC:
		# STRIKE PHASE (first 40%): head moves forward and drops down.
		var st: float = t / PECK_STRIKE_FRAC   # Progress through strike phase (0→1).

		# Forward offset: quarter-sine ease-in, maxes out at PECK_FORWARD.
		z_off = sin(st * PI * 0.5) * PECK_FORWARD

		# Downward offset: delayed start (begins at 20% of strike), eases in.
		var yst: float = clampf((st - 0.2) / 0.8, 0.0, 1.0)
		y_off = sin(yst * PI * 0.5) * PECK_DROP
	else:
		# RECOVERY PHASE (last 60%): head returns to rest.
		var rt: float = (t - PECK_STRIKE_FRAC) / (1.0 - PECK_STRIKE_FRAC)
		# recovery_weight goes from 1.0 (fully extended) to 0.0 (fully returned).
		var recovery_weight: float = 1.0 - sin(rt * PI * 0.5)
		z_off = recovery_weight * PECK_FORWARD
		y_off = recovery_weight * PECK_DROP

	# Apply offsets to head and beak positions (relative to rest positions).
	head.position.z = head_z_rest + z_off
	head.position.y = head_y_rest - y_off   # Subtract for downward drop.
	beak.position.z = beak_z_rest + z_off
	beak.position.y = beak_y_rest - y_off

	# When the peck animation completes:
	if peck_time >= PECK_DURATION:
		is_pecking = false

		# Snap back to exact rest positions to avoid floating-point drift.
		head.position.z = head_z_rest
		head.position.y = head_y_rest
		beak.position.z = beak_z_rest
		beak.position.y = beak_y_rest


# =============================================================================
# LINES 125–138 — _update_walk_bob(delta): Head-bob while moving
# =============================================================================

# Animates the head forward/backward in a wave pattern while the NPC is moving.
# Identical concept to the walk-bob in player.gd.
# See player.gd lines 59–72 for a full explanation of the sin() bob technique.

func _update_walk_bob(delta: float) -> void:
	# Don't bob while a peck is playing — the peck controls head position.
	if is_pecking:
		return

	# Determine if the NPC is currently moving (not pausing).
	var is_moving: bool = not is_pausing

	if is_moving:
		# Choose the speed to use for bob rate: faster movement = faster bob.
		var move_speed := flee_speed if is_fleeing else speed

		# Advance the bob timer proportional to movement speed.
		# The "5.0" multiplier tunes the bob frequency to feel right.
		bob_time += delta * move_speed * 5.0

		# Calculate bob offset using sine wave.
		# Split into bob_sin (raw -1 to 1 value) and bob (scaled displacement).
		# We need the raw sin value separately for zero-crossing footstep detection below.
		var bob_sin := sin(bob_time)
		var bob := bob_sin * HEAD_BOB_Z

		# Apply to head and beak Z positions.
		head.position.z = head_z_rest + bob
		beak.position.z = beak_z_rest + bob

		# FOOTSTEP SOUND — zero-crossing detection (same pattern as player.gd).
		# When the sine wave crosses from negative to positive, one "step" has completed.
		# "_prev_sin <= 0.0 and bob_sin > 0.0" detects that exact crossing.
		# randf() returns a random float between 0.0 and 1.0 each call.
		# "< 0.3" means roughly a 30% chance to play — prevents all 5 NPC pigeons
		# from making sounds simultaneously, which would be overwhelming.
		if _prev_sin <= 0.0 and bob_sin > 0.0:
			# Play the footstep through this NPC's own 3D audio player.
			# The 30% random chance is no longer needed — distance falloff means
			# far-away birds are naturally quiet, so all steps can fire freely.
			_step_sfx.play()
		_prev_sin = bob_sin
	else:
		# NPC has stopped. Smoothly return head and beak to rest.
		# lerp(from, to, weight) with weight = delta * 10 ≈ 0.16 per frame.
		# This eases the head back to rest rather than snapping instantly.
		head.position.z = lerp(head.position.z, head_z_rest, delta * 10.0)
		beak.position.z = lerp(beak.position.z, beak_z_rest, delta * 10.0)


# =============================================================================
# LINES 139–148 — choose_new_behavior(): Randomly pick the next wander behaviour
# =============================================================================

# Called at scene start and whenever the NPC's wander timer expires.
# Randomly decides whether the NPC will stand still (pause) or walk in a new direction.

func choose_new_behavior() -> void:
	# randf() returns a random float between 0.0 and 1.0.
	# 0.35 (35%) chance of pausing; 0.65 (65%) chance of walking.
	# This means the bird mostly wanders but occasionally stops to forage.
	is_pausing = randf() < 0.35

	if is_pausing:
		# NPC will stand still for a random duration.
		time_until_change = randf_range(0.7, 2.0)   # 0.7 to 2 seconds paused.

		# Start a countdown to the first peck in this pause period.
		next_peck_timer = randf_range(0.2, 0.8)   # First peck within 0.2–0.8 seconds.
	else:
		# NPC will walk in a random new direction.

		# Pick a random angle around a full circle (0 to TAU = 0 to 360°).
		var angle: float = randf_range(0.0, TAU)

		# Convert the angle to a 3D direction vector on the horizontal plane.
		# sin(angle) → X component, 0 → Y (no vertical movement), cos(angle) → Z component.
		# The resulting vector has length ≈ 1 (a unit circle), so it's already normalized.
		direction = Vector3(sin(angle), 0.0, cos(angle))

		# Walk in this direction for 1 to 3 seconds before picking a new behaviour.
		time_until_change = randf_range(1.0, 3.0)

		# Rotate the NPC to face its chosen direction.
		# Same "subtract from position" trick used in _do_wander():
		# look_at with (position - direction) makes -Z face the direction we want to move.
		look_at(global_position - direction, Vector3.UP)


# =============================================================================
# EXECUTION FLOW SUMMARY
# =============================================================================
#
# WHEN THE SCENE LOADS:
#   1. @onready fills in head, beak, ranger references.
#   2. _ready() records head/beak rest positions, sets peck timer, picks first behaviour.
#
# EVERY FRAME (_process):
#   1. _update_peck(delta) — Run peck animation if active (independent of state).
#   2. Check if ranger is within flee_distance → set is_fleeing.
#   3. If fleeing: _do_flee(delta) — run away from ranger.
#      If not: _do_wander(delta) — random wander or pause + idle peck.
#   4. _update_walk_bob(delta) — Bob head if moving; return to rest if still.
#
# WANDER BEHAVIOUR LOOP:
#   choose_new_behavior() → is_pausing OR is_walking for a random duration
#   → time expires → choose_new_behavior() again → loop
#   (interrupted by flee if ranger gets too close)
#
# PECK DURING PAUSE:
#   _idle_peck() counts down next_peck_timer
#   → timer expires → is_pecking = true
#   → _update_peck() runs the animation over PECK_DURATION (0.55 seconds)
#   → is_pecking = false, next_peck_timer reset
#   → repeat
