class_name ParkAmbienceDirector
extends Node

# One cheap, deterministic ambience loop lives with the active level.  The
# Ambience bus is deliberately separate from Music so either can be muted
# without changing the other.

signal profile_started(profile_id: StringName)

const SETTINGS_PATH: String = "user://settings.cfg"
const BUS_NAME: StringName = &"Ambience"
const DIRECTOR_GROUP: StringName = &"park_ambience_directors"
const MIX_RATE: int = 11025
const LOOP_SECONDS: float = 8.0
const BASE_VOLUME_DB: float = -9.0
const TENSION_DUCK_DB: float = -10.0

@export var profile_override: StringName = &""

var active_profile_id: StringName = &"level_01"
var _player: AudioStreamPlayer
var _tension: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Stop the legacy autoload loop before registering this director.  The
	# SoundManager integration can then delegate start/stop calls through the
	# group without two ambience beds playing at once.
	var sound_manager := get_node_or_null("/root/SoundManager")
	if sound_manager != null and sound_manager.has_method("stop_ambient"):
		sound_manager.call("stop_ambient")
	add_to_group(DIRECTOR_GROUP)
	ensure_ambience_bus()
	load_saved_volume()
	active_profile_id = profile_override if not profile_override.is_empty() else _resolve_level_id()
	_player = AudioStreamPlayer.new()
	_player.name = "AmbiencePlayer"
	_player.bus = BUS_NAME
	_player.volume_db = BASE_VOLUME_DB
	_player.stream = build_profile_stream(active_profile_id)
	add_child(_player)
	start_ambient()
	profile_started.emit(active_profile_id)

func start_ambient() -> void:
	if is_instance_valid(_player) and not _player.playing:
		_player.play()

func stop_ambient() -> void:
	if is_instance_valid(_player):
		_player.stop()

func set_tension(amount: float) -> void:
	_tension = clampf(amount, 0.0, 1.0)
	if is_instance_valid(_player):
		_player.volume_db = BASE_VOLUME_DB + TENSION_DUCK_DB * _tension * _tension

func _resolve_level_id() -> StringName:
	var level := get_parent()
	if level != null:
		var config: Variant = level.get("level_config")
		if config != null:
			var configured_id: Variant = config.get("level_id")
			if configured_id != null and not String(configured_id).is_empty():
				return StringName(configured_id)
		match String(level.name):
			"Level02_Playground":
				return &"level_02"
			"Level03_Lakeside":
				return &"level_03"
			"Level04_Festival":
				return &"level_04"
			"Level05_BotanicalGardens":
				return &"level_05"
	return &"level_01"

static func profile_for_level_id(level_id: StringName) -> Dictionary:
	# All levels retain the park's bird/people identity. Optional layers
	# add place without creating a different audio system for every scene.
	match level_id:
		&"level_02":
			return {
				"id": &"level_02", "seed": 202,
				"birds": 0.28, "people": 0.16, "water": 0.0,
				"festival": 0.0, "bird_calls": 3,
			}
		&"level_03":
			return {
				"id": &"level_03", "seed": 303,
				"birds": 0.18, "people": 0.08, "water": 0.18,
				"festival": 0.0, "bird_calls": 2,
			}
		&"level_04":
			return {
				"id": &"level_04", "seed": 404,
				"birds": 0.12, "people": 0.24, "water": 0.0,
				"festival": 0.18, "bird_calls": 1,
			}
		&"level_05":
			return {
				"id": &"level_05", "seed": 505,
				"birds": 0.32, "people": 0.10, "water": 0.0,
				"festival": 0.0, "bird_calls": 3,
			}
		_:
			return {
				"id": &"level_01", "seed": 101,
				"birds": 0.24, "people": 0.12, "water": 0.10,
				"festival": 0.0, "bird_calls": 2,
			}

static func active_layer_names(level_id: StringName) -> PackedStringArray:
	var profile := profile_for_level_id(level_id)
	var layers := PackedStringArray(["birds", "people"])
	if float(profile["water"]) > 0.0:
		layers.append("water")
	if float(profile["festival"]) > 0.0:
		layers.append("festival_crowd")
	return layers

