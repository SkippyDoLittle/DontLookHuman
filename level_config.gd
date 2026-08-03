class_name LevelConfig
extends Resource

@export var level_id: StringName
@export var display_name: String
@export_range(1.0, 600.0, 1.0) var time_limit: float = 60.0
@export_file("*.tscn") var next_level_scene: String = ""
@export_multiline var intro_text: String = "READY?\n\nPress SPACE to begin"

@export_group("Scoring")
@export_range(1.0, 600.0, 1.0) var lightning_time: float = 20.0
@export_range(1.0, 600.0, 1.0) var great_time: float = 35.0
@export_range(1.0, 600.0, 1.0) var nice_time: float = 50.0

func grade_thresholds() -> Array[float]:
	return [
		lightning_time,
		maxf(great_time, lightning_time),
		maxf(nice_time, great_time),
	]
