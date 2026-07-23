# =============================================================================
# SCRIPT: game_timer.gd
# ATTACHED TO: The "GameTimer" node in Main.tscn
# =============================================================================
#
# OVERVIEW
# --------
# This is the "director" script of the game. It manages the highest-level game
# logic — the things that span the entire session and coordinate multiple systems:
#
#   - The title screen (shown before the game starts)
#   - The countdown timer (90 seconds of playtime)
#   - Detecting win and lose conditions
#   - Screen shake when the player is caught
#   - Pulsing the exit marker (green arrow) once all food is collected
#   - Countdown sound ticks when time is almost up
#   - Displaying the result screen (score, time used, peak suspicion)
#   - Saving and loading the personal best time to disk
#
# HOW IT FITS INTO THE GAME
# -------------------------
# GameTimer sits at the top of the game's logic hierarchy. While ranger.gd and
# player.gd manage their own individual behaviours, game_timer.gd monitors both
# of them and declares the game won or lost when the right conditions are met.
#
# When the game ends (for any reason), _finish() is called. It shows the result
# screen UI and hides the gameplay HUD — this works for all three endings:
# caught, time's up, and escaped.

# =============================================================================
# LINE 1 — INHERITANCE
# =============================================================================

# Extends Node (the simplest Godot node type). This script is pure logic —
# it has no 3D position, no visuals, no collision. It just watches and coordinates.
extends Node


# =============================================================================
# LINES 3–4 — EXPORTED VARIABLES
# =============================================================================

@export var time_limit: float = 60.0
# time_limit — How many seconds the player has to steal all food and escape.
# 60.0 = 1 minute. Short enough that you always feel the clock ticking.
# Exported so you can change it in the Inspector without touching the code.

@export var items_total: int = 3
# items_total — How many food items exist in the scene. Used in the results screen
# to calculate how many items were stolen (total - remaining = collected).
# Must be kept in sync with how many PicnicFood nodes are actually in the scene.
# "int" = whole number (no decimals). You can't have 2.5 food items.


# =============================================================================
# LINES 6–16 — @onready NODE REFERENCES
# =============================================================================

# All of these use get_node() with a path starting from Main (the parent scene).
# "../" means "go up to my parent, then find the named child."
# These are all UI (HUD) elements and scene objects the script needs to access.

@onready var timer_label: Label = get_node("../HUD/TimerLabel")
# timer_label — The on-screen text showing the time remaining (e.g., "1:30").
# Updated every frame by _update_timer().

@onready var result_bg: ColorRect = get_node("../HUD/ResultBackground")
# result_bg — A solid colored rectangle that darkens the screen behind the result text.
# Made visible when the game ends (win or lose) to focus attention on the result.
# ColorRect is a UI node that draws a filled rectangle of a single color.

@onready var result_label: Label = get_node("../HUD/ResultLabel")
# result_label — The text label showing the end-of-game summary:
# "CAUGHT!" or "ESCAPED!" plus time used, items stolen, and peak suspicion.

@onready var status_label: Label = get_node("../HUD/RangerStatus")
# status_label — The label showing "Ranger: Calm", "Ranger: Alert!", etc.
# Hidden when the result screen appears (it's irrelevant after the game ends).

@onready var objective_label: Label = get_node("../HUD/ObjectiveStatus")
# objective_label — The label showing the current objective (how many items left, etc.).
# Also hidden when the result screen appears.

@onready var suspicion_bar: ProgressBar = get_node("../HUD/SuspicionBar")
# suspicion_bar — The visual bar showing suspicion level (0–100).
# Hidden on the result screen.

@onready var ranger: Node3D = get_node("../Ranger")
# ranger — Reference to the Ranger node. Used to read the ranger's suspicion
# and caught values each frame to detect game-over conditions.

@onready var exit_area: Node = get_node("../EscapeZone/ExitArea")
# exit_area — Reference to the ExitArea node (the invisible trigger zone at the park exit).
# Used to read the "escaped" property — when it becomes true, the player has won.

