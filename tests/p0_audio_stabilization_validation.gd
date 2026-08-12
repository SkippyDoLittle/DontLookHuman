extends SceneTree

# Focused P0 audio regression checks.
# Run headless: --headless --path . --script res://tests/p0_audio_stabilization_validation.gd

const SOUND_MANAGER_SCRIPT = preload("res://sound_manager.gd")

var _pass_count: int = 0
var _fail_count: int = 0

func _init() -> void:
	call_deferred("_run_all")

func _run_all() -> void:
	_test_repetitive_music_removed()
	_test_npc_emitters_use_quiet_manager_gains()
	_test_npc_voice_limits_are_bounded_and_independent()
	await process_frame
	print("P0_AUDIO RESULTS: %d passed, %d failed" % [_pass_count, _fail_count])
	quit(0 if _fail_count == 0 else 1)

func _test_repetitive_music_removed() -> void:
	var sound_source := _read_source("res://sound_manager.gd")
	var session_source := _read_source("res://game_timer.gd")
	_assert("six second melody builder removed", not sound_source.contains("_melody_loop"))
	_assert("session no longer starts placeholder music", not session_source.contains("start_music"))
	_assert("session no longer stops placeholder music", not session_source.contains("stop_music"))

func _test_npc_emitters_use_quiet_manager_gains() -> void:
	var npc_source := _read_source("res://npc_animal.gd")
	var manager := SOUND_MANAGER_SCRIPT.new()
	_assert("npc peck gain is minus 28 dB", is_equal_approx(manager.npc_peck_volume_db(), -28.0))
	_assert("npc step gain is minus 16 dB", is_equal_approx(manager.npc_step_volume_db(), -16.0))
	_assert("npc peck uses managed quiet gain", npc_source.contains("npc_peck_volume_db()"))
	_assert("npc step uses managed quiet gain", npc_source.contains("npc_step_volume_db()"))
	_assert("npc peck bypass removed", not npc_source.contains("_peck_sfx.play()"))
	_assert("npc step bypass removed", not npc_source.contains("_step_sfx.play()"))
	manager.free()

func _test_npc_voice_limits_are_bounded_and_independent() -> void:
	var manager := SOUND_MANAGER_SCRIPT.new()
	var peck_voices := _make_voices(4, 1.0)
	var step_voices := _make_voices(6, 1.0)
	for index in 3:
		_assert("peck voice %d accepted" % index, manager.request_npc_peck(peck_voices[index]))
	_assert("fourth peck voice rejected", not manager.request_npc_peck(peck_voices[3]))
	for index in 5:
		_assert("step voice %d accepted" % index, manager.request_npc_step(step_voices[index]))
	_assert("sixth step voice rejected", not manager.request_npc_step(step_voices[5]))
	for voice in peck_voices + step_voices:
		voice.stop()
		voice.stream = null
		voice.free()
	manager.free()

func _make_voices(count: int, duration: float) -> Array[AudioStreamPlayer3D]:
	var result: Array[AudioStreamPlayer3D] = []
	for _index in count:
		var stream := AudioStreamWAV.new()
		stream.format = AudioStreamWAV.FORMAT_16_BITS
		stream.mix_rate = 1000
		stream.data = PackedByteArray()
		stream.data.resize(int(duration * 1000.0) * 2)
		var voice := AudioStreamPlayer3D.new()
		voice.stream = stream
		root.add_child(voice)
		result.append(voice)
	return result

func _read_source(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var source := file.get_as_text()
	file.close()
	return source

func _assert(label: String, condition: bool) -> void:
	if condition:
		print("P0_AUDIO_%s_OK" % label.to_upper().replace(" ", "_"))
		_pass_count += 1
	else:
		print("P0_AUDIO_%s_FAIL" % label.to_upper().replace(" ", "_"))
		_fail_count += 1
