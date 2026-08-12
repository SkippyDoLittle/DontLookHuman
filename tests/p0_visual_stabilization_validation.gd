extends SceneTree

# P0 contract: the emergency presentation cleanup must remain reversible,
# resolution-independent, and free of a blanket material replacement pass.

const LEVEL_PATHS: Array[String] = [
	"res://scenes/levels/Level01_Park.tscn",
	"res://scenes/levels/Level02_Playground.tscn",
	"res://scenes/levels/Level03_Lakeside.tscn",
	"res://scenes/levels/Level04_Festival.tscn",
	"res://scenes/levels/Level05_BotanicalGardens.tscn",
]

var _pass_count := 0
var _fail_count := 0

func _init() -> void:
	_test_global_override_removed()
	_test_level_profiles_are_distinct()
	_test_vignette_is_resolution_independent()
	_test_vignette_is_capped_for_readability()
	print("P0 VISUAL RESULTS: %d passed, %d failed" % [_pass_count, _fail_count])
	quit(0 if _fail_count == 0 else 1)

func _assert(label: String, condition: bool) -> void:
	if condition:
		print("P0_VISUAL_%s_OK" % label.to_upper().replace(" ", "_"))
		_pass_count += 1
	else:
		push_error("P0_VISUAL_%s_FAIL" % label.to_upper().replace(" ", "_"))
		_fail_count += 1

func _read_source(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var source := file.get_as_text()
	file.close()
	return source

func _test_global_override_removed() -> void:
	var base_level_source := _read_source("res://base_level.gd")
	_assert(
		"blanket material override removed",
		not base_level_source.contains("SceneVisualOverride")
		and not FileAccess.file_exists("res://scene_visual_override.gd")
		and not FileAccess.file_exists("res://flat_shading.gdshader")
	)

func _test_level_profiles_are_distinct() -> void:
	var sky_colors: Dictionary = {}
	var scenes_readable := true
	for path in LEVEL_PATHS:
		var source := _read_source(path)
		var marker := "shader_parameter/sky_top_color = Color("
		var start := source.find(marker)
		if start < 0:
			# Level 2 keeps alignment spaces around the equals sign.
			marker = "shader_parameter/sky_top_color    = Color("
			start = source.find(marker)
		if start >= 0:
			var line_end := source.find("\n", start)
			sky_colors[source.substr(start, line_end - start)] = true
		else:
			scenes_readable = false
		if not source.begins_with("[gd_scene"):
			scenes_readable = false
	_assert("all five level sources are readable", scenes_readable)
	_assert("all five levels retain distinct sky profiles", sky_colors.size() == LEVEL_PATHS.size())

func _test_vignette_is_resolution_independent() -> void:
	var shader_source := _read_source("res://vignette.gdshader")
	_assert(
		"vignette derives viewport aspect ratio",
		shader_source.contains("SCREEN_PIXEL_SIZE")
		and not shader_source.contains("1.778")
	)

func _test_vignette_is_capped_for_readability() -> void:
	var hud_source := _read_source("res://ranger_hud_controller.gd")
	_assert(
		"danger vignette maximum is thirty two percent",
		hud_source.contains("maximum / 100.0 * 0.32")
	)
