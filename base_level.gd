class_name BaseLevel
extends Node3D

@export var level_config: LevelConfig

@onready var _start_label: Label = $TitleScreen/StartLabel

func _ready() -> void:
	if level_config == null:
		push_warning("BaseLevel: no LevelConfig assigned to %s" % name)
		return

	if not level_config.intro_text.is_empty():
		_start_label.text = level_config.intro_text
