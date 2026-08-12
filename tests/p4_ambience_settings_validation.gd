extends SceneTree

# P4 ambience and settings regression checks.
# Run headless: --headless --path . --script res://tests/p4_ambience_settings_validation.gd

const AMBIENCE_DIRECTOR = preload("res://park_ambience_director.gd")
const LEVEL_IDS: Array[StringName] = [
	&"level_01", &"level_02", &"level_03", &"level_04", &"level_05",
]

var _failures: int = 0
var _settings_path := "user://p4_ambience_settings_validation_%d.cfg" % Time.get_ticks_usec()

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	Engine.time_scale = 1.0
	_validate_profiles()
	_validate_pcm_budget_and_identity()
	_validate_independent_bus()
	await _validate_level_profile_resolution()
	await _validate_menu_settings_persistence()
	await _validate_pause_settings_persistence()
	_validate_source_contracts()
	_cleanup_settings()
	if _failures == 0:
		print("P4_AMBIENCE_SETTINGS_VALIDATION_OK")
	quit(_failures)

func _validate_profiles() -> void:
	var signatures: Dictionary = {}
	for level_id in LEVEL_IDS:
		var profile := AMBIENCE_DIRECTOR.profile_for_level_id(level_id)
		_check(float(profile["wind"]) > 0.0, "%s has wind" % level_id)
		_check(float(profile["birds"]) > 0.0, "%s has birds" % level_id)
		_check(float(profile["people"]) > 0.0, "%s has distant people" % level_id)
		var signature := "%s|%s|%s|%s|%s" % [
			profile["wind"], profile["birds"], profile["people"],
			profile["water"], profile["festival"],
		]
		signatures[signature] = true
	_check(signatures.size() == LEVEL_IDS.size(), "All five levels have distinct ambience mixes")
	_check(
		float(AMBIENCE_DIRECTOR.profile_for_level_id(&"level_01")["water"]) > 0.0
		and float(AMBIENCE_DIRECTOR.profile_for_level_id(&"level_03")["water"]) > 0.0,
		"Community Park and Lakeside include water"
	)
	for level_id in [&"level_02", &"level_04", &"level_05"]:
		_check(
			is_zero_approx(float(AMBIENCE_DIRECTOR.profile_for_level_id(level_id)["water"])),
			"%s does not add an unrelated water bed" % level_id
		)
	_check(
		float(AMBIENCE_DIRECTOR.profile_for_level_id(&"level_04")["festival"]) > 0.0,
		"Festival has its dedicated crowd layer"
	)
	for level_id in [&"level_01", &"level_02", &"level_03", &"level_05"]:
		_check(
			is_zero_approx(float(AMBIENCE_DIRECTOR.profile_for_level_id(level_id)["festival"])),
			"%s does not add festival crowd" % level_id
		)

func _validate_pcm_budget_and_identity() -> void:
	var stream_hashes: Dictionary = {}
	for level_id in LEVEL_IDS:
		var stream := AMBIENCE_DIRECTOR.build_profile_stream(level_id)
		_check(stream.mix_rate == 11025, "%s uses a modest 11.025 kHz mix rate" % level_id)
		_check(not stream.stereo, "%s ambience is memory-efficient mono" % level_id)
		_check(stream.format == AudioStreamWAV.FORMAT_16_BITS, "%s uses 16-bit PCM" % level_id)
		_check(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "%s loops continuously" % level_id)
		_check(stream.data.size() <= 180000, "%s PCM stays below 180 KB" % level_id)
		_check(stream.get_length() <= 8.01, "%s loop is no longer than eight seconds" % level_id)
		_check(StringName(stream.get_meta("profile_id")) == level_id, "%s stream keeps its profile identity" % level_id)
		stream_hashes[hash(stream.data)] = true
	_check(stream_hashes.size() == LEVEL_IDS.size(), "Each ambience profile renders distinct PCM")

func _validate_independent_bus() -> void:
	var music_index := AudioServer.get_bus_index(&"Music")
	var ambience_index := AMBIENCE_DIRECTOR.ensure_ambience_bus()
	_check(music_index >= 0, "Music bus exists")
	_check(ambience_index >= 0, "Ambience bus exists")
	_check(music_index != ambience_index, "Ambience is independent from Music")
	var sound_manager := root.get_node_or_null("SoundManager")
	if sound_manager != null and sound_manager.has_method("set_music_volume"):
		sound_manager.call("set_music_volume", 0.0)
	AMBIENCE_DIRECTOR.set_ambient_volume(0.65)
	_check(
		not AudioServer.is_bus_mute(ambience_index)
		and db_to_linear(AudioServer.get_bus_volume_db(ambience_index)) > 0.60,
		"Ambience stays audible when Music is zero"
	)
	if sound_manager != null and sound_manager.has_method("set_music_volume"):
		sound_manager.call("set_music_volume", 1.0)

