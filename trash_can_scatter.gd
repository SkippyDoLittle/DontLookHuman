# trash_can_scatter.gd — Procedurally scatter background trash cans using MultiMeshInstance3D.
# Attach to a Node3D child of Main.  Tune the @export vars in Inspector.
# Trash cans are visual-only — no collision — since they appear outside the playable park.
# The two hand-placed TrashCan/TrashCan2 nodes inside the park remain for gameplay use.
extends Node3D

# Density matches benches — sparse, occasional detail.
@export var trash_count:    int   = 60

# Half-width of the square clear zone centred on the world origin (matches the 20×20 park).
@export var park_half_size: float = 13.0

# Maximum distance from origin that trash cans can appear.
@export var outer_radius:   float = 220.0

# Manufactured objects — keep scale variation narrow.
@export var scale_min:      float = 0.85
@export var scale_max:      float = 1.15

# Different seed from tree_scatter (42), bench_scatter (99), table_scatter (77).
@export var rng_seed:       int   = 66

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed

	# ── Generate positions ────────────────────────────────────────────────────
	var instances: Array = []
	var attempts  := 0
	var r2        := outer_radius * outer_radius

	while instances.size() < trash_count and attempts < trash_count * 40:
		attempts += 1
		var x := rng.randf_range(-outer_radius, outer_radius)
		var z := rng.randf_range(-outer_radius, outer_radius)
		# Keep the playable park clear.
		if abs(x) < park_half_size and abs(z) < park_half_size:
			continue
		# Stay within a circle so the world edge looks natural.
		if x * x + z * z > r2:
			continue
		instances.append({
			"x":  x,
			"z":  z,
			"s":  rng.randf_range(scale_min, scale_max),
			"ry": rng.randf_range(0.0, TAU),
		})

	var count := instances.size()

	# ── Build meshes (matching the hand-placed TrashCan node exactly) ─────────
	# Reuse the same material instances so colour changes on the originals propagate here.
	var body_mat: Material = null
	var lid_mat:  Material = null
	var ref := get_node_or_null("../TrashCan")
	if ref:
		body_mat = ref.get_node("CanBody").get_surface_override_material(0)
		lid_mat  = ref.get_node("CanLid").get_surface_override_material(0)

	# CanBody: top_radius=0.2, bottom_radius=0.18, height=0.7 at local (0, 0.35, 0)
	var body_mesh          := CylinderMesh.new()
	body_mesh.top_radius    = 0.2
	body_mesh.bottom_radius = 0.18
	body_mesh.height        = 0.7
	body_mesh.radial_segments = 8
	body_mesh.material      = body_mat

	# CanLid: top_radius=0.22, bottom_radius=0.22, height=0.5 at local (0, 0.73, 0)
	var lid_mesh           := CylinderMesh.new()
	lid_mesh.top_radius     = 0.22
	lid_mesh.bottom_radius  = 0.22
	lid_mesh.height         = 0.5
	lid_mesh.radial_segments = 8
	lid_mesh.material       = lid_mat

	# ── Create MultiMesh buffers ──────────────────────────────────────────────
	var body_mm := MultiMesh.new()
	body_mm.transform_format = MultiMesh.TRANSFORM_3D
	body_mm.instance_count   = count
	body_mm.mesh             = body_mesh

	var lid_mm := MultiMesh.new()
	lid_mm.transform_format = MultiMesh.TRANSFORM_3D
	lid_mm.instance_count   = count
	lid_mm.mesh             = lid_mesh

	# ── Fill transforms ───────────────────────────────────────────────────────
	for i in count:
		var d: Dictionary = instances[i]
		var x  := float(d["x"])
		var z  := float(d["z"])
		var s  := float(d["s"])
		var ry := float(d["ry"])

		# Y-rotation only, then uniform scale — same pattern as bench/table scatter.
		var b   := Basis(Vector3.UP, ry).scaled(Vector3(s, s, s))
		var org := Vector3(x, 0.0, z)

		body_mm.set_instance_transform(i, Transform3D(b, org + b * Vector3(0.0, 0.35, 0.0)))
		lid_mm.set_instance_transform( i, Transform3D(b, org + b * Vector3(0.0, 0.73, 0.0)))

	# ── Attach MultiMeshInstance3D children ───────────────────────────────────
	var body_mmi       := MultiMeshInstance3D.new()
	body_mmi.name      = "BodyInstances"
	body_mmi.multimesh = body_mm
	add_child(body_mmi)

	var lid_mmi        := MultiMeshInstance3D.new()
	lid_mmi.name       = "LidInstances"
	lid_mmi.multimesh  = lid_mm
	add_child(lid_mmi)