static func build_profile_stream(level_id: StringName) -> AudioStreamWAV:
	var profile := profile_for_level_id(level_id)
	var frame_count := int(LOOP_SECONDS * float(MIX_RATE))
	var samples := PackedFloat32Array()
	samples.resize(frame_count)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(profile["seed"])

	var murmur_fast := 0.0
	var murmur_slow := 0.0
	var water_fast := 0.0
	var water_slow := 0.0
	var festival_fast := 0.0
	var festival_slow := 0.0
	for frame in frame_count:
		var t := float(frame) / float(MIX_RATE)
		murmur_fast = lerpf(murmur_fast, rng.randf_range(-1.0, 1.0), 0.055)
		murmur_slow = lerpf(murmur_slow, murmur_fast, 0.006)
		water_fast = lerpf(water_fast, rng.randf_range(-1.0, 1.0), 0.12)
		water_slow = lerpf(water_slow, water_fast, 0.018)
		festival_fast = lerpf(festival_fast, rng.randf_range(-1.0, 1.0), 0.08)
		festival_slow = lerpf(festival_slow, festival_fast, 0.010)

		var people := (murmur_fast - murmur_slow) * (0.70 + 0.30 * sin(TAU * t / 3.2))
		var water := (water_fast - water_slow) * (0.58 + 0.42 * sin(TAU * t / 2.7))
		var festival := (festival_fast - festival_slow) * (0.78 + 0.22 * sin(TAU * t / 5.0))
		samples[frame] = (
			people * float(profile["people"])
			+ water * float(profile["water"])
			+ festival * float(profile["festival"])
		)

	_add_bird_calls(samples, profile)
	# Fade a very short boundary at both ends; the loop joins at zero instead
	# of producing a PCM click, without a noticeable rhythmic pulse.
	var seam_frames := int(0.06 * float(MIX_RATE))
	for frame in frame_count:
		var seam_gain := minf(
			1.0,
			minf(float(frame), float(frame_count - 1 - frame)) / float(seam_frames)
		)
		samples[frame] = clampf(samples[frame] * seam_gain * 0.62, -0.92, 0.92)

	var data := PackedByteArray()
	data.resize(frame_count * 2)
	for frame in frame_count:
		_write_pcm16(data, frame, samples[frame])

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.stereo = false
	stream.mix_rate = MIX_RATE
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = frame_count - 1
	stream.set_meta("profile_id", String(profile["id"]))
	stream.set_meta("layers", active_layer_names(StringName(profile["id"])))
	return stream

static func _add_bird_calls(samples: PackedFloat32Array, profile: Dictionary) -> void:
	var frame_count := samples.size()
	var call_count := int(profile["bird_calls"])
	var profile_seed := int(profile["seed"])
	for call_index in call_count:
		var call_time := 0.75 + fmod(
			float(call_index) * 2.71 + float(profile_seed % 17) * 0.29,
			LOOP_SECONDS - 1.5
		)
		var start_frame := int(call_time * float(MIX_RATE))
		var call_frames := int((0.10 + float(call_index % 2) * 0.025) * float(MIX_RATE))
		var phase := 0.0
		for local_frame in call_frames:
			var frame := start_frame + local_frame
			if frame >= frame_count:
				break
			var progress := float(local_frame) / float(maxi(call_frames - 1, 1))
			var sweep := sin(PI * progress)
			var frequency := 1750.0 + float(profile_seed % 9) * 85.0 + sweep * 820.0
			phase += TAU * frequency / float(MIX_RATE)
			samples[frame] += (
				sin(phase)
				* sweep
				* float(profile["birds"])
				* 0.30
			)

static func _write_pcm16(data: PackedByteArray, frame: int, sample: float) -> void:
	var value := clampi(roundi(sample * 32767.0), -32768, 32767)
	data[frame * 2] = value & 0xFF
	data[frame * 2 + 1] = (value >> 8) & 0xFF

static func ensure_ambience_bus() -> int:
	var bus_index := AudioServer.get_bus_index(BUS_NAME)
	if bus_index < 0:
		AudioServer.add_bus()
		bus_index = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(bus_index, BUS_NAME)
		AudioServer.set_bus_send(bus_index, &"Master")
	return bus_index

static func set_ambient_volume(linear: float) -> void:
	var bus_index := ensure_ambience_bus()
	var clamped := clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_mute(bus_index, clamped <= 0.0001)
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(maxf(clamped, 0.001)))

static func load_saved_volume(settings_path: String = SETTINGS_PATH) -> float:
	var config := ConfigFile.new()
	var saved_volume := 1.0
	if config.load(settings_path) == OK:
		saved_volume = float(config.get_value("audio", "ambient", 1.0))
	set_ambient_volume(saved_volume)
	return saved_volume