@onready var _camera: Camera3D = get_node("../Player/SpringArm3D/Camera3D")
# _camera — Reference to the game camera. We shift its h_offset and v_offset each frame
# during screen shake to jitter the view without actually moving the camera's position.
# Camera3D is Godot's 3D camera node — the player sees the world through it.

@onready var _title_screen: CanvasLayer = get_node("../TitleScreen")
# _title_screen — Reference to the TitleScreen CanvasLayer node (the menu shown before
# the game starts). We make it invisible when the player presses Space to begin.
# CanvasLayer is a node that renders 2D UI on top of the 3D world.

@onready var _exit_marker: MeshInstance3D = get_node("../EscapeZone/ExitMarker")
# _exit_marker — Reference to the green exit portal mesh in the scene.
# We animate its color in code (pulsing green) once all food is collected.

@onready var _fade_overlay: ColorRect = get_node("../HUD/FadeOverlay")
# _fade_overlay — A full-screen black ColorRect that fades from opaque to transparent
# when the scene loads. Gives a smooth reveal instead of the scene just appearing.
# After the fade it is hidden completely so it doesn't block any UI interaction.

@onready var _transition_rect: ColorRect = get_node("../TransitionLayer/FadeRect")
# _transition_rect — A full-screen black ColorRect on its own CanvasLayer at layer 20.
# Layer 20 sits ABOVE both the TitleScreen (layer 10) and the HUD (layer 1), so this
# rect can cover ANY UI when we need a screen transition.
# Used for: title → game (fade to black then reveal game world)
#           game over → restart (fade to black before scene reload)
# CanvasLayer does NOT have a "modulate" property (it's not a CanvasItem), so we tween
# this ColorRect's "color:a" alpha instead — that's legal because ColorRect IS a CanvasItem.

@onready var _stamina_bar: ProgressBar = get_node("../HUD/StaminaBar")
# _stamina_bar — Reference to the stamina ProgressBar so we can hide it on the
# result screen (the stamina system is irrelevant once the game has ended).

@onready var _countdown_label: Label = get_node("../HUD/CountdownLabel")
# _countdown_label — Large centered label that displays "3", "2", "1", "GO!" just
# before the level starts. Hidden by default; shown and hidden by countdown logic.

@onready var _pause_menu: CanvasLayer = get_node("../PauseMenu")
# _pause_menu — Reference to the PauseMenu CanvasLayer in Main.tscn.
# Showing it (visible = true) opens the pause overlay; hiding it closes it.
# The pause menu sets PROCESS_MODE_ALWAYS itself so its buttons respond while the
# scene tree is paused — same pattern used by this node and SoundManager.


# =============================================================================
# LINE 18 — CONSTANT: Save File Path
# =============================================================================

const SAVE_PATH: String = "user://best_time.dat"
# SAVE_PATH — The file path where the best time is saved between sessions.
# "user://" is Godot's special prefix for the user's save data directory.
# On Windows this maps to: C:\Users\[name]\AppData\Roaming\Godot\app_userdata\[project]\
# "best_time.dat" is the filename. ".dat" = data file (no specific format required).
# Using a constant means this path is defined in one place — easy to change if needed.


# =============================================================================
# LINES 20–27 — RUNTIME VARIABLES
# =============================================================================

var time_remaining: float = 0.0
# time_remaining — How many seconds are left on the clock. Starts at 0 and is set
# to time_limit in _ready(). Counts DOWN each frame in _process().

var peak_suspicion: float = 0.0
# peak_suspicion — The highest suspicion value the ranger ever reached during this run.
# Tracked to show on the results screen. Updated each frame by comparing to current suspicion.

var game_over: bool = false
# game_over — Set to true when the game ends (win or lose). Prevents _finish() from
# being called twice and halts most of the game logic.

