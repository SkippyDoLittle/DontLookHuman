# sound_manager.gd — Autoload singleton; all sounds generated from math, no audio files.
# Any script calls SoundManager.play_X() — the AudioStreamPlayer lives here, not in the caller.

extends Node

const SAMPLE_RATE: int = 22050   # half CD quality — sufficient for SFX, saves memory

var _peck:      AudioStreamPlayer
var _npc_peck:  AudioStreamPlayer
var _collect:   AudioStreamPlayer
var _alert:     AudioStreamPlayer
var _caught:    AudioStreamPlayer
var _escape:    AudioStreamPlayer
var _tick:      AudioStreamPlayer
var _ambient:   AudioStreamPlayer
var _step_walk: AudioStreamPlayer
var _step_run:  AudioStreamPlayer
var _portal:    AudioStreamPlayer
var _exhaust:    AudioStreamPlayer
var _wall_bump:  AudioStreamPlayer

func _ready() -> void:
	# PROCESS_MODE_ALWAYS so audio keeps playing while the scene tree is paused (countdown, pause menu).
	process_mode = Node.PROCESS_MODE_ALWAYS

	_ensure_bus("Music")
	_ensure_bus("SFX")
	_load_saved_volumes()

	# Frequencies/durations in comments use note names for quick tuning reference.
	_peck      = _player(_noise(0.05,  60.0,  0.06), -6.0)
	_npc_peck  = _player(_noise(0.05,  60.0,  0.06), -28.0)  # 22 dB quieter — 5 NPCs peck constantly; they'd overwhelm at normal volume
	_collect   = _player(_chime([1046.5, 1318.5, 1568.0],        [0.12, 0.14, 0.20]), -2.0)  # C6 E6 G6
	_alert     = _player(_sweep(350.0, 700.0, 0.18), -5.0)    # rising = alarm
	_caught    = _player(_sweep(440.0,  90.0, 0.65), -2.0)    # falling = defeated
	_escape    = _player(_chime([523.25, 659.25, 783.99, 1046.5], [0.10, 0.10, 0.12, 0.28]), -2.0)  # C5 E5 G5 C6
	_tick      = _player(_tone(1200.0, 0.035, 25.0), -10.0)
	_ambient   = _player(_park_ambient(), -20.0)
	_step_walk = _player(_noise(0.028,  85.0,  0.07), -16.0)
	_step_run  = _player(_noise(0.022, 100.0,  0.10), -12.0)
	_portal    = _player(_chime([523.25, 783.99, 1046.5, 1318.5, 1568.0], [0.08, 0.08, 0.10, 0.12, 0.30]), -2.0)  # C5 G5 C6 E6 G6
	_exhaust   = _player(_noise(0.08,   40.0,  0.12), -14.0)
	_wall_bump = _player(_noise(0.06,   35.0,  0.18), -10.0)  # low thud for hitting park boundary

	for p in [_peck, _npc_peck, _collect, _alert, _caught, _escape, _tick, _ambient, _step_walk, _step_run, _portal, _exhaust, _wall_bump]:
		add_child(p)
		p.bus = "SFX"

	# Ambient audio is controlled independently by the Music slider. SoundManager is
	# an autoload, so level scenes explicitly restart it through start_ambient().
	_ambient.bus = "Music"
	start_ambient()

# ── PUBLIC API ───────────────────────────────────────────────────────────────────

func play_peck()    -> void: _peck.play()
func play_collect() -> void: _collect.play()
func play_alert()   -> void: _alert.play()
func play_caught()  -> void: _caught.play()
func play_escape()  -> void: _escape.play()
func play_tick()    -> void: _tick.play()
func play_portal()  -> void: _portal.play()
func play_exhaust()   -> void: _exhaust.play()
func play_wall_bump() -> void: _wall_bump.play()

func start_ambient() -> void:
	if not _ambient.playing:
		_ambient.play()

func stop_ambient() -> void:
	_ambient.stop()

func play_step(sprint: bool) -> void:
	if sprint: _step_run.play()
	else:      _step_walk.play()

# Returns the stream so each NPC can attach its own AudioStreamPlayer3D for distance falloff.
func npc_peck_stream()  -> AudioStreamWAV: return _npc_peck.stream as AudioStreamWAV
func npc_step_stream()  -> AudioStreamWAV: return _step_walk.stream as AudioStreamWAV

func set_music_volume(linear: float) -> void:
	var idx := AudioServer.get_bus_index("Music")
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.001)))

func set_sfx_volume(linear: float) -> void:
	var idx := AudioServer.get_bus_index("SFX")
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.001)))

# ── AUDIO BUILDER HELPERS ────────────────────────────────────────────────────────

