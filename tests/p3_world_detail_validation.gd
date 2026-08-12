extends SceneTree

const SWAY_SHADER := preload("res://world_detail_sway.gdshader")

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_validate")


func _validate() -> void:
	var specs: Array[Dictionary] = [
		{
			"path": "res://scenes/levels/Level01_Park.tscn",
			"profile": WorldDetailScatter.Profile.PARK,
			"seed": 181,
			"layers": [&"GrassBlades", &"FallenLeaves"],
			"count": 220,
			"sway": &"GrassBlades",
		},
		{
			"path": "res://scenes/levels/Level02_Playground.tscn",
			"profile": WorldDetailScatter.Profile.PLAYGROUND,
			"seed": 283,
			"layers": [&"BrightPebbles", &"ChalkAccents"],
			"count": 155,
			"sway": &"",
		},
		{
			"path": "res://scenes/levels/Level03_Lakeside.tscn",
			"profile": WorldDetailScatter.Profile.LAKESIDE,
			"seed": 389,
			"layers": [&"ReedBlades", &"ShoreStones"],
			"count": 170,
			"sway": &"ReedBlades",
		},
		{
			"path": "res://scenes/levels/Level04_Festival.tscn",
			"profile": WorldDetailScatter.Profile.FESTIVAL,
			"seed": 487,
			"layers": [&"Confetti", &"PaperScraps"],
			"count": 220,
			"sway": &"",
		},
		{
			"path": "res://scenes/levels/Level05_BotanicalGardens.tscn",
			"profile": WorldDetailScatter.Profile.BOTANICAL,
			"seed": 593,
			"layers": [&"GroundFoliage", &"FlowerStems", &"FlowerBlooms"],
			"count": 226,
			"sway": &"GroundFoliage",
		},
	]

	var seen_profiles: Dictionary = {}
	var seen_seeds: Dictionary = {}
	for spec in specs:
		await _validate_level(spec)
		seen_profiles[spec["profile"]] = true
		seen_seeds[spec["seed"]] = true

	_check(seen_profiles.size() == 5, "all five levels use distinct detail profiles")
	_check(seen_seeds.size() == 5, "all five levels use distinct deterministic seeds")
	_validate_source_contract()
	_validate_shader_contract()

	if _failures == 0:
		print("P3_WORLD_DETAIL_VALIDATION_OK")
	quit(_failures)


