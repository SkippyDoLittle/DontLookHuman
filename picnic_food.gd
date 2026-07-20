extends Node3D

@export var collect_distance: float = 1.2

@onready var player: Node3D = get_node("../Player") as Node3D
@onready var objective_label: Label = get_node("../HUD/ObjectiveStatus") as Label

var collected: bool = false

func _ready() -> void:
	add_to_group("collectibles")

func _process(_delta: float) -> void:
	if collected:
		return

	if global_position.distance_to(player.global_position) <= collect_distance:
		collected = true
		SoundManager.play_collect()
		_spawn_burst()
		var remaining: int = get_tree().get_nodes_in_group("collectibles").size() - 1
		if remaining <= 0:
			objective_label.text = "All items stolen! Reach the exit!"
		else:
			objective_label.text = "%d item(s) left to steal!" % remaining
		queue_free()

func _spawn_burst() -> void:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var mesh := SphereMesh.new()
	mesh.radius = 0.06
	mesh.height = 0.12
	mesh.radial_segments = 4
	mesh.rings = 2
	mesh.surface_set_material(0, mat)

	var p := CPUParticles3D.new()
	p.emitting = true
	p.one_shot = true
	p.amount = 14
	p.lifetime = 0.55
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0
	p.gravity = Vector3(0.0, -6.0, 0.0)
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 4.5
	p.color = Color(1.0, 0.85, 0.2)
	p.mesh = mesh
	get_parent().add_child(p)
	p.global_position = global_position
	p.finished.connect(p.queue_free)
