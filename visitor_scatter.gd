# visitor_scatter.gd — Spawns extra background park visitors spread across the whole map.
# Attach to a VisitorScatter Node3D in Main.tscn.
#
# ── PERFORMANCE NOTE ──────────────────────────────────────────────────────────
# Each visitor is a CharacterBody3D running _process (wander AI) and
# _physics_process (move_and_slide) every frame.  park_visitor.gd is lighter
# than npc_animal.gd — no peck animation, no audio — so visitors cost less per
# frame than pigeons.
#
# Combined NPC count at defaults:
#   5  original park pigeons  (npc_animal.gd — heaviest: animation + audio)
#   20 scatter pigeons        (npc_animal.gd)
#   3  original park visitors (park_visitor.gd — lighter)
#   15 scatter visitors       (park_visitor.gd)
#   1  Ranger                 (ranger.gd)
#   ─────────────────────────────────────────────────────
#   44 total CharacterBody3D nodes
#
# On a typical modern PC this is fine.  On older/weaker hardware, reduce
# pigeon_count in PigeonScatter and visitor_count here until frame rate is smooth.
extends Node3D

# ── Tunable in Inspector ──────────────────────────────────────────────────────

# How many extra visitors to spawn (on top of the 3 already in the scene).
@export var visitor_count: int   = 15

# Visitors won't spawn closer than this to the world origin.
@export var min_radius:    float = 6.0

# Visitors won't spawn further than this from the world origin.
@export var max_radius:    float = 70.0

# Change this number to get a completely different layout.
@export var rng_seed:      int   = 43

# ── Constants ─────────────────────────────────────────────────────────────────

# Clear bubble around where the player starts.
const PLAYER_START: Vector3 = Vector3(3.0, 0.0, 0.0)
const PLAYER_CLEAR: float   = 4.5

# Minimum gap between any two spawn points so visitors don't pile up.
const MIN_SEP: float = 4.5   # slightly wider than pigeons — human models are larger

# Spawn height — CharacterBody3D centre sits at y=0.525 for park visitors.
const VISITOR_Y: float = 0.525


func _ready() -> void:
	# Defer so all sibling _ready() calls complete before we start duplicating.
	call_deferred("_spawn")


func _spawn() -> void:
	var template := get_node_or_null("../ParkVisitor1")
	if template == null:
		push_warning("VisitorScatter: ParkVisitor1 template not found — no visitors spawned")
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed

	var positions := _gen_positions(rng)

	for i in positions.size():
		var dup := template.duplicate()
		dup.name = "Visitor_s%d" % i

		# Widen wander_radius BEFORE add_child so _ready() picks the first target
		# in the wider range — otherwise distant visitors walk straight back to the
		# park centre on their very first move.
		dup.set("wander_radius", max_radius)

		get_parent().add_child(dup)

		# Set position after entering the tree so global_position is valid.
		dup.global_position = positions[i]


func _gen_positions(rng: RandomNumberGenerator) -> Array[Vector3]:
	# Returns up to visitor_count well-separated spawn points in a ring around the origin.
	var result: Array[Vector3] = []
	var attempts := 0

	while result.size() < visitor_count and attempts < visitor_count * 40:
		attempts += 1

		var angle := rng.randf_range(0.0, TAU)
		var dist  := rng.randf_range(min_radius, max_radius)
		var pos   := Vector3(cos(angle) * dist, VISITOR_Y, sin(angle) * dist)

		# Skip if too close to player start.
		if pos.distance_to(PLAYER_START) < PLAYER_CLEAR:
			continue

		# Skip if too close to another already-chosen spawn point.
		var too_close := false
		for existing: Vector3 in result:
			if pos.distance_to(existing) < MIN_SEP:
				too_close = true
				break

		if not too_close:
			result.append(pos)

	return result
