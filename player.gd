# =============================================================================
# SCRIPT: player.gd
# ATTACHED TO: The "Player" node in Main.tscn
# =============================================================================
#
# OVERVIEW
# --------
# This script controls everything the player does: walking, running, rotating
# to face the direction of movement, head-bobbing while moving, and pecking.
#
# It is attached to the Player node, which is a CharacterBody3D — a special
# Godot node designed for characters that need to move through a 3D world while
# colliding with walls, floors, and other objects.
#
# HOW IT FITS INTO THE GAME
# -------------------------
# The player is a pigeon trying to steal picnic food. This script reads keyboard
# input every frame and translates it into movement. It also animates the pigeon's
# head and beak to make the movement feel alive: the head bobs when walking, and
# the head/beak dip forward and down when the player presses the peck key.
#
# HOW GODOT SCRIPTS WORK (for beginners)
# ----------------------------------------
# In Godot, a "script" is a file of code you attach to a node. The node gains
# the behaviour defined in the script. Think of it like a recipe card attached
# to a robot — the robot reads the card and knows what to do.
#
# GDScript is Godot's own programming language. It looks similar to Python.
# Lines that start with # are "comments" — the game ignores them completely.
# They exist only for humans to read.

# =============================================================================
# LINE 1 — INHERITANCE: What kind of node is this?
# =============================================================================

# "extends" means "this script adds behaviour ON TOP OF an existing Godot class."
# CharacterBody3D is a built-in Godot class for 3D game characters that:
#   - can move through the world
#   - automatically detect when they're touching the floor
#   - push against walls and other collision shapes
#
# Think of "extends" like saying: "I want a car (CharacterBody3D) and I'm going
# to customise it by adding my own steering wheel, engine settings, and horn."
# The base car already handles the physical structure; we just add our custom bits.
#
# INHERITANCE (a programming concept):
# When you "extend" a class, your script automatically gets ALL the built-in
# properties and functions of that class — you don't have to write them yourself.
# For example, CharacterBody3D already has a `velocity` property and a
# `move_and_slide()` function. We use both in this script without defining them.
extends CharacterBody3D


# =============================================================================
# LINES 3–7 — EXPORTED VARIABLES: Tuning knobs visible in the Godot Inspector
# =============================================================================

# "@export" is a special GDScript keyword that makes a variable appear in the
# Godot Editor's "Inspector" panel on the right side of the screen. This means
# you can change these values visually, without touching the code at all.
#
# WHY THIS IS USEFUL:
# Instead of hard-coding "speed = 1.2" deep in the code, you can tweak it
# in real time while the game is running and immediately see the result.
# It's like having sliders on a mixing board rather than having to rewrite music.
#
# DATA TYPE — "float":
# A "float" (short for "floating-point number") is any number that can have
# a decimal point: 1.2, 4.0, 0.3, etc.
# The opposite is an "int" (integer) — whole numbers only: 1, 4, 0, etc.
# Speeds and times need fractions, so we use float.

@export var walk_speed: float = 1.2
# walk_speed — How many Godot units per second the pigeon moves when walking.
# 1.2 is a slow, natural pigeon-like pace. Used when the player is NOT holding
# the run key.

@export var run_speed: float = 4.0
# run_speed — How many units per second when sprinting. 4.0 is noticeably faster.
# But sprinting raises the ranger's suspicion, so the player must use it carefully.

@export var turn_speed: float = 10.0
# turn_speed — How quickly the pigeon visually rotates to face the movement direction.
# A higher number = snappier turning. A lower number = sluggish, floaty turning.
# This is used inside a "lerp_angle" call (explained later at line 57).

@export var peck_duration: float = 0.55
# peck_duration — How long one full peck animation takes, in seconds.
# 0.55 seconds means it takes just over half a second for the head to go
# forward-down and then return to its resting position.

@export var peck_cooldown: float = 0.3
# peck_cooldown — After a peck finishes, the player must wait this many seconds
# before they can peck again. Prevents spamming the peck key.
# 0.3 seconds = 300 milliseconds, which feels natural.

@export var max_stamina: float = 100.0
# max_stamina — The maximum stamina the player can have. The stamina bar on the
# HUD goes from 0 to this value. 100 is a round number that maps directly to
# the ProgressBar's built-in 0–100 range (no conversion needed).

@export var stamina_drain: float = 30.0
# stamina_drain — How many stamina points are lost PER SECOND while sprinting.
# At 30/s, a full tank (100) lasts about 3.3 seconds of constant sprinting.
# This makes sprint a burst tool — useful for escapes, not a default mode.

