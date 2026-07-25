# =============================================================================
# SCRIPT: ranger.gd
# ATTACHED TO: The "Ranger" node in Main.tscn
# =============================================================================
#
# OVERVIEW
# --------
# This script controls the park ranger — the enemy / antagonist of the game.
# The ranger is an AI (artificial intelligence) character, meaning the computer
# controls its behaviour, not the player.
#
# The ranger has three possible "states" (modes of behaviour):
#   PATROL     — Wandering randomly around the park, not actively suspicious.
#   INVESTIGATE — Walking toward the player because they're acting suspicious.
#   CHASE       — Running toward the player because suspicion is maxed out.
#
# This pattern — having a character switch between distinct behaviours based on
# conditions — is called a "state machine." Think of it like a traffic light:
# it can only be red, yellow, or green, and it switches based on rules.
#
# HOW IT FITS INTO THE GAME
# -------------------------
# The ranger monitors the player's behaviour every frame. It tracks a "suspicion"
# value from 0 to 100. If suspicion hits 100, the player is "caught" and the game ends.
# Several things raise suspicion:
#   - Sprinting nearby
#   - Moving directly toward food
#   - Staring at the ranger while walking
#   - Being the only animal in the area (not blending in with NPC pigeons)
# Pecking and staying still reduces suspicion.
#
# The ranger also:
#   - Controls the on-screen "suspicion bar" and status text labels
#   - Controls the red vignette (screen-edge darkening) via a shader
#   - Shows warning popups ("!" and "DANGER!") at key suspicion thresholds
#   - Plays an alert sound when entering a new threat state

# =============================================================================
# LINE 1 — INHERITANCE
# =============================================================================

# This script extends CharacterBody3D — the same base class the player uses.
# CharacterBody3D understands physics: it has gravity, stays on the ground,
# and is blocked by walls, trees, benches, and other StaticBody3D objects in
# the scene. We move the ranger by setting "velocity" and calling move_and_slide()
# in _physics_process(), rather than directly changing "position".
extends CharacterBody3D


# =============================================================================
# LINES 3 — ENUM: Defining the set of allowed states
# =============================================================================

# An "enum" (short for "enumeration") defines a custom data type that can only
# hold one of a fixed set of named values.
#
# WHY USE AN ENUM?
# We could use integers (0=patrol, 1=investigate, 2=chase), but that's hard to read.
# An enum lets us write "RangerState.PATROL" instead of "0" — much clearer.
# Godot also validates enum values, so you can't accidentally assign an invalid number.
#
# This creates a type called "RangerState" with exactly three possible values:
#   RangerState.PATROL       — number 0 internally
#   RangerState.INVESTIGATE  — number 1 internally
#   RangerState.CHASE        — number 2 internally
enum RangerState { PATROL, INVESTIGATE, CHASE }


# =============================================================================
# LINES 5–29 — EXPORTED VARIABLES: Tuning values visible in the Inspector
# =============================================================================

# All these use @export (explained in player.gd) so you can tweak them in the editor.

@export var notice_distance: float = 6.5
# notice_distance — How close the player must be (in Godot units) for the ranger
# to even begin checking their behaviour. Outside this radius, the ranger is
# completely unaware of the player. Think of it as the ranger's peripheral vision range.
# 6.5 units — wide enough that the ranger covers a large portion of the park,
# so the player can't simply walk around him without planning.

@export var suspicious_speed: float = 2.0
# suspicious_speed — If the player is moving faster than this value (in units/sec),
# the ranger considers it suspicious. The pigeon's walk speed is 1.2 and run speed
# is 4.0, so anything above 2.0 means the player is sprinting. Sprinting = suspicious.

@export var suspicion_gain_per_second: float = 30.0
# suspicion_gain_per_second — How many suspicion points are added per second when
# the player is sprinting near the ranger. At 30 points/sec, sprinting in his detection
# zone fills suspicion in ~3.3 seconds. Slightly lower than before because the detection
# zone is now bigger — the player will be in range more often, so per-second gain
# doesn't need to be as punishing.

@export var suspicion_loss_per_second: float = 22.0
# suspicion_loss_per_second — How many suspicion points are removed per second when
# the player is doing nothing suspicious. Raised from 15 to 22 — breaking line-of-sight
# now feels meaningfully rewarding. The player gets clear feedback: "I got away."
# The gain-to-loss ratio (30 gain vs 22 loss) still means suspicion builds faster
# than it drains, keeping the tension.

@export var peck_loss_per_second: float = 20.0
# peck_loss_per_second — BONUS loss rate added on top of suspicion_loss_per_second
# while the pigeon is pecking. Pecking signals "I'm just a normal bird eating."
# So 15 + 20 = 35 points/sec total loss while pecking — drains suspicion quickly.

@export var patrol_speed: float = 1.1
# patrol_speed — How fast (units/sec) the ranger wanders during PATROL state.
# Raised from 0.8 to 1.1 — the ranger now strolls with purpose instead of shuffling.
# Still slower than the player's walk speed (1.2), so you can always outpace him
# calmly, but he covers ground fast enough to feel like a real presence.

@export var patrol_radius: float = 9.5
# patrol_radius — How far from the centre of the park the ranger is allowed to wander.
# Raised from 7.0 to 9.5 — now covers almost the full park area. The ranger will
# regularly pass near the food items and the escape zone, so the player has to
# watch his position rather than ignoring him until he wanders close.

@export var investigate_threshold: float = 65.0
# investigate_threshold — Suspicion value at which the ranger enters INVESTIGATE state.
# Once suspicion reaches 65, the ranger starts walking toward the player.

@export var investigate_speed: float = 1.8
# investigate_speed — Movement speed during INVESTIGATE state. Raised from 1.4 to 1.8.
# The ranger now approaches with clear intent — you can see him heading your way.
# Still slower than chase (3.5) but noticeably faster than patrol, so the transition
# between states feels meaningful rather than hard to notice.

@export var chase_threshold: float = 90.0
# chase_threshold — Suspicion value at which the ranger enters CHASE state.
# At 90 suspicion, the ranger sprints toward the player. The player is nearly caught.

