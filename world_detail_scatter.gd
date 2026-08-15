class_name WorldDetailScatter
extends Node3D

const SWAY_SHADER := preload("res://world_detail_sway.gdshader")

## Deterministic, visual-only ground detail for the five park themes.
##
## Each authored layer is one MultiMesh draw call. Generation happens once in
## _ready(); there is no per-frame CPU work and none of the generated children
## participate in collision or physics.

enum Profile {
	PARK,
	PLAYGROUND,
	LAKESIDE,
	FESTIVAL,
	BOTANICAL,
}

@export_enum("Park", "Playground", "Lakeside", "Festival", "Botanical") var profile: int = Profile.PARK
@export var rng_seed: int = 181
@export_range(3.0, 9.0, 0.25) var central_clear_radius: float = 5.5
@export_range(9.0, 15.0, 0.25) var outer_radius: float = 14.25
@export_range(0.5, 3.0, 0.1) var objective_clearance: float = 1.7

var detail_instance_count: int = 0
var draw_call_count: int = 0
var generated_signature: int = 0
var build_count: int = 0
var excluded_point_count: int = 0
var sway_draw_call_count: int = 0
var generated_positions_by_layer: Dictionary = {}
var generated_scales_by_layer: Dictionary = {}

var _built: bool = false
var _shared_sway_material: ShaderMaterial


func _ready() -> void:
	# Rendering remains active when processing is disabled. This node only needs
	# one initialization pass; transforms stay in the MultiMesh GPU buffers.
	set_process(false)
	set_physics_process(false)
	_build_details()


func _build_details() -> void:
	if _built:
		return
	_built = true
	build_count += 1

	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var exclusions := _collect_exclusion_points()
	excluded_point_count = exclusions.size()
	var shared_placements: Dictionary = {}

	for layer in _profile_layers():
		_add_layer(layer, rng, exclusions, shared_placements)


func _add_layer(
		layer: Dictionary,
		rng: RandomNumberGenerator,
		exclusions: PackedVector3Array,
		shared_placements: Dictionary
	) -> void:
	var placement_key: StringName = layer.get("placement_key", layer["name"])
	var positions: PackedVector3Array
	if shared_placements.has(placement_key):
		positions = shared_placements[placement_key]
	else:
		positions = _sample_positions(
			int(layer["count"]),
			rng,
			exclusions,
			float(layer.get("radius_min", central_clear_radius + 0.25)),
			float(layer.get("radius_max", outer_radius))
		)
		shared_placements[placement_key] = positions

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.instance_count = positions.size()
	multimesh.mesh = layer["mesh"]

	var palette: Array = layer["palette"]
	var scale_min: float = float(layer.get("scale_min", 0.85))
	var scale_max: float = float(layer.get("scale_max", 1.2))
	var base_scale: Vector3 = layer.get("base_scale", Vector3.ONE)
	var base_y: float = float(layer.get("base_y", 0.01))
	var is_flat: bool = bool(layer.get("flat", false))
	var generated_scales := PackedVector3Array()

	for index in range(positions.size()):
		var sampled_position := positions[index]
		var uniform_scale := rng.randf_range(scale_min, scale_max)
		var instance_scale := base_scale * uniform_scale
		generated_scales.append(instance_scale)
		var yaw := rng.randf_range(0.0, TAU)
		var instance_basis: Basis
		if is_flat:
			instance_basis = Basis.from_euler(Vector3(
				rng.randf_range(-0.045, 0.045),
				yaw,
				rng.randf_range(-0.045, 0.045)
			))
		else:
			instance_basis = Basis(Vector3.UP, yaw)
		instance_basis = instance_basis.scaled(instance_scale)
		var origin := Vector3(
			sampled_position.x,
			base_y * instance_scale.y,
			sampled_position.z
		)
		multimesh.set_instance_transform(index, Transform3D(instance_basis, origin))
		multimesh.set_instance_color(index, palette[rng.randi_range(0, palette.size() - 1)])
		_accumulate_signature(origin, yaw, instance_scale)

	var instances := MultiMeshInstance3D.new()
	instances.name = StringName(layer["name"])
	instances.multimesh = multimesh
	instances.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instances.visibility_range_end = 42.0
	instances.visibility_range_end_margin = 5.0
	add_child(instances)
	generated_positions_by_layer[StringName(layer["name"])] = positions
	generated_scales_by_layer[StringName(layer["name"])] = generated_scales

	draw_call_count += 1
	detail_instance_count += positions.size()
	if bool(layer.get("sway", false)):
		sway_draw_call_count += 1


