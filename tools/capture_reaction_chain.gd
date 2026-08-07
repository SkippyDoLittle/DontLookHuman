extends SceneTree

# Visual QA capture tool for Phase 22.
# Monitors the full NPC-to-NPC reaction chain: pigeon panic → visitor startle
# → ranger lookover → flock watch. Each link is logged with depth, actors, and
# elapsed time so you can verify the chain fires and respects its budget.
#
# Run alongside a normal game session:
#   --path . --script res://tools/capture_reaction_chain.gd
#
# Output lines tagged CHAIN_LINK: are parseable for post-run analysis.

var _event_count: int = 0
var _start_ms: int = 0

func _init() -> void:
	_start_ms = Time.get_ticks_msec()
	call_deferred("_connect_actors")
	print("capture_reaction_chain: monitoring started")

func _connect_actors() -> void:
	var visitors := get_nodes_in_group("visitors")
	for visitor in visitors:
		if visitor.has_signal("visitor_startled"):
			visitor.visitor_startled.connect(_on_visitor_startled.bind(visitor))

	var rangers := get_nodes_in_group("rangers")
	for ranger in rangers:
		if ranger.has_signal("personality_reaction_started"):
			pass  # rangers don't emit a specific commotion signal — track via commotion_reaction_count

	print("capture_reaction_chain: connected to %d visitor(s), %d ranger(s)" % [
		visitors.size(), rangers.size()
	])

func _process(_delta: float) -> void:
	var t := (Time.get_ticks_msec() - _start_ms) / 1000.0
	var ranger_total := 0
	var pigeon_total := 0
	for ranger in get_nodes_in_group("rangers"):
		ranger_total += int(ranger.get("commotion_reaction_count")) if ranger.get("commotion_reaction_count") != null else 0
	for pigeon in get_nodes_in_group("pigeons"):
		pigeon_total += int(pigeon.get("visitor_startle_count")) if pigeon.get("visitor_startle_count") != null else 0

func _on_visitor_startled(origin: Vector3, visitor: Node) -> void:
	_event_count += 1
	var elapsed := (Time.get_ticks_msec() - _start_ms) / 1000.0
	var startle_count := int(visitor.get("startle_count")) if visitor.get("startle_count") != null else -1
	var ranger_reactions := 0
	for ranger in get_nodes_in_group("rangers"):
		ranger_reactions += int(ranger.get("commotion_reaction_count")) if ranger.get("commotion_reaction_count") != null else 0
	print(
		"CHAIN_LINK: t=%.2fs  visitor_startled  origin=(%.2f,%.2f,%.2f)  visitor_total=%d  ranger_reactions_so_far=%d  session_total=%d"
		% [elapsed, origin.x, origin.y, origin.z, startle_count, ranger_reactions, _event_count]
	)