@export var stamina_recover: float = 15.0
# stamina_recover — How many stamina points are recovered PER SECOND while NOT
# sprinting. 15/s means a fully depleted bar takes about 6.7 seconds to refill.
# Recovery is intentionally slower than drain to create risk/reward tension.


# =============================================================================
# LINES 9–12 — CONSTANTS: Values that NEVER change while the game runs
# =============================================================================

# "const" declares a constant — a value that is set once and cannot be changed.
# Unlike variables (declared with "var"), constants are fixed forever.
# By convention, constant names are written in ALL_CAPS_WITH_UNDERSCORES.
#
# WHY USE CONSTANTS INSTEAD OF VARIABLES?
# It makes the code clearer. When you see PECK_FORWARD, you know immediately
# that this value never changes — it's a fixed property of the animation, not
# something that gets updated at runtime.

const PECK_FORWARD: float = 0.12
# PECK_FORWARD — How far forward (in Godot units along the Z axis) the head and
# beak move during the peak of the peck animation. 0.12 is a small but
# visible lunge forward, like a bird actually striking at food.

const PECK_DROP: float = 0.13
# PECK_DROP — How far DOWN (along the Y axis) the head and beak move at the peak
# of the peck. 0.13 gives a believable dipping motion, as if the pigeon is
# bending its neck toward the ground.

const PECK_STRIKE_FRAC: float = 0.40
# PECK_STRIKE_FRAC — The peck animation has two phases: the "strike" (going down)
# and the "recovery" (coming back up). This constant defines what fraction of the
# total peck duration is the strike phase. 0.40 = 40% of the time goes forward/down,
# and the remaining 60% pulls back to the resting position.
# This makes the strike feel quick and snappy, with a slower, more relaxed recovery.

const HEAD_BOB_Z: float = 0.06
# HEAD_BOB_Z — The maximum distance the head moves forward and backward along the
# Z axis while the pigeon is walking. 0.06 is subtle — just enough to give the
# walk a natural, alive feeling without looking exaggerated.


# =============================================================================
# LINES 14–23 — RUNTIME VARIABLES: Values that change as the game plays
# =============================================================================

# "var" declares a variable — a named box in memory that holds a value.
# Variables (unlike constants) can be changed at any time during the game.
# Each variable here stores a piece of information the script needs to remember
# between frames.

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
# gravity — The strength of gravity that pulls the pigeon downward each frame.
#
# WHAT IS ProjectSettings.get_setting()?
# ProjectSettings is a built-in Godot object that stores all the configuration
# for your project. "physics/3d/default_gravity" is the path to the gravity
# setting in that configuration — by default it's 9.8 (like Earth's gravity in m/s²).
# We read it here so that if you ever change the gravity setting in the project,
# this script automatically uses the new value without any code changes.
#
# WHY DO WE NEED TO APPLY GRAVITY MANUALLY?
# CharacterBody3D does NOT apply gravity automatically. It moves exactly where
# you tell it to move via the "velocity" property. So we must manually reduce
# the Y component of velocity each frame to simulate gravity pulling the pigeon down.

var is_pecking: bool = false
# is_pecking — A boolean (true/false) "flag" that tracks whether the peck animation
# is currently playing.
#
# BOOLEAN DATA TYPE:
# A bool can only ever be "true" or "false". It's like a light switch — on or off.
# This flag is used throughout the script to block certain actions while pecking
# (e.g., you can't start a new peck while one is already happening, and
# the head-bob is paused while pecking).

var peck_time: float = 0.0
# peck_time — A timer, in seconds, that counts up from 0 while a peck is happening.
# When peck_time reaches peck_duration (0.55), the peck animation is complete.
# It's reset to 0.0 each time a new peck starts.

var peck_cooldown_timer: float = 0.0
# peck_cooldown_timer — Counts DOWN from peck_cooldown (0.3) after a peck finishes.
# While this is greater than 0, the player cannot peck again.
# Each frame, delta is subtracted from it until it reaches 0 (ready to peck again).

var head_y_rest: float = 0.0
# head_y_rest — The head's Y position when no animation is playing (its "resting height").
# Y in 3D space means up/down. We record this in _ready() and use it as the
# baseline to return to after a peck. Without it, the peck wouldn't know where
# the head started, so it couldn't return to the right place.

var beak_y_rest: float = 0.0
# beak_y_rest — Same as head_y_rest but for the beak mesh. The beak is a separate
# node, so it needs its own recorded rest position.

