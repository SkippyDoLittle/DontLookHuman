# adaptive_music_director.gd -- Long-form procedural score with an adaptive mix.
#
# The four streams share the same 24-second, 16-bar timeline. They always begin
# sample-aligned, while their gains crossfade in response to suspicion and session
# state. Keeping adaptation in the mix (rather than rebuilding audio at runtime)
# makes transitions smooth and predictable even while the scene tree is paused.

class_name AdaptiveMusicDirector
extends Node

const SAMPLE_RATE: int = 22050
const LOOP_SECONDS: float = 24.0
const BAR_COUNT: int = 16
const BAR_SECONDS: float = LOOP_SECONDS / float(BAR_COUNT)
const BEAT_SECONDS: float = BAR_SECONDS / 4.0
const CROSSFADE_SECONDS: float = 0.85
const MUSIC_OUTPUT_LINEAR_GAIN: float = 0.55
const SILENT_GAIN: float = 0.0001
const STOP_GAIN: float = 0.001
const MAX_PCM_BYTES: int = 8 * 1024 * 1024

const LAYER_NORMAL: StringName = &"normal"
const LAYER_TENSION: StringName = &"tension"
const LAYER_RHYTHM: StringName = &"rhythm"
const LAYER_CHASE: StringName = &"chase"
const LAYER_NAMES: Array[StringName] = [
	LAYER_NORMAL,
	LAYER_TENSION,
	LAYER_RHYTHM,
	LAYER_CHASE,
]

var _players: Dictionary = {}
var _current_gains: Dictionary = {}
var _target_gains: Dictionary = {}
var _tension: float = 0.0
var _session_state: StringName = &"title"
var _outcome: StringName = &""
var _running: bool = false
var _stop_when_silent: bool = false
var _level_id: StringName = &""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_players()
	_apply_mix_targets()

func _process(delta: float) -> void:
	var fade_step := maxf(delta, 0.0) / CROSSFADE_SECONDS
	var loudest_gain := 0.0
	for layer_name in LAYER_NAMES:
		var current := float(_current_gains.get(layer_name, 0.0))
		var target := float(_target_gains.get(layer_name, 0.0))
		current = move_toward(current, target, fade_step)
		_current_gains[layer_name] = current
		loudest_gain = maxf(loudest_gain, current)
		var player := _players.get(layer_name) as AudioStreamPlayer
		if is_instance_valid(player):
			player.volume_db = linear_to_db(maxf(
				current * MUSIC_OUTPUT_LINEAR_GAIN,
				SILENT_GAIN
			))

	if _stop_when_silent and loudest_gain <= STOP_GAIN:
		_stop_when_silent = false
		_running = false
		for layer_name in LAYER_NAMES:
			var player := _players.get(layer_name) as AudioStreamPlayer
			if is_instance_valid(player):
				player.stop()

# Starts all stems sample-aligned. Only stems selected by the current adaptive mix
# are audible; the others remain silent so a later crossfade cannot drift off beat.
func start_music(level_id: StringName = &"") -> void:
	_level_id = level_id
	_outcome = &""
	_stop_when_silent = false
	_running = true
	var pitch := _level_pitch(level_id)
	for layer_name in LAYER_NAMES:
		var player := _players.get(layer_name) as AudioStreamPlayer
		if not is_instance_valid(player):
			continue
		player.pitch_scale = pitch
		if not player.playing:
			player.play(0.0)
	_apply_mix_targets()

# Fades the score instead of cutting it. Processing is ALWAYS, so this completes
# even when the result screen or pause menu has paused the gameplay tree.
func stop_music() -> void:
	_stop_when_silent = true
	for layer_name in LAYER_NAMES:
		_target_gains[layer_name] = 0.0

func set_tension(amount: float) -> void:
	_tension = clampf(amount, 0.0, 1.0)
	if _outcome.is_empty():
		_apply_mix_targets()

func set_session_state(session_state: StringName) -> void:
	_session_state = session_state
	if _outcome.is_empty():
		_apply_mix_targets()

# These reshape/duck the adaptive bed; SoundManager's existing caught and escape
# stings remain the foreground punctuation and are intentionally not replaced.
func play_success() -> void:
	_outcome = &"success"
	_stop_when_silent = false
	_set_targets(0.42, 0.0, 0.10, 0.0)