var game_started: bool = false
# game_started — Set to true when the player presses Space on the title screen.
# Until this is true, the countdown doesn't run and the game doesn't respond to gameplay.

var _tick_timer: float = 0.0
# _tick_timer — Countdown timer for the next tick sound. When it reaches 0, a tick
# plays and the timer resets. Gets shorter as time runs out (1 sec when under 20s,
# then 2 sec intervals, then 1 sec intervals under 10s).
# Wait — actually: it resets to 2.0 if time > 10 seconds, 1.0 if under 10 seconds.

var _shake_trauma: float = 0.0
# _shake_trauma — Controls the intensity of the screen shake effect.
# Set to 1.0 when the player is caught (maximum shake), then decays to 0 each frame.
# "Trauma" is a common game dev term for the input to a shake system:
# higher trauma = more intense shake.

var _exit_mat: StandardMaterial3D
# _exit_mat — The material (color/shader) applied to the exit marker mesh.
# We create this in code (not from the editor) so we can change its color at runtime
# to create the pulsing effect. StandardMaterial3D is Godot's default 3D material type.

var _exit_pulse_time: float = 0.0
# _exit_pulse_time — A timer that increases every frame once all food is collected.
# Used as the input to sin() to create the pulsing color animation on the exit marker.

var _counting_down: bool  = false
# _counting_down — True while the 3-2-1-GO! countdown is running.
# During this time everything is still frozen (tree is paused) and we block all
# other game logic. Flips to false when the countdown finishes.

var _countdown_val:   int   = 3
# _countdown_val — The number currently shown on screen (3, 2, 1, then 0 = GO!).

var _countdown_timer: float = 0.0
# _countdown_timer — Accumulates delta each frame. When it reaches 1.0, we
# decrement _countdown_val and reset this timer to 0.0 (counts once per second).


# =============================================================================
# LINES 29–38 — _ready(): Setup when scene loads
# =============================================================================

func _ready() -> void:
	# ── FADE-IN FROM BLACK ────────────────────────────────────────────────────
	# The FadeOverlay is a full-screen black rectangle that starts fully opaque.
	# A Tween is Godot's built-in tool for smoothly animating a value over time.
	# create_tween() creates a new Tween attached to this node.
	var tween := create_tween()
	# tween_property(target_node, "property_path", end_value, duration_in_seconds)
	# "modulate:a" is the alpha (opacity) component of the node's color tint.
	# We animate it from 1.0 (fully opaque black) to 0.0 (fully transparent) over 0.8s.
	tween.tween_property(_fade_overlay, "modulate:a", 0.0, 0.8)
	# tween_callback() queues a function to run AFTER the previous step finishes.
	# Once the fade is done, we hide the overlay so it can't block any input.
	# "func():" creates an anonymous function (a "lambda") called right here inline.
	tween.tween_callback(func(): _fade_overlay.visible = false)

	# Set the initial time. We store it in time_remaining (not directly using time_limit)
	# because time_remaining will count down — time_limit stays unchanged as the full amount.
	time_remaining = time_limit

	# Create a brand-new material for the exit marker.
	# We do NOT use the material already on the mesh in the scene, because that material
	# is "shared" — if we change its color, it would affect every mesh using that same material.
	# Creating a new StandardMaterial3D gives us a private copy we can modify safely.
	_exit_mat = StandardMaterial3D.new()

	# Start with solid green (R=0, G=1, B=0, A=1). Alpha=1.0 means fully opaque.
	_exit_mat.albedo_color = Color(0.0, 1.0, 0.0, 1.0)

	# Assign our new material to surface 0 (the first/only surface) of the exit marker mesh.
	# set_surface_override_material(index, material) replaces the material on that surface
	# with a new one that is unique to this instance — our private copy above.
	_exit_marker.set_surface_override_material(0, _exit_mat)

	# Load the personal best time (used on the result screen, not the ready screen).
	# We call this here so the best is available when _finish() runs.
	# The variable is stored as an instance variable via _load_best().
	var _best_check := _load_best()   # Result unused here — _finish() calls _load_best() again.

	# ── FREEZE UNTIL READY ───────────────────────────────────────────────────
	# Set this node to ALWAYS process so it can receive Space key input and run
	# the countdown even while the scene tree is paused below.
	# PROCESS_MODE_ALWAYS = this node's _process() runs regardless of pause state.
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Pause the entire scene tree. Every node with default process mode
	# (PROCESS_MODE_PAUSABLE / PROCESS_MODE_INHERIT) will stop:
	# - Player can't move (CharacterBody3D _physics_process freezes)
	# - NPCs freeze in place
	# - Ranger stops patrolling
	# The tree stays paused until the countdown finishes and "GO!" fires.
	get_tree().paused = true