var head_z_rest: float = 0.0
# head_z_rest — The head's Z position at rest (Z = forward/backward in Godot's
# default orientation). Used as the baseline for both the peck animation and
# the walking head-bob.

var beak_z_rest: float = 0.0
# beak_z_rest — Same as head_z_rest but for the beak.

var bob_time: float = 0.0
# bob_time — A continuously increasing timer (in seconds, scaled by speed) used
# as the input to a sin() wave to create the head-bob effect.
# sin() needs a "time" input that increases over time to produce a repeating wave.
# This variable provides that ever-growing input.

var _prev_sin: float = 0.0
# _prev_sin — Stores the sin() value from the PREVIOUS frame. By comparing the
# previous frame's value to the current frame's value, we can detect the exact
# moment the sin wave crosses from negative to positive — which is the foot
# "stepping" moment. We use that crossing to trigger a footstep sound.
# The underscore prefix (_) is a convention meaning "this is an internal detail,
# not meant to be accessed from outside this script."

var _stamina: float = 100.0
# _stamina — The player's current stamina, starting at full (max_stamina).
# Drains while sprinting, recovers while walking or standing still.
# Sprint is locked out completely when this hits 0 — the pigeon is out of breath.

var _stamina_depleted: bool = false
# _stamina_depleted — Prevents the exhaust sound from repeating on every frame
# while stamina is at zero. Set true when stamina first hits 0; reset when it
# refills above 10 so the sound can fire again on the next depletion event.


# =============================================================================
# LINES 25–27 — @onready NODE REFERENCES: Shortcuts to child nodes
# =============================================================================

# "@onready" means: "Wait until the scene is fully loaded, THEN run this line."
# These lines give the script direct access to specific child nodes by name.
#
# WHAT IS A NODE?
# In Godot, everything in a scene is a "node." Nodes are organized in a tree
# (called the "scene tree"). The Player is one node; its children (PigeonVisual,
# Head, Beak) are nodes too. Think of it like a family tree.
#
# THE $ SHORTCUT:
# "$PigeonVisual" is shorthand for get_node("PigeonVisual"). It tells Godot:
# "Find a child node of mine named PigeonVisual and give me a reference to it."
# A "reference" is like storing someone's phone number — you can call them later.
# "$PigeonVisual/Head" means: inside PigeonVisual, find the child named "Head".
#
# WHY NOT JUST WRITE get_node() EVERY TIME?
# @onready runs once at scene start and stores the result in a variable.
# That's much faster than calling get_node() 60 times per second inside _process().

@onready var pigeon_visual: Node3D = $PigeonVisual
# pigeon_visual — A reference to the PigeonVisual node, which is a Node3D.
# Node3D is the base type for any 3D object in Godot.
# This node contains all the pigeon's visible mesh parts (head, body, beak).
# We need access to it to rotate the pigeon to face the movement direction.
# We rotate the visual (not the physics body) so that the collision shape
# doesn't spin around — only what the player SEES rotates.

@onready var head: MeshInstance3D = $PigeonVisual/Head
# head — A reference to the Head mesh node inside PigeonVisual.
# MeshInstance3D is the node type that displays a 3D mesh (a 3D shape) in the world.
# We animate this node's position for the peck and head-bob effects.

@onready var beak: MeshInstance3D = $PigeonVisual/Beak
# beak — A reference to the Beak mesh node. Like the head, it's a MeshInstance3D.
# The beak moves in sync with the head during peck and bob animations.

@onready var _stamina_bar: ProgressBar = get_node("../HUD/StaminaBar")
# _stamina_bar — Reference to the StaminaBar ProgressBar in the HUD.
# We update its "value" property every frame to reflect the current stamina level.
# "get_node(../HUD/StaminaBar)" goes up to Main (the parent), then into HUD.


# =============================================================================
# LINES 29–33 — _ready(): Runs ONCE when the node enters the scene
# =============================================================================

# _ready() is a special function that Godot calls automatically, exactly once,
# as soon as this node is added to the game world (the "scene tree").
# It's the ideal place to do setup that only needs to happen at the start:
# store values, connect signals, initialize state, etc.
#
# WHAT IS A FUNCTION?
# A function is a named block of code that you can run ("call") at any time.
# "func _ready() -> void:" means: "Here is the function named _ready.
# It takes no inputs and returns nothing (-> void)."
# "void" means the function doesn't produce a result value — it just does things.
# Godot calls this for you; you never need to call it yourself.