func play_caught() -> void:
	_outcome = &"caught"
	_stop_when_silent = false
	_set_targets(0.0, 0.18, 0.0, 0.28)

func is_music_running() -> bool:
	return _running

func loop_duration_seconds() -> float:
	return LOOP_SECONDS

func arrangement_bar_count() -> int:
	return BAR_COUNT

func layer_names() -> Array[StringName]:
	return LAYER_NAMES.duplicate()

func layer_player(layer_name: StringName) -> AudioStreamPlayer:
	return _players.get(layer_name) as AudioStreamPlayer

func layer_target_linear(layer_name: StringName) -> float:
	return float(_target_gains.get(layer_name, 0.0))

func layer_current_linear(layer_name: StringName) -> float:
	return float(_current_gains.get(layer_name, 0.0))

func music_output_linear_gain() -> float:
	return MUSIC_OUTPUT_LINEAR_GAIN

func total_pcm_bytes() -> int:
	var total := 0
	for layer_name in LAYER_NAMES:
		var player := _players.get(layer_name) as AudioStreamPlayer
		if is_instance_valid(player) and player.stream is AudioStreamWAV:
			total += (player.stream as AudioStreamWAV).data.size()
	return total

func _build_players() -> void:
	var streams: Dictionary = {
		LAYER_NORMAL: _build_normal_layer(),
		LAYER_TENSION: _build_tension_layer(),
		LAYER_RHYTHM: _build_rhythm_layer(),
		LAYER_CHASE: _build_chase_layer(),
	}
	for layer_name in LAYER_NAMES:
		var player := AudioStreamPlayer.new()
		player.name = String(layer_name).capitalize() + "MusicLayer"
		player.stream = streams[layer_name]
		player.bus = &"Music"
		player.volume_db = linear_to_db(SILENT_GAIN)
		add_child(player)
		_players[layer_name] = player
		_current_gains[layer_name] = 0.0
		_target_gains[layer_name] = 0.0

func _apply_mix_targets() -> void:
	if _stop_when_silent:
		return
	var normal_drop := smoothstep(0.12, 0.92, _tension)
	var normal := lerpf(0.78, 0.10, normal_drop)
	var tension := smoothstep(0.16, 0.74, _tension) * 0.48
	var rhythm := smoothstep(0.34, 0.76, _tension) * 0.54
	var chase := smoothstep(0.68, 1.0, _tension) * 0.82

	match _session_state:
		&"title":
			normal *= 0.56
			tension = 0.0
			rhythm = 0.0
			chase = 0.0
		&"countdown":
			normal *= 0.72
			rhythm = maxf(rhythm, 0.08)
		&"paused":
			normal *= 0.46
			tension *= 0.38
			rhythm = 0.0
			chase = 0.0
		&"finished":
			normal *= 0.34
			tension *= 0.22
			rhythm = 0.0
			chase = 0.0
		_:
			pass
	_set_targets(normal, tension, rhythm, chase)

func _set_targets(normal: float, tension: float, rhythm: float, chase: float) -> void:
	_target_gains[LAYER_NORMAL] = clampf(normal, 0.0, 1.0)
	_target_gains[LAYER_TENSION] = clampf(tension, 0.0, 1.0)
	_target_gains[LAYER_RHYTHM] = clampf(rhythm, 0.0, 1.0)
	_target_gains[LAYER_CHASE] = clampf(chase, 0.0, 1.0)

func _level_pitch(level_id: StringName) -> float:
	if level_id.is_empty():
		return 1.0
	var variants: Array[float] = [0.97, 1.0, 1.03]
	var variant_index := absi(String(level_id).hash()) % variants.size()
	return variants[variant_index]

# -- Arrangement builders ---------------------------------------------------

func _new_buffer() -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(int(LOOP_SECONDS * float(SAMPLE_RATE)))
	result.fill(0.0)
	return result