@export var chase_speed: float = 3.5
# chase_speed — Movement speed during CHASE state. Raised from 2.8 to 3.5.
# The player's sprint speed is 4.0, so the ranger nearly keeps pace during a chase.
# The player can escape but only by sprinting the whole way — no casual jogging out.

@export var approach_stop_distance: float = 1.8
# approach_stop_distance — During INVESTIGATE or CHASE, the ranger stops moving
# toward the player once within this distance. Prevents the ranger from walking
# INTO the player. 1.8 units ≈ just within arm's reach.

@export var food_aim_threshold: float = 0.9
# food_aim_threshold — A dot product threshold (0.0 to 1.0) used to detect whether
# the player is walking DIRECTLY toward a food item. A value of 0.9 means the
# player's movement direction must be within ~26 degrees of the direction to the
# nearest food. (Explained more in _is_aiming_at_food below.)

@export var food_aim_delay: float = 0.5
# food_aim_delay — How many seconds the player must be aiming at food before
# suspicion starts rising from that behaviour. Reduced from 0.8 to 0.5 — the ranger
# catches on faster, so the player needs to approach food at an angle rather than
# walking straight at it from a distance.

@export var food_aim_gain_per_second: float = 25.0
# food_aim_gain_per_second — Suspicion points added per second when the player
# has been aiming at food for longer than food_aim_delay.

@export var stare_threshold: float = 0.85
# stare_threshold — Dot product threshold for detecting whether the player's pigeon
# is "staring at" the ranger. 0.85 means the pigeon must be facing within ~32 degrees
# of the ranger for it to count as staring.

@export var stare_delay: float = 0.6
# stare_delay — How many seconds of staring before suspicion starts rising.
# Reduced from 1.0 to 0.6 — the player has less time to look directly at the ranger
# before it starts costing them. Encourages looking past or away from him.

@export var stare_gain_per_second: float = 20.0
# stare_gain_per_second — Suspicion points per second from staring at the ranger.
# A bird staring at a human for over a second would definitely seem weird.

@export var separation_distance: float = 4.0
# separation_distance — Used to detect if the player is "isolated" — far from all
# NPC pigeons. If no NPC pigeon is within 4 units of the player, the player's pigeon
# looks suspicious (a lone pigeon instead of part of a flock).

@export var separation_gain_per_second: float = 15.0
# separation_gain_per_second — Suspicion added per second from being isolated.
# Raised from 10 to 15. With 5 NPC pigeons now in the park, the player has more
# opportunities to blend in — so blending in should actually matter more.
# Straying from the flock now costs you noticeably.

@export var straight_line_threshold: float = 2.5
# straight_line_threshold — How many seconds the player must walk in a nearly
# straight line before suspicion starts rising from it.
# Real pigeons constantly veer, peck, and bob their heads — they never march in a
# straight line. 2.5 seconds gives the player meaningful grace time before the
# ranger notices — enough to cross open ground without being immediately penalised.

@export var straight_line_dot: float = 0.97
# straight_line_dot — How "straight" the movement must be to count.
# This is a dot product threshold (explained fully in _is_aiming_at_food above).
# 0.97 ≈ within 14° of the same direction between consecutive frames.
# A bird always wobbles at least a little — staying within 14° for 1.5 seconds
# is abnormally controlled movement.

@export var straight_line_gain_per_second: float = 10.0
# straight_line_gain_per_second — Suspicion points per second from walking too straight.
# 10/sec is gentle — it takes 10 full seconds of perfectly straight walking to fill
# the bar on its own, so this only becomes a real threat when combined with other
# suspicious behaviours (sprinting, isolation, etc.).


# =============================================================================
# LINES 31–36 — @onready NODE REFERENCES
# =============================================================================

# See player.gd for a full explanation of @onready and get_node().
# "../" means "go UP one level to the parent, then find the named child."
# The ranger is a child of the Main scene (Main → Ranger), so "../Player" means
# "go up to Main, then find the child named Player."

@onready var player: CharacterBody3D = get_node("../Player")
# player — Reference to the Player node. We need this to:
#   - Measure the distance between ranger and player
#   - Read the player's velocity (to detect sprinting)
#   - Check the player's position for movement direction analysis
#   - Read the "is_pecking" property from player.gd

@onready var status_label: Label = get_node("../HUD/RangerStatus")
# status_label — Reference to the "RangerStatus" Label UI node.
# A Label is a UI text element. We update this each frame to show the player
# what the ranger is doing ("Ranger: Calm", "Ranger: Alert!", etc.).
# HUD = Heads-Up Display, the on-screen UI layer.

@onready var suspicion_bar: ProgressBar = get_node("../HUD/SuspicionBar")
# suspicion_bar — Reference to the ProgressBar UI node that shows the suspicion level.
# ProgressBar has a "value" property (0–100) and displays it as a visual bar.
# We set suspicion_bar.value = suspicion each frame to keep it updated.

@onready var pigeon_visual: Node3D = get_node("../Player/PigeonVisual")
# pigeon_visual — Reference to the PigeonVisual node inside the Player.
# We need this specifically to calculate which direction the pigeon is FACING
# (to detect if it's staring at the ranger). The visual's Z axis = the pigeon's
# forward direction.

@onready var _vignette_mat: ShaderMaterial = get_node("../HUD/VignetteRect").material
# _vignette_mat — Reference to the ShaderMaterial on the VignetteRect (a fullscreen
# ColorRect with a custom shader). A ShaderMaterial lets us pass values into
# a GPU shader program from GDScript.
# We drive the vignette's "intensity" parameter with the suspicion level, making
# the screen edges darken red as suspicion rises.

@onready var _warn_label: Label = get_node("../HUD/WarnLabel")
# _warn_label — Reference to the warning label that briefly shows "!" or "DANGER!"
# when suspicion crosses key thresholds. It fades out automatically over time.

@onready var _alert_label: Label3D = get_node("AlertLabel")
# _alert_label — A Label3D floating above the ranger's head in 3D world space.
# It displays "!" when the ranger is investigating, "!!" when chasing, and is
# blank when patrolling. Label3D always faces the camera (billboard mode),
# so the player can read it from any angle.


# =============================================================================
# LINES 38–49 — RUNTIME VARIABLES
# =============================================================================