func _sample_positions(
		count: int,
		rng: RandomNumberGenerator,
		exclusions: PackedVector3Array,
		requested_min_radius: float,
		requested_max_radius: float
	) -> PackedVector3Array:
	var positions := PackedVector3Array()
	var radius_min := maxf(central_clear_radius + 0.25, requested_min_radius)
	var radius_max := minf(outer_radius, requested_max_radius)
	var minimum_squared := radius_min * radius_min
	var maximum_squared := radius_max * radius_max
	var attempts := 0
	var max_attempts := count * 30

	while positions.size() < count and attempts < max_attempts:
		attempts += 1
		# Square-root sampling keeps density visually even across the annulus.
		var radius := sqrt(rng.randf_range(minimum_squared, maximum_squared))
		var angle := rng.randf_range(0.0, TAU)
		var candidate := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		if _is_excluded(candidate, exclusions):
			continue
		positions.append(candidate)

	return positions


func _is_excluded(candidate: Vector3, exclusions: PackedVector3Array) -> bool:
	var clearance_squared := objective_clearance * objective_clearance
	for point in exclusions:
		var delta := Vector2(candidate.x - point.x, candidate.z - point.z)
		if delta.length_squared() < clearance_squared:
			return true
	return false


func _collect_exclusion_points() -> PackedVector3Array:
	var points := PackedVector3Array()
	var level := get_parent()
	if level == null:
		return points

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
			points.append(to_local((child as Node3D).global_position))
	return points


func _accumulate_signature(origin: Vector3, yaw: float, detail_scale: Vector3) -> void:
	var component := (
		int(round(origin.x * 1000.0)) * 17
		+ int(round(origin.z * 1000.0)) * 31
		+ int(round(yaw * 1000.0)) * 13
		+ int(round(detail_scale.x * 1000.0))
	)
	generated_signature = abs((generated_signature * 65599 + component) % 2147483647)


func _profile_layers() -> Array[Dictionary]:
	match profile:
		Profile.PLAYGROUND:
			return _playground_layers()
		Profile.LAKESIDE:
			return _lakeside_layers()
		Profile.FESTIVAL:
			return _festival_layers()
		Profile.BOTANICAL:
			return _botanical_layers()
		_:
			return _park_layers()


func _park_layers() -> Array[Dictionary]:
	return [
		{
			"name": &"GrassBlades",
			"count": 150,
			"mesh": _box_mesh(Vector3(0.035, 0.24, 0.085), _sway_material()),
			"palette": [Color("47733e"), Color("5f8744"), Color("7b9348")],
			"base_y": 0.12,
			"scale_min": 0.7,
			"scale_max": 1.35,
			"radius_min": 6.0,
			"sway": true,
		},
		{
			"name": &"FallenLeaves",
			"count": 70,
			"mesh": _box_mesh(Vector3(0.15, 0.012, 0.085), _material()),
			"palette": [Color("bb6b35"), Color("d1983c"), Color("8d4c2d")],
			"base_y": 0.016,
			"scale_min": 0.75,
			"scale_max": 1.25,
			"radius_max": 13.75,
			"flat": true,
		},
	]


func _playground_layers() -> Array[Dictionary]:
	return [
		{
			"name": &"BrightPebbles",
			"count": 90,
			"mesh": _sphere_mesh(0.065, 0.09, _material()),
			"palette": [Color("e95d50"), Color("e7c84d"), Color("55a9d9"), Color("72ba74")],
			"base_y": 0.045,
			"base_scale": Vector3(1.0, 0.72, 1.15),
			"scale_min": 0.7,
			"scale_max": 1.25,
			"radius_min": 6.0,
		},
		{
			"name": &"ChalkAccents",
			"count": 65,
			"mesh": _box_mesh(Vector3(0.24, 0.01, 0.035), _material()),
			"palette": [Color("f7eee1"), Color("f4a7b9"), Color("9bd9ea"), Color("f2db75")],
			"base_y": 0.018,
			"scale_min": 0.65,
			"scale_max": 1.35,
			"radius_max": 13.5,
			"flat": true,
		},
	]


