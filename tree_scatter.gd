# tree_scatter.gd — Procedurally places background trees with MultiMeshInstance3D.
# Attach to a Node3D child of Main.  Tune the @export vars in Inspector.
# Trees are visual-only (no collision) — they live outside the playable park,
# which is enclosed by invisible wall colliders anyway.
extends Node3D

# Total number of background trees to scatter.
@export var tree_count:     int   = 600

# Half-width of the square clear zone centred on the world origin.
# The park is 20×20, so 13 keeps every tree outside its bounds (diagonal = 14.1).
@export var park_half_size: float = 13.0

# How far from the origin trees can appear.  220 puts them well past the visible
# horizon at normal gameplay camera heights.
@export var outer_radius:   float = 220.0

# Uniform scale range — produces a natural mix of short and tall trees.
@export var scale_min:      float = 0.75
@export var scale_max:      float = 1.35

# Change this to get a completely different layout without touching anything else.
@export var rng_seed:       int   = 42

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed

	# ── Generate positions ────────────────────────────────────────────────────
	# Reject positions inside the park square and beyond the round outer boundary.
	var instances: Array = []
	var attempts  := 0
	var r2        := outer_radius * outer_radius

	while instances.size() < tree_count and attempts < tree_count * 30:
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

	# ── Build meshes (same dimensions as the hand-placed park trees) ──────────
	var tmesh := CylinderMesh.new()
	tmesh.top_radius      = 0.25
	tmesh.bottom_radius   = 0.25
	tmesh.height          = 2.0
	tmesh.radial_segments = 8
	tmesh.rings           = 1   # straight trunk needs no lateral splits

	var lmesh := SphereMesh.new()
	lmesh.radius          = 1.1
	lmesh.height          = 1.6
	lmesh.radial_segments = 8
	lmesh.rings           = 4

	# Reuse the exact material instances from the hand-placed "Tree" node so
	# colour changes there automatically propagate to the whole forest.
	var ref := get_node_or_null("../Tree")
	if ref:
		tmesh.material = ref.get_node("Trunk").get_surface_override_material(0)
		lmesh.material = ref.get_node("Leaves").get_surface_override_material(0)

	# ── Fill MultiMesh transform buffers ──────────────────────────────────────
	var tmm := MultiMesh.new()
	tmm.transform_format = MultiMesh.TRANSFORM_3D
	tmm.instance_count   = count
	tmm.mesh             = tmesh

	var lmm := MultiMesh.new()
	lmm.transform_format = MultiMesh.TRANSFORM_3D
	lmm.instance_count   = count
	lmm.mesh             = lmesh

	for i in count:
		var d  := instances[i]
		var s  := float(d["s"])
		var x  := float(d["x"])
		var z  := float(d["z"])
		var ry := float(d["ry"])

		# Y-rotation only, then uniform scale.
		# CylinderMesh is centred at its local origin (spans y -1..+1 at scale 1).
		# Lifting the trunk by s puts its base exactly on y = 0 (ground level).
		var b := Basis(Vector3.UP, ry).scaled(Vector3(s, s, s))
		tmm.set_instance_transform(i, Transform3D(b, Vector3(x, s,       z)))
		lmm.set_instance_transform(i, Transform3D(b, Vector3(x, s * 2.4, z)))

	# ── Attach MultiMeshInstance3D children ───────────────────────────────────
	var trunk_mmi       := MultiMeshInstance3D.new()
	trunk_mmi.name      = "TrunkInstances"
	trunk_mmi.multimesh = tmm
	add_child(trunk_mmi)

	var leaves_mmi       := MultiMeshInstance3D.new()
	leaves_mmi.name      = "LeavesInstances"
	leaves_mmi.multimesh = lmm
	add_child(leaves_mmi)
