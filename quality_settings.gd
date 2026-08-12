class_name VisualQualitySettings
extends Node

signal preset_changed(preset_name: String)

const SETTINGS_PATH: String = "user://settings.cfg"
const DEFAULT_PRESET: String = "Medium"
const PRESET_NAMES: Array[String] = ["Low", "Medium", "High"]
const PRESET_CONFIGS: Dictionary = {
	"Low": {
		"render_scale": 0.75,
		"screen_space_aa": Viewport.SCREEN_SPACE_AA_FXAA,
		"msaa_3d": Viewport.MSAA_DISABLED,
		"shadow_quality": RenderingServer.SHADOW_QUALITY_HARD,
		"ssao_enabled": false,
	},
	"Medium": {
		"render_scale": 1.0,
		"screen_space_aa": Viewport.SCREEN_SPACE_AA_FXAA,
		"msaa_3d": Viewport.MSAA_DISABLED,
		"shadow_quality": RenderingServer.SHADOW_QUALITY_SOFT_LOW,
		"ssao_enabled": true,
	},
	"High": {
		"render_scale": 1.0,
		"screen_space_aa": Viewport.SCREEN_SPACE_AA_DISABLED,
		"msaa_3d": Viewport.MSAA_2X,
		"shadow_quality": RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM,
		"ssao_enabled": true,
	},
}

var settings_path: String = SETTINGS_PATH
var current_preset: String = DEFAULT_PRESET

func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	load_and_apply()

func load_and_apply() -> String:
	var config := ConfigFile.new()
	var saved_preset := DEFAULT_PRESET
	if config.load(settings_path) == OK:
		saved_preset = String(config.get_value("display", "quality_preset", DEFAULT_PRESET))
	apply_preset(saved_preset, false)
	return current_preset

func apply_preset(preset_name: String, persist: bool = true) -> void:
	current_preset = normalize_preset_name(preset_name)
	var profile := PRESET_CONFIGS[current_preset] as Dictionary
	_apply_viewport_profile(profile)
	_apply_to_existing_world_environments(profile)
	if persist:
		_save_current_preset()
	preset_changed.emit(current_preset)

func apply_preset_index(index: int, persist: bool = true) -> void:
	apply_preset(preset_name_from_index(index), persist)

func current_preset_index() -> int:
	return preset_index(current_preset)

func preset_names() -> Array[String]:
	return PRESET_NAMES.duplicate()

func preset_name_from_index(index: int) -> String:
	return PRESET_NAMES[clampi(index, 0, PRESET_NAMES.size() - 1)]

func preset_index(preset_name: String) -> int:
	var normalized := normalize_preset_name(preset_name)
	return PRESET_NAMES.find(normalized)

func normalize_preset_name(preset_name: String) -> String:
	for candidate in PRESET_NAMES:
		if candidate.to_lower() == preset_name.strip_edges().to_lower():
			return candidate
	return DEFAULT_PRESET

func profile_for(preset_name: String) -> Dictionary:
	return (PRESET_CONFIGS[normalize_preset_name(preset_name)] as Dictionary).duplicate()

func _apply_viewport_profile(profile: Dictionary) -> void:
	if not is_inside_tree():
		return
	var root_viewport := get_tree().root
	root_viewport.scaling_3d_scale = float(profile["render_scale"])
	var renderer_name := RenderingServer.get_current_rendering_method()
	if renderer_name != "gl_compatibility":
		root_viewport.screen_space_aa = int(profile["screen_space_aa"]) as Viewport.ScreenSpaceAA
	else:
		root_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	root_viewport.msaa_3d = int(profile["msaa_3d"]) as Viewport.MSAA
	root_viewport.use_taa = false
	var shadow_quality := int(profile["shadow_quality"]) as RenderingServer.ShadowQuality
	RenderingServer.directional_soft_shadow_filter_set_quality(shadow_quality)
	RenderingServer.positional_soft_shadow_filter_set_quality(shadow_quality)

func _apply_to_existing_world_environments(profile: Dictionary) -> void:
	if not is_inside_tree():
		return
	_apply_to_world_environments_below(get_tree().root, bool(profile["ssao_enabled"]))

func _apply_to_world_environments_below(node: Node, ssao_enabled: bool) -> void:
	if node is WorldEnvironment:
		_set_world_environment_ssao(node as WorldEnvironment, ssao_enabled)
	for child in node.get_children():
		_apply_to_world_environments_below(child, ssao_enabled)

func _on_node_added(node: Node) -> void:
	if node is WorldEnvironment:
		call_deferred("_apply_current_ssao", node)

func _apply_current_ssao(world_environment: WorldEnvironment) -> void:
	if not is_instance_valid(world_environment):
		return
	var profile := PRESET_CONFIGS[current_preset] as Dictionary
	_set_world_environment_ssao(world_environment, bool(profile["ssao_enabled"]))

func _set_world_environment_ssao(world_environment: WorldEnvironment, enabled: bool) -> void:
	if world_environment.environment != null:
		if not world_environment.has_meta("quality_environment_is_local"):
			world_environment.environment = world_environment.environment.duplicate(true)
			world_environment.set_meta("quality_environment_is_local", true)
		world_environment.environment.ssao_enabled = enabled

func _save_current_preset() -> void:
	var config := ConfigFile.new()
	config.load(settings_path)
	config.set_value("display", "quality_preset", current_preset)
	var save_error := config.save(settings_path)
	if save_error != OK:
		push_warning("Could not save visual quality preset to %s (error %d)." % [settings_path, save_error])