var suspicion: float = 0.0
# suspicion — The central number that drives almost everything in this script.
# Ranges from 0.0 (completely unsuspicious) to 100.0 (caught).
# Other scripts (like game_timer.gd) read this value via ranger.get("suspicion")
# to track peak suspicion for the end-of-game results screen.

var caught: bool = false
# caught — Set to true when suspicion reaches 100. Once true, the game-over
# logic in game_timer.gd will end the game.

var state: RangerState = RangerState.PATROL
# state — The current behaviour state of the ranger. Starts as PATROL.
# Updated each frame based on the suspicion value.
# Uses the RangerState enum defined above.

var _prev_state: RangerState = RangerState.PATROL
# _prev_state — The state from the PREVIOUS frame. By comparing state to _prev_state,
# we can detect when the state CHANGES — and play an alert sound exactly once
# at the moment of change, not every frame.

var _pulse_time: float = 0.0
# _pulse_time — A growing timer used to drive the pulsing color of the suspicion bar.
# sin(_pulse_time * frequency) creates the repeating pulse animation.

var _warn_timer: float = 0.0
# _warn_timer — Countdown timer (in seconds) for how long the warning label ("!" or
# "DANGER!") remains visible. It counts down from 1.5 or 1.8 to 0, then hides the label.

var _desired_move: Vector3 = Vector3.ZERO
# _desired_move — The horizontal speed the ranger wants to move this frame.
# Set by the AI logic in _process(), then consumed by _physics_process() which
# applies it as velocity and calls move_and_slide(). Using a stored variable
# bridges the gap between the AI update rate (_process) and physics rate (_physics_process).
# Y is always left at 0 here — gravity is handled separately in _physics_process.

var _prev_suspicion: float = 0.0
# _prev_suspicion — Suspicion value from the previous frame. Used to detect when
# suspicion CROSSES a threshold (e.g., from below 65 to above 65) so we show the
# warning label exactly once at that crossing point.

var _alert_tween: Tween
# _alert_tween — Tracks the active pop-in animation for the alert label.
# Stored so it can be cancelled (killed) before starting a new one if the
# ranger changes state while an animation is still playing.

var patrol_direction: Vector3 = Vector3.FORWARD
# patrol_direction — The direction the ranger is currently walking while patrolling.
# Vector3.FORWARD is (0, 0, -1) in Godot — pointing toward the camera's "into screen" axis.
# This is randomly changed by choose_new_patrol_direction().

var time_until_turn: float = 0.0
# time_until_turn — A countdown timer (seconds). When it reaches 0 during patrol,
# the ranger picks a new random direction to walk.

var stare_time: float = 0.0
# stare_time — How long (in seconds) the player has been staring at the ranger
# continuously. Resets when the player looks away.

var food_aim_time: float = 0.0
# food_aim_time — How long (in seconds) the player has been walking toward food.
# Resets (quickly) when the player stops aiming at food.

var _straight_time: float = 0.0
# _straight_time — How long (in seconds) the player has been moving in a nearly
# straight line without turning. Resets when the player turns or stops.

var _last_move_dir: Vector2 = Vector2.ZERO
# _last_move_dir — The player's horizontal movement direction from the PREVIOUS frame.
# We compare this to the current frame's direction to measure how much the player turned.
# Stored as a 2D vector (X and Z axes only) because Y (vertical) doesn't affect turning.

var npc_animals: Array = []
# npc_animals — An Array (list) that stores references to all NPC pigeon nodes.
# Array is a built-in Godot type that holds an ordered collection of values.
# We populate this in _ready() and use it in _is_isolated() to check
# whether any NPC is near the player.


# =============================================================================
# LINES 51–56 — _ready(): Initialization
# =============================================================================

func _ready() -> void:
	# Pick a random starting patrol direction so the ranger doesn't always
	# start walking in the same direction every new game.
	choose_new_patrol_direction()

	# Start with the alert label hidden — the script will show it when the
	# ranger enters INVESTIGATE or CHASE state.
	_alert_label.visible = false

	# Build the list of NPC animal nodes.
	# We look for nodes named "NPC_Animal" through "NPC_Animal5" in the scene.
	# These are the background pigeons that help the player "blend in."
	# NPC_Animal4 and NPC_Animal5 are the two extra pigeons added in step 3.
	for npc_name in ["NPC_Animal", "NPC_Animal2", "NPC_Animal3", "NPC_Animal4", "NPC_Animal5"]:
		# "for x in collection" is a loop that runs once for each item in a list.
		# Here, npc_name takes the values "NPC_Animal", "NPC_Animal2", "NPC_Animal3" in turn.

		# get_node_or_null() is like get_node() but returns null (nothing) instead of
		# crashing if the node doesn't exist. Safe to use when a node might not be present.
		# "../" + npc_name builds the path string: "../NPC_Animal", "../NPC_Animal2", ..., "../NPC_Animal5".
		# The "+" operator joins (concatenates) two strings together.
		var npc := get_node_or_null("../" + npc_name)

		# Only add the npc to our list if it was actually found.
		# "if npc:" is shorthand for "if npc != null" — null is falsy in GDScript.
		if npc:
			# .append() adds an item to the end of an Array.
			npc_animals.append(npc)


# =============================================================================
# LINES 58–201 — _process(delta): Main AI loop, runs every frame
# =============================================================================

# We use _process() (not _physics_process()) here because the ranger's movement is
# simple position math — we don't need collision detection. _process() runs once per
# rendered frame, usually at 60+ fps but not guaranteed to be exactly 60.
# We still use delta to make all time-based calculations frame-rate independent.