# =============================================================================
# LINES 40–89 — _process(delta): Main game loop logic, runs every frame
# =============================================================================

func _process(delta: float) -> void:

	# ── SECTION 1: SCREEN SHAKE ─────────────────────────────────────────────

	# If there is any remaining trauma, apply camera shake.
	if _shake_trauma > 0.0:
		# Decay the trauma over time. 1.8 is the decay rate.
		# maxf(a, b) returns the larger value — prevents going below 0.0.
		_shake_trauma = maxf(_shake_trauma - delta * 1.8, 0.0)

		# Screen shake magnitude = trauma squared. This is the standard game dev formula
		# for trauma-based shake. Squaring gives small trauma = very little shake,
		# and large trauma = very dramatic shake. Much better than linear scaling.
		# 0.04 scales the max magnitude to a visible but not extreme jitter (±0.04 units).
		var mag: float = _shake_trauma * _shake_trauma * 0.04

		# Apply random offsets to the camera's horizontal and vertical position.
		# h_offset and v_offset shift the camera's view without moving the camera node itself.
		# This is important: if we moved the SpringArm or camera position directly, it
		# would break the camera's follow behaviour. Offset is a "safe" way to jitter.
		# randf_range(-mag, mag) returns a random float between -mag and +mag.
		_camera.h_offset = randf_range(-mag, mag)
		_camera.v_offset = randf_range(-mag, mag)
	else:
		# No trauma — ensure camera offsets are exactly zero (no residual jitter).
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0

	# ── SECTION 2: COUNTDOWN ────────────────────────────────────────────────

	# If the countdown is running, update it each second and block all game logic.
	# The tree is still paused here — only this node runs (PROCESS_MODE_ALWAYS).
	if _counting_down:
		_countdown_timer += delta
		if _countdown_timer >= 1.0:
			_countdown_timer -= 1.0
			_countdown_val   -= 1
			if _countdown_val > 0:
				# Still counting — update the displayed number.
				_countdown_label.text = str(_countdown_val)
			else:
				# Countdown complete — show "GO!" and start the game.
				_countdown_label.text = "GO!"
				_counting_down = false
				game_started   = true
				# Unpause the scene tree so player, NPCs, and ranger all start moving.
				get_tree().paused = false
				# Hide "GO!" after a short pause so it doesn't linger on screen.
				var tween := create_tween()
				tween.tween_interval(0.55)
				tween.tween_callback(func(): _countdown_label.visible = false)
		return   # Don't process game logic while counting down.

	# ── SECTION 3: READY SCREEN ─────────────────────────────────────────────

	# If the game hasn't started yet, wait for Space to begin the countdown.
	if not game_started:
		if Input.is_action_just_pressed("ui_accept"):
			# Fade the ready screen to black, then launch the countdown.
			# Using _transition_rect (layer 20) covers everything cleanly.
			var tween := create_tween()
			tween.tween_property(_transition_rect, "color:a", 1.0, 0.20)
			tween.tween_callback(func():
				_title_screen.visible  = false   # Hide the "READY?" overlay.
				_transition_rect.color.a = 0.0   # Instantly clear the black rect.
				_countdown_val   = 3
				_countdown_timer = 0.0
				_counting_down   = true
				_countdown_label.text    = "3"
				_countdown_label.visible = true
			)
		return   # Don't run game logic before the countdown has finished.

	# ── PAUSE TOGGLE ────────────────────────────────────────────────────────

	# Escape key opens/closes the pause menu during active gameplay.
	# This check only runs after the countdown has finished (game_started = true,
	# _counting_down = false). It does NOT fire during game over — that section
	# is handled separately below.
	# game_timer.gd has PROCESS_MODE_ALWAYS so it detects Escape while paused.
	if not game_over:
		if Input.is_action_just_pressed("pause_game"):
			if _pause_menu.visible:
				# Already paused — close the menu and unpause the scene tree.
				_pause_menu.visible = false
				get_tree().paused   = false
			else:
				# Not paused — open the menu and freeze the scene tree.
				_pause_menu.visible = true
				get_tree().paused   = true

	# If the pause menu is visible, skip all remaining game logic so the timer
	# doesn't keep counting and win/lose conditions aren't evaluated while frozen.
	if _pause_menu.visible:
		return

	# ── SECTION 4: GAME OVER HANDLING ───────────────────────────────────────

	# If the game has ended (win or lose), only listen for the restart key.
	if game_over:
		if Input.is_action_just_pressed("restart"):
			# Fade to black before reloading — prevents a jarring hard cut.
			# We use _transition_rect (layer 20) so the black covers the result screen too.
			# (_fade_overlay lives in the HUD at layer 1 — it would be hidden beneath the
			# result screen's ColorRect background. _transition_rect is always on top.)
			# Once fully black, reload the scene — the new scene fades in on its own.
			var tween := create_tween()
			tween.tween_property(_transition_rect, "color:a", 1.0, 0.4)
			tween.tween_callback(func(): get_tree().reload_current_scene())
		return   # Don't run the rest of the game logic after game over.

	# ── SECTION 5: TRACK PEAK SUSPICION ──────────────────────────────────────

	# Read the ranger's current suspicion value.
	# float() converts whatever .get() returns into a float to be safe.
	# ranger.get("suspicion") is a runtime property lookup — reads "suspicion"
	# from ranger.gd by name (works even though game_timer.gd doesn't formally
	# "know about" ranger.gd's properties at compile time).
	var s: float = float(ranger.get("suspicion"))

	# Update peak suspicion if this frame's value is higher than any seen before.
	# ">" = "greater than."
	if s > peak_suspicion:
		peak_suspicion = s

	# ── SECTION 5: CHECK WIN/LOSE CONDITIONS ─────────────────────────────────

	# Check if the ranger has caught the player.
	# bool() converts the value to true/false.
	if bool(ranger.get("caught")):
		_finish(false, "CAUGHT!")   # false = not a success.
		return

	# Check if the player has escaped through the exit zone.
	if bool(exit_area.get("escaped")):
		_finish(true, "ESCAPED!")   # true = success.
		return

	# ── SECTION 6: COUNT DOWN THE TIMER ──────────────────────────────────────

	# Subtract this frame's time from the remaining time.
	# maxf(..., 0.0) prevents time from going below zero.
	time_remaining = maxf(time_remaining - delta, 0.0)

	# Update the displayed timer text.
	_update_timer()

	# ── SECTION 7: PULSE THE EXIT MARKER ─────────────────────────────────────

	# Count items still in the scene.
	var items_left: int = get_tree().get_nodes_in_group("collectibles").size()

	# Only pulse when all items have been collected.
	if items_left == 0:
		# Advance the pulse timer.
		_exit_pulse_time += delta

		# Create a 0.0–1.0 oscillating value.
		# TAU * 1.5 = pulsing 1.5 times per second.
		# sin() range is -1 to +1. Multiplying by 0.5 and adding 0.5 maps it to 0–1.
		var pulse: float = sin(_exit_pulse_time * TAU * 1.5) * 0.5 + 0.5

		# Set the exit marker's material color based on the pulse value.
		# Color(r, g, b, a): r and b pulse from 0 to 0.3/0.2; g pulses from 0.5 to 1.0.
		# Result: the marker pulsates between dark green and bright green.
		_exit_mat.albedo_color = Color(pulse * 0.3, 0.5 + pulse * 0.5, pulse * 0.2, 1.0)

	# ── SECTION 8: COUNTDOWN TICK SOUNDS ─────────────────────────────────────

	# Only play tick sounds when under 20 seconds remaining (and time isn't up yet).
	if time_remaining > 0.0 and time_remaining < 20.0:
		# Count down the tick interval timer.
		_tick_timer -= delta

		if _tick_timer <= 0.0:
			# Time to play a tick!
			SoundManager.play_tick()

			# Reset the tick interval. Under 10 seconds: every 1 second.
			# Between 10 and 20 seconds: every 2 seconds.
			# The ternary "a if condition else b" chooses between the two values.
			_tick_timer = 1.0 if time_remaining < 10.0 else 2.0

	# ── SECTION 9: TIME'S UP ─────────────────────────────────────────────────

	# If the timer has run out, trigger the failure ending.
	if time_remaining <= 0.0:
		_finish(false, "TIME'S UP!")


