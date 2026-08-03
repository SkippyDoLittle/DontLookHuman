class_name LevelConfig
extends Resource

@export var level_id: StringName
@export var display_name: String
@export_range(1.0, 600.0, 1.0) var time_limit: float = 60.0
@export_file("*.tscn") var next_level_scene: String = ""
@export_multiline var intro_text: String = "READY?\n\nPress SPACE to begin"