func _process(delta: float) -> void:

	# Clear movement intent at the top of every frame.
	# Each movement branch below sets _desired_move if it wants the ranger to move.
	# If no branch runs, the ranger stays still (velocity goes to zero in _physics_process).
	_desired_move = Vector3.ZERO

	# ── SECTION 1: HANDLE "CAUGHT" STATE ────────────────────────────────────

	# If the player has been caught, lock the suspicion bar at 100 and show
	# the game-over message. Also listen for the restart key.
	if caught:
		suspicion_bar.value = 100.0
		status_label.text = "CAUGHT! Press R to retry"

		# Listen for the restart key while showing the caught message.
		# Note: game_timer.gd ALSO handles the restart — this is belt-and-suspenders.
		if Input.is_action_just_pressed("restart"):
			# reload_current_scene() restarts the entire scene from scratch —
			# all nodes are destroyed and recreated, all variables reset.
			get_tree().reload_current_scene()
		return
		# "return" exits the function immediately. Everything below this line is skipped.
		# This prevents the rest of the AI from running after the game is over.

	# ── SECTION 2: MEASURE DISTANCE AND PLAYER SPEED ─────────────────────────

	# global_position.distance_to() calculates the straight-line distance between
	# two 3D points. "Global" position means the position in the WORLD, not relative
	# to any parent node.
	var distance_to_player: float = global_position.distance_to(player.global_position)

	# The player's "velocity" property (from CharacterBody3D) is a Vector3: (x, y, z) speed.
	# We only care about horizontal speed (X and Z), not vertical (Y, which is gravity).
	# Vector2(x, z).length() gives us the 2D magnitude — overall horizontal speed.
	# This tells us: is the pigeon running fast, or walking slow?
	var player_speed: float = Vector2(player.velocity.x, player.velocity.z).length()

	# ── SECTION 3: DYNAMIC NOTICE RANGE ──────────────────────────────────────

	# The ranger's notice radius grows when it's already highly alert.
	# This simulates the ranger "keeping an eye out" for the known suspect.
	# At full chase suspicion, the ranger can notice the player from 20 units away —
	# much further than the default 4 units.
	var effective_notice: float
	if suspicion >= chase_threshold:
		# Fully alert — wide notice range (20 units).
		effective_notice = 20.0
	elif suspicion >= investigate_threshold:
		# Investigating — doubled notice range.
		effective_notice = notice_distance * 2.0
	else:
		# Calm patrol — standard notice range.
		effective_notice = notice_distance

	# is_nearby is true if the player is within the ranger's current notice range.
	var is_nearby: bool = distance_to_player <= effective_notice

	# ── SECTION 4: CALCULATE SUSPICION GAIN ──────────────────────────────────

	# active_gain accumulates total suspicion gain from ALL suspicious behaviours this frame.
	# "reason" is a human-readable string shown in the status label so the player knows
	# WHY they're raising suspicion.
	var active_gain: float = 0.0
	var reason: String = ""

	# SUSPICIOUS BEHAVIOUR 1: Sprinting nearby
	# "and" requires BOTH conditions to be true.
	# player_speed > suspicious_speed: player is running fast.
	# is_nearby: ranger is close enough to notice.
	if is_nearby and player_speed > suspicious_speed:
		active_gain += suspicion_gain_per_second   # += means "add to existing value"
		reason = "Too fast!"

	# SUSPICIOUS BEHAVIOUR 2: Moving directly toward food
	# _is_aiming_at_food() is a helper function (defined later) that returns true
	# if the player's movement direction closely matches the direction toward a food item.
	if is_nearby and _is_aiming_at_food(player_speed):
		# Accumulate time spent aiming at food.
		food_aim_time += delta

		# Only add suspicion after the delay has elapsed.
		if food_aim_time >= food_aim_delay:
			active_gain += food_aim_gain_per_second
			# Only set reason if it hasn't been set by a higher-priority behaviour.
			if reason == "":
				reason = "Moving suspiciously"
	else:
		# Not currently aiming at food — decay the timer at double speed.
		# maxf(a, b) returns the larger of the two values. Using maxf(..., 0.0) prevents
		# the timer from going negative.
		food_aim_time = maxf(food_aim_time - delta * 2.0, 0.0)

	# SUSPICIOUS BEHAVIOUR 3: Staring at the ranger while moving
	# We check player_speed > 0.1 because when the pigeon stands still, its
	# facing direction is frozen at whatever angle it last moved. A stationary pigeon
	# could accidentally appear to "stare" at the ranger. Only count staring while moving.
	if is_nearby and player_speed > 0.1 and _is_facing_ranger():
		stare_time += delta
		if stare_time >= stare_delay:
			active_gain += stare_gain_per_second
			if reason == "":
				reason = "Staring..."
	else:
		# Decay stare timer at double speed when not staring.
		stare_time = maxf(stare_time - delta * 2.0, 0.0)

	# SUSPICIOUS BEHAVIOUR 4: Isolated (away from other pigeons)
	# _is_isolated() returns true if NO NPC pigeon is within separation_distance of the player.
	# A lone pigeon that doesn't flock with others looks suspicious.
	if is_nearby and _is_isolated():
		active_gain += separation_gain_per_second
		if reason == "":
			reason = "Acting alone"

	# SUSPICIOUS BEHAVIOUR 5: Wading in the pond
	# Pigeons don't swim — a pigeon standing in the water looks wrong to a ranger.
	# player.get("in_water") reads the flag set by player.gd's water check each frame.
	# We use .get() (runtime lookup) because ranger.gd doesn't import player.gd directly.
	if is_nearby and player.get("in_water"):
		active_gain += 12.0
		if reason == "":
			reason = "In the water!"

	# SUSPICIOUS BEHAVIOUR 6: Walking in a straight line
	# Real pigeons are constantly bobbing, veering, and changing direction — they never
	# march in a straight line. A pigeon that walks in a perfectly straight path for
	# more than a couple of seconds looks like a person controlling it.
	#
	# HOW IT WORKS:
	# Every frame we compare the player's current movement direction to the direction
	# from the previous frame. If they're nearly identical (within 14°), the player
	# is walking "too straight." We accumulate that time in _straight_time. Once
	# it exceeds straight_line_threshold (1.5s), suspicion starts rising.
	#
	# We use player_speed > 0.3 so this only fires while actively moving — standing
	# still doesn't count as "walking straight."
	if is_nearby and player_speed > 0.3:
		# Get the player's current horizontal movement direction as a 2D vector.
		# Vector2(x, z) extracts only the horizontal plane (we ignore Y / up-down).
		# .normalized() scales the vector to length 1.0 so it's a pure direction.
		var cur_dir := Vector2(player.velocity.x, player.velocity.z).normalized()

		# We can only compare directions if we have a valid previous direction.
		# _last_move_dir.length() < 0.5 means either this is the first frame of movement
		# or the previous frame had near-zero speed (player just started moving).
		# In either case, skip the comparison and just record the current direction.
		if _last_move_dir.length() > 0.5:
			# DOT PRODUCT: cur_dir.dot(_last_move_dir) gives cos(angle between them).
			# 1.0 = same direction, 0.0 = 90° apart, -1.0 = opposite.
			# straight_line_dot = 0.97 means we only count it as "straight" when the
			# angle between this frame and last frame is less than ~14°.
			var dot := cur_dir.dot(_last_move_dir)
			if dot >= straight_line_dot:
				# Still moving in nearly the same direction — accumulate time.
				_straight_time += delta
				if _straight_time >= straight_line_threshold:
					active_gain += straight_line_gain_per_second
					if reason == "":
						reason = "Moving too straight"
			else:
				# Turned enough — decay the straight-line timer at double speed.
				# Double-speed decay means a brief turn gives noticeable relief,
				# rewarding the player for weaving naturally.
				_straight_time = maxf(_straight_time - delta * 2.0, 0.0)

		# Always update the stored direction to this frame's direction.
		_last_move_dir = cur_dir
	else:
		# Player stopped or is below the minimum speed. Decay the timer quickly
		# (3× speed) since stopping is a bigger break than turning.
		_straight_time = maxf(_straight_time - delta * 3.0, 0.0)
		# Clear the stored direction so the comparison starts fresh when movement
		# resumes — avoids a false "same direction" reading on the first moving frame.
		if player_speed <= 0.1:
			_last_move_dir = Vector2.ZERO

	# ── SECTION 5: UPDATE THE SUSPICION VALUE ────────────────────────────────

	if active_gain > 0.0:
		# Suspicion is rising. Add the total gain this frame (scaled by delta).
		# minf(a, b) returns the smaller of two values — this caps suspicion at 100.0.
		suspicion = minf(suspicion + active_gain * delta, 100.0)
	else:
		# Nothing suspicious — suspicion drains.
		var loss_rate := suspicion_loss_per_second   # Start with base loss rate.

		# Check if the player is currently pecking.
		# player.get("is_pecking") safely reads the "is_pecking" variable from player.gd.
		# .get() is used here because ranger.gd doesn't "know" about player.gd's properties
		# at compile time — this is a runtime property lookup.
		if player.get("is_pecking"):
			# Bonus loss from pecking: pigeon looks innocent when foraging.
			loss_rate += peck_loss_per_second

		# Reduce suspicion, but not below 0.
		suspicion = maxf(suspicion - loss_rate * delta, 0.0)

	# ── SECTION 6: UPDATE UI ──────────────────────────────────────────────────

	# Set the progress bar to match the current suspicion (0–100).
	suspicion_bar.value = suspicion

	# Update the vignette shader intensity.
	# suspicion / 100.0 converts to 0.0–1.0 range.
	# Multiplying by 0.65 caps the max intensity at 65% — not fully black, just ominous.
	# set_shader_parameter() passes a value into the shader's "intensity" uniform variable.
	_vignette_mat.set_shader_parameter("intensity", suspicion / 100.0 * 0.65)

	# ── SECTION 7: CHECK FOR CAUGHT ──────────────────────────────────────────

	if suspicion >= 100.0:
		# Set the caught flag and return. Next frame, the "if caught:" block at the
		# top of this function will handle the caught state permanently.
		caught = true
		return

	# ── SECTION 8: DETERMINE STATE FROM SUSPICION ────────────────────────────

	# Map the current suspicion level to one of the three states.
	# These if/elif checks run in priority order (chase > investigate > patrol).
	if suspicion >= chase_threshold:
		state = RangerState.CHASE
	elif suspicion >= investigate_threshold:
		state = RangerState.INVESTIGATE
	else:
		state = RangerState.PATROL

	# Detect a state CHANGE by comparing current state to previous state.
	# "!=" means "not equal to."
	if state != _prev_state:
		# The state just changed. If entering an alert state, play a sound once.
		# "or" means either condition being true is sufficient.
		if state == RangerState.INVESTIGATE or state == RangerState.CHASE:
			SoundManager.play_alert()

		# Kill any in-progress pop animation before starting a new one.
		# If the ranger switches states rapidly (e.g., INVESTIGATE → CHASE),
		# we don't want two tweens fighting over the label's scale at the same time.
		if _alert_tween:
			_alert_tween.kill()

		# Update the floating label above the ranger's head with text, color,
		# and a bounce pop-in animation so the player clearly notices the change.
		match state:
			RangerState.PATROL:
				# Back to calm — hide the label entirely.
				_alert_label.visible = false
				_alert_label.text = ""

			RangerState.INVESTIGATE:
				# "!" — yellow-orange, moderate bounce.
				_alert_label.text = "!"
				_alert_label.modulate = Color(1.0, 0.85, 0.1, 1.0)
				_alert_label.scale    = Vector3.ZERO
				_alert_label.visible  = true
				# Tween the scale: squish up to 1.3× then settle back to 1.0.
				# This "overshoot and settle" motion draws the eye without feeling clunky.
				_alert_tween = create_tween()
				_alert_tween.tween_property(_alert_label, "scale",
						Vector3(1.3, 1.3, 1.3), 0.10)
				_alert_tween.tween_property(_alert_label, "scale",
						Vector3(1.0, 1.0, 1.0), 0.12)

			RangerState.CHASE:
				# "!!" — red, bigger and faster bounce to signal maximum danger.
				_alert_label.text = "!!"
				_alert_label.modulate = Color(1.0, 0.2, 0.2, 1.0)
				_alert_label.scale    = Vector3.ZERO
				_alert_label.visible  = true
				_alert_tween = create_tween()
				_alert_tween.tween_property(_alert_label, "scale",
						Vector3(1.6, 1.6, 1.6), 0.08)
				_alert_tween.tween_property(_alert_label, "scale",
						Vector3(1.0, 1.0, 1.0), 0.14)

		# Update the previous state record.
		_prev_state = state

	# ── SECTION 9: MOVE THE RANGER BASED ON STATE ─────────────────────────────

	# "match" is like a switch statement — it runs one block based on the value.
	# match state: checks state against each case (RangerState.PATROL, etc.).
	# This is neater than a chain of if/elif when checking the same variable multiple times.
	match state:
		RangerState.PATROL:
			_do_patrol(delta)
		RangerState.INVESTIGATE:
			_move_toward_player(delta, investigate_speed)
		RangerState.CHASE:
			_move_toward_player(delta, chase_speed)

	# ── SECTION 10: PULSE THE SUSPICION BAR COLOR ─────────────────────────────

	# Visual feedback: the bar pulses color based on state.
	# PATROL: steady white.
	# INVESTIGATE: orange pulse, moderate speed.
	# CHASE: fast red pulse — urgent!
	match state:
		RangerState.PATROL:
			_pulse_time = 0.0                           # Reset the pulse timer.
			suspicion_bar.modulate = Color.WHITE         # White = no tint.

		RangerState.INVESTIGATE:
			_pulse_time += delta
			# sin() oscillates between -1 and 1. Rescaling with * 0.5 + 0.5 maps it to 0–1.
			# TAU is 2*PI (~6.28). TAU * 2.5 = frequency — pulses 2.5 times per second.
			var p: float = sin(_pulse_time * TAU * 2.5) * 0.5 + 0.5
			# Color(r, g, b) — red stays 1.0, green pulses between 0.35 and 0.75, blue pulses low.
			# lerp(a, b, t) blends between a and b by amount t (0=a, 1=b).
			suspicion_bar.modulate = Color(1.0, lerp(0.35, 0.75, p), p * 0.1)
			# Pulse the alert label's opacity in sync with the bar — gentle 60%→100% fade.
			# modulate.a is the alpha (opacity) channel. Pulsing it keeps the label visible
			# but adds life so it doesn't look like static text.
			_alert_label.modulate = Color(1.0, 0.85, 0.1, lerp(0.6, 1.0, p))

		RangerState.CHASE:
			_pulse_time += delta
			# TAU * 6.0 = very fast pulse (6 times per second) — alarm-like urgency.
			var p: float = sin(_pulse_time * TAU * 6.0) * 0.5 + 0.5
			# Red stays solid, green barely changes, blue = 0. Angry red pulse.
			suspicion_bar.modulate = Color(1.0, lerp(0.0, 0.3, p), 0.0)
			# Fast red flash on the label — 50%→100% opacity at chase frequency.
			_alert_label.modulate = Color(1.0, 0.2, 0.2, lerp(0.5, 1.0, p))

	# ── SECTION 11: THRESHOLD CROSSING WARNING LABELS ─────────────────────────

	# Show a warning popup at the exact moment suspicion crosses a threshold.
	# We detect the crossing by comparing current suspicion to previous-frame suspicion.
	#
	# "suspicion >= chase_threshold AND _prev_suspicion < chase_threshold" means:
	#   "This frame we're at/above 90, but LAST frame we were below 90."
	#   → We just crossed 90 for the first time.
	if suspicion >= chase_threshold and _prev_suspicion < chase_threshold:
		_warn_label.text = "DANGER!"
		_warn_label.modulate = Color(1.0, 0.15, 0.15, 1.0)   # Deep red, fully opaque.
		_warn_label.visible = true
		_warn_timer = 1.8   # Show for 1.8 seconds.

	elif suspicion >= investigate_threshold and _prev_suspicion < investigate_threshold:
		_warn_label.text = "!"
		_warn_label.modulate = Color(1.0, 0.8, 0.1, 1.0)   # Yellow-orange.
		_warn_label.visible = true
		_warn_timer = 1.5   # Show for 1.5 seconds.

	# Count down the warning timer and fade out the label.
	if _warn_timer > 0.0:
		_warn_timer -= delta   # Count down.

		# Fade the alpha (opacity) of the label as the timer approaches 0.
		# modulate.a is the alpha channel (0.0 = invisible, 1.0 = fully visible).
		# clampf(value, min, max) clamps a value between min and max.
		# _warn_timer / 0.5 ramps from 1 to 0 during the last 0.5 seconds.
		# Before that last 0.5s, the value is >1, which clampf caps to 1.0 (fully visible).
		_warn_label.modulate.a = clampf(_warn_timer / 0.5, 0.0, 1.0)

		if _warn_timer <= 0.0:
			_warn_label.visible = false   # Hide completely when timer expires.

	# Save current suspicion for next frame's threshold-crossing check.
	_prev_suspicion = suspicion

	# ── SECTION 12: UPDATE STATUS LABEL TEXT ──────────────────────────────────

	# Show human-readable status text based on state and what's happening.
	# "%" is the string formatting operator in GDScript.
	# "%s" is a placeholder for a string value. The value after % replaces the placeholder.
	match state:
		RangerState.CHASE:
			status_label.text = "Ranger: Alert!"

		RangerState.INVESTIGATE:
			if active_gain > 0.0:
				status_label.text = "Ranger: Suspicious — %s" % reason
			else:
				status_label.text = "Ranger: Investigating..."

		RangerState.PATROL:
			if active_gain > 0.0:
				status_label.text = "Ranger: Suspicious — %s" % reason
			elif is_nearby:
				status_label.text = "Ranger: Watching"
			else:
				status_label.text = "Ranger: Calm"