# =============================================================================
# LINES 91–99 — _update_timer(): Format and display the countdown timer
# =============================================================================

func _update_timer() -> void:
	# Convert remaining seconds to a whole number, rounding UP.
	# ceili() = "ceiling integer" = always rounds up. E.g., ceili(29.3) = 30.
	# We round UP so the display shows 1 while there is still any fraction of
	# a second left — it reads "0" ONLY when time has fully expired.
	var secs: int = ceili(time_remaining)

	# Format as M:SS (minutes and zero-padded seconds).
	# secs / 60 = minutes (integer division in GDScript truncates to whole number).
	# secs % 60 = seconds remainder. %02d pads to 2 digits (e.g., 7 → "07").
	# E.g., secs=87 → "1:27". secs=5 → "0:05".
	timer_label.text = "%d:%02d" % [secs / 60.0, secs % 60]

	# Change the timer color to signal urgency:
	if time_remaining <= 20.0:
		# Under 20 seconds: red (danger).
		timer_label.modulate = Color(1.0, 0.3, 0.3)
	elif time_remaining <= 40.0:
		# Under 40 seconds: orange/yellow (warning).
		timer_label.modulate = Color(1.0, 0.75, 0.2)
	else:
		# Over 40 seconds: white (neutral/safe).
		timer_label.modulate = Color.WHITE
		# Color.WHITE is shorthand for Color(1.0, 1.0, 1.0, 1.0).
		# "modulate" tints the node and all its children by multiplying their colors
		# by this value. White = no tint (1.0 × anything = anything unchanged).


