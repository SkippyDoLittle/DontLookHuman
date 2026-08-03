# picnic_food.gd — Attached to each PicnicFood node
# Detects a nearby player peck, plays effects, and removes the node.
# Each instance is independent — PicnicFood and PicnicFood2 have separate "collected" flags.

extends Node3D

@export var collect_distance: float = 1.2

@onready var player:          Node3D = get_node("../Player") as Node3D
@onready var objective_label: Label  = get_node("../HUD/ObjectiveStatus") as Label

var collected: bool = false
# Guard flag — queue_free() isn't instant, so without this the collection logic
# could run twice in the one-frame gap before the node is actually removed.

func _ready() -> void:
	# Joining "collectibles" is how ranger.gd, escape_zone.gd, and game_timer.gd
	# all find and count food items. queue_free() removes the node from the group automatically.
	add_to_group("collectibles")

func _process(_delta: float) -> void:
	if collected:
		return

	if (
		global_position.distance_to(player.global_position) <= collect_distance
		and bool(player.call("try_consume_peck"))
	):
		collected = true
		SoundManager.play_collect()
		_spawn_burst()

		# Count remaining AFTER this one — still in the group until queue_free runs,
		# so subtract 1 to get the post-collection count.
		var remaining: int = get_tree().get_nodes_in_group("collectibles").size() - 1
		if remaining <= 0:
			objective_label.text = "All items stolen! Reach the exit!"
		else:
			objective_label.text = "%d item(s) left to steal!" % remaining

		queue_free()

func _spawn_burst() -> void:
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
	p.amount           = 14
	p.lifetime         = 0.55
	p.explosiveness    = 1.0            # all particles burst at once
	p.direction        = Vector3.UP
	p.spread           = 180.0          # full sphere spread
	p.gravity          = Vector3(0.0, -6.0, 0.0)
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 4.5
	p.color            = Color(1.0, 0.85, 0.2)   # golden yellow
	p.mesh             = mesh

	# Add to the parent (Main), not this node — queue_free() would destroy child nodes
	# before the particles finish playing.
	get_parent().add_child(p)
	p.global_position = global_position   # must be set after add_child()

	# Auto-destroy when the particle burst finishes.
	p.finished.connect(p.queue_free)