# =============================================================================
# LINES 202–210 — _move_toward_player(): Move the ranger toward the player
# =============================================================================

# This helper function is called during INVESTIGATE and CHASE states.
# "_delta" is kept in the signature for consistency with Godot conventions but is
# no longer used directly — movement is stored in _desired_move and applied with
# move_and_slide() in _physics_process() instead of position += ... * delta.
# "spd" (speed) is passed in from the caller — different speeds for each state.

func _move_toward_player(_delta: float, spd: float) -> void:
	# Calculate the direction vector from ranger to player.
	# "to_player" = player's world position MINUS ranger's world position.
	# The result is a Vector3 pointing from the ranger toward the player.
	var to_player := player.global_position - global_position

	# Zero out the Y component — we only want horizontal movement.
	# Without this, the ranger would try to move UP or DOWN toward the player's
	# exact height, which looks wrong and can cause issues.
	to_player.y = 0.0

	# If the ranger and player are at essentially the same position (distance < 0.1),
	# return early to avoid divide-by-zero errors in the math below.
	if to_player.length() < 0.1:
		return

	# Build a look target that's at the same height as the ranger.
	# look_at() rotates the node to face a target point. But if we gave it
	# the player's actual position, and the player is at a slightly different Y,
	# the ranger would tilt up or down — looking unrealistic.
	# By using global_position.y for the Y of the look target, we guarantee
	# the ranger always faces horizontally.
	var look_target := Vector3(player.global_position.x, global_position.y, player.global_position.z)

	# look_at(target, up) rotates this node so its -Z axis points at the target.
	# Vector3.UP is (0, 1, 0) — the "up" reference direction, so the node stays level.
	look_at(look_target, Vector3.UP)

	# Only move if the ranger is farther than approach_stop_distance from the player.
	# This creates a "personal space" zone — the ranger doesn't walk INTO the pigeon.
	if to_player.length() > approach_stop_distance:
		# .normalized() converts a direction vector to length exactly 1.0.
		# This gives a "pure direction" with no distance information.
		# We store the desired speed (units/second) in _desired_move.
		# _physics_process() multiplies this by the physics delta via move_and_slide().
		_desired_move = to_player.normalized() * spd


