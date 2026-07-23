# =============================================================================
# SCRIPT: sound_manager.gd
# ATTACHED TO: An Autoload singleton named "SoundManager"
# =============================================================================
#
# OVERVIEW
# --------
# This script generates ALL of the game's sound effects entirely from code —
# no audio files are loaded from disk. Every sound (footsteps, peck, collect,
# alert, caught, escape, tick, ambient) is built by computing mathematical
# waveforms and storing the result as audio data.
#
# This approach is called "procedural audio" — audio created by a procedure
# (a set of math instructions) rather than a recording.
#
# WHY GENERATE SOUNDS IN CODE?
# - No audio asset files needed — the entire game is self-contained in code.
# - Sounds can be mathematically tuned by changing numbers.
# - It demonstrates how digital audio works at the fundamental level.
#
# WHAT IS AUDIO AT A FUNDAMENTAL LEVEL?
# Sound is vibration. A speaker vibrates back and forth very quickly, pushing
# air in waves that your ear perceives as sound. In a computer, sound is stored
# as a sequence of numbers, each one representing how far the speaker cone
# should be pushed in or out at that exact moment.
#
# These numbers are called "samples." If we have 22050 samples per second
# (this game's sample rate), the speaker updates its position 22,050 times
# every second. The pattern of these numbers creates the waveform — the shape
# of the sound.
#
# HOW IT FITS INTO THE GAME
# -------------------------
# SoundManager is an "Autoload" — a Godot feature that creates a single
# global instance of a script that all other scripts can access by name.
# Think of it as a sound effects board shared across the whole game.
# Any script can call SoundManager.play_peck() or SoundManager.play_step()
# without needing its own audio player setup.
#
# AUTOLOAD (a Godot concept):
# Normally, scripts only run when their node is in the current scene. Autoloads
# are different — they're created when the game starts and live for the entire
# session. Other scripts access them by their registered name ("SoundManager").
# It's like a global variable that is itself a node with behaviour.

# =============================================================================
# LINE 1 — INHERITANCE
# =============================================================================

# This extends Node — the most basic node type in Godot. Node has no 3D position,
# no visuals, no physics. It's a pure container for logic, which is perfect for a
# manager script that just holds audio players.
extends Node


# =============================================================================
# LINE 3 — CONSTANT: Sample Rate
# =============================================================================

# SAMPLE_RATE is how many audio samples exist per second of sound.
# 22050 is "half CD quality" (CD quality is 44100 Hz). It's sufficient for
# game sound effects and uses half the memory of full CD quality.
#
# HERTZ (Hz): A unit of frequency meaning "times per second."
# 22050 Hz = 22,050 samples per second.
#
# WHY DOES SAMPLE RATE MATTER?
# According to the Nyquist theorem, a sample rate can only accurately reproduce
# frequencies UP TO half the sample rate. At 22050 Hz, we can produce sounds
# up to 11025 Hz — well within the range of human hearing (20 Hz – 20,000 Hz).
const SAMPLE_RATE: int = 22050


# =============================================================================
# LINES 5–13 — AUDIO PLAYER VARIABLES
# =============================================================================

# Each sound effect gets its own AudioStreamPlayer node. This allows multiple
# sounds to play at the same time independently (e.g., footsteps while ambient
# music is playing).
#
# WHAT IS AudioStreamPlayer?
# AudioStreamPlayer is a Godot node that plays audio. You give it an AudioStreamWAV
# (the audio data) and call .play() to make it start. It plays through the game's
# audio engine and out the speakers/headphones.
#
# WHY DECLARE THESE AS var INSTEAD OF @onready?
# We create these nodes PROGRAMMATICALLY in _ready() rather than placing them
# in the scene editor. @onready is for nodes already in the scene tree — these
# are created from scratch by our code.

var _peck: AudioStreamPlayer
# _peck — Plays a short thudding noise when the player's pigeon pecks.

var _npc_peck: AudioStreamPlayer
# _npc_peck — Same sound as _peck but played at much lower volume for NPC pigeons.
# NPCs peck constantly in the background; keeping them quiet makes them feel like
# ambient atmosphere rather than competing with the player's own peck feedback.

var _collect: AudioStreamPlayer
# _collect — Plays a cheerful rising chime when food is collected.

var _alert: AudioStreamPlayer
# _alert — Plays an upward frequency sweep when the ranger enters alert state.

var _caught: AudioStreamPlayer
# _caught — Plays a descending frequency sweep when the player is caught.
# Descending = sad/defeated (opposite of the ascending alert).

