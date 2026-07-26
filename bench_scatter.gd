# bench_scatter.gd — Procedurally scatter background benches using MultiMeshInstance3D.
# Attach to a Node3D child of Main.  Tune the @export vars in Inspector.
# Benches are visual-only — no collision — since they appear outside the playable park.
extends Node3D

# Keep bench_count well below tree_count so benches feel like occasional detail.
@export var bench_count:    int   = 60

# Half-width of the square clear zone centred on the world origin (matches the 20×20 park).
@export var park_half_size: float = 13.0

# Maximum distance from origin that benches can appear.
@export var outer_radius:   float = 220.0

# Less scale variation than trees — benches are manufactured objects.
@export var scale_min:      float = 0.85
@export var scale_max:      float = 1.15

# Different from tree_scatter's seed (42) to prevent benches clustering at tree positions.
@export var rng_seed:       int   = 99

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed

	# ── Generate positions ────────────────────────────────────────────────────
	var instances: Array = []
	var attempts  := 0
	var r2        := outer_radius * outer_radius

	while instances.size() < bench_count and attempts < bench_count * 40:
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

	var count := instances.size()

	# ── Build meshes (same dimensions as the hand-placed Bench node) ──────────
	# All bench materials share the same wood colour, so one material covers all parts.
	var wood_mat: Material = null
	var ref := get_node_or_null("../Bench")
	if ref:
		wood_mat = ref.get_node("BenchSeat").get_surface_override_material(0)

	var seat_mesh := BoxMesh.new()
	seat_mesh.size     = Vector3(2.0, 0.1, 0.5)
	seat_mesh.material = wood_mat

	var back_mesh := BoxMesh.new()
	back_mesh.size     = Vector3(2.0, 0.5, 0.3)
	back_mesh.material = wood_mat

	var leg_mesh := BoxMesh.new()
	leg_mesh.size     = Vector3(0.1, 0.45, 0.45)
	leg_mesh.material = wood_mat

	# ── Create MultiMesh buffers ──────────────────────────────────────────────
	var seat_mm := MultiMesh.new()
	seat_mm.transform_format = MultiMesh.TRANSFORM_3D
	seat_mm.instance_count   = count
	seat_mm.mesh             = seat_mesh

	var back_mm := MultiMesh.new()
	back_mm.transform_format = MultiMesh.TRANSFORM_3D
	back_mm.instance_count   = count
	back_mm.mesh             = back_mesh

	# Both legs share the same BoxMesh — pack them into one buffer (2 per bench).
	var leg_mm := MultiMesh.new()
	leg_mm.transform_format = MultiMesh.TRANSFORM_3D
	leg_mm.instance_count   = count * 2
	leg_mm.mesh             = leg_mesh

	# ── Fill transforms ───────────────────────────────────────────────────────
	# Each bench part's local offset is rotated + scaled by the bench basis so
	# parts stay correctly positioned relative to each other at any scale/angle.
	for i in count:
		var d: Dictionary = instances[i]
		var x  := float(d["x"])
		var z  := float(d["z"])
		var s  := float(d["s"])
		var ry := float(d["ry"])

		var b   := Basis(Vector3.UP, ry).scaled(Vector3(s, s, s))
		var org := Vector3(x, 0.0, z)

		seat_mm.set_instance_transform(i, Transform3D(b, org + b * Vector3(0.0,  0.45,  0.0 )))
		back_mm.set_instance_transform(i, Transform3D(b, org + b * Vector3(0.0,  0.70, -0.22)))
		leg_mm.set_instance_transform(i * 2,     Transform3D(b, org + b * Vector3(-0.8, 0.225, 0.0)))
		leg_mm.set_instance_transform(i * 2 + 1, Transform3D(b, org + b * Vector3( 0.8, 0.225, 0.0)))

	# ── Attach MultiMeshInstance3D children ───────────────────────────────────
	var seat_mmi       := MultiMeshInstance3D.new()
	seat_mmi.name      = "SeatInstances"
	seat_mmi.multimesh = seat_mm
	add_child(seat_mmi)

	var back_mmi       := MultiMeshInstance3D.new()
	back_mmi.name      = "BackInstances"
	back_mmi.multimesh = back_mm
	add_child(back_mmi)

	var leg_mmi        := MultiMeshInstance3D.new()
	leg_mmi.name       = "LegInstances"
	leg_mmi.multimesh  = leg_mm
	add_child(leg_mmi)