# =============================================================================
# LINES 212–223 — _get_nearest_food(): Find the closest uncollected food item
# =============================================================================

# Returns a reference to the nearest food item (Node3D) to the player,
# or null if no food items remain.

func _get_nearest_food() -> Node3D:
	var nearest: Node3D = null    # Will hold the closest food found so far.
	var nearest_dist: float = INF # Start with "infinity" — any real distance is smaller.
	# INF is a built-in constant for infinity (the largest possible float value).

	# get_nodes_in_group("collectibles") returns an Array of all nodes that have been
	# added to the "collectibles" group. picnic_food.gd calls add_to_group("collectibles")
	# in its _ready(), so this gives us all uncollected food items.
	for item in get_tree().get_nodes_in_group("collectibles"):
		# Cast the item to Node3D to access 3D position properties.
		# "as Node3D" tries to treat the item as a Node3D. If it's not, food_node = null.
		var food_node := item as Node3D
		if food_node == null:
			continue   # "continue" skips to the next iteration of the loop.

		# Measure the distance from the PLAYER to this food item.
		# (We want to detect if the player is heading TOWARD food, so player-to-food distance matters.)
		var d: float = player.global_position.distance_to(food_node.global_position)

		# If this food is closer than any found so far, remember it.
		if d < nearest_dist:
			nearest_dist = d
			nearest = food_node

	return nearest   # Return the nearest food, or null if the loop found nothing.