var _escape: AudioStreamPlayer
# _escape — Plays a four-note ascending chime when the player escapes.

var _tick: AudioStreamPlayer
# _tick — Plays a short high-pitched tick to signal the countdown when time is running out.

var _ambient: AudioStreamPlayer
# _ambient — Plays a continuously looping low-volume noise that simulates
# background atmosphere (like wind or distant park sounds).

var _step_walk: AudioStreamPlayer
# _step_walk — Plays a soft thud sound for each footstep while walking.

var _step_run: AudioStreamPlayer
# _step_run — Plays a sharper, louder thud for each footstep while running.

var _portal: AudioStreamPlayer
# _portal — A triumphant 5-note rising arpeggio that plays the moment the exit
# portal appears (when all food is collected). More dramatic than the collect
# chime to signal "now go escape!" to the player.

var _exhaust: AudioStreamPlayer
# _exhaust — A soft short noise played once when sprint stamina hits zero.
# Gives the player audio feedback that they've run out of sprint fuel.


# =============================================================================
# LINES 15–27 — _ready(): Create and configure all sound effects
# =============================================================================

func _ready() -> void:
	# Keep this node (and all its AudioStreamPlayer children) running even when the
	# scene tree is paused. Without this, pausing for the pre-game countdown would
	# also silence all audio, including the ambient park sound.
	# PROCESS_MODE_ALWAYS = ignore the scene tree's paused state entirely.
	process_mode = Node.PROCESS_MODE_ALWAYS

	# ── AUDIO BUSES ─────────────────────────────────────────────────────────
	# Godot routes audio through "buses" — named channels you can adjust independently.
	# We create two buses so Music and SFX can have separate volume controls:
	#   "Music" bus — ambient park soundscape
	#   "SFX"   bus — all sound effects (footsteps, pecks, chimes, etc.)
	# Both buses feed into the built-in "Master" bus, which controls overall volume.
	# _ensure_bus() creates the bus only if it doesn't exist yet (safe to call repeatedly).
	_ensure_bus("Music")
	_ensure_bus("SFX")

	# Apply saved volume settings immediately when the game starts.
	# This loads user://settings.cfg so the last chosen volumes are active
	# before any sound plays — even if the player skips the main menu (e.g. in editor).
	_load_saved_volumes()

	# Each sound is created by calling a generator function (like _noise, _chime, _sweep)
	# which returns an AudioStreamWAV — the raw audio data.
	# That AudioStreamWAV is then wrapped in an AudioStreamPlayer via _player().
	# _player() also sets the volume in decibels (dB).
	#
	# DECIBELS (dB):
	# Decibels measure loudness on a logarithmic scale. In Godot audio:
	# - 0 dB = "standard volume" (full volume of the source).
	# - Negative dB = quieter. -6 dB ≈ half as loud. -20 dB ≈ one-tenth as loud.
	# - Positive dB = louder (can cause distortion).

	_peck      = _player(_noise(0.05, 60.0, 0.06), -6.0)
	# _noise(0.05, 60.0, 0.06) = 0.05 seconds of low-pass filtered noise with fast
	# decay (60.0) and subtle filtering (0.06) — a very short muffled thud.
	# Volume: -6 dB (moderately quiet — pecks shouldn't dominate the mix).

	_npc_peck  = _player(_noise(0.05, 60.0, 0.06), -28.0)
	# Same waveform as _peck but 22 dB quieter — barely audible background texture.
	# With 5 NPCs all pecking at random intervals, keeping each peck very soft
	# lets them blend into the park soundscape without drawing attention.
	# Volume: -28 dB (almost inaudible individually, noticeable as a group).

	_collect   = _player(_chime([1046.5, 1318.5, 1568.0], [0.12, 0.14, 0.20]), -2.0)
	# _chime with three frequencies (C6, E6, G6 — a C major chord going up).
	# Durations [0.12, 0.14, 0.20] — each note slightly longer than the last.
	# Together they sound like a cheerful "ding-ding-ding!" pick-up sound.
	# Volume: -2 dB (nearly full volume — collecting food is a key event).

	_alert     = _player(_sweep(350.0, 700.0, 0.18), -5.0)
	# _sweep(350, 700, 0.18) — a 0.18-second rising pitch from 350 Hz to 700 Hz.
	# Rising pitch = alarm/alert — something to be wary of.
	# Volume: -5 dB (noticeable but not overwhelming).

	_caught    = _player(_sweep(440.0, 90.0, 0.65), -2.0)
	# _sweep(440, 90, 0.65) — a 0.65-second FALLING pitch from 440 Hz to 90 Hz.
	# 440 Hz = concert A. Falling to 90 Hz = a low, defeated "waaah" sound.
	# Volume: -2 dB (this is an important moment — make it heard).

	_escape    = _player(_chime([523.25, 659.25, 783.99, 1046.5], [0.10, 0.10, 0.12, 0.28]), -2.0)
	# _chime with four frequencies (C5, E5, G5, C6 — a C major arpeggio).
	# Victory fanfare — four notes climbing up, with the final note held longest.

	_tick      = _player(_tone(1200.0, 0.035, 25.0), -10.0)
	# _tone(1200, 0.035, 25.0) — a very short 1200 Hz sine tone with rapid decay.
	# 0.035 seconds, decay rate 25.0 (fades very fast) = a crisp, clean tick.
	# Volume: -10 dB (a subtle, unobtrusive countdown beep).

	_ambient   = _player(_park_ambient(), -20.0)
	# _park_ambient() — generates an 8-second looping park soundscape: soft wind
	# that breathes in and out, two rhythmic cricket voices, and two bird tweets.
	# Volume: -20 dB (quiet background — present but never intrusive).

	_step_walk = _player(_noise(0.028, 85.0, 0.07), -16.0)
	# Short noise (0.028s) with very fast decay (85.0) = a soft footstep tap.
	# Volume: -16 dB (quiet — steps should be subtle during walking).

	_step_run  = _player(_noise(0.022, 100.0, 0.10), -12.0)
	# Even shorter noise (0.022s), faster decay (100.0), slightly more filtering (0.10).
	# Produces a crisper, sharper step sound for running.
	# Volume: -12 dB (louder than walk steps — running is more energetic).

	_portal    = _player(_chime([523.25, 783.99, 1046.5, 1318.5, 1568.0], [0.08, 0.08, 0.10, 0.12, 0.30]), -2.0)
	# 5-note rising arpeggio: C5, G5, C6, E6, G6 — a triumphant "ta-da!" sound.
	# More notes and a longer final note than the collect chime, making it feel
	# like a bigger event. Volume: -2 dB (prominent — this is an important moment).

	_exhaust   = _player(_noise(0.08, 40.0, 0.12), -14.0)
	# A soft short noise (0.08s, moderate decay) — a subtle "puff" or wheeze.
	# Volume: -14 dB (quiet enough not to be annoying, loud enough to register).

	# Add all AudioStreamPlayer nodes as children so Godot's audio engine can use them.
	for p in [_peck, _npc_peck, _collect, _alert, _caught, _escape, _tick, _ambient, _step_walk, _step_run, _portal, _exhaust]:
		add_child(p)

	# ── BUS ASSIGNMENT ───────────────────────────────────────────────────────
	# Route each player to the correct bus so volume sliders affect the right sounds.
	# AudioStreamPlayer.bus is just the name of the bus as a String.
	_ambient.bus   = "SFX"    # Park soundscape → SFX bus (no music yet)
	for p in [_peck, _npc_peck, _collect, _alert, _caught, _escape, _tick, _step_walk, _step_run, _portal, _exhaust]:
		p.bus = "SFX"           # Everything else → SFX bus

	# Start the ambient loop playing immediately.
	# It loops forever (configured in _park_ambient) so it never needs to be called again.
	_ambient.play()


