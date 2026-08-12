extends SceneTree

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
	_test_bounded_distinct_profiles()
	_test_targeted_material_language()
	_test_camera_composition()
	_test_single_camera_feedback_owner()
	_test_capture_uses_shipping_lighting()
	print("P1 VISUAL RESULTS: %d passed, %d failed" % [_pass_count, _fail_count])
	quit(0 if _fail_count == 0 else 1)

func _assert(label: String, condition: bool) -> void:
	if condition:
		print("P1_VISUAL_%s_OK" % label.to_upper().replace(" ", "_"))
		_pass_count += 1
	else:
		push_error("P1_VISUAL_%s_FAIL" % label.to_upper().replace(" ", "_"))
		_fail_count += 1

func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var source := file.get_as_text()
	file.close()
	return source

func _test_bounded_distinct_profiles() -> void:
	var profile_signatures: Dictionary = {}
	var bounded := true
	for path in LEVEL_PATHS:
		var source := _read(path)
		bounded = bounded and source.contains("tonemap_mode = 2")
		bounded = bounded and source.contains("ssao_enabled = true")
		bounded = bounded and source.contains("directional_shadow_max_distance = 32.0")
		bounded = bounded and not source.contains("light_energy = 3.5")
		bounded = bounded and not source.contains("adjustment_enabled = true")
		bounded = bounded and not source.contains("glow_enabled = true")
		var fog_start := source.find("fog_density = ")
		var sky_start := source.find("shader_parameter/sky_top_color")
		if fog_start >= 0 and sky_start >= 0:
			var fog_end := source.find("\n", fog_start)
			var sky_end := source.find("\n", sky_start)
			profile_signatures[
				source.substr(sky_start, sky_end - sky_start)
				+ source.substr(fog_start, fog_end - fog_start)
			] = true
	_assert("five bounded cinematic environment profiles", bounded)
	_assert("environment profiles remain distinct", profile_signatures.size() == 5)

func _test_targeted_material_language() -> void:
	var player := _read("res://scenes/actors/Player.tscn")
	var ranger := _read("res://scenes/actors/Ranger.tscn")
	var tree := _read("res://scenes/props/Tree.tscn")
	var bench := _read("res://scenes/props/Bench.tscn")
	var trash := _read("res://scenes/props/TrashCan.tscn")
	_assert("pigeon feather surfaces have authored roughness", player.count("roughness =") >= 4)
	_assert("ranger cloth and metal surfaces differ", ranger.contains("metallic =") and ranger.count("roughness =") >= 6)
	_assert("foliage and bark remain rough", tree.count("roughness =") >= 2)
	_assert("wood and metal props respond differently", bench.contains("metallic =") and trash.contains("metallic ="))

func _test_camera_composition() -> void:
	var player_scene := _read("res://scenes/actors/Player.tscn")
	_assert("pigeon scale camera uses sixty two degree FOV", player_scene.contains("fov = 62.0"))
	_assert("camera near and far planes fit pigeon scale", player_scene.contains("near = 0.05") and player_scene.contains("far = 260.0"))
	_assert("spring arm collision framing is preserved", player_scene.contains("spring_length = 4.0"))

func _test_single_camera_feedback_owner() -> void:
	var transition := _read("res://transition_controller.gd")
	var controller := _read("res://camera_feedback_controller.gd")
	_assert(
		"transition feedback uses shared camera compositor",
		transition.contains("CameraFeedbackController.shared_for_camera")
	)
	var camera := Camera3D.new()
	var first := CameraFeedbackController.shared_for_camera(camera)
	var second := CameraFeedbackController.shared_for_camera(camera)
	_assert("camera systems resolve one shared feedback owner", first == second)
	camera.free()
	_assert(
		"transition feedback has one offset writer",
		controller.contains("_camera.h_offset")
		and not transition.contains("_camera.h_offset")
	)

func _test_capture_uses_shipping_lighting() -> void:
	var trailer := _read("res://tools/capture_gameplay_video.gd")
	_assert(
		"marketing capture uses authored shipping lighting",
		not trailer.contains("_polish_lighting")
		and not trailer.contains("adjustment_contrast")
		and not trailer.contains("light_energy *=")
	)
