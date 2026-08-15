class_name AccessibilitySettings
extends RefCounted

## Lightweight persisted accessibility state shared without an autoload.
## Values are loaded lazily and cached per path so tests and tools can inject an
## isolated ConfigFile without disturbing the player's real preferences.

const DEFAULT_SETTINGS_PATH: String = "user://settings.cfg"
const SECTION: String = "accessibility"
const REDUCED_MOTION_KEY: String = "reduced_motion"

static var _reduced_motion_cache: Dictionary = {}


static func is_reduced_motion_enabled(settings_path: String = DEFAULT_SETTINGS_PATH) -> bool:
	var resolved_path := _resolved_path(settings_path)
	if not _reduced_motion_cache.has(resolved_path):
		var config := ConfigFile.new()
		var load_error := config.load(resolved_path)
		var enabled := false
		if load_error == OK:
			enabled = bool(config.get_value(SECTION, REDUCED_MOTION_KEY, false))
		_reduced_motion_cache[resolved_path] = enabled
	return bool(_reduced_motion_cache[resolved_path])


static func set_reduced_motion(
	enabled: bool,
	settings_path: String = DEFAULT_SETTINGS_PATH
) -> Error:
	var resolved_path := _resolved_path(settings_path)
	var config := ConfigFile.new()
	var load_error := config.load(resolved_path)
	if load_error != OK and load_error != ERR_FILE_NOT_FOUND:
		return load_error
	config.set_value(SECTION, REDUCED_MOTION_KEY, enabled)
	var save_error := config.save(resolved_path)
	if save_error == OK:
		_reduced_motion_cache[resolved_path] = enabled
	return save_error


static func invalidate_cache(settings_path: String = "") -> void:
	if settings_path.is_empty():
		_reduced_motion_cache.clear()
		return
	_reduced_motion_cache.erase(_resolved_path(settings_path))


static func _resolved_path(settings_path: String) -> String:
	return DEFAULT_SETTINGS_PATH if settings_path.is_empty() else settings_path