# =============================================================================
# LINES 29–39 — PUBLIC PLAY FUNCTIONS: Called by other scripts
# =============================================================================

# These functions are the "public interface" of SoundManager — the functions other
# scripts call. They are simple one-liners that call .play() on the appropriate player.
#
# WHY HAVE WRAPPER FUNCTIONS INSTEAD OF CALLING .play() DIRECTLY?
# Other scripts don't need to know HOW sounds are stored or generated.
# They just call "SoundManager.play_peck()". If we ever change the implementation
# (e.g., load an mp3 instead of generating sound), we only change this file,
# not every script that plays sounds. This is the programming principle of
# "encapsulation" — hiding implementation details behind a clean interface.

func play_peck()     -> void: _peck.play()
# play_peck() — plays the peck sound. Called from player.gd when the peck key is pressed.

func npc_peck_stream() -> AudioStreamWAV:
# npc_peck_stream() — returns the raw audio data for the NPC peck sound so that
# each NPC can create its OWN AudioStreamPlayer3D attached to its body.
# Using AudioStreamPlayer3D (instead of the global AudioStreamPlayer) means Godot
# automatically fades the sound with distance — you only hear an NPC peck when
# you're close to that specific bird. All five NPCs share the same stream data
# but each has its own player node positioned in the world.
	return _npc_peck.stream as AudioStreamWAV

