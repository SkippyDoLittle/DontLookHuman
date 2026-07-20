extends Node

const SAMPLE_RATE: int = 22050

var _peck: AudioStreamPlayer
var _collect: AudioStreamPlayer
var _alert: AudioStreamPlayer
var _caught: AudioStreamPlayer
var _escape: AudioStreamPlayer
var _tick: AudioStreamPlayer
var _ambient: AudioStreamPlayer
var _step_walk: AudioStreamPlayer
var _step_run: AudioStreamPlayer

func _ready() -> void:
	_peck      = _player(_noise(0.05, 60.0, 0.06), -6.0)
	_collect   = _player(_chime([1046.5, 1318.5, 1568.0], [0.12, 0.14, 0.20]), -2.0)
	_alert     = _player(_sweep(350.0, 700.0, 0.18), -5.0)
	_caught    = _player(_sweep(440.0, 90.0, 0.65), -2.0)
	_escape    = _player(_chime([523.25, 659.25, 783.99, 1046.5], [0.10, 0.10, 0.12, 0.28]), -2.0)
	_tick      = _player(_tone(1200.0, 0.035, 25.0), -10.0)
	_ambient   = _player(_ambient_loop(5.0, 0.04), -22.0)
	_step_walk = _player(_noise(0.028, 85.0, 0.07), -16.0)
	_step_run  = _player(_noise(0.022, 100.0, 0.10), -12.0)
	for p in [_peck, _collect, _alert, _caught, _escape, _tick, _ambient, _step_walk, _step_run]:
		add_child(p)
	_ambient.play()

func play_peck()    -> void: _peck.play()
func play_collect() -> void: _collect.play()
func play_alert()   -> void: _alert.play()
func play_caught()  -> void: _caught.play()
func play_escape()  -> void: _escape.play()
func play_tick()    -> void: _tick.play()
func play_step(sprint: bool) -> void:
	if sprint:
		_step_run.play()
	else:
		_step_walk.play()

# ── helpers ────────────────────────────────────────────────────────────────

func _player(stream: AudioStreamWAV, vol_db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = vol_db
	return p

func _put(d: PackedByteArray, i: int, val: float) -> void:
	var v: int = clampi(int(val * 32767.0), -32768, 32767)
	d[i * 2]     = v & 0xFF
	d[i * 2 + 1] = (v >> 8) & 0xFF

func _done(d: PackedByteArray) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format   = AudioStreamWAV.FORMAT_16_BITS
	w.stereo   = false
	w.mix_rate = SAMPLE_RATE
	w.data     = d
	return w

# Short sine burst with exponential decay
func _tone(freq: float, dur: float, decay: float) -> AudioStreamWAV:
	var n: int = int(dur * float(SAMPLE_RATE))
	var d := PackedByteArray(); d.resize(n * 2)
	for i in n:
		var t: float = float(i) / float(SAMPLE_RATE)
		_put(d, i, sin(TAU * freq * t) * exp(-t * decay))
	return _done(d)

# Low-pass filtered noise (muffled thud)
func _noise(dur: float, decay: float, filter: float = 0.35) -> AudioStreamWAV:
	var n: int = int(dur * float(SAMPLE_RATE))
	var d := PackedByteArray(); d.resize(n * 2)
	var prev: float = 0.0
	for i in n:
		var t: float = float(i) / float(SAMPLE_RATE)
		prev = lerp(prev, randf_range(-1.0, 1.0) * exp(-t * decay), filter)
		_put(d, i, prev)
	return _done(d)

# Frequency sweep (rising = alert, falling = caught)
func _sweep(f0: float, f1: float, dur: float) -> AudioStreamWAV:
	var n: int = int(dur * float(SAMPLE_RATE))
	var d := PackedByteArray(); d.resize(n * 2)
	var phase: float = 0.0
	for i in n:
		var frac: float = float(i) / float(n)
		phase += TAU * lerp(f0, f1, frac) / float(SAMPLE_RATE)
		_put(d, i, sin(phase) * (1.0 - frac * 0.6))
	return _done(d)

# Sequence of decaying sine tones (chime)
func _ambient_loop(dur: float, filter: float) -> AudioStreamWAV:
	var n: int = int(dur * float(SAMPLE_RATE))
	var d := PackedByteArray(); d.resize(n * 2)
	var prev: float = 0.0
	for i in n:
		prev = lerp(prev, randf_range(-1.0, 1.0), filter)
		_put(d, i, prev * 0.75)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.stereo = false
	w.mix_rate = SAMPLE_RATE
	w.data = d
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n - 1
	return w

func _chime(freqs: Array, durs: Array) -> AudioStreamWAV:
	var gap: int = int(0.018 * float(SAMPLE_RATE))
	var total: int = 0
	for dur in durs:
		total += int(float(dur) * float(SAMPLE_RATE)) + gap
	var d := PackedByteArray(); d.resize(total * 2)
	var offset: int = 0
	for fi in freqs.size():
		var freq: float = float(freqs[fi])
		var frames: int = int(float(durs[fi]) * float(SAMPLE_RATE))
		for i in frames:
			var t: float = float(i) / float(SAMPLE_RATE)
			_put(d, offset + i, sin(TAU * freq * t) * exp(-t * 6.0) * 0.85)
		offset += frames + gap
	return _done(d)
