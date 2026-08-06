# picnic_food.gd — Attached to each PicnicFood node
# Detects a nearby player peck, awards the pickup immediately, then visibly
# arcs the food into the pigeon's beak before removing the presentation node.
# Each instance is independent — PicnicFood and PicnicFood2 have separate "collected" flags.

extends Node3D

signal food_collected(food: Node3D, origin: Vector3)
signal collection_animation_started
signal collection_animation_completed

@export var collect_distance: float = 1.2
@export_range(0.1, 1.0, 0.01) var collection_animation_duration: float = 0.34

@onready var player: Node3D = get_node("../Player") as Node3D

var collected: bool = false
var _collection_time: float = 0.0
var _collection_origin: Vector3 = Vector3.ZERO
var _collection_scale: Vector3 = Vector3.ONE
var _flight_trail: CPUParticles3D
# Guard flag — queue_free() isn't instant, so without this the collection logic
# could run twice in the one-frame gap before the node is actually removed.

func _ready() -> void:
	# Joining "collectibles" is how ranger suspicion, EscapeZone, and GameSession
	# all find and count food items. queue_free() removes the node from the group automatically.
	add_to_group("collectibles")

func _process(delta: float) -> void:
	if collected:
		_update_collection_animation(delta)
		return

	if (
		global_position.distance_to(player.global_position) <= collect_distance
		and bool(player.call("try_consume_peck"))
	):
		_begin_collection()

func _begin_collection() -> void:
	collected = true
	_collection_time = 0.0
	_collection_origin = global_position
	_collection_scale = scale
	# Gameplay awards the item now, exactly as the old queue_free path did on the
	# collection frame. The node remains briefly only as a visual projectile.
	remove_from_group("collectibles")
	SoundManager.play_food_snatch()
	_spawn_burst_at(_collection_origin, Color(1.0, 0.78, 0.18), 9, 3.2)
	_create_flight_trail()
	if player.has_method("play_food_snatch_reaction"):
		player.call("play_food_snatch_reaction")
	collection_animation_started.emit()
	food_collected.emit(self, _collection_origin)

func _update_collection_animation(delta: float) -> void:
	_collection_time += delta
	var progress := clampf(
		_collection_time / maxf(collection_animation_duration, 0.001),
		0.0,
		1.0
	)
	var eased := smoothstep(0.0, 1.0, progress)
	var target := _collection_target()
	global_position = _collection_origin.lerp(target, eased)
	global_position.y += sin(progress * PI) * 0.58
	if is_instance_valid(_flight_trail):
		_flight_trail.global_position = global_position
	rotation.x += delta * 13.0
	rotation.y += delta * 19.0
	rotation.z += delta * 9.0
	scale = _collection_scale * lerpf(1.0, 0.22, eased)
	if progress < 1.0:
		return
	SoundManager.play_collect()
	_spawn_burst_at(target, Color(1.0, 0.9, 0.35), 16, 4.0)
	if is_instance_valid(_flight_trail):
		_flight_trail.emitting = false
		get_tree().create_timer(0.45).timeout.connect(_flight_trail.queue_free)
	collection_animation_completed.emit()
	queue_free()

func _collection_target() -> Vector3:
	if not is_instance_valid(player):
		return _collection_origin + Vector3.UP * 0.35
	var player_beak := player.get_node_or_null("PigeonVisual/Beak") as Node3D
	if player_beak != null:
		return player_beak.global_position + Vector3.UP * 0.015
	return player.global_position + Vector3.UP * 0.35

func _create_flight_trail() -> void:
	_flight_trail = CPUParticles3D.new()
	_flight_trail.name = "FoodSnatchTrail"
	_flight_trail.amount = 22
	_flight_trail.lifetime = 0.28
	_flight_trail.local_coords = false
	_flight_trail.direction = Vector3.UP
	_flight_trail.spread = 180.0
	_flight_trail.gravity = Vector3(0.0, -1.8, 0.0)
	_flight_trail.initial_velocity_min = 0.15
	_flight_trail.initial_velocity_max = 0.55
	_flight_trail.scale_amount_min = 0.45
	_flight_trail.scale_amount_max = 0.9
	_flight_trail.color = Color(1.0, 0.78, 0.12, 0.95)
	var trail_mesh := SphereMesh.new()
	trail_mesh.radius = 0.035
	trail_mesh.height = 0.07
	trail_mesh.radial_segments = 4
	trail_mesh.rings = 2
	var trail_material := StandardMaterial3D.new()
	trail_material.vertex_color_use_as_albedo = true
	trail_material.emission_enabled = true
	trail_material.emission = Color(1.0, 0.48, 0.04, 1.0)
	trail_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trail_mesh.material = trail_material
	_flight_trail.mesh = trail_mesh
	get_parent().add_child(_flight_trail)
	_flight_trail.global_position = global_position
	_flight_trail.emitting = true

func _spawn_burst_at(origin: Vector3, color: Color, amount: int, speed: float) -> void:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true   # lets p.color below take effect
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED   # flat color, unaffected by lights

	var mesh := SphereMesh.new()
	mesh.radius = 0.06
	mesh.height = 0.12
	mesh.radial_segments = 4   # low-poly diamond shape to match art style
	mesh.rings = 2
	mesh.surface_set_material(0, mat)

	var p := CPUParticles3D.new()
	p.emitting         = true
	p.one_shot         = true
	p.amount           = amount
	p.lifetime         = 0.55
	p.explosiveness    = 1.0            # all particles burst at once
	p.direction        = Vector3.UP
	p.spread           = 180.0          # full sphere spread
	p.gravity          = Vector3(0.0, -6.0, 0.0)
	p.initial_velocity_min = speed * 0.55
	p.initial_velocity_max = speed
	p.color            = color
	p.mesh             = mesh

	# Add to the parent (Main), not this node — queue_free() would destroy child nodes
	# before the particles finish playing.
	get_parent().add_child(p)
	p.global_position = origin   # must be set after add_child()

	# Auto-destroy when the particle burst finishes.
	p.finished.connect(p.queue_free)
