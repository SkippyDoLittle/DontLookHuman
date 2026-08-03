# pigeon_scatter.gd — Spawns extra blending pigeons inside the playable park.
# Attach to a PigeonScatter Node3D in Main.tscn.
#
# ── PERFORMANCE NOTE ──────────────────────────────────────────────────────────
# Every pigeon is a full CharacterBody3D: _process (AI + peck animation) and
# _physics_process (move_and_slide) run every frame, plus 2 AudioStreamPlayer3D
# nodes each.  The 5 original park pigeons are already doing this.
#
# Recommended cap: keep pigeon_count at or below 25 on a typical PC.
# At 50+ total pigeons you may notice frame-rate cost on lower-end hardware.
# If you want large numbers in the distance, a future optimisation would be a
# lightweight "dumb wander" script (transform-only, no physics, no audio) for
# any pigeon beyond ~40 units — but that requires a second script file.
extends Node3D

# ── Tunable in Inspector ──────────────────────────────────────────────────────

# How many extra pigeons to spawn (on top of the 5 already in the scene).
@export var pigeon_count: int   = 20

# Pigeons won't spawn closer than this to the world origin.
@export var min_radius:   float = 6.0

# Pigeons stay inside the playable park walls so they can provide real blending cover.
@export var max_radius:   float = 14.0

# Change this number to get a completely different layout.
@export var rng_seed:     int   = 31

# ── Constants ─────────────────────────────────────────────────────────────────

# Clear bubble around the level's actual player spawn.
const PLAYER_CLEAR: float   = 4.5

# Minimum gap between any two spawn points so pigeons don't pile up.
const MIN_SEP: float = 4.0

# Spawn height — CharacterBody3D centre sits at y=1 in the original scene nodes.
const PIGEON_Y: float = 1.0


func _ready() -> void:
	# Defer so all sibling _ready() calls complete before we start duplicating.
	call_deferred("_spawn")


func _spawn() -> void:
	var template := get_node_or_null("../NPC_Animal")
	if template == null:
		push_warning("PigeonScatter: NPC_Animal template not found — no pigeons spawned")
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed

	var player := get_node_or_null("../Player") as Node3D
	var player_start := player.global_position if player != null else Vector3.ZERO
	var occupied: Array[Vector3] = []
	for pigeon in get_tree().get_nodes_in_group("pigeons"):
		if pigeon is Node3D:
			occupied.append(pigeon.global_position)
	var positions := _gen_positions(rng, player_start, occupied)

	for i in positions.size():
		var dup := template.duplicate()
		dup.name = "Pigeon_s%d" % i

		# Set wander_radius BEFORE add_child so _ready() uses this level's playable radius.
		dup.set("wander_radius", max_radius)

		get_parent().add_child(dup)

		# Set position after entering the tree so global_position is valid.
		dup.global_position = positions[i]


func _gen_positions(
	rng: RandomNumberGenerator,
	player_start: Vector3,
	occupied: Array[Vector3]
) -> Array[Vector3]:
	# Returns up to pigeon_count well-separated spawn points inside an annular ring.
	var result: Array[Vector3] = []
	var attempts := 0

	while result.size() < pigeon_count and attempts < pigeon_count * 40:
		attempts += 1

		var angle := rng.randf_range(0.0, TAU)
		var dist  := rng.randf_range(min_radius, max_radius)
		var pos   := Vector3(cos(angle) * dist, PIGEON_Y, sin(angle) * dist)

		# Skip if too close to player start.
		if Vector2(pos.x, pos.z).distance_to(Vector2(player_start.x, player_start.z)) < PLAYER_CLEAR:
			continue

		# Skip if too close to another already-chosen spawn point.
		var too_close := false
		for existing: Vector3 in occupied + result:
			if pos.distance_to(existing) < MIN_SEP:
				too_close = true
				break

		if not too_close:
			result.append(pos)

	return result