# =============================================================================
# LINES 225–237 — _is_aiming_at_food(): Is the player walking toward food?
# =============================================================================

# Returns true if the player is moving quickly and aimed at the nearest food item.

func _is_aiming_at_food(player_speed: float) -> bool:
	# Ignore very slow movement — shuffling sideways shouldn't trigger this.
	if player_speed < 0.3:
		return false

	# Find the nearest food item.
	var food_item: Node3D = _get_nearest_food()
	if food_item == null:
		return false   # No food remains — can't aim at it.

	# Vector from player to the food item.
	var to_food := food_item.global_position - player.global_position
	to_food.y = 0.0   # Flatten to horizontal (ignore height differences).

	# If the player is already very close to the food (within 0.5 units),
	# don't count it as "aiming" — they're basically already on it.
	if to_food.length() < 0.5:
		return false

	# Convert the player's velocity to a 2D horizontal direction.
	# .normalized() makes it length 1.0 — just direction, no speed.
	var move_dir := Vector2(player.velocity.x, player.velocity.z).normalized()

	# Convert the food direction to a 2D horizontal direction.
	var food_dir := Vector2(to_food.x, to_food.z).normalized()

	# THE DOT PRODUCT:
	# move_dir.dot(food_dir) computes the "dot product" of two unit vectors.
	# The dot product of two unit vectors = cos(angle between them).
	# - If they point in exactly the same direction: dot = 1.0 (angle = 0°)
	# - If they point perpendicular to each other: dot = 0.0 (angle = 90°)
	# - If they point opposite: dot = -1.0 (angle = 180°)
	#
	# food_aim_threshold = 0.9, so we return true when the angle is less than ~26°.
	# In plain English: "Is the player heading toward the food within a 26° cone?"
	return move_dir.dot(food_dir) >= food_aim_threshold


# =============================================================================
# LINES 239–246 — _is_facing_ranger(): Is the pigeon staring at the ranger?
# =============================================================================

# Returns true if the pigeon's forward direction points closely toward the ranger.

func _is_facing_ranger() -> bool:
	# Vector from the player to the ranger.
	var to_ranger := global_position - player.global_position
	to_ranger.y = 0.0   # Flatten to horizontal.

	# If they're extremely close together, skip the check (avoids division by zero).
	if to_ranger.length() < 0.5:
		return false

	# The pigeon's forward direction in world space.
	# In Godot, a node's "local Z axis" points in the direction the node faces.
	# global_transform.basis.z gives us the node's Z axis as a world-space vector.
	# (We use pigeon_visual because that's the node that actually rotates to face movement.)
	var forward := pigeon_visual.global_transform.basis.z
	forward.y = 0.0   # Flatten to horizontal.

	# Dot product check: is the pigeon's forward direction aligned with the direction to the ranger?
	# stare_threshold = 0.85 → within ~32° counts as staring.
	return forward.normalized().dot(to_ranger.normalized()) >= stare_threshold


# =============================================================================
# LINES 248–252 — _is_isolated(): Is the player alone (away from all NPCs)?
# =============================================================================

# Returns true if the player is more than separation_distance away from ALL NPC pigeons.
# Returns false if even ONE NPC is close enough (player is "blending in").

func _is_isolated() -> bool:
	for npc in npc_animals:
		# is_instance_valid() checks that the NPC node still exists in the scene.
		# Nodes can be removed from the scene, and accessing a removed node causes a crash.
		# This guard ensures safety even if an NPC were ever removed.
		if is_instance_valid(npc) and player.global_position.distance_to(npc.global_position) <= separation_distance:
			return false   # Found an NPC close enough — player is NOT isolated.
	return true   # No NPC was close enough — player IS isolated.


