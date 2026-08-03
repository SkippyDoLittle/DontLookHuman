extends SceneTree

const LEVEL_SPECS: Array[Dictionary] = [
	{
		"path": "res://scenes/levels/Level01_Park.tscn",
		"id": &"level_01",
		"next_id": &"level_02",
		"thresholds": [40.0, 55.0, 75.0],
	},
	{
		"path": "res://scenes/levels/Level02_Playground.tscn",
		"id": &"level_02",
		"next_id": &"level_03",
		"thresholds": [42.0, 55.0, 72.0],
	},
	{
		"path": "res://scenes/levels/Level03_Lakeside.tscn",
		"id": &"level_03",
		"next_id": &"level_04",
		"thresholds": [35.0, 48.0, 65.0],
	},
	{
		"path": "res://scenes/levels/Level04_Festival.tscn",
		"id": &"level_04",
		"next_id": &"level_05",
		"thresholds": [48.0, 65.0, 80.0],
	},
	{
		"path": "res://scenes/levels/Level05_BotanicalGardens.tscn",
		"id": &"level_05",
		"next_id": &"",
		"thresholds": [32.0, 45.0, 58.0],
	},
]

var _failures: int = 0
var _temporary_paths: Array[String] = []

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	_validate_grade_boundaries()
	_validate_timer_expiration()
	_validate_per_level_score_storage()
	await _validate_levels_and_progression()
	await _validate_debug_overlay()
	_cleanup_temporary_files()

	if _failures == 0:
		print("PHASE6_RELIABILITY_VALIDATION_OK")
	quit(_failures)

func _validate_grade_boundaries() -> void:
	var scorer := ScoreManager.new()
	var thresholds: Array[float] = [40.0, 55.0, 75.0]
	var time_limit: float = 85.0
	var cases: Array[Dictionary] = [
		{"used": 40.0, "score": 1000},
		{"used": 40.01, "score": 750},
		{"used": 55.0, "score": 750},
		{"used": 55.01, "score": 500},
		{"used": 75.0, "score": 500},
		{"used": 75.01, "score": 250},
	]
	for grade_case in cases:
		var summary := scorer.calculate(
			true,
			time_limit,
			time_limit - float(grade_case.used),
			5,
			0,
			thresholds
		)
		_check(
			summary.score == grade_case.score,
			"Score boundary %.2fs awards %d points" % [grade_case.used, grade_case.score]
		)

	var failed := scorer.calculate(false, time_limit, 60.0, 6, 2, thresholds)
	_check(failed.score == 0, "Failed sessions never receive a completion score")
	_check(failed.collected == 4 and failed.total == 6, "Score summary counts arbitrary collectibles")

func _validate_timer_expiration() -> void:
	var timer := SessionTimer.new()
	var expirations: Array[int] = [0]
	timer.expired.connect(func(): expirations[0] += 1)
	timer.reset(2.0)
	timer.advance(0.75)
	_check(is_equal_approx(timer.time_remaining, 1.25), "Timer subtracts partial elapsed time")
	timer.advance(5.0)
	timer.advance(1.0)
	_check(is_zero_approx(timer.time_remaining), "Timer clamps expiration at zero")
	_check(expirations[0] == 1, "Timer emits expiration exactly once")
	timer.reset(1.0)
	timer.advance(1.0)
	_check(expirations[0] == 2, "Reset timer can expire once in a new session")

func _validate_per_level_score_storage() -> void:
	var token := str(Time.get_ticks_usec())
	var score_path := "user://phase6_scores_%s.cfg" % token
	var legacy_path := "user://phase6_legacy_%s.dat" % token
	_temporary_paths.assign([score_path, legacy_path])
	var store := BestScoreStore.new(score_path, legacy_path)

	_check(store.save_best(&"level_01", 500) == OK, "Level 1 score saves")
	_check(store.save_best(&"level_02", 750) == OK, "Level 2 score saves")
	_check(store.load_best(&"level_01") == 500, "Level 1 score uses its own key")
	_check(store.load_best(&"level_02") == 750, "Level 2 score uses its own key")
	_check(store.load_best(&"level_03") == 0, "Unplayed levels do not inherit another score")
	_check(store.save_best(&"level_01", 250) == OK, "Lower scores are accepted without errors")
	_check(store.load_best(&"level_01") == 500, "Lower scores do not replace a best score")
	_check(store.save_best(&"", 1000) == ERR_INVALID_PARAMETER, "Empty level keys are rejected")

	_cleanup_path(score_path)
	var legacy_file := FileAccess.open(legacy_path, FileAccess.WRITE)
	if legacy_file != null:
		legacy_file.store_32(333)
		legacy_file.close()
	_check(store.load_best(&"level_01") == 333, "Legacy shared score remains available to Level 1")
	_check(store.load_best(&"level_02") == 0, "Legacy shared score does not leak into later levels")
	_check(store.save_best(&"level_02", 750) == OK, "A later-level record can coexist with legacy data")
	_check(store.load_best(&"level_01") == 333, "A later-level record does not hide the Level 1 fallback")
	_check(store.save_best(&"level_01", 250) == OK, "A lower score does not overwrite the legacy best")
	_check(store.load_best(&"level_01") == 333, "Legacy best survives a lower Level 1 score")
	_check(store.save_best(&"level_01", 500) == OK, "A higher Level 1 score migrates into the new store")
	_check(store.load_best(&"level_01") == 500, "Migrated Level 1 score replaces the fallback")