# =============================================================================
# LINES 101–137 — _finish(): Called once when the game ends (win or lose)
# =============================================================================

# Parameters:
#   success  — true if the player escaped successfully, false if caught or time ran out.
#   headline — the main message to show ("ESCAPED!", "CAUGHT!", "TIME'S UP!").

func _finish(success: bool, headline: String) -> void:
	# Guard: if _finish was somehow called twice, do nothing the second time.
	# This prevents a situation where both "caught" and "time's up" trigger at
	# the same moment and try to show two result screens.
	if game_over:
		return

	# Mark the game as over — this stops the main game logic in _process().
	game_over = true

	if success:
		# Play the victory sound.
		SoundManager.play_escape()
	else:
		# Play the failure sound.
		SoundManager.play_caught()

		# Trigger screen shake by setting trauma to maximum (1.0).
		# The shake decay in _process() will handle fading it out.
		_shake_trauma = 1.0

	# ── CALCULATE RESULT STATISTICS ──────────────────────────────────────────

	# How many food items are still in the scene? (Remaining = not yet collected.)
	var remaining: int = get_tree().get_nodes_in_group("collectibles").size()

	# How many were collected? (Started with items_total, subtract those remaining.)
	var collected: int = items_total - remaining

	# How much time was used? (Total time minus what's left = time elapsed.)
	var used: float = time_limit - time_remaining

	# Convert elapsed time to minutes and seconds.
	var m: int = int(used / 60.0)   # int() truncates — no rounding.
	var s: int = int(used) % 60     # Remainder seconds.

	# ── CALCULATE LETTER GRADE ───────────────────────────────────────────────
	# Grade is only awarded for successful escapes — failure always earns F.
	# Score is 0–100, split across three categories:
	#   Items  (40 pts): full marks for stealing every item.
	#   Time   (35 pts): more time remaining = higher score.
	#   Stealth(25 pts): lower peak suspicion = higher score.
	var grade: String = "F"
	if success:
		var item_score:  float = float(collected) / float(items_total) * 40.0
		var time_score:  float = maxf(0.0, (time_limit - used) / time_limit) * 35.0
		var susp_score:  float = maxf(0.0, 1.0 - peak_suspicion / 100.0) * 25.0
		var total_score: float = item_score + time_score + susp_score
		# Thresholds: A=85+, B=70+, C=55+, D=40+, F=below 40
		if   total_score >= 85.0: grade = "A"
		elif total_score >= 70.0: grade = "B"
		elif total_score >= 55.0: grade = "C"
		elif total_score >= 40.0: grade = "D"
		# else stays "F" (shouldn't happen on success but guards edge cases)

	# ── BUILD THE RESULT TEXT ─────────────────────────────────────────────────

	# Short flavor line giving each outcome its own personality.
	var flavor: String
	if headline == "ESCAPED!":
		flavor = "\"Just a pigeon. Nothing to see here.\""
	elif headline == "CAUGHT!":
		flavor = "Caught red-beaked by the ranger!"
	else: # TIME'S UP!
		flavor = "The picnic packed up before you could escape."

	# "──────────────────" uses the Unicode box-drawing character (U+2500).
	# It draws a clean horizontal divider line between the headline and the stats.
	# "\n" creates a new line; "%d/%02d/%%" fill in the numeric placeholders.
	result_label.text = (
		headline
		+ "\n" + flavor
		+ "\n\n──────────────────"
		+ "\nGrade:          " + grade
		+ "\nTime:           %d:%02d"
		+ "\nItems stolen:   %d / %d"
		+ "\nPeak suspicion: %d%%"
		+ "\n──────────────────"
	) % [m, s, collected, items_total, int(peak_suspicion)]

	# ── HANDLE BEST TIME (ALL OUTCOMES) ──────────────────────────────────────
	# Load the saved best time. Returns INF if no run has ever been saved.
	var best: float = _load_best()

	if success:
		var is_new_best: bool = (best == INF or used < best)
		if is_new_best:
			_save_best(used)
			result_label.text += "\n★  New best time!"
		else:
			var bm: int = int(best / 60.0)
			var bs: int = int(best) % 60
			result_label.text += "\nBest: %d:%02d" % [bm, bs]
	else:
		# Show the existing best on failure screens so the player has a target.
		# Only shown if at least one successful run has been completed.
		if best != INF:
			var bm: int = int(best / 60.0)
			var bs: int = int(best) % 60
			result_label.text += "\nBest so far: %d:%02d" % [bm, bs]

	result_label.text += "\n\nPress R to play again"

	# ── COLOR THE RESULT ──────────────────────────────────────────────────────

	# Tint the result label green on win, red on loss.
	result_label.modulate = Color(0.35, 1.0, 0.45) if success else Color(1.0, 0.35, 0.35)

	# Shift the background panel color to reinforce the outcome:
	# Win → dark green tint, Loss → dark red tint.
	# The base darkness stays high (alpha 0.88) so the 3D scene behind is readable.
	result_bg.color = Color(0.03, 0.14, 0.06, 0.88) if success else Color(0.14, 0.03, 0.03, 0.88)

	# ── SHOW THE RESULT SCREEN, HIDE THE GAMEPLAY HUD ────────────────────────

	result_bg.visible = true
	result_label.visible = true
	timer_label.visible = false
	status_label.visible = false
	objective_label.visible = false
	suspicion_bar.visible = false
	_stamina_bar.visible = false

	# Stop the ambient background loop. Keeping it playing over the result screen
	# sounds odd — silence (or just the result fanfare) feels more appropriate.
	SoundManager.stop_ambient()


