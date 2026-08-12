extends SceneTree

# P4 adaptive music contract and runtime validation.
# Run headless: --headless --path . --script res://tests/p4_adaptive_music_validation.gd

const DIRECTOR_SCRIPT = preload("res://adaptive_music_director.gd")

var _pass_count: int = 0
var _fail_count: int = 0

func _init() -> void:
	call_deferred("_run_all")

func _run_all() -> void:
	var director := DIRECTOR_SCRIPT.new() as AdaptiveMusicDirector
	root.add_child(director)
	_test_long_form_layer_contract(director)
	_test_adaptive_targets_and_crossfade(director)
	_test_outcome_mix_and_stop(director)
	_test_session_integration_contract()
	director.free()
	await process_frame
	print("P4_ADAPTIVE_MUSIC RESULTS: %d passed, %d failed" % [_pass_count, _fail_count])
	quit(0 if _fail_count == 0 else 1)

func _test_long_form_layer_contract(director: AdaptiveMusicDirector) -> void:
	_assert("director processes while paused", director.process_mode == Node.PROCESS_MODE_ALWAYS)
	_assert("arrangement has sixteen authored bars", director.arrangement_bar_count() == 16)
	_assert("arrangement lasts at least twenty four seconds", director.loop_duration_seconds() >= 24.0)
	var layer_names := director.layer_names()
	_assert("four adaptive layers exist", layer_names.size() == 4)
	var stream_ids: Dictionary = {}
	for layer_name in layer_names:
		var player := director.layer_player(layer_name)
		_assert("%s player exists" % layer_name, is_instance_valid(player))
		if not is_instance_valid(player):
			continue
		_assert("%s uses Music bus" % layer_name, player.bus == &"Music")
		_assert("%s has runtime wav" % layer_name, player.stream is AudioStreamWAV)
		if not player.stream is AudioStreamWAV:
			continue
		var stream := player.stream as AudioStreamWAV
		_assert("%s loop is long form" % layer_name, stream.get_length() >= 23.9)
		_assert("%s stream loops forward" % layer_name, stream.loop_mode == AudioStreamWAV.LOOP_FORWARD)
		stream_ids[stream.get_instance_id()] = true
	_assert("each adaptive layer owns a distinct stream", stream_ids.size() == 4)
	_assert("music pcm remains below eight megabytes", director.total_pcm_bytes() < 8 * 1024 * 1024)
	_assert("music pcm contains four complete stems", director.total_pcm_bytes() > 4 * 1024 * 1024)

func _test_adaptive_targets_and_crossfade(director: AdaptiveMusicDirector) -> void:
	director.set_session_state(&"active")
	director.set_tension(0.0)
	director.start_music(&"level_01_park")
	_assert("score reports running", director.is_music_running())
	_assert("normal stem leads calm gameplay", director.layer_target_linear(&"normal") > 0.65)
	_assert("calm tension stem is silent", director.layer_target_linear(&"tension") <= 0.001)
	_assert("calm rhythm stem is silent", director.layer_target_linear(&"rhythm") <= 0.001)
	_assert("calm chase stem is silent", director.layer_target_linear(&"chase") <= 0.001)

	var calm_target := director.layer_target_linear(&"normal")
	director._process(0.10)
	var first_fade_gain := director.layer_current_linear(&"normal")
	_assert("calm stem fades up from silence", first_fade_gain > 0.0)
	_assert("calm fade does not jump to target", first_fade_gain < calm_target)

	director.set_tension(0.50)
	_assert("mid tension adds suspense", director.layer_target_linear(&"tension") > 0.0)
	_assert("mid tension adds rhythm", director.layer_target_linear(&"rhythm") > 0.0)
	_assert("mid tension keeps chase silent", director.layer_target_linear(&"chase") <= 0.001)

	director.set_tension(0.88)
	var chase_target := director.layer_target_linear(&"chase")
	var chase_before := director.layer_current_linear(&"chase")
	_assert("high tension enables chase layer", chase_target > 0.20)
	_assert("chase target changes before current gain", chase_before < chase_target)
	director._process(0.12)
	var chase_during := director.layer_current_linear(&"chase")
	_assert("chase crossfade advances smoothly", chase_during > chase_before and chase_during < chase_target)

func _test_outcome_mix_and_stop(director: AdaptiveMusicDirector) -> void:
	director.play_success()
	_assert("success clears tension layer", director.layer_target_linear(&"tension") <= 0.001)
	_assert("success clears chase layer", director.layer_target_linear(&"chase") <= 0.001)
	_assert("success keeps a light resolving bed", director.layer_target_linear(&"normal") > 0.0)
	director.start_music(&"level_02_playground")
	director.play_caught()
	_assert("caught ducks normal layer", director.layer_target_linear(&"normal") <= 0.001)
	_assert("caught keeps a short danger bed", director.layer_target_linear(&"chase") > 0.0)

	director.stop_music()
	for layer_name in director.layer_names():
		_assert("%s stop target is silent" % layer_name, director.layer_target_linear(layer_name) <= 0.001)
	director._process(1.0)
	_assert("score stops after fade reaches silence", not director.is_music_running())
	for layer_name in director.layer_names():
		var player := director.layer_player(layer_name)
		_assert("%s player stops after fade" % layer_name, is_instance_valid(player) and not player.playing)

func _test_session_integration_contract() -> void:
	var sound_source := _read_source("res://sound_manager.gd")
	var session_source := _read_source("res://game_timer.gd")
	_assert("sound manager exposes public music start", sound_source.contains("func start_music"))
	_assert("sound manager exposes public music stop", sound_source.contains("func stop_music"))
	_assert("sound manager forwards suspicion tension", sound_source.contains("_music_director.set_tension"))
	_assert("caught sfx api remains", sound_source.contains("func play_caught()"))
	_assert("escape sfx api remains", sound_source.contains("func play_escape()"))
	_assert("session begins score by level id", session_source.contains("begin_level_score"))
	_assert("session forwards adaptive state", session_source.contains("set_music_session_state"))
	_assert("session forwards result outcome", session_source.contains("finish_level_score"))

func _read_source(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var source := file.get_as_text()
	file.close()
	return source

func _assert(label: String, condition: bool) -> void:
	if condition:
		print("P4_ADAPTIVE_MUSIC_%s_OK" % label.to_upper().replace(" ", "_"))
		_pass_count += 1
	else:
		print("P4_ADAPTIVE_MUSIC_%s_FAIL" % label.to_upper().replace(" ", "_"))
		_fail_count += 1
