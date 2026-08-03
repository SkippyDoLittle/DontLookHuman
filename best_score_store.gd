class_name BestScoreStore
extends RefCounted

const DEFAULT_SAVE_PATH: String = "user://best_score.dat"

var save_path: String

func _init(path: String = DEFAULT_SAVE_PATH) -> void:
	save_path = path

func load_best() -> int:
	if not FileAccess.file_exists(save_path):
		return 0
	var file := FileAccess.open(save_path, FileAccess.READ)
	return file.get_32() if file != null else 0

func save_best(score: int) -> void:
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file != null:
		file.store_32(score)