# A mischievous pizzicato lead, alternating motifs and answering bass notes.
# Sixteen independently arranged bars prevent the old short-loop repetition.
func _build_normal_layer() -> AudioStreamWAV:
	var buffer := _new_buffer()
	var roots: Array[int] = [50, 46, 53, 48, 50, 55, 46, 48, 50, 46, 53, 48, 55, 53, 48, 50]
	var motifs: Array[Array] = [
		[0, 3, 7, 5], [0, 7, 10, 3], [0, 2, 7, 3], [0, 5, 3, -2],
		[0, 3, 10, 7], [0, 7, 5, 12], [0, 10, 7, 3], [0, 5, 10, 7],
	]
	for bar in BAR_COUNT:
		var bar_start := float(bar) * BAR_SECONDS
		var root := roots[bar]
		var motif: Array = motifs[bar % motifs.size()]
		_add_pluck(buffer, bar_start, 0.34, _midi(root - 12), 0.20, 0.7)
		for beat in 4:
			var note_offset := int(motif[beat])
			var anticipation := -0.045 if beat == 3 and bar % 3 == 1 else 0.0
			_add_pluck(
				buffer,
				bar_start + float(beat) * BEAT_SECONDS + anticipation,
				0.24,
				_midi(root + 12 + note_offset),
				0.20 if beat > 0 else 0.25,
				1.0
			)
		if bar % 4 == 3:
			_add_pluck(buffer, bar_start + BAR_SECONDS - 0.18, 0.16, _midi(root + 24), 0.14, 1.2)
	return _finish_stream(buffer)

# A low, gently dissonant tremolo bed. It has harmonic motion but leaves enough
# space for ranger whistles, heartbeat, footsteps, and the normal melody.
func _build_tension_layer() -> AudioStreamWAV:
	var buffer := _new_buffer()
	var roots: Array[int] = [38, 38, 34, 36, 38, 41, 34, 36, 38, 34, 41, 36, 41, 39, 36, 38]
	for bar in BAR_COUNT:
		var bar_start := float(bar) * BAR_SECONDS
		var root := roots[bar]
		_add_drone(buffer, bar_start, BAR_SECONDS + 0.06, _midi(root), 0.16, 3.0 + float(bar % 3))
		_add_drone(buffer, bar_start + 0.05, BAR_SECONDS, _midi(root + (6 if bar % 2 == 0 else 7)), 0.08, 4.0)
		if bar % 4 == 2:
			_add_pluck(buffer, bar_start + BAR_SECONDS * 0.5, 0.42, _midi(root + 18), 0.10, 0.45)
	return _finish_stream(buffer)

# Muted park-percussion: soft shoe taps, twig clicks, and off-beat brush hits.
func _build_rhythm_layer() -> AudioStreamWAV:
	var buffer := _new_buffer()
	for bar in BAR_COUNT:
		var bar_start := float(bar) * BAR_SECONDS
		_add_low_hit(buffer, bar_start, 0.18, 74.0, 0.30)
		_add_noise_hit(buffer, bar_start + BEAT_SECONDS * 2.0, 0.11, 0.18, 0.24 + float(bar))
		for beat in 4:
			if beat == 2 and bar % 2 == 0:
				continue
			var swing := 0.035 if beat % 2 == 1 else 0.0
			_add_noise_hit(
				buffer,
				bar_start + float(beat) * BEAT_SECONDS + BEAT_SECONDS * 0.5 + swing,
				0.055,
				0.11,
				float(bar * 7 + beat)
			)
		if bar % 4 == 3:
			_add_noise_hit(buffer, bar_start + BAR_SECONDS - 0.12, 0.09, 0.17, 90.0 + float(bar))
	return _finish_stream(buffer)

# Fast bass/woodblock pursuit stem. It only enters at high suspicion.
func _build_chase_layer() -> AudioStreamWAV:
	var buffer := _new_buffer()
	var roots: Array[int] = [38, 38, 34, 36, 38, 41, 34, 36, 38, 34, 41, 36, 41, 39, 36, 38]
	var patterns: Array[Array] = [
		[0, 0, 7, 3, 0, 10, 7, 3],
		[0, 7, 0, 10, 3, 7, 12, 10],
		[0, 3, 7, 0, 10, 7, 3, -2],
		[0, 0, 3, 7, 10, 12, 10, 7],
	]
	for bar in BAR_COUNT:
		var bar_start := float(bar) * BAR_SECONDS
		var root := roots[bar]
		var pattern: Array = patterns[bar % patterns.size()]
		for eighth in 8:
			var start := bar_start + float(eighth) * BAR_SECONDS / 8.0
			_add_pluck(buffer, start, 0.15, _midi(root + int(pattern[eighth])), 0.20, 0.35)
			if eighth in [0, 3, 6]:
				_add_noise_hit(buffer, start, 0.045, 0.12, float(bar * 11 + eighth))
		_add_low_hit(buffer, bar_start, 0.22, 58.0, 0.28)
		_add_low_hit(buffer, bar_start + BEAT_SECONDS * 2.0, 0.18, 64.0, 0.22)
	return _finish_stream(buffer)