func _validate_levels_and_progression() -> void:
	for spec in LEVEL_SPECS:
		var packed := load(String(spec.path)) as PackedScene
		_check(packed != null, "%s loads" % spec.id)
		if packed == null:
			continue

		var level := packed.instantiate() as BaseLevel
		if spec.id == &"level_01":
			var extra_collectible := Node3D.new()
			extra_collectible.name = "Phase6ExtraCollectible"
			extra_collectible.add_to_group("collectibles")
			level.add_child(extra_collectible)
		root.add_child(level)
		await process_frame
		await process_frame

		var config := level.level_config
		var session := level.get_node("GameTimer") as GameSession
		var actual_collectibles := get_nodes_in_group("collectibles").size()
		_check(config.level_id == spec.id, "%s keeps a stable save key" % spec.id)
		_check(session.level_id == spec.id, "%s passes its save key to GameSession" % spec.id)
		_check(session.items_total == actual_collectibles, "%s derives its collectible total from the scene" % spec.id)
		_check(config.grade_thresholds() == spec.thresholds, "%s keeps its grade thresholds" % spec.id)
		_check(config.nice_time <= config.time_limit, "%s grade thresholds fit inside its timer" % spec.id)

		if spec.next_id == &"":
			_check(config.next_level_scene.is_empty(), "%s ends the campaign" % spec.id)
		else:
			_check(ResourceLoader.exists(config.next_level_scene), "%s progression target exists" % spec.id)
			if ResourceLoader.exists(config.next_level_scene):
				var next_level := (load(config.next_level_scene) as PackedScene).instantiate() as BaseLevel
				_check(next_level.level_config.level_id == spec.next_id, "%s progresses to %s" % [spec.id, spec.next_id])
				next_level.free()

		var initial_total := session.items_total
		get_nodes_in_group("collectibles")[0].queue_free()
		await process_frame
		_check(session.call("_refresh_collectible_count") == initial_total - 1, "%s notices collectible removal" % spec.id)

		paused = false
		level.queue_free()
		await process_frame

func _validate_debug_overlay() -> void:
	var level := (
		load("res://scenes/levels/Level05_BotanicalGardens.tscn") as PackedScene
	).instantiate() as BaseLevel
	root.add_child(level)
	await process_frame
	await process_frame
	var overlay := level.get_node_or_null("HUD/DebugOverlay") as DebugOverlay
	_check(overlay != null, "Shared HUD includes the development overlay")
	if overlay != null:
		overlay.refresh_now()
		var debug_text := (overlay.get_node("MarginContainer/DebugText") as Label).text
		_check("Level: level_05" in debug_text, "Debug overlay reports the current level ID")
		_check("Session: TITLE" in debug_text, "Debug overlay reports session state")
		_check("Collectibles: 5 / 5 remaining" in debug_text, "Debug overlay reports collectibles")
		_check("Player in water: no" in debug_text, "Debug overlay reports player water state")
		_check(debug_text.count("suspicion") == 4, "Debug overlay reports every ranger")
		var toggle_event := InputEventKey.new()
		toggle_event.keycode = KEY_F3
		toggle_event.pressed = true
		overlay.call("_unhandled_input", toggle_event)
		_check(overlay.visible, "F3 shows the debug overlay")
	paused = false
	level.queue_free()
	await process_frame

func _cleanup_temporary_files() -> void:
	for path in _temporary_paths:
		_cleanup_path(path)

func _cleanup_path(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("Phase 6 reliability validation failed: %s" % message)