func _player(stream: AudioStreamWAV, vol_db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream    = stream
	p.volume_db = vol_db
	return p

# Write one float sample as 16-bit little-endian PCM into byte array d at sample index i.
func _put(d: PackedByteArray, i: int, val: float) -> void:
	var v: int   = clampi(int(val * 32767.0), -32768, 32767)
	d[i * 2]     = v & 0xFF
	d[i * 2 + 1] = (v >> 8) & 0xFF

func _done(d: PackedByteArray) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format   = AudioStreamWAV.FORMAT_16_BITS
	w.stereo   = false
	w.mix_rate = SAMPLE_RATE
	w.data     = d
	return w

# ── WAVEFORM GENERATORS ──────────────────────────────────────────────────────────

func _tone(freq: float, dur: float, decay: float) -> AudioStreamWAV:
	var n := int(dur * float(SAMPLE_RATE))
	var d := PackedByteArray(); d.resize(n * 2)
	for i in n:
		var t := float(i) / float(SAMPLE_RATE)
		_put(d, i, sin(TAU * freq * t) * exp(-t * decay))
	return _done(d)

func _noise(dur: float, decay: float, filter: float = 0.35) -> AudioStreamWAV:
	var n := int(dur * float(SAMPLE_RATE))
	var d := PackedByteArray(); d.resize(n * 2)
	var prev: float = 0.0
	for i in n:
		var t := float(i) / float(SAMPLE_RATE)
		# First-order IIR low-pass filter via lerp — small filter value = mostly previous sample = smoother/warmer sound.
		prev = lerp(prev, randf_range(-1.0, 1.0) * exp(-t * decay), filter)
		_put(d, i, prev)
	return _done(d)

func _sweep(f0: float, f1: float, dur: float) -> AudioStreamWAV:
	var n := int(dur * float(SAMPLE_RATE))
	var d := PackedByteArray(); d.resize(n * 2)
	# Accumulate phase rather than computing sin(TAU*f*t) directly — changing frequency
	# in the middle of a wave would otherwise create a discontinuity (audible click).
	var phase: float = 0.0
	for i in n:
		var frac := float(i) / float(n)
		phase += TAU * lerp(f0, f1, frac) / float(SAMPLE_RATE)
		_put(d, i, sin(phase) * (1.0 - frac * 0.6))
	return _done(d)

func _chime(freqs: Array, durs: Array) -> AudioStreamWAV:
	var gap := int(0.018 * float(SAMPLE_RATE))   # brief silence between notes
	var total := 0
	for dur in durs:
		total += int(float(dur) * float(SAMPLE_RATE)) + gap
	var d := PackedByteArray(); d.resize(total * 2)
	var offset := 0
	for fi in freqs.size():
		var freq   := float(freqs[fi])
		var frames := int(float(durs[fi]) * float(SAMPLE_RATE))
		for i in frames:
			var t := float(i) / float(SAMPLE_RATE)
			_put(d, offset + i, sin(TAU * freq * t) * exp(-t * 6.0) * 0.85)
		offset += frames + gap
	return _done(d)

func _park_ambient() -> AudioStreamWAV:
	var dur := 8.0
	var n   := int(dur * float(SAMPLE_RATE))
	# Float buffer so we can add layers cleanly before converting to bytes.
	var buf := PackedFloat32Array(); buf.resize(n)

	# ── Wind: ultra-heavy low-pass (0.007) creates smooth hiss; slow sine breathes amplitude.
	var wnd: float = 0.0
	for i in n:
		var t := float(i) / float(SAMPLE_RATE)
		wnd    = lerp(wnd, randf_range(-1.0, 1.0), 0.007)
		buf[i] = wnd * 0.28 * (0.75 + 0.25 * sin(TAU * t / 3.2))

	# ── Crickets: two voices at 3200/3500 Hz, offset by half a period so they interleave.
	# 8-second loop was chosen so the 2.0 s cricket cycle completes exactly 4 times (no seam).
	var c_pulse := int(0.018 * float(SAMPLE_RATE))
	var c_gap   := int(0.007 * float(SAMPLE_RATE))
	var c_step  := int(2.0   * float(SAMPLE_RATE))
	var c_half  := int(c_step * 0.5)   # float multiply avoids GDScript int/int division warning

	for voice in 2:
		var freq  := 3200.0 + float(voice) * 300.0
		var burst := voice * c_half
		while burst < n:
			for pulse in 4:
				var ps := burst + pulse * (c_pulse + c_gap)
				for si in c_pulse:
					var idx := ps + si
					if idx >= n: break
					var tl := float(si) / float(SAMPLE_RATE)
					buf[idx] = buf[idx] + sin(TAU * freq * tl) * exp(-tl * 90.0) * 0.08
			burst += c_step

	# ── Birds: two brief tweets (100 ms each) with phase-accumulated pitch sweep to avoid clicks.
	for call_t in [1.8, 5.6]:
		var call_start := int(call_t * float(SAMPLE_RATE))
		var call_n     := int(0.10   * float(SAMPLE_RATE))
		var bphase: float = 0.0
		for si in call_n:
			var idx := call_start + si
			if idx >= n: break
			var frac := float(si) / float(call_n)
			var bfreq: float
			if frac < 0.5:
				bfreq = lerp(2400.0, 3200.0, frac * 2.0)
			else:
				bfreq = lerp(3200.0, 2600.0, (frac - 0.5) * 2.0)
			bphase     += TAU * bfreq / float(SAMPLE_RATE)
			# sin(PI * frac) = bell curve envelope — smooth attack and release.
			buf[idx]    = buf[idx] + sin(bphase) * sin(PI * frac) * 0.35

	var d := PackedByteArray(); d.resize(n * 2)
	for i in n:
		_put(d, i, clampf(buf[i], -0.98, 0.98))

	var w := AudioStreamWAV.new()
	w.format     = AudioStreamWAV.FORMAT_16_BITS
	w.stereo     = false
	w.mix_rate   = SAMPLE_RATE
	w.data       = d
	w.loop_mode  = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end   = n - 1
	return w

# ── BUS UTILITIES ────────────────────────────────────────────────────────────────

func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) == -1:
		AudioServer.add_bus()
		var idx := AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")

func _load_saved_volumes() -> void:
	# Apply saved volumes before the first sound plays; skip gracefully if no save file yet.
	var config := ConfigFile.new()
	if config.load("user://settings.cfg") != OK:
		return
	set_music_volume(config.get_value("audio", "music", 1.0))
	set_sfx_volume(  config.get_value("audio", "sfx",   1.0))