func _add_pluck(
	buffer: PackedFloat32Array,
	start_seconds: float,
	duration: float,
	frequency: float,
	amplitude: float,
	brightness: float
) -> void:
	var start_frame := maxi(int(start_seconds * float(SAMPLE_RATE)), 0)
	var frame_count := int(duration * float(SAMPLE_RATE))
	var end_frame := mini(start_frame + frame_count, buffer.size())
	for frame in range(start_frame, end_frame):
		var local_time := float(frame - start_frame) / float(SAMPLE_RATE)
		var envelope := (1.0 - exp(-local_time * 75.0)) * exp(-local_time * 10.0)
		var phase := TAU * frequency * local_time
		var voice := sin(phase) * 0.72
		voice += sin(phase * 2.0) * 0.20 * brightness
		voice += sin(phase * 3.0) * 0.08 * brightness
		buffer[frame] += voice * envelope * amplitude

func _add_drone(
	buffer: PackedFloat32Array,
	start_seconds: float,
	duration: float,
	frequency: float,
	amplitude: float,
	tremolo_rate: float
) -> void:
	var start_frame := maxi(int(start_seconds * float(SAMPLE_RATE)), 0)
	var frame_count := int(duration * float(SAMPLE_RATE))
	var end_frame := mini(start_frame + frame_count, buffer.size())
	for frame in range(start_frame, end_frame):
		var local_time := float(frame - start_frame) / float(SAMPLE_RATE)
		var progress := local_time / duration
		var edge_fade := sin(PI * clampf(progress, 0.0, 1.0))
		var tremolo := 0.68 + 0.32 * sin(TAU * tremolo_rate * local_time)
		var phase := TAU * frequency * local_time
		var voice := sin(phase) * 0.78 + sin(phase * 1.005) * 0.22
		buffer[frame] += voice * edge_fade * tremolo * amplitude

func _add_low_hit(
	buffer: PackedFloat32Array,
	start_seconds: float,
	duration: float,
	frequency: float,
	amplitude: float
) -> void:
	var start_frame := maxi(int(start_seconds * float(SAMPLE_RATE)), 0)
	var frame_count := int(duration * float(SAMPLE_RATE))
	var end_frame := mini(start_frame + frame_count, buffer.size())
	for frame in range(start_frame, end_frame):
		var local_time := float(frame - start_frame) / float(SAMPLE_RATE)
		var pitch_drop := frequency * (1.0 - 0.20 * local_time / duration)
		buffer[frame] += sin(TAU * pitch_drop * local_time) * exp(-local_time * 18.0) * amplitude

func _add_noise_hit(
	buffer: PackedFloat32Array,
	start_seconds: float,
	duration: float,
	amplitude: float,
	seed_offset: float
) -> void:
	var start_frame := maxi(int(start_seconds * float(SAMPLE_RATE)), 0)
	var frame_count := int(duration * float(SAMPLE_RATE))
	var end_frame := mini(start_frame + frame_count, buffer.size())
	var filtered := 0.0
	for frame in range(start_frame, end_frame):
		var local_time := float(frame - start_frame) / float(SAMPLE_RATE)
		var raw := _deterministic_noise(float(frame) + seed_offset * 997.0)
		filtered = lerpf(filtered, raw, 0.28)
		buffer[frame] += filtered * exp(-local_time * 34.0) * amplitude

func _deterministic_noise(value: float) -> float:
	var scrambled := sin(value * 12.9898 + 78.233) * 43758.5453
	return (scrambled - floor(scrambled)) * 2.0 - 1.0

func _midi(note_number: int) -> float:
	return 440.0 * pow(2.0, (float(note_number) - 69.0) / 12.0)

func _finish_stream(buffer: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(buffer.size() * 2)
	for frame in buffer.size():
		var value := clampi(int(clampf(buffer[frame], -0.96, 0.96) * 32767.0), -32768, 32767)
		data[frame * 2] = value & 0xFF
		data[frame * 2 + 1] = (value >> 8) & 0xFF
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.stereo = false
	stream.mix_rate = SAMPLE_RATE
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = buffer.size() - 1
	return stream