func _ready() -> void:
	# Record the head's Y position as it appears in the scene editor.
	# At this point, @onready has already set up the "head" reference, so
	# head.position.y gives us the initial vertical height set in the Godot editor.
	# We save it so the peck animation knows where "resting" is.
	head_y_rest = head.position.y

	# Same for the beak — store its initial resting Y position.
	beak_y_rest = beak.position.y

	# Store the head's initial Z position (forward/backward).
	# Both peck and head-bob animations shift the head along Z, so we need this
	# baseline to correctly offset from.
	head_z_rest = head.position.z

	# Store the beak's initial Z position for the same reason.
	beak_z_rest = beak.position.z


# =============================================================================
# LINES 35–110 — _physics_process(delta): Runs every physics tick (~60×/second)
# =============================================================================

# _physics_process() is another special Godot function. Unlike _process(),
# which runs every render frame (and can vary in timing), _physics_process()
# runs at a FIXED rate — typically 60 times per second — tied to the physics engine.
#
# WHY USE _physics_process() INSTEAD OF _process() FOR MOVEMENT?
# Character movement must be consistent. If the game slows down (e.g., to 30fps),
# _process() would run less often, making the character move slower.
# _physics_process() always runs at the same rate regardless of frame rate.
# Also, move_and_slide() (Godot's character movement function) MUST be called
# in _physics_process() for correct collision detection.
#
# WHAT IS "delta"?
# delta is the time (in seconds) since the LAST call to _physics_process().
# At 60fps, delta is approximately 0.016 seconds (1/60th of a second).
# Multiplying a speed by delta makes movement frame-rate independent.
# EXAMPLE: If speed = 4.0 and delta = 0.016, then movement = 4.0 * 0.016 = 0.064 units.
# No matter how fast or slow the game runs, the total movement per second stays 4.0.

