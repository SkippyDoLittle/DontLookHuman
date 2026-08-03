class_name CampaignProgressStore
extends RefCounted

const DEFAULT_SAVE_PATH: String = "user://campaign_progress.cfg"
const CAMPAIGN_SECTION: String = "campaign"
const HIGHEST_UNLOCKED_KEY: String = "highest_unlocked"
const COMPLETED_SECTION: String = "completed_levels"
const LEVEL_IDS: Array[StringName] = [
	&"level_01",
	&"level_02",
	&"level_03",
	&"level_04",
	&"level_05",
]

var save_path: String

func _init(path: String = DEFAULT_SAVE_PATH) -> void:
	save_path = path

func load_highest_unlocked() -> int:
	var config := _load_config()
	return clampi(
		int(config.get_value(CAMPAIGN_SECTION, HIGHEST_UNLOCKED_KEY, 0)),
		0,
		LEVEL_IDS.size() - 1
	)

func is_unlocked(level_index: int) -> bool:
	return level_index >= 0 and level_index <= load_highest_unlocked()

func is_completed(level_id: StringName) -> bool:
	if not LEVEL_IDS.has(level_id):
		return false
	var config := _load_config()
	return bool(config.get_value(COMPLETED_SECTION, String(level_id), false))

func record_completion(level_id: StringName) -> Error:
	var level_index := LEVEL_IDS.find(level_id)
	if level_index < 0:
		return ERR_INVALID_PARAMETER

	var config := _load_config()
	config.set_value(COMPLETED_SECTION, String(level_id), true)
	var current_highest := clampi(
		int(config.get_value(CAMPAIGN_SECTION, HIGHEST_UNLOCKED_KEY, 0)),
		0,
		LEVEL_IDS.size() - 1
	)
	var next_index := mini(level_index + 1, LEVEL_IDS.size() - 1)
	config.set_value(CAMPAIGN_SECTION, HIGHEST_UNLOCKED_KEY, maxi(current_highest, next_index))
	return config.save(save_path)

func clear_all() -> Error:
	if not FileAccess.file_exists(save_path):
		return OK
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))

func _load_config() -> ConfigFile:
	var config := ConfigFile.new()
	var load_error := config.load(save_path)
	if load_error != OK and load_error != ERR_FILE_NOT_FOUND:
		push_warning("Could not load campaign progress from %s (error %d)." % [save_path, load_error])
	return config
