# table_scatter.gd — Procedurally scatter background picnic tables using MultiMeshInstance3D.
# Attach to a Node3D child of Main.  Tune the @export vars in Inspector.
# Tables are visual-only — no collision — since they appear outside the playable park.
extends Node3D

# Denser than benches (60) but sparser than trees (600).
@export var table_count:    int   = 150

# Half-width of the square clear zone centred on the world origin (matches the 20×20 park).
@export var park_half_size: float = 13.0

# Maximum distance from origin that tables can appear.
@export var outer_radius:   float = 220.0

# Tables are manufactured objects so keep scale variation modest.
@export var scale_min:      float = 0.85
@export var scale_max:      float = 1.15

# Seed independent of tree_scatter (42) and bench_scatter (99).
@export var rng_seed:       int   = 77

# Filled during _ready() with the world-XZ position of every placed table (y = 0).
# path_network.gd reads this after _ready() runs to draw dirt trails between nearby objects.
var positions: Array[Vector3] = []

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed

	# ── Generate positions ────────────────────────────────────────────────────
	var instances: Array = []
	var attempts  := 0
	var r2        := outer_radius * outer_radius

	while instances.size() < table_count and attempts < table_count * 40:
		attempts += 1
		var x := rng.randf_range(-outer_radius, outer_radius)
		var z := rng.randf_range(-outer_radius, outer_radius)
		if abs(x) < park_half_size and abs(z) < park_half_size:
			continue
		if x * x + z * z > r2:
			continue
		instances.append({
			"x":  x,
			"z":  z,
			"s":  rng.randf_range(scale_min, scale_max),
			"ry": rng.randf_range(0.0, TAU),
		})
		positions.append(Vector3(x, 0.0, z))

	var count := instances.size()

	# ── Build meshes (same dimensions as the hand-placed PicnicTable node) ────
	# All five parts share the same lighter-wood colour.
	var wood_mat: Material = null
	var ref := get_node_or_null("../PicnicTable")
	if ref:
		wood_mat = ref.get_node("TableTop").get_surface_override_material(0)

	# TableTop: 1.8 × 0.08 × 0.9 at local (0, 0.72, 0)
	var top_mesh := BoxMesh.new()
	top_mesh.size     = Vector3(1.8, 0.08, 0.9)
	top_mesh.material = wood_mat

	# Seats (left & right share this mesh): 1.6 × 0.06 × 0.3
	# SeatLeft at local (0, 0.4, 0.65), SeatRight at (0, 0.4, -0.65)
	var seat_mesh := BoxMesh.new()
	seat_mesh.size     = Vector3(1.6, 0.06, 0.3)
	seat_mesh.material = wood_mat

	# Legs (A & B share this mesh): 0.08 × 0.72 × 0.8
	# LegA at local (-0.8, 0.36, 0), LegB at (0.8, 0.36, 0)
	var leg_mesh := BoxMesh.new()
	leg_mesh.size     = Vector3(0.08, 0.72, 0.8)
	leg_mesh.material = wood_mat

	# ── Create MultiMesh buffers ──────────────────────────────────────────────
	var top_mm := MultiMesh.new()
	top_mm.transform_format = MultiMesh.TRANSFORM_3D
	top_mm.instance_count   = count
	top_mm.mesh             = top_mesh

	# Two seats per table packed into one buffer.
	var seat_mm := MultiMesh.new()
	seat_mm.transform_format = MultiMesh.TRANSFORM_3D
	seat_mm.instance_count   = count * 2
	seat_mm.mesh             = seat_mesh

	# Two legs per table packed into one buffer.
	var leg_mm := MultiMesh.new()
	leg_mm.transform_format = MultiMesh.TRANSFORM_3D
	leg_mm.instance_count   = count * 2
	leg_mm.mesh             = leg_mesh

	# ── Fill transforms ───────────────────────────────────────────────────────
	for i in count:
		var d: Dictionary = instances[i]
		var x  := float(d["x"])
		var z  := float(d["z"])
		var s  := float(d["s"])
		var ry := float(d["ry"])

		var b   := Basis(Vector3.UP, ry).scaled(Vector3(s, s, s))
		var org := Vector3(x, 0.0, z)

		top_mm.set_instance_transform(i, Transform3D(b, org + b * Vector3(0.0,  0.72,  0.0 )))

		seat_mm.set_instance_transform(i * 2,     Transform3D(b, org + b * Vector3(0.0,  0.4,  0.65)))
		seat_mm.set_instance_transform(i * 2 + 1, Transform3D(b, org + b * Vector3(0.0,  0.4, -0.65)))

		leg_mm.set_instance_transform(i * 2,     Transform3D(b, org + b * Vector3(-0.8, 0.36, 0.0)))
		leg_mm.set_instance_transform(i * 2 + 1, Transform3D(b, org + b * Vector3( 0.8, 0.36, 0.0)))

	# ── Attach MultiMeshInstance3D children ───────────────────────────────────
	var top_mmi       := MultiMeshInstance3D.new()
	top_mmi.name      = "TopInstances"
	top_mmi.multimesh = top_mm
	add_child(top_mmi)

	var seat_mmi       := MultiMeshInstance3D.new()
	seat_mmi.name      = "SeatInstances"
	seat_mmi.multimesh = seat_mm
	add_child(seat_mmi)

	var leg_mmi        := MultiMeshInstance3D.new()
	leg_mmi.name       = "LegInstances"
	leg_mmi.multimesh  = leg_mm
	add_child(leg_mmi)