# =============================================================================
# LINES 254–267 — _do_patrol(): Random wandering behaviour
# =============================================================================

# Called every frame when in PATROL state.
# The ranger walks in a random direction, periodically picks a new direction,
# and turns back if it reaches the edge of the patrol boundary.

func _do_patrol(delta: float) -> void:
	# Count down the time-until-turn timer.
	time_until_turn -= delta

	# Check if the ranger has wandered outside its allowed patrol area (±7 units).
	# absf() returns the absolute value — makes negative numbers positive.
	# absf(-8) = 8, absf(5) = 5. So this checks "is X or Z further than 7 from centre?"
	# "or" means the ranger turns back if EITHER X OR Z is out of bounds.
	var is_outside_bounds: bool = (
		absf(position.x) > patrol_radius
		or absf(position.z) > patrol_radius
	)

	if is_outside_bounds:
		# Turn back toward the centre. The direction from current position to origin (0,0,0)
		# is simply the negation of the current position: -position.x, -position.z.
		# We zero the Y so the direction is purely horizontal.
		# .normalized() makes the direction vector length 1.0 (just direction, no distance).
		patrol_direction = Vector3(-position.x, 0.0, -position.z).normalized()

		# Give the ranger 1 second in this direction before it can turn again.
		time_until_turn = 1.0

	elif time_until_turn <= 0.0:
		# Inside bounds and timer expired — pick a new random direction.
		choose_new_patrol_direction()

	# Rotate the ranger to face its patrol direction.
	# We check length > 0.001 to avoid calling look_at() with a zero-length direction
	# (which would crash). This is a safety guard.
	if patrol_direction.length() > 0.001:
		# look_at() points the ranger's -Z axis toward the target point.
		# Adding patrol_direction to global_position gives a point IN FRONT of the ranger.
		look_at(global_position + patrol_direction, Vector3.UP)

	# Store the desired patrol velocity for _physics_process() to apply.
	# patrol_speed is in units/second — move_and_slide() handles the delta timing.
	_desired_move = patrol_direction * patrol_speed


# =============================================================================
# LINES 269–272 — choose_new_patrol_direction(): Pick a random walk direction
# =============================================================================

# Called at startup and whenever the patrol timer expires.

func choose_new_patrol_direction() -> void:
	# randf_range(min, max) returns a random float between min and max.
	# TAU is 2*PI ≈ 6.283 — a full circle in radians.
	# So this picks a random angle pointing anywhere in a full 360° circle.
	var angle: float = randf_range(0.0, TAU)

	# Convert the angle to a direction vector.
	# In a top-down 2D view, a point on a unit circle at angle θ is (sin(θ), cos(θ)).
	# We map that to 3D: X = sin(angle), Y = 0 (flat ground), Z = cos(angle).
	# The result is a unit vector (length = 1) pointing in a random horizontal direction.
	patrol_direction = Vector3(sin(angle), 0.0, cos(angle))

	# Pick a random time (2–4 seconds) before the next direction change.
	time_until_turn = randf_range(2.0, 4.0)


# =============================================================================
# _physics_process(delta): Applies movement and gravity every physics tick
# =============================================================================
#
# Why is this separate from _process()?
# Godot's physics engine (collision detection, move_and_slide) runs on a fixed
# timestep — _physics_process() is called at that fixed rate (default 60 Hz).
# _process() runs once per rendered frame, which can vary.
# move_and_slide() MUST be called from _physics_process() to interact correctly
# with StaticBody3D walls, the ground, and other physics bodies.
#
# The AI logic in _process() sets _desired_move (the direction + speed to travel).
# This function consumes that intent and actually moves the ranger through physics.

func _physics_process(delta: float) -> void:
	# Apply the horizontal movement set by the AI state machine in _process().
	# _desired_move.x and .z are the horizontal speed components (units/second).
	# We don't touch velocity.y here — that's handled by gravity below.
	velocity.x = _desired_move.x
	velocity.z = _desired_move.z

	# Apply gravity so the ranger falls to and stays on the ground.
	# is_on_floor() returns true when the CharacterBody3D's bottom is touching a
	# StaticBody3D (or any physics body) below it.
	# 9.8 is the standard gravitational acceleration (metres per second squared).
	if not is_on_floor():
		# Gravity pulls the ranger downward at 9.8 units/sec². Accumulate over time.
		velocity.y -= 9.8 * delta
	else:
		# On the ground — zero out downward velocity so it doesn't accumulate.
		velocity.y = 0.0

	# move_and_slide() moves the CharacterBody3D by the current "velocity" vector,
	# slides along surfaces it hits (instead of stopping dead), and updates
	# "velocity" to reflect any deflections caused by collision.
	# This is what makes the ranger stop at trees, walls, and the pond edges.
	move_and_slide()


# =============================================================================
# EXECUTION FLOW SUMMARY
# =============================================================================
#
# WHEN THE SCENE LOADS:
#   1. @onready variables are filled in (player, labels, bars, vignette).
#   2. _ready() runs: picks an initial patrol direction and finds all NPC animals.
#
# EVERY FRAME (_process):
#   1. If caught: freeze UI, listen for restart, stop.
#   2. Measure distance to player and player's speed.
#   3. Calculate the effective notice range based on current alert level.
#   4. Check all six suspicious behaviours (sprint, food-aim, stare, isolation,
#      in-water, straight-line walking) and accumulate a total suspicion gain for this frame.
#   5. Add or subtract from suspicion (scaled by delta) and cap at 0–100.
#   6. Update the progress bar and vignette shader intensity.
#   7. If suspicion hits 100, set caught = true and stop.
#   8. Map suspicion to state (PATROL / INVESTIGATE / CHASE).
#   9. Detect state changes and play the alert sound if entering a new threat state.
#  10. Move the ranger according to its state.
#  11. Pulse the suspicion bar color to match the threat level.
#  12. Show warning labels ("!" / "DANGER!") at threshold crossings and fade them out.
#  13. Update the text status label.