func _physics_process(delta: float) -> void:

	# ── SECTION 1: GRAVITY ──────────────────────────────────────────────────

	# "is_on_floor()" is a built-in function from CharacterBody3D.
	# It returns true if the character's collision shape is touching the floor,
	# and false if the character is in the air (or falling).
	#
	# "not is_on_floor()" means "if the character is NOT on the floor" — i.e., airborne.
	# "not" flips a boolean: "not true" = false, "not false" = true.
	if not is_on_floor():
		# The character is in the air, so apply gravity.
		# "velocity" is a built-in Vector3 property of CharacterBody3D.
		# It represents the character's speed and direction as three numbers: X, Y, Z.
		# X = left/right, Y = up/down, Z = forward/backward.
		#
		# We're only changing velocity.y (the vertical component).
		# "-=" is a shorthand for "subtract and assign": velocity.y = velocity.y - (gravity * delta)
		# Subtracting gravity * delta from Y makes the pigeon fall faster over time.
		# Multiplying by delta ensures the fall rate is correct regardless of frame rate.
		velocity.y -= gravity * delta
	else:
		# The character IS on the floor.
		# We set a small negative Y velocity (-0.1) instead of 0.
		# WHY? "is_on_floor()" only returns true if the character was slightly pressed
		# into the floor on the previous frame. If we set velocity.y = 0, the character
		# might "float" off the floor. A tiny downward push keeps it firmly grounded.
		velocity.y = -0.1

	# ── SECTION 2: READ PLAYER INPUT ────────────────────────────────────────

	# Input.get_vector() reads four keyboard/gamepad actions simultaneously and
	# returns a Vector2 — a pair of numbers (x, y) representing a 2D direction.
	#
	# WHAT IS A Vector2?
	# A Vector2 has two components: .x and .y.
	# Input.get_vector("left", "right", "up", "down") works like this:
	#   - If only "move_left" is pressed:  returns (-1.0, 0.0)
	#   - If only "move_right" is pressed: returns ( 1.0, 0.0)
	#   - If only "move_forward" is pressed: returns (0.0, -1.0)  ← forward = negative Z
	#   - If only "move_back" is pressed: returns (0.0, 1.0)
	#   - Diagonal (e.g. left + forward): returns (-0.7, -0.7) — automatically normalized
	#
	# WHY Vector2 FOR 3D MOVEMENT?
	# We only need horizontal (ground-level) movement from the player.
	# Gravity handles vertical. So X (strafe) and Z (forward/back) are enough —
	# which maps perfectly to a Vector2's x and y components.
	var input_vector: Vector2 = Input.get_vector(
		"move_left",    # If this action is pressed, result.x goes toward -1
		"move_right",   # If this action is pressed, result.x goes toward +1
		"move_forward", # If this action is pressed, result.y goes toward -1
		"move_back"     # If this action is pressed, result.y goes toward +1
	)

	# Check if the "run" action (Shift key) is currently held down.
	# is_action_pressed() returns true CONTINUOUSLY as long as the key is held.
	# (Compare to is_action_just_pressed(), which only returns true for ONE frame.)
	var want_sprint: bool = Input.is_action_pressed("run")

	# STAMINA — drain while sprinting, recover ONLY when not holding the sprint key.
	# Three possible cases:
	#   1. Holding sprint AND have stamina → drain.
	#   2. Holding sprint AND stamina is 0 → do nothing (locked out, can't recover).
	#   3. Not holding sprint → recover.
	# Case 2 is the important one: without it, the bar would recover by a tiny amount
	# every frame while shift is held, immediately re-enabling sprint — making the
	# limit pointless. The player must release shift to refill the gauge.
	if want_sprint and _stamina > 0.0:
		# Drain stamina. "delta" is the time since the last frame (in seconds).
		# Multiplying rate × delta converts "per second" into "this frame's amount."
		_stamina -= stamina_drain * delta
	elif not want_sprint:
		# Only recover when the player has let go of the sprint key.
		_stamina += stamina_recover * delta
	# (If want_sprint is true but stamina is 0: neither branch runs — gauge holds at 0.)
	_stamina = clamp(_stamina, 0.0, max_stamina)

	# Sprinting is only allowed when the key is held AND stamina is above zero.
	var sprinting: bool = want_sprint and _stamina > 0.0

	# Play a one-shot exhaust puff when stamina first hits zero.
	# The _stamina_depleted flag prevents it from firing every frame while empty.
	# It resets once stamina recovers past 10 — ready for the next depletion event.
	if _stamina <= 0.0 and not _stamina_depleted:
		_stamina_depleted = true
		SoundManager.play_exhaust()
	elif _stamina > 10.0:
		_stamina_depleted = false

	# Update the on-screen stamina bar to reflect the current stamina value.
	# ProgressBar.value expects a number in the range [0, max_value].
	# Since max_stamina = 100 and max_value = 100, this works directly.
	_stamina_bar.value = _stamina

	# Choose the speed based on whether we're sprinting.
	# This is a "ternary expression" — a one-line if/else:
	#   condition ? value_if_true : value_if_false
	# In GDScript: value_if_true if condition else value_if_false
	# So: if sprinting, use run_speed (4.0); otherwise use walk_speed (1.2)
	var current_speed: float = run_speed if sprinting else walk_speed

	# ── SECTION 3: APPLY HORIZONTAL MOVEMENT ────────────────────────────────

	# Set the velocity's X component (left/right movement).
	# input_vector.x is -1 (left), 0 (none), or +1 (right), or something between.
	# Multiplying by current_speed scales the direction into actual units-per-second.
	velocity.x = input_vector.x * current_speed

	# Set the velocity's Z component (forward/backward movement).
	# input_vector.y maps to the Z axis (not Y!) because in 3D space,
	# "forward" is along the Z axis, not the Y axis (which is up/down).
	# This is a common source of confusion: the 2D "y" from input maps to 3D "z".
	velocity.z = input_vector.y * current_speed

	# ── SECTION 4: ROTATE THE PIGEON TO FACE ITS DIRECTION OF MOVEMENT ─────

	# Only rotate if the player is actually pressing a direction key.
	# input_vector.length() returns the magnitude (overall size) of the vector.
	# If no keys are pressed, length() = 0. If pressed, length() ≈ 1.0 (or less diagonally).
	# We check > 0.1 (not > 0) to ignore tiny accidental inputs from analog sticks.
	if input_vector.length() > 0.1:
		# Build a 3D direction vector from the 2D input.
		# We use input_vector.x for X (left/right) and input_vector.y for Z (forward/back).
		# The Y component is 0 because the pigeon moves flat on the ground (no up/down rotation).
		#
		# WHAT IS A Vector3?
		# Vector3 has three components: x, y, z. In Godot's 3D space:
		#   +X = right, -X = left
		#   +Y = up, -Y = down
		#   +Z = backward (toward camera), -Z = forward (into screen)
		var direction := Vector3(input_vector.x, 0, input_vector.y)

		# atan2(y, x) is a math function that converts a 2D direction into an angle.
		# It returns the angle (in radians) that points from the origin toward (x, y).
		#
		# WHAT IS A RADIAN?
		# Angles can be measured in degrees (0–360) or radians (0–TAU, where TAU ≈ 6.28).
		# Radians are what math functions use internally.
		#
		# WHY atan2(direction.x, direction.z) instead of atan2(direction.y, direction.x)?
		# We want the angle around the Y axis (horizontal spin). That angle is determined
		# by the X (left/right) and Z (forward/back) components, not X and Y.
		var target_angle := atan2(direction.x, direction.z)

		# lerp_angle() smoothly interpolates between two angles.
		# "lerp" stands for "linear interpolation" — blending two values.
		# lerp_angle(from, to, weight) returns an angle between "from" and "to",
		# where weight=0 returns "from" exactly, and weight=1 returns "to" exactly.
		#
		# HERE: weight = delta * turn_speed = 0.016 * 10.0 = 0.16 per frame.
		# This means each frame the pigeon rotates 16% closer to the target angle.
		# The result is smooth rotation that never snaps instantly.
		#
		# WHY NOT JUST SET rotation.y = target_angle?
		# That would make the pigeon spin instantly to face any direction — jarring and
		# unnatural. lerp_angle gives a smooth, organic turn.
		#
		# WHY pigeon_visual.rotation.y INSTEAD OF the whole player's rotation?
		# We only rotate the visual mesh (PigeonVisual), not the physics body (CharacterBody3D).
		# This keeps the collision shape axis-aligned, which prevents physics glitches
		# where rotating the collision shape could cause it to clip through walls.
		pigeon_visual.rotation.y = lerp_angle(pigeon_visual.rotation.y, target_angle, delta * turn_speed)

	# ── SECTION 5: HEAD-BOB ANIMATION (WHILE WALKING/RUNNING) ───────────────

	# Only bob the head when NOT in the middle of a peck.
	# If the peck animation is playing, it controls head position — we don't
	# want the bob interfering with it.
	if not is_pecking:
		# Sub-check: are we actually moving? (Same 0.1 threshold as before)
		if input_vector.length() > 0.1:
			# Advance the bob timer.
			# We multiply by current_speed so the bob speed matches movement speed —
			# faster movement = faster bobbing. The 5.0 multiplier is a tuning constant
			# that makes the bob feel right at both walk and run speeds.
			bob_time += delta * current_speed * 5.0

			# sin() is the "sine" mathematical function. It takes an angle (in radians)
			# and returns a value that smoothly oscillates between -1.0 and +1.0.
			# As bob_time increases, sin(bob_time) goes up, then down, then up again —
			# creating a repeating wave. This is the core of the head-bob effect.
			#
			# REAL-WORLD ANALOGY: Think of a buoy floating on gentle waves.
			# The buoy's height over time is a sine wave — up, down, up, down.
			# The pigeon's head position does the same thing.
			var bob_sin: float = sin(bob_time)

			# Calculate the actual offset to apply to Z (forward/backward position).
			# bob_sin ranges from -1 to +1, so bob ranges from -HEAD_BOB_Z to +HEAD_BOB_Z.
			# HEAD_BOB_Z = 0.06, so the head swings ±0.06 units forward/backward.
			var bob := bob_sin * HEAD_BOB_Z

			# Apply the bob offset to the head's local Z position.
			# Local position is relative to the parent node (PigeonVisual), not the world.
			# Adding to head_z_rest means we bob AROUND the rest position, not from zero.
			head.position.z = head_z_rest + bob

			# Apply the same bob offset to the beak so it moves in sync with the head.
			beak.position.z = beak_z_rest + bob

			# FOOTSTEP SOUND TRIGGER: zero-crossing detection.
			# We want to play a footstep sound once per "step" — approximately once per
			# bob cycle. The cleanest moment to trigger it is when the sine wave crosses
			# from negative to positive (the upswing), which happens once per full cycle.
			#
			# "_prev_sin <= 0.0" means last frame's sin value was zero or negative.
			# "bob_sin > 0.0" means this frame's sin value is now positive.
			# If BOTH are true, the wave just crossed from negative to positive → play a step.
			# This is called "zero-crossing detection."
			if _prev_sin <= 0.0 and bob_sin > 0.0:
				# SoundManager is an Autoload (a global object — explained in sound_manager.gd).
				# play_step(sprinting) plays either the walk step or run step sound
				# depending on whether the pigeon is sprinting.
				SoundManager.play_step(sprinting)

			# Save this frame's sin value so next frame can compare against it.
			_prev_sin = bob_sin

		else:
			# Player has STOPPED moving. Smoothly return head and beak to rest position.
			# lerp(from, to, weight) blends linearly between "from" and "to".
			# weight = delta * 10.0 ≈ 0.016 * 10 = 0.16 per frame.
			# Each frame the head moves 16% closer to rest — it "eases in."
			# This feels more natural than snapping back instantly.
			head.position.z = lerp(head.position.z, head_z_rest, delta * 10.0)
			beak.position.z = lerp(beak.position.z, beak_z_rest, delta * 10.0)

			# When standing still, reset the previous-sin tracker to 0.
			# This ensures the very first bob when moving again starts fresh —
			# otherwise we might get an accidental footstep sound triggered on
			# the first frame of movement.
			_prev_sin = 0.0

	# ── SECTION 6: PECK COOLDOWN COUNTDOWN ──────────────────────────────────

	# If the cooldown timer is still counting down (greater than zero),
	# subtract delta (the time since last frame) from it.
	# This counts DOWN toward zero in real-world time.
	# Once it reaches 0, the player can peck again.
	if peck_cooldown_timer > 0.0:
		peck_cooldown_timer -= delta

	# ── SECTION 7: DETECT PECK INPUT AND START PECK ANIMATION ───────────────

	# is_action_just_pressed() returns true for EXACTLY ONE FRAME when the key
	# is first pressed. Unlike is_action_pressed(), it does NOT stay true if
	# the key is held down. This prevents the peck from repeating while holding E.
	#
	# ALL conditions must be true (using "and") for a peck to start:
	#   1. The peck key (E) was just pressed this frame
	#   2. We're not already in a peck animation (is_pecking == false)
	#   3. The cooldown has fully expired (timer is at or below 0)
	#   4. We're not sprinting (no peck while running — pigeon can't do both)
	if Input.is_action_just_pressed("peck") and not is_pecking and peck_cooldown_timer <= 0.0 and not sprinting:
		# Start the peck: set the flag to true.
		is_pecking = true

		# Reset the peck timer to 0 so the animation starts from the beginning.
		peck_time = 0.0

		# Play the peck sound effect through the global SoundManager.
		SoundManager.play_peck()

	# ── SECTION 8: UPDATE PECK ANIMATION ────────────────────────────────────

	# If a peck is currently happening, update the animation each frame.
	if is_pecking:
		# Add delta to the peck timer — counting UP from 0.0 toward peck_duration (0.55).
		peck_time += delta

		# Calculate "t" — the normalized progress through the peck animation.
		# t = 0.0 means "just started", t = 1.0 means "fully complete."
		# Dividing peck_time by peck_duration converts from "seconds elapsed"
		# to "fraction of animation complete." This is a very common pattern in animation.
		var t: float = peck_time / peck_duration

		# Declare z_off and y_off — the offsets we'll apply to head and beak position.
		# These start undefined; they'll be set in one of the two branches below.
		var z_off: float
		var y_off: float

		# The peck has two phases, split at PECK_STRIKE_FRAC (0.40 = 40% of the animation):
		# Phase 1 (t < 0.40): Strike — head moves FORWARD and DOWN (toward the food).
		# Phase 2 (t >= 0.40): Recovery — head returns to rest position.
		if t < PECK_STRIKE_FRAC:
			# PHASE 1: STRIKE PHASE
			# "st" (strike time) is the progress through just the strike phase, 0.0 to 1.0.
			# We remap t from [0, PECK_STRIKE_FRAC] to [0, 1] by dividing by the fraction.
			var st: float = t / PECK_STRIKE_FRAC

			# Calculate the forward (Z) offset using a quarter-sine curve.
			# sin(st * PI * 0.5) goes from sin(0)=0 to sin(PI/2)=1 smoothly.
			# This gives us a nice "ease in" — starts slow, then accelerates forward.
			# Multiplying by PECK_FORWARD (0.12) scales it to the desired max distance.
			z_off = sin(st * PI * 0.5) * PECK_FORWARD

			# Calculate the downward (Y) offset, but with a DELAYED start.
			# clampf((st - 0.2) / 0.8, 0.0, 1.0) means:
			#   - The drop doesn't start until st reaches 0.2 (20% into the strike)
			#   - After that, it ramps up over the remaining 80% of the strike
			#   - clampf ensures the value stays between 0.0 and 1.0
			# This delay makes the head move forward first, THEN drop — more pigeon-like.
			var yst: float = clampf((st - 0.2) / 0.8, 0.0, 1.0)
			y_off = sin(yst * PI * 0.5) * PECK_DROP

		else:
			# PHASE 2: RECOVERY PHASE
			# "rt" (recovery time) is the progress through just the recovery phase, 0.0 to 1.0.
			# Remap t from [PECK_STRIKE_FRAC, 1.0] to [0.0, 1.0]:
			#   Subtract the starting point: t - PECK_STRIKE_FRAC
			#   Divide by the length of the phase: 1.0 - PECK_STRIKE_FRAC = 0.60
			var rt: float = (t - PECK_STRIKE_FRAC) / (1.0 - PECK_STRIKE_FRAC)

			# This annotation tells GDScript's warning system: "I know 'sin' is also
			# a built-in global function. I'm intentionally shadowing it here with
			# a local variable named 'recovery_weight'. Don't warn me about it."
			# (A "shadowed global identifier" means a local variable name matches
			# a built-in name — it's legal but GDScript warns about it by default.)
			@warning_ignore("shadowed_global_identifier")

			# recovery_weight goes from 1.0 (at rt=0, fully extended) to 0.0 (at rt=1, fully returned).
			# sin(rt * PI * 0.5) goes from 0 to 1 as rt goes from 0 to 1.
			# So 1.0 - that goes from 1 to 0 — a value that starts at 1 and eases back to 0.
			# This gives a smooth "ease out" — the head pulls back slowly at first,
			# then snaps back faster. Natural and satisfying.
			var recovery_weight: float = 1.0 - sin(rt * PI * 0.5)

			# Scale the max offsets by recovery_weight.
			# At the start of recovery, recovery_weight=1 → full extension.
			# At the end of recovery, recovery_weight=0 → fully returned to rest.
			z_off = recovery_weight * PECK_FORWARD
			y_off = recovery_weight * PECK_DROP

		# Apply the calculated offsets to the head's local position.
		# Z gets ADDED to rest position (head pushes forward).
		head.position.z = head_z_rest + z_off

		# Y gets SUBTRACTED from rest position (head drops downward, and positive Y is up).
		head.position.y = head_y_rest - y_off

		# Apply the same offsets to the beak so it moves identically with the head.
		beak.position.z = beak_z_rest + z_off
		beak.position.y = beak_y_rest - y_off

		# Check if the peck animation has finished (peck_time has reached or exceeded duration).
		# ">=" means "greater than or equal to."
		if peck_time >= peck_duration:
			# Mark the peck as done.
			is_pecking = false

			# Start the cooldown timer. It will count DOWN from peck_cooldown (0.3) to 0.
			peck_cooldown_timer = peck_cooldown

			# Snap head and beak back to their exact rest positions.
			# Even though the math above should get us very close to rest,
			# snapping to the exact value ensures no tiny floating-point drift accumulates.
			head.position.z = head_z_rest
			head.position.y = head_y_rest
			beak.position.z = beak_z_rest
			beak.position.y = beak_y_rest

	# ── SECTION 9: APPLY MOVEMENT TO THE CHARACTER ───────────────────────────

	# move_and_slide() is a built-in CharacterBody3D function. It does a lot:
	#   1. Moves the character according to the "velocity" property.
	#   2. Detects collisions with walls, floors, and ceilings.
	#   3. "Slides" the character along surfaces instead of stopping dead.
	#      (If you walk into a diagonal wall at full speed, you'll slide along it.)
	#   4. Handles the is_on_floor() check — it must be called for that to work.
	#
	# This MUST be the last thing called each frame. It finalises all the velocity
	# changes we made above and actually moves the character in the world.
	move_and_slide()