# =============================================================================
# LINES 139–143 — _load_best(): Read best time from disk
# =============================================================================

# Returns the saved best time in seconds, or INF if no save file exists.
# INF is used as a sentinel value meaning "no best time has been saved."

func _load_best() -> float:
	# Check if the save file exists before trying to open it.
	# FileAccess.file_exists() returns true or false.
	# If we skip this check and the file doesn't exist, the open() call returns null,
	# and calling .get_float() on null would crash.
	if not FileAccess.file_exists(SAVE_PATH):
		return INF   # No save file — no best time.

	# Open the file for reading. FileAccess.READ means "open existing file, read-only."
	# FileAccess.open() returns a FileAccess object, or null if the open fails.
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)

	# Read and return the float stored in the file, or INF if the file couldn't be opened.
	# This is a ternary: "if f is not null, read the float; otherwise return INF."
	return f.get_float() if f != null else INF


# =============================================================================
# _save_best(): Write the best time to disk
# =============================================================================
#
# This function has ONE job: save the player's best completion time to a file
# so it can be loaded again the next time the game is launched.
# It is only called from _finish() when the player escapes with a new record.

func _save_best(time_used: float) -> void:
	# Open (or create) the save file for writing.
	# FileAccess.WRITE creates the file if it doesn't exist, or overwrites it if it does.
	# SAVE_PATH is the constant defined at the top of this script ("user://best_time.dat").
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)

	# Only write if the file opened successfully.
	# If f is null it means the file could not be opened (e.g., disk is full or
	# the path is invalid). The "if f != null" guard prevents a crash in that case.
	if f != null:
		# store_float() writes the time_used value as a 4-byte floating-point number.
		# This is the format that get_float() in _load_best() knows how to read back.
		# FileAccess in Godot 4 closes the file automatically when "f" goes out of scope
		# (when the function ends), so no manual close call is needed.
		f.store_float(time_used)