func _lakeside_layers() -> Array[Dictionary]:
	return [
		{
			"name": &"ReedBlades",
			"count": 105,
			"mesh": _box_mesh(Vector3(0.035, 0.46, 0.075), _sway_material()),
			"palette": [Color("597344"), Color("71864d"), Color("9a8f54")],
			"base_y": 0.23,
			"scale_min": 0.7,
			"scale_max": 1.35,
			"radius_min": 6.0,
			"radius_max": 13.75,
			"sway": true,
		},
		{
			"name": &"ShoreStones",
			"count": 65,
			"mesh": _sphere_mesh(0.11, 0.12, _material()),
			"palette": [Color("657078"), Color("7f8078"), Color("968b77")],
			"base_y": 0.06,
			"base_scale": Vector3(1.25, 0.58, 0.9),
			"scale_min": 0.65,
			"scale_max": 1.35,
			"flat": true,
		},
	]


func _festival_layers() -> Array[Dictionary]:
	return [
		{
			"name": &"Confetti",
			"count": 170,
			"mesh": _box_mesh(Vector3(0.09, 0.009, 0.035), _material()),
			"palette": [Color("ef476f"), Color("ffd166"), Color("06d6a0"), Color("4fa3e3"), Color("c77dff")],
			"base_y": 0.018,
			"scale_min": 0.65,
			"scale_max": 1.3,
			"radius_min": 5.25,
			"flat": true,
		},
		{
			"name": &"PaperScraps",
			"count": 50,
			"mesh": _box_mesh(Vector3(0.17, 0.012, 0.11), _material()),
			"palette": [Color("e9dfcf"), Color("d97745"), Color("4d8c8b"), Color("9b6b8f")],
			"base_y": 0.018,
			"scale_min": 0.7,
			"scale_max": 1.25,
			"radius_min": 6.0,
			"radius_max": 13.75,
			"flat": true,
		},
	]


func _botanical_layers() -> Array[Dictionary]:
	return [
		{
			"name": &"GroundFoliage",
			"count": 130,
			"mesh": _box_mesh(Vector3(0.04, 0.27, 0.11), _sway_material()),
			"palette": [Color("2f6b43"), Color("4d844e"), Color("73914d")],
			"base_y": 0.135,
			"scale_min": 0.65,
			"scale_max": 1.3,
			"radius_min": 5.75,
			"sway": true,
		},
		{
			"name": &"FlowerStems",
			"count": 48,
			"placement_key": &"flowers",
			"mesh": _cylinder_mesh(0.014, 0.28, _material()),
			"palette": [Color("477348"), Color("5d8b51")],
			"base_y": 0.14,
			"scale_min": 0.75,
			"scale_max": 1.2,
			"radius_min": 6.5,
			"radius_max": 13.75,
		},
		{
			"name": &"FlowerBlooms",
			"count": 48,
			"placement_key": &"flowers",
			"mesh": _sphere_mesh(0.06, 0.095, _material()),
			"palette": [Color("f3c84b"), Color("ef7ca8"), Color("ab8bd8"), Color("f4eee3")],
			"base_y": 0.305,
			"scale_min": 0.75,
			"scale_max": 1.2,
			"radius_min": 6.5,
			"radius_max": 13.75,
		},
	]


func _material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.WHITE
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.92
	return material


func _sway_material() -> ShaderMaterial:
	if _shared_sway_material == null:
		_shared_sway_material = ShaderMaterial.new()
		_shared_sway_material.shader = SWAY_SHADER
	return _shared_sway_material


func _box_mesh(size: Vector3, material: Material) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	return mesh


func _sphere_mesh(radius: float, height: float, material: Material) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 8
	mesh.rings = 4
	mesh.material = material
	return mesh


func _cylinder_mesh(radius: float, height: float, material: Material) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 5
	mesh.rings = 1
	mesh.material = material
	return mesh