# =============================================================================
# EXECUTION FLOW SUMMARY (Top to Bottom)
# =============================================================================
#
# WHEN THE SCENE FIRST LOADS:
#   1. Godot creates the Player node and all its children.
#   2. @onready variables are filled in (head, beak, pigeon_visual).
#   3. _ready() runs: the resting positions of head and beak are recorded.
#
# EVERY PHYSICS TICK (~60 times per second):
#   _physics_process(delta) runs and does the following in order:
#
#   1. GRAVITY: If in the air, pull the pigeon down. If on ground, hold it there.
#   2. INPUT: Read the directional keys and whether Shift is held.
#   3. SPEED: Choose walk or run speed based on Shift.
#   4. VELOCITY: Set velocity.x and velocity.z to move the pigeon.
#   5. ROTATION: If moving, smoothly rotate PigeonVisual to face the direction.
#   6. HEAD BOB: If moving and not pecking, oscillate head/beak along Z using sin().
#      Detect footstep moments via zero-crossing and trigger sound.
#   7. COOLDOWN: Count down the peck cooldown timer.
#   8. PECK INPUT: If E is pressed (and conditions allow), start a peck.
#   9. PECK ANIMATION: If pecking, compute strike or recovery offsets and
#      apply them to head and beak positions. End the peck when time is up.
#  10. MOVE: Call move_and_slide() to actually move the character and handle collisions.
