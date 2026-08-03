extends SceneTree

var _failures: int = 0

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var specs: Array[Dictionary] = [
		{
			"path": "res://scenes/levels/Level01_Park.tscn",
			"id": &"level_01",
			"time": 85.0,
			"next": "res://scenes/levels/Level02_Playground.tscn",
			"spawn": Vector3(3, 1, 0),
		},
		{
			"path": "res://scenes/levels/Level02_Playground.tscn",
			"id": &"level_02",
			"time": 80.0,
			"next": "res://scenes/levels/Level03_Lakeside.tscn",
			"spawn": Vector3(0, 1, 0),
		},
		{
			"path": "res://scenes/levels/Level03_Lakeside.tscn",
			"id": &"level_03",
			"time": 75.0,
			"next": "res://scenes/levels/Level04_Festival.tscn",
			"spawn": Vector3(7, 1, 7),
		},
		{
			"path": "res://scenes/levels/Level04_Festival.tscn",
			"id": &"level_04",
			"time": 85.0,
			"next": "res://scenes/levels/Level05_BotanicalGardens.tscn",
			"spawn": Vector3(0, 1, 8),
		},
		{
			"path": "res://scenes/levels/Level05_BotanicalGardens.tscn",
			"id": &"level_05",
			"time": 65.0,
			"next": "",
			"spawn": Vector3(7, 1, 7),
		},
	]

	for spec in specs:
		var packed := load(spec.path) as PackedScene
		_check(packed != null, "%s loads" % spec.id)
		if packed == null:
			continue

		var level := packed.instantiate()
		root.add_child(level)
		await process_frame

		_check(level is BaseLevel, "%s inherits BaseLevel" % spec.id)
		for node_path in [
			"Player",
			"HUD",
			"GameTimer",
			"TitleScreen/StartLabel",
			"TransitionLayer/FadeRect",
			"PauseMenu",
			"HowToPlayScreen",
		]:
			_check(level.get_node_or_null(node_path) != null, "%s inherits %s" % [spec.id, node_path])

		var config: LevelConfig = (level as BaseLevel).level_config
		_check(config != null, "%s has configuration" % spec.id)
		if config != null:
			_check(config.level_id == spec.id, "%s keeps its level ID" % spec.id)
			_check(is_equal_approx(config.time_limit, spec.time), "%s keeps its time limit" % spec.id)
			_check(config.next_level_scene == spec.next, "%s keeps its next-level route" % spec.id)
			_check(level.get_node("TitleScreen/StartLabel").text == config.intro_text, "%s applies its intro" % spec.id)

		var timer := level.get_node("GameTimer")
		_check(is_equal_approx(timer.time_limit, spec.time), "%s configures GameTimer" % spec.id)
		_check(is_equal_approx(timer.time_remaining, spec.time), "%s initializes countdown" % spec.id)
		_check(level.get_node("Player").position.is_equal_approx(spec.spawn), "%s keeps its spawn" % spec.id)

		paused = false
		level.queue_free()
		await process_frame

	if _failures == 0:
		print("PHASE3_VALIDATION_OK")
	quit(_failures)

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("Phase 3 validation failed: %s" % message)
