class_name TrailerSoundtrack
extends RefCounted

const SAMPLE_RATE: int = 22050

static func build(duration: float) -> AudioStreamWAV:
	var sample_count := int(duration * float(SAMPLE_RATE))
	var pcm := PackedByteArray()
	pcm.resize(sample_count * 2)

	for sample_index in sample_count:
		var time := float(sample_index) / float(SAMPLE_RATE)
		var value := _music_sample(time, sample_index)
		var encoded := clampi(int(clampf(value, -0.96, 0.96) * 32767.0), -32768, 32767)
		pcm[sample_index * 2] = encoded & 0xFF
		pcm[sample_index * 2 + 1] = (encoded >> 8) & 0xFF

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.stereo = false
	stream.mix_rate = SAMPLE_RATE
	stream.data = pcm
	return stream

static func _music_sample(time: float, sample_index: int) -> float:
	var value := 0.0
	var noise := _deterministic_noise(sample_index)

	# The first five seconds are sparse so the peck, pickup, and ranger alert lead.
	if time < 5.0:
		var pulse_phase := fmod(time, 0.80)
		if pulse_phase < 0.20:
			var pulse_pitch := lerpf(72.0, 42.0, pulse_phase / 0.20)
			value += sin(TAU * pulse_pitch * pulse_phase) * exp(-pulse_phase * 15.0) * 0.48
		value += sin(TAU * 36.0 * time) * 0.055

	# A dry, playful stealth beat arrives with the first major cut.
	if time >= 5.0 and time < 15.0:
		value += _rhythm_section(time - 5.0, 0.50, noise, 0.72)
		value += _bass_section(time - 5.0, 0.50, [73.42, 87.31, 65.41, 58.27], 0.24)
		value += _pluck_section(time - 5.0, 0.25, [293.66, 349.23, 440.0, 523.25], 0.10)

	# The chase section runs faster and adds a second rhythmic layer.
	if time >= 15.0 and time < 29.0:
		var chase_time := time - 15.0
		value += _rhythm_section(chase_time, 0.375, noise, 0.86)
		value += _bass_section(chase_time, 0.375, [73.42, 65.41, 58.27, 87.31], 0.32)
		value += _pluck_section(chase_time, 0.1875, [293.66, 440.0, 349.23, 523.25], 0.14)
		var drive_phase := fmod(chase_time, 0.75)
		value += sin(TAU * 146.83 * chase_time) * exp(-drive_phase * 5.0) * 0.045

	# Three-second riser into the final escape, without covering the in-game SFX.
	if time >= 26.0 and time < 29.0:
		var rise := (time - 26.0) / 3.0
		var rise_frequency := lerpf(220.0, 1100.0, rise * rise)
		value += sin(TAU * rise_frequency * time) * rise * 0.12
		value += noise * rise * 0.035

	# Hard musical stop after the escape, then a short warm logo sting.
	if time >= 29.0:
		value *= exp(-(time - 29.0) * 18.0)
	if time >= 29.8:
		var sting_time := time - 29.8
		value += _logo_chord(sting_time)

	return value

static func _rhythm_section(time: float, interval: float, noise: float, strength: float) -> float:
	var phase := fmod(time, interval)
	var value := 0.0
	if phase < 0.16:
		var pitch := lerpf(105.0, 48.0, phase / 0.16)
		value += sin(TAU * pitch * phase) * exp(-phase * 22.0) * 0.62 * strength

	var beat_index := int(floor(time / interval))
	if beat_index % 2 == 1 and phase < 0.11:
		value += noise * exp(-phase * 32.0) * 0.34 * strength

	var hat_interval := interval * 0.5
	var hat_phase := fmod(time, hat_interval)
	if hat_phase < 0.035:
		value += noise * exp(-hat_phase * 75.0) * 0.13 * strength
	return value

static func _bass_section(
	time: float,
	interval: float,
	notes: Array,
	strength: float
) -> float:
	var note_index := int(floor(time / interval)) % notes.size()
	var phase := fmod(time, interval)
	var frequency := float(notes[note_index])
	var envelope := exp(-phase * 4.5)
	return (
		sin(TAU * frequency * time)
		+ sin(TAU * frequency * 2.0 * time) * 0.24
	) * envelope * strength

static func _pluck_section(
	time: float,
	interval: float,
	notes: Array,
	strength: float
) -> float:
	var note_index := int(floor(time / interval)) % notes.size()
	var phase := fmod(time, interval)
	var frequency := float(notes[note_index])
	return sin(TAU * frequency * phase) * exp(-phase * 18.0) * strength

static func _logo_chord(time: float) -> float:
	if time < 0.0 or time > 3.2:
		return 0.0
	var attack := clampf(time / 0.08, 0.0, 1.0)
	var release := exp(-time * 1.4)
	var chord := (
		sin(TAU * 146.83 * time)
		+ sin(TAU * 220.0 * time) * 0.72
		+ sin(TAU * 293.66 * time) * 0.48
	)
	return chord * attack * release * 0.19

static func _deterministic_noise(sample_index: int) -> float:
	var raw := sin(float(sample_index) * 12.9898 + 78.233) * 43758.5453
	return (raw - floor(raw)) * 2.0 - 1.0