func npc_step_stream() -> AudioStreamWAV:
# npc_step_stream() — returns the walk footstep audio data so each NPC can attach
# its own AudioStreamPlayer3D for footsteps. Same distance-falloff logic as
# npc_peck_stream(): the sound is automatically quieter the further away the bird is.
	return _step_walk.stream as AudioStreamWAV

func play_collect() -> void: _collect.play()
# play_collect() — plays the collect chime. Called from picnic_food.gd when food is taken.

func play_alert()   -> void: _alert.play()
# play_alert() — plays the alert sweep. Called from ranger.gd when entering INVESTIGATE/CHASE.

func play_caught()  -> void: _caught.play()
# play_caught() — plays the descending "caught" sound. Called from game_timer.gd on failure.

func play_escape()  -> void: _escape.play()
# play_escape() — plays the victory chime. Called from game_timer.gd on successful escape.

func play_tick()    -> void: _tick.play()
# play_tick() — plays the countdown tick. Called from game_timer.gd every 1–2 seconds
# when time is running low.

func play_portal()  -> void: _portal.play()
# play_portal() — plays the portal reveal chime. Called from escape_zone.gd the
# first time the exit portal becomes visible (all food collected).

func play_exhaust() -> void: _exhaust.play()
# play_exhaust() — plays the stamina depleted puff. Called from player.gd when
# sprint stamina first hits zero in a depletion event.

func stop_ambient() -> void: _ambient.stop()
# stop_ambient() — stops the background ambient loop. Called from game_timer.gd
# when the game ends so the hiss doesn't keep playing over the result screen.

func set_music_volume(linear: float) -> void:
# set_music_volume() — sets the Music bus volume. Nothing routes to this bus yet;
# it is reserved for when actual music tracks are added to the game.
	var idx: int = AudioServer.get_bus_index("Music")
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.001)))

func set_sfx_volume(linear: float) -> void:
# set_sfx_volume() — sets the SFX bus volume. Same logic as set_music_volume().
	var idx: int = AudioServer.get_bus_index("SFX")
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.001)))

func play_step(sprint: bool) -> void:
# play_step() — plays the appropriate footstep sound.
# "sprint" is a boolean parameter (true = running, false = walking).
# Called from player.gd at each footstep's zero-crossing moment.
	if sprint:
		_step_run.play()    # Louder, crisper step for running.
	else:
		_step_walk.play()   # Softer step for walking.


# =============================================================================
# LINES 43–47 — _player(): Wrap an AudioStreamWAV in an AudioStreamPlayer
# =============================================================================

# Helper function that creates a configured AudioStreamPlayer.
# Parameters:
#   stream — the AudioStreamWAV (raw audio data) to play
#   vol_db — volume in decibels (negative = quieter than default)
# Returns: a ready-to-use AudioStreamPlayer node.