func _validate_level(spec: Dictionary) -> void:
	var packed := load(spec["path"]) as PackedScene
	_check(packed != null, "%s loads" % spec["path"])
	if packed == null:
		return

	var level := packed.instantiate()
	root.add_child(level)
	await process_frame
	await process_frame

	var scatter := level.get_node_or_null("WorldDetailScatter") as WorldDetailScatter
	_check(scatter != null, "%s has one stable WorldDetailScatter" % spec["path"])
	if scatter == null:
		await _unload_level(level)
		return

	_check(scatter.profile == int(spec["profile"]), "%s uses its intended profile" % spec["path"])
	_check(scatter.rng_seed == int(spec["seed"]), "%s keeps its intended seed" % spec["path"])
	_check(scatter.build_count == 1, "%s builds detail exactly once" % spec["path"])
	_check(not scatter.is_processing(), "%s has no idle processing" % spec["path"])
	_check(not scatter.is_physics_processing(), "%s has no physics processing" % spec["path"])
	_check(scatter.draw_call_count >= 2 and scatter.draw_call_count <= 4,
		"%s stays within the 2-4 detail draw-call budget" % spec["path"])
	_check(scatter.draw_call_count == Array(spec["layers"]).size(),
		"%s exposes one MultiMesh per authored layer" % spec["path"])
	_check(scatter.detail_instance_count == int(spec["count"]),
		"%s generates the deliberate bounded instance count" % spec["path"])
	_check(scatter.detail_instance_count <= 240,
		"%s keeps total detail instances bounded" % spec["path"])
	var expected_sway_calls := 0 if StringName(spec["sway"]) == &"" else 1
	_check(scatter.sway_draw_call_count == expected_sway_calls,
		"%s keeps GPU sway to its intended single layer" % spec["path"])

	var exclusion_points := _level_exclusion_points(level, scatter)
	var measured_instances := 0
	for expected_layer in Array(spec["layers"]):
		var layer := scatter.get_node_or_null(NodePath(String(expected_layer))) as MultiMeshInstance3D
		_check(layer != null, "%s contains %s" % [spec["path"], expected_layer])
		if layer == null:
			continue
		_check(layer.get_child_count() == 0, "%s is render-only" % expected_layer)
		_check(layer.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"%s disables small-detail shadows" % expected_layer)
		var multimesh := layer.multimesh
		_check(multimesh != null and multimesh.mesh != null, "%s owns one shared mesh" % expected_layer)
		if multimesh == null or multimesh.mesh == null:
			continue
		_check(multimesh.use_colors, "%s uses per-instance palette colors" % expected_layer)
		_check(multimesh.mesh.material != null, "%s shares one material across instances" % expected_layer)
		var should_sway := StringName(expected_layer) == StringName(spec["sway"])
		_check((multimesh.mesh.material is ShaderMaterial) == should_sway,
			"%s has the intended static/GPU-sway material" % expected_layer)
		if should_sway and multimesh.mesh.material is ShaderMaterial:
			_check((multimesh.mesh.material as ShaderMaterial).shader == SWAY_SHADER,
				"%s uses the shared lightweight sway shader" % expected_layer)

		measured_instances += multimesh.instance_count
		var positions: PackedVector3Array = scatter.generated_positions_by_layer.get(
			StringName(expected_layer), PackedVector3Array()
		)
		var scales: PackedVector3Array = scatter.generated_scales_by_layer.get(
			StringName(expected_layer), PackedVector3Array()
		)
		_check(positions.size() == multimesh.instance_count,
			"%s records every generated GPU transform position" % expected_layer)
		_check(scales.size() == multimesh.instance_count,
			"%s records every generated GPU transform scale" % expected_layer)
		var central_zone_clear := true
		var inside_outer_composition := true
		var exclusions_clear := true
		for origin in positions:
			var horizontal_radius := Vector2(origin.x, origin.z).length()
			central_zone_clear = central_zone_clear and horizontal_radius >= scatter.central_clear_radius + 0.2
			inside_outer_composition = inside_outer_composition and horizontal_radius <= scatter.outer_radius + 0.01
			for point in exclusion_points:
				var distance := Vector2(origin.x - point.x, origin.z - point.z).length()
				exclusions_clear = exclusions_clear and distance >= scatter.objective_clearance - 0.001
		_check(central_zone_clear, "%s stays outside the central action zone" % expected_layer)
		_check(inside_outer_composition, "%s stays inside the playable outer composition" % expected_layer)
		_check(exclusions_clear, "%s preserves objective/player clearance" % expected_layer)

	_check(measured_instances == scatter.detail_instance_count,
		"%s reports the actual MultiMesh instance total" % spec["path"])
	_check(_collision_descendant_count(scatter) == 0,
		"%s detail creates no collision or physics objects" % spec["path"])

	var first_signature := scatter.generated_signature
	_check(first_signature != 0, "%s produces a deterministic signature" % spec["path"])
	await _unload_level(level)

	var repeat_level := packed.instantiate()
	root.add_child(repeat_level)
	await process_frame
	await process_frame
	var repeat_scatter := repeat_level.get_node_or_null("WorldDetailScatter") as WorldDetailScatter
	_check(repeat_scatter != null and repeat_scatter.generated_signature == first_signature,
		"%s reproduces the same layout for the same seed" % spec["path"])
	await _unload_level(repeat_level)


func _level_exclusion_points(level: Node, scatter: Node3D) -> PackedVector3Array:
	var points := PackedVector3Array()
	for child in level.get_children():
		if not child is Node3D:
			continue
		var child_name := String(child.name)
		if child_name == "Player" \
				or child_name.begins_with("PicnicFood") \
				or child_name.begins_with("EscapeZone") \
				or child_name == "WaterZone" \
				or child_name == "Pond" \
				or child_name == "Lake" \
				or child_name == "Fountain":
			points.append(scatter.to_local((child as Node3D).global_position))
	return points


func _collision_descendant_count(node: Node) -> int:
	var count := 0
	for child in node.get_children():
		if child is CollisionObject3D or child is CollisionShape3D or child is CollisionPolygon3D:
			count += 1
		count += _collision_descendant_count(child)
	return count


func _validate_source_contract() -> void:
	var source := _read_source("res://world_detail_scatter.gd")
	_check(not source.contains("func _process("), "scatter source defines no per-frame idle callback")
	_check(not source.contains("func _physics_process("), "scatter source defines no physics callback")
	_check(source.contains("MultiMesh.new()"), "scatter uses MultiMesh GPU batches")
	_check(not source.contains("CollisionShape3D.new()"), "scatter never allocates collision shapes")


func _validate_shader_contract() -> void:
	var source := _read_source("res://world_detail_sway.gdshader")
	_check(source.contains("void vertex()"), "sway is GPU vertex motion")
	_check(source.contains("MODEL_MATRIX"), "sway phase varies by world/instance position")
	_check(source.contains("TIME"), "sway animates without CPU updates")
	_check(not source.contains("texture("), "sway shader has no texture sampling cost")
	_check(not source.contains("discard"), "sway shader has no fragment discard cost")


func _read_source(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var source := file.get_as_text()
	file.close()
	return source


func _unload_level(level: Node) -> void:
	if is_instance_valid(level):
		level.queue_free()
	await process_frame


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("P3 WORLD DETAIL: %s" % message)
