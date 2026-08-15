extends SceneTree

# P1 validation: scalable visual presets, persistence, and settings-menu access.

var _pass_count: int = 0
var _fail_count: int = 0
var _temporary_paths: Array[String] = []
var _quality_settings: VisualQualitySettings

func _initialize() -> void:
	_quality_settings = root.get_node("QualitySettings") as VisualQualitySettings
	call_deferred("_run_all")

func _run_all() -> void:
	var original_preset := _quality_settings.current_preset
	_test_preset_contracts()
	await _test_runtime_application_and_ssao()
	_test_persistence()
	await _test_settings_menu_integration()
	_quality_settings.apply_preset(original_preset, false)
	_cleanup_temporary_files()
	print("P1 QUALITY RESULTS: %d passed, %d failed" % [_pass_count, _fail_count])
	quit(0 if _fail_count == 0 else 1)

func _assert(label: String, condition: bool) -> void:
	if condition:
		print("P1_QUALITY_%s_OK" % label.to_upper().replace(" ", "_"))
		_pass_count += 1
	else:
		push_error("P1_QUALITY_%s_FAIL" % label.to_upper().replace(" ", "_"))
		_fail_count += 1

func _test_preset_contracts() -> void:
	_assert("Preset order is Low Medium High", _quality_settings.preset_names() == ["Low", "Medium", "High"])
	var low := _quality_settings.profile_for("Low")
	var medium := _quality_settings.profile_for("Medium")
	var high := _quality_settings.profile_for("High")
	_assert("Low preset reduces render scale", is_equal_approx(float(low["render_scale"]), 0.75))
	_assert("Medium preset keeps native render scale", is_equal_approx(float(medium["render_scale"]), 1.0))
	_assert("High preset keeps native render scale", is_equal_approx(float(high["render_scale"]), 1.0))
	_assert("Medium and High enable authored SSAO", not bool(low["ssao_enabled"]) and bool(medium["ssao_enabled"]) and bool(high["ssao_enabled"]))
	_assert("Invalid preset falls back to Medium", _quality_settings.normalize_preset_name("unknown") == "Medium")

func _test_runtime_application_and_ssao() -> void:
	_quality_settings.apply_preset("Low", false)
	_assert("Low applies seventy five percent 3D scale", is_equal_approx(root.scaling_3d_scale, 0.75))
	var renderer_method := RenderingServer.get_current_rendering_method()
	_assert(
		"Low applies renderer compatible antialiasing",
		root.screen_space_aa == (
			Viewport.SCREEN_SPACE_AA_DISABLED
			if renderer_method == "gl_compatibility"
			else Viewport.SCREEN_SPACE_AA_FXAA
		)
	)
	_assert("Low disables MSAA", root.msaa_3d == Viewport.MSAA_DISABLED)

	var world_environment := WorldEnvironment.new()
	var shared_environment := Environment.new()
	shared_environment.ssao_enabled = true
	world_environment.environment = shared_environment
	root.add_child(world_environment)
	_quality_settings.apply_preset("Low", false)
	_assert("Low disables SSAO on active environments", not world_environment.environment.ssao_enabled)
	_assert("Quality changes do not mutate shared environment assets", shared_environment.ssao_enabled)
	_quality_settings.apply_preset("High", false)
	_assert("High applies two sample MSAA", root.msaa_3d == Viewport.MSAA_2X)
	_assert("High enables SSAO on active environments", world_environment.environment.ssao_enabled)
	_quality_settings.apply_preset("Medium", false)
	_assert("Medium keeps SSAO on active environments", world_environment.environment.ssao_enabled)
	world_environment.queue_free()
	await process_frame

func _test_persistence() -> void:
	var path := _temporary_path("manager")
	var manager := VisualQualitySettings.new()
	manager.settings_path = path
	manager.apply_preset("low", true)
	var config := ConfigFile.new()
	_assert("Quality preset save file loads", config.load(path) == OK)
	_assert("Quality preset persists canonical name", String(config.get_value("display", "quality_preset", "")) == "Low")
	manager.free()

func _test_settings_menu_integration() -> void:
	var path := _temporary_path("menu")
	var config := ConfigFile.new()
	config.set_value("display", "quality_preset", "High")
	config.save(path)

	var menu := (load("res://MainMenu.tscn") as PackedScene).instantiate()
	menu.set("settings_path", path)
	menu.set("_score_store", BestScoreStore.new(_temporary_path("menu_scores"), _temporary_path("menu_legacy")))
	menu.set("_progress_store", CampaignProgressStore.new(_temporary_path("menu_progress")))
	root.add_child(menu)
	await process_frame
	await process_frame
	var settings_box := menu.get_node("CanvasLayer/SettingsPanel/VBoxContainer")
	var quality_option := settings_box.get_node("QualityPresetOption") as OptionButton
	_assert("Settings menu exposes three quality choices", quality_option.item_count == 3)
	_assert("Settings menu loads saved High preset", quality_option.get_item_text(quality_option.selected) == "High")
	_assert("Quality selector accepts keyboard and controller focus", quality_option.focus_mode != Control.FOCUS_NONE)
	_assert(
		"Quality selector has controller focus neighbors",
		not quality_option.focus_neighbor_top.is_empty()
		and not quality_option.focus_neighbor_bottom.is_empty()
	)
	_assert(
		"Settings controls fit the 720p panel",
		settings_box.get_combined_minimum_size().y <= settings_box.size.y
	)
	quality_option.select(0)
	menu.call("_on_quality_preset_selected", 0)
	var saved := ConfigFile.new()
	_assert("Menu quality change saves settings", saved.load(path) == OK)
	_assert("Menu persists selected Low preset", String(saved.get_value("display", "quality_preset", "")) == "Low")
	menu.queue_free()
	await process_frame

func _temporary_path(label: String) -> String:
	var path := "user://p1_quality_%s_%s.cfg" % [label, Time.get_ticks_usec()]
	_temporary_paths.append(path)
	return path

func _cleanup_temporary_files() -> void:
	for path in _temporary_paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