func _validate_level_profile_resolution() -> void:
	var specs := [
		["res://scenes/levels/Level01_Park.tscn", &"level_01"],
		["res://scenes/levels/Level04_Festival.tscn", &"level_04"],
	]
	for spec in specs:
		var level := (load(String(spec[0])) as PackedScene).instantiate()
		root.add_child(level)
		await process_frame
		await process_frame
		var director := level.get_node_or_null("ParkAmbienceDirector") as ParkAmbienceDirector
		_check(director != null, "%s has the shared ambience director" % spec[1])
		if director != null:
			_check(director.active_profile_id == spec[1], "%s resolves its own profile" % spec[1])
			var player := director.get_node_or_null("AmbiencePlayer") as AudioStreamPlayer
			_check(player != null and player.bus == &"Ambience", "%s plays only on Ambience" % spec[1])
			_check(player != null and player.playing, "%s ambience starts with the level" % spec[1])
		level.queue_free()
		await process_frame

func _validate_menu_settings_persistence() -> void:
	var initial := ConfigFile.new()
	initial.set_value("audio", "music", 0.42)
	initial.set_value("audio", "ambient", 0.58)
	initial.set_value("audio", "sfx", 0.37)
	initial.set_value("camera", "mouse_sensitivity", 0.004)
	initial.set_value("camera", "controller_sensitivity", 2.7)
	initial.set_value("camera", "invert_y", true)
	initial.set_value("display", "fullscreen", false)
	initial.set_value("display", "quality_preset", "Medium")
	initial.set_value("future_section", "preserve_me", "yes")
	initial.save(_settings_path)

	var menu := (load("res://MainMenu.tscn") as PackedScene).instantiate()
	menu.set("settings_path", _settings_path)
	root.add_child(menu)
	await process_frame
	var ambient_slider := menu.get_node("CanvasLayer/SettingsPanel/VBoxContainer/AmbientSlider") as HSlider
	_check(is_equal_approx(ambient_slider.value, 0.58), "Main menu loads saved ambient volume")
	ambient_slider.value = 0.27
	await process_frame
	var saved := ConfigFile.new()
	saved.load(_settings_path)
	_check(is_equal_approx(float(saved.get_value("audio", "ambient", -1.0)), 0.27), "Main menu saves ambient volume")
	_check(is_equal_approx(float(saved.get_value("audio", "music", -1.0)), 0.42), "Main menu preserves music setting")
	_check(is_equal_approx(float(saved.get_value("audio", "sfx", -1.0)), 0.37), "Main menu preserves SFX setting")
	_check(saved.get_value("future_section", "preserve_me", "") == "yes", "Main menu preserves unrelated settings")
	menu.queue_free()
	await process_frame

func _validate_pause_settings_persistence() -> void:
	var level := (load("res://scenes/levels/Level02_Playground.tscn") as PackedScene).instantiate()
	var pause_menu := level.get_node("PauseMenu")
	pause_menu.set("settings_path", _settings_path)
	root.add_child(level)
	await process_frame
	await process_frame
	var ambient_slider := pause_menu.get_node("VBoxContainer/AudioPanel/AmbientSlider") as HSlider
	ambient_slider.value = 0.31
	await process_frame
	var saved := ConfigFile.new()
	saved.load(_settings_path)
	_check(is_equal_approx(float(saved.get_value("audio", "ambient", -1.0)), 0.31), "Pause menu saves ambient volume")
	_check(saved.has_section_key("display", "quality_preset"), "Pause menu preserves display settings")
	_check(saved.get_value("future_section", "preserve_me", "") == "yes", "Pause menu preserves unrelated settings")
	level.queue_free()
	await process_frame

func _validate_source_contracts() -> void:
	var ambience_source := _read_source("res://park_ambience_director.gd").to_lower()
	var menu_source := _read_source("res://main_menu.gd")
	var pause_source := _read_source("res://pause_menu.gd")
	_check(not ambience_source.contains("cricket"), "Ambience has no loud repetitive cricket layer")
	_check(menu_source.contains("config.load(settings_path)"), "Main menu loads before saving existing settings")
	_check(pause_source.contains("config.load(settings_path)"), "Pause menu loads before saving existing settings")
	_check(
		menu_source.contains("set_ambient_volume") and pause_source.contains("set_ambient_volume"),
		"Both settings screens use the shared ambient-volume API"
	)

func _read_source(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var source := file.get_as_text()
	file.close()
	return source

func _cleanup_settings() -> void:
	if FileAccess.file_exists(_settings_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_settings_path))

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("P4 ambience/settings validation failed: %s" % message)