func _player(stream: AudioStreamWAV, vol_db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()   # Create a new AudioStreamPlayer node from scratch.
	p.stream = stream                  # Assign the audio data to play.
	p.volume_db = vol_db               # Set the volume.
	return p                           # Return the configured player to the caller.


# =============================================================================
# LINES 49–52 — _put(): Write one audio sample into the byte array
# =============================================================================

# This function converts a float audio sample value into the two bytes used by
# 16-bit PCM audio format, and writes them into the raw data array.
#
# WHAT IS PCM AUDIO?
# PCM = Pulse Code Modulation. It's the most common way to store digital audio.
# Each sample is a number representing the speaker's displacement at that moment.
# In 16-bit audio: each sample is stored as a 16-bit integer (2 bytes).
# The range is -32768 (maximum inward push) to +32767 (maximum outward push).
#
# WHAT ARE BYTES?
# A byte is 8 bits. A bit is either 0 or 1. One byte can hold values 0–255.
# A 16-bit sample needs TWO bytes. The 16-bit value is split into a "low byte"
# (the lower 8 bits) and a "high byte" (the upper 8 bits).
# This splitting is called "little-endian" byte order (low byte first).

func _put(d: PackedByteArray, i: int, val: float) -> void:
	# Convert the float (-1.0 to +1.0) to a 16-bit integer (-32768 to +32767).
	# Multiplying by 32767 scales the full -1.0..+1.0 range to the full int range.
	# int() truncates to a whole number (removes the decimal part).
	# clampi(value, min, max) ensures the result stays within the valid int range.
	# This prevents audio "clipping" (values outside the range cause distortion).
	var v: int = clampi(int(val * 32767.0), -32768, 32767)

	# Write the LOW byte into the array at position i*2.
	# "& 0xFF" is a bitwise AND with 0xFF (binary 11111111).
	# This keeps only the lowest 8 bits of v — the "low byte."
	# d[i * 2] = low byte position (each sample takes 2 bytes: i*2 and i*2+1).
	d[i * 2]     = v & 0xFF

	# Write the HIGH byte into the array at position i*2+1.
	# ">> 8" is a right-shift by 8 bits — moves the upper 8 bits down to become the low 8.
	# "& 0xFF" then keeps only those low 8 bits (discards any sign extension).
	d[i * 2 + 1] = (v >> 8) & 0xFF


# =============================================================================
# LINES 54–60 — _done(): Package raw audio bytes into an AudioStreamWAV object
# =============================================================================

# Takes a completed PackedByteArray of audio samples and wraps it in an
# AudioStreamWAV object that Godot can play.
# This is always the last step in any sound-generation function.

func _done(d: PackedByteArray) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()              # Create a new audio stream.
	w.format   = AudioStreamWAV.FORMAT_16_BITS # Declare the format: 16-bit samples.
	w.stereo   = false                         # Mono audio (one channel, not stereo/two channels).
	w.mix_rate = SAMPLE_RATE                   # Tell Godot how many samples per second (22050).
	w.data     = d                             # Attach the raw byte data.
	return w                                   # Return the ready AudioStreamWAV.


# =============================================================================
# LINES 63–69 — _tone(): Generate a pure sine wave with exponential decay
# =============================================================================
#
# Creates a single musical tone — a clean, pure pitch like a tuning fork or bell.
# The sound starts at full volume and fades out exponentially (quickly at first, then slowly).
#
# Parameters:
#   freq  — frequency in Hz (higher number = higher pitch). 440 Hz = concert A.
#   dur   — duration in seconds.
#   decay — how fast the sound fades (higher = faster fade).

func _tone(freq: float, dur: float, decay: float) -> AudioStreamWAV:
	# Calculate total number of samples needed: duration × samples per second.
	# int() converts the float result to an integer (sample count must be whole number).
	var n: int = int(dur * float(SAMPLE_RATE))

	# PackedByteArray is an efficient array of bytes (raw memory).
	# We need n samples × 2 bytes each = n*2 bytes total.
	var d := PackedByteArray(); d.resize(n * 2)

	# Generate each sample one by one.
	for i in n:
		# t = time in seconds for this sample.
		# float() converts int to float for accurate division (int/int in GDScript = int).
		var t: float = float(i) / float(SAMPLE_RATE)

		# The sample value = a sine wave × an exponential decay envelope.
		#
		# sin(TAU * freq * t):
		#   TAU = 2*PI ≈ 6.283. TAU * freq = angular frequency (radians per second).
		#   Multiplying by t gives total angle at this moment in time.
		#   sin() oscillates between -1 and +1, producing the tone's waveform.
		#
		# exp(-t * decay):
		#   exp() is "e to the power of". e ≈ 2.718.
		#   At t=0: exp(0) = 1.0 (full volume).
		#   As t increases, -t * decay becomes more negative, exp() approaches 0.
		#   This is an "exponential decay" — the sound fades naturally like a bell.
		_put(d, i, sin(TAU * freq * t) * exp(-t * decay))

	return _done(d)   # Package and return the audio stream.


# =============================================================================
# LINES 72–80 — _noise(): Generate low-pass filtered noise (soft thud/rustle)
# =============================================================================
#
# Creates "noise" — a random signal that produces a breathy, thuddy, or rustle-like sound.
# Pure random noise sounds harsh and hissy. "Low-pass filtering" smooths it out,
# removing high frequencies to produce softer, warmer sounds.
#
# Parameters:
#   dur    — duration in seconds.
#   decay  — how fast the sound fades (controls how "punchy" it is).
#   filter — controls the strength of low-pass filtering (0=no filter, 1=heavily filtered).
#            Smaller = more high frequencies kept (brighter). Larger = more filtered (softer).

func _noise(dur: float, decay: float, filter: float = 0.35) -> AudioStreamWAV:
	var n: int = int(dur * float(SAMPLE_RATE))
	var d := PackedByteArray(); d.resize(n * 2)

	# "prev" holds the previous sample value — used for the low-pass filter.
	var prev: float = 0.0

	for i in n:
		var t: float = float(i) / float(SAMPLE_RATE)

		# Generate a random value between -1.0 and +1.0, scaled by decay envelope.
		# randf_range(-1.0, 1.0) returns a different random number every call.
		# exp(-t * decay) applies the volume envelope — starts loud, fades out.
		# The product is a sample of decaying random noise.
		#
		# LOW-PASS FILTER (using lerp):
		# Instead of using the raw random sample directly, we blend it with the
		# previous sample using lerp. lerp(prev, new, filter) means:
		#   result = prev * (1 - filter) + new * filter
		# When filter is small (e.g., 0.07): result = mostly prev, a little new.
		# This means each sample is very close to the one before → smooth, filtered sound.
		# When filter is large (e.g., 0.35): each sample jumps more → harsher sound.
		# This is a "first-order IIR low-pass filter" — used in audio hardware for centuries.
		prev = lerp(prev, randf_range(-1.0, 1.0) * exp(-t * decay), filter)
		_put(d, i, prev)

	return _done(d)


# =============================================================================
# LINES 83–91 — _sweep(): Generate a frequency sweep (pitch rising or falling)
# =============================================================================
#
# Creates a sound where the pitch changes over time — either rising (alert sound)
# or falling (caught sound). The technical name for this is a "chirp."
#
# Parameters:
#   f0  — starting frequency in Hz.
#   f1  — ending frequency in Hz. If f1 > f0, pitch rises. If f1 < f0, pitch falls.
#   dur — duration in seconds.

func _sweep(f0: float, f1: float, dur: float) -> AudioStreamWAV:
	var n: int = int(dur * float(SAMPLE_RATE))
	var d := PackedByteArray(); d.resize(n * 2)

	# "phase" accumulates the total angle of the sine wave so far.
	# WHY ACCUMULATE PHASE INSTEAD OF COMPUTING sin(TAU * f * t)?
	# When frequency changes over time, using TAU * f * t directly causes
	# "phase discontinuities" — sudden jumps in the waveform that sound like clicks.
	# Accumulating the phase smoothly avoids this.
	var phase: float = 0.0

	for i in n:
		# frac = how far through the sweep we are, from 0.0 (start) to 1.0 (end).
		var frac: float = float(i) / float(n)

		# The current frequency at this moment, interpolated between f0 and f1.
		# lerp(f0, f1, frac) gives f0 when frac=0, f1 when frac=1, and in between otherwise.
		# This smoothly slides the pitch from the start frequency to the end frequency.
		#
		# Add the phase increment for this sample:
		# TAU * current_freq / SAMPLE_RATE = radians per sample at the current frequency.
		phase += TAU * lerp(f0, f1, frac) / float(SAMPLE_RATE)

		# Generate the sample: sine of accumulated phase, with slight volume fade toward end.
		# (1.0 - frac * 0.6) means the volume goes from 1.0 at start to 0.4 at end —
		# a gentle trailing off so the sound doesn't cut off abruptly.
		_put(d, i, sin(phase) * (1.0 - frac * 0.6))

	return _done(d)


# =============================================================================
# LINES 94–109 — _park_ambient(): Generate a looping park soundscape
# =============================================================================
#
# Creates a realistic outdoor park ambience by layering three sound types:
#
#   1. WIND     — very softly filtered noise that breathes in and out (gentle gusts)
#   2. CRICKETS — two cricket "voices" chirping at slightly different pitches
#   3. BIRDS    — two brief ascending/descending tweet calls spaced in the loop
#
# WHY USE A FLOAT BUFFER?
# Each layer is ADDED on top of the previous ones. Working in floats lets us do that
# cleanly (no precision loss). We convert to bytes just once at the end.
#
# WHY 8 SECONDS?
# Cricket bursts repeat every 2.0 s. 8 ÷ 2.0 = exactly 4 — the cricket pattern
# completes an integer number of cycles, so the loop has no audible seam.

func _park_ambient() -> AudioStreamWAV:
	var dur: float = 8.0
	var n: int = int(dur * float(SAMPLE_RATE))   # 8 × 22050 = 176400 samples

	# Float buffer for mixing all three layers before converting to bytes.
	# PackedFloat32Array is an efficient Godot array type for 32-bit floats.
	var buf := PackedFloat32Array()
	buf.resize(n)

	# ── LAYER 1: SOFT WIND ────────────────────────────────────────────────────
	# Ultra-heavy low-pass filter (0.007) = each sample is 99.3% the previous one.
	# Result: a very smooth, gentle hiss — not harsh static.
	# A slow sine wave (period ~3.2 s) breathes the amplitude up/down like natural gusts.
	var wnd: float = 0.0
	for i in n:
		var t: float = float(i) / float(SAMPLE_RATE)
		wnd = lerp(wnd, randf_range(-1.0, 1.0), 0.007)
		# Gust envelope: amplitude varies between 0.50 and 1.00 on a slow cycle.
		var gust: float = 0.75 + 0.25 * sin(TAU * t / 3.2)
		buf[i] = wnd * 0.28 * gust   # Wind is the base layer — sets every index.

	# ── LAYER 2: CRICKET CHIRPS ───────────────────────────────────────────────
	# Real crickets chirp by rubbing their wings together ("stridulation").
	# We model each chirp burst as 4 rapid short pulses of a high-frequency sine tone.
	# Two "voices" at slightly different pitches (3200 Hz / 3500 Hz) are offset by
	# half a period so they interleave — one chirps while the other is silent.
	var c_pulse: int = int(0.018 * float(SAMPLE_RATE))   # 18 ms per pulse ≈ 397 samples
	var c_gap:   int = int(0.007 * float(SAMPLE_RATE))   # 7 ms silence between pulses
	var c_step:  int = int(2.0   * float(SAMPLE_RATE))   # 2.0 s between burst starts (spaced out)

	# Half a step in samples — used to offset voice 1 so it chirps between voice 0's chirps.
	# Computed with float math (c_step * 0.5) then cast to int to avoid GDScript's
	# integer-division warning, which fires when "/" is used between two int values.
	var c_half: int = int(c_step * 0.5)

	for voice in 2:
		var freq: float = 3200.0 + float(voice) * 300.0   # 3200 Hz or 3500 Hz (lower, less shrill)
		# voice 0 starts at sample 0; voice 1 starts at c_half (halfway through the interval).
		var burst: int = voice * c_half
		while burst < n:
			for pulse in 4:
				# Sample index where this individual pulse begins.
				var ps: int = burst + pulse * (c_pulse + c_gap)
				for si in c_pulse:
					var idx: int = ps + si
					if idx >= n:
						break   # Don't write past the end of the buffer.
					var tl: float = float(si) / float(SAMPLE_RATE)
					# Rapid decay (90.0) = pulse rings for only a few milliseconds.
					# exp(-tl * 90) drops from 1.0 to near zero in about 50 ms.
					buf[idx] = buf[idx] + sin(TAU * freq * tl) * exp(-tl * 90.0) * 0.08
			burst += c_step

	# ── LAYER 3: BIRD TWEETS ─────────────────────────────────────────────────
	# Two brief bird calls placed at t=1.8 s and t=5.6 s in the 8-second loop.
	# Each tweet is a 100 ms sine tone that sweeps up (2400→3200 Hz) then down (→2600 Hz),
	# with a bell-shaped volume envelope so it fades in and out smoothly.
	var bird_times: Array = [1.8, 5.6]
	for call_t in bird_times:
		var call_start: int = int(call_t * float(SAMPLE_RATE))
		var call_n: int     = int(0.10 * float(SAMPLE_RATE))   # 100 ms = 2205 samples
		var bphase: float   = 0.0   # Accumulated phase — avoids pitch-change clicks.
		for si in call_n:
			var idx: int = call_start + si
			if idx >= n:
				break
			var frac: float = float(si) / float(call_n)   # Progress: 0.0 → 1.0
			# Pitch sweeps up in the first half, then back down in the second half.
			var bfreq: float
			if frac < 0.5:
				bfreq = lerp(2400.0, 3200.0, frac * 2.0)           # Rising
			else:
				bfreq = lerp(3200.0, 2600.0, (frac - 0.5) * 2.0)  # Falling
			bphase += TAU * bfreq / float(SAMPLE_RATE)
			# sin(PI × frac) = a bell curve (0 → 1 → 0) — smooth attack and release.
			buf[idx] = buf[idx] + sin(bphase) * sin(PI * frac) * 0.35

	# ── PACK FLOATS TO PCM BYTES ──────────────────────────────────────────────
	# clampf() prevents any sample from exceeding ±0.98, avoiding audio clipping.
	var d := PackedByteArray()
	d.resize(n * 2)
	for i in n:
		_put(d, i, clampf(buf[i], -0.98, 0.98))

	# Build the looping AudioStreamWAV.
	var w := AudioStreamWAV.new()
	w.format     = AudioStreamWAV.FORMAT_16_BITS
	w.stereo     = false
	w.mix_rate   = SAMPLE_RATE
	w.data       = d
	# LOOP_FORWARD: when playback reaches loop_end, it jumps back to loop_begin instantly.
	w.loop_mode  = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end   = n - 1
	return w


# =============================================================================
# LINES 111–125 — _chime(): Generate a sequence of musical tones
# =============================================================================
#
# Creates a chime: a series of musical notes played one after another, each
# note being a decaying sine tone (like a piano key or xylophone hit).
# Used for the collect sound (3 notes) and escape sound (4 notes).
#
# Parameters:
#   freqs — Array of frequencies (Hz) for each note, in order.
#   durs  — Array of durations (seconds) for each note. Must match freqs in length.

func _chime(freqs: Array, durs: Array) -> AudioStreamWAV:
	# gap = number of samples of silence between notes.
	# 0.018 seconds * 22050 samples/sec ≈ 397 samples of gap.
	# A small gap prevents notes from running together.
	var gap: int = int(0.018 * float(SAMPLE_RATE))

	# Calculate total length: sum of all notes + a gap after each.
	var total: int = 0
	for dur in durs:
		# For each note: convert duration to sample count, add the gap.
		total += int(float(dur) * float(SAMPLE_RATE)) + gap

	# Allocate the full byte array for all notes combined.
	var d := PackedByteArray(); d.resize(total * 2)

	# "offset" tracks which sample position we're writing to.
	# Each note is written after the previous one, advancing the offset.
	var offset: int = 0

	# Loop over each note using its index (fi = "frequency index").
	# freqs.size() returns the number of elements in the freqs array.
	for fi in freqs.size():
		# Get the frequency and duration for this note.
		var freq: float = float(freqs[fi])
		var frames: int = int(float(durs[fi]) * float(SAMPLE_RATE))

		# Generate the samples for this note.
		for i in frames:
			var t: float = float(i) / float(SAMPLE_RATE)
			# Each note is a sine wave with exponential decay (decay rate = 6.0).
			# 0.85 scales peak volume slightly below 1.0 to avoid clipping
			# (since multiple notes combined in one stream can add up if not careful).
			_put(d, offset + i, sin(TAU * freq * t) * exp(-t * 6.0) * 0.85)

		# Move the write position forward by this note's length PLUS the gap.
		# The gap samples are left as zeros (silence) — d.resize() zero-initializes.
		offset += frames + gap

	return _done(d)   # Package and return the complete chime stream.


# =============================================================================
# AUDIO BUS HELPERS
# =============================================================================

func _ensure_bus(bus_name: String) -> void:
	# Creates an audio bus with the given name if one doesn't already exist.
	# AudioServer.get_bus_index() returns -1 if no bus with that name exists.
	# AudioServer.add_bus() appends a new bus at the end of the bus list.
	# get_bus_count()-1 is the index of the newly added bus.
	# set_bus_send() connects this bus to "Master" so its output goes through
	# the main volume control before reaching the speakers.
	if AudioServer.get_bus_index(bus_name) == -1:
		AudioServer.add_bus()
		var idx: int = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")

func _load_saved_volumes() -> void:
	# Loads user://settings.cfg and applies the saved volume levels.
	# Called once in _ready() so volumes are correct from the very first sound.
	# If no settings file exists yet (first run), this returns early and uses
	# the default bus volumes (0 dB = full volume).
	var config := ConfigFile.new()
	if config.load("user://settings.cfg") != OK:
		return
	set_music_volume(config.get_value("audio", "music", 1.0))
	set_sfx_volume(config.get_value("audio",  "sfx",   1.0))


# =============================================================================
# EXECUTION FLOW SUMMARY
# =============================================================================
#
# WHEN THE GAME STARTS:
#   1. SoundManager (Autoload) is created before any scene loads.
#   2. _ready() runs:
#      a. Nine audio streams are generated using math (noise, tones, sweeps, chimes).
#      b. Nine AudioStreamPlayer nodes are created, each holding one stream.
#      c. All nine players are added as children of SoundManager.
#      d. The ambient loop starts playing immediately.
#
# DURING GAMEPLAY:
#   - Any script calls SoundManager.play_peck(), play_step(), etc.
#   - The matching AudioStreamPlayer.play() is called, starting playback.
#   - Multiple sounds can play simultaneously because each has its own player.
#
# AUDIO GENERATION CHAIN (for each sound):
#   Math functions → PackedByteArray → _done() → AudioStreamWAV → _player() → AudioStreamPlayer
