class_name BestScoreStore
extends RefCounted

const DEFAULT_SAVE_PATH: String = "user://best_scores.cfg"
const LEGACY_SAVE_PATH: String = "user://best_score.dat"
const SCORE_SECTION: String = "best_scores"

var save_path: String
var legacy_save_path: String

func _init(path: String = DEFAULT_SAVE_PATH, legacy_path: String = LEGACY_SAVE_PATH) -> void:
	save_path = path
	legacy_save_path = legacy_path

func load_best(level_id: StringName) -> int:
	if level_id.is_empty():
		return 0
	var config := ConfigFile.new()
	if config.load(save_path) == OK:
		if config.has_section_key(SCORE_SECTION, String(level_id)):
			return maxi(int(config.get_value(SCORE_SECTION, String(level_id), 0)), 0)
		if level_id == &"level_01":
			return _load_legacy_best()
		return 0
	if level_id == &"level_01":
		return _load_legacy_best()
	return 0

func save_best(level_id: StringName, score: int) -> Error:
	if level_id.is_empty() or score <= 0:
		return ERR_INVALID_PARAMETER
	var config := ConfigFile.new()
	var load_error := config.load(save_path)
	if load_error != OK and load_error != ERR_FILE_NOT_FOUND:
		return load_error
	var current_best := load_best(level_id)
	if score <= current_best:
		return OK
	config.set_value(SCORE_SECTION, String(level_id), score)
	return config.save(save_path)

func clear_all() -> Error:
	for path in [save_path, legacy_save_path]:
		if not FileAccess.file_exists(path):
			continue
		var remove_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		if remove_error != OK:
			return remove_error
	return OK

func _load_legacy_best() -> int:
	if not FileAccess.file_exists(legacy_save_path):
		return 0
	var file := FileAccess.open(legacy_save_path, FileAccess.READ)
	return maxi(file.get_32(), 0) if file != null else 0