# =============================================================================
# EXECUTION FLOW SUMMARY
# =============================================================================
#
# WHEN THE SCENE LOADS:
#   1. @onready fills in all node references.
#   2. _ready() sets up the timer, creates the exit material, and loads the best time.
#
# WHILE TITLE SCREEN IS SHOWING:
#   - Screen shake is still updated (cosmetic, in case of future use).
#   - _process() returns early — no game logic runs.
#   - Player presses Space → game_started = true, title screen hides.
#
# DURING GAMEPLAY:
#   Every frame:
#   1. Screen shake is updated (decaying from 0 by default).
#   2. Peak suspicion is tracked from ranger.
#   3. Win/lose conditions are checked (caught? escaped?).
#   4. Timer counts down. Timer label is updated with color-coded urgency.
#   5. Once all food is collected: exit marker pulses green.
#   6. Under 20 seconds: tick sounds play at increasing frequency.
#   7. If time hits 0: _finish(false, "TIME'S UP!") is called.
#
# ON GAME END (_finish):
#   1. game_over is set true (stops the loop).
#   2. Sound plays (escape chime or caught sweep).
#   3. Screen shake is triggered if caught.
#   4. Result statistics are calculated and formatted.
#   5. Result label is colored green (win) or red (lose).
#   6. If escaped and new best time: best time is saved to disk.
#   7. Result screen appears and gameplay HUD is hidden (always, for all endings).
#   8. Player presses R to reload the scene and try again.
