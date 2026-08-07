extends SceneTree

# Visual QA capture tool for Phase 21.
# Monitors collision_stumble_started signals from all rangers and logs
# each event with collider type, origin, and timestamps to stdout.
# Run alongside a normal game session to verify comedy fires correctly:
#   --path . --script res://tools/capture_collision_comedy.gd
#
# Output lines tagged COLLISION_STUMBLE: are parseable for post-run analysis.

var _event_count: int = 0
var _start_ms: int = 0

func _init() -> void:
	_start_ms = Time.get_ticks_msec()
	call_deferred("_connect_rangers")
	print("capture_collision_comedy: monitoring started")

func _connect_rangers() -> void:
	var rangers := get_nodes_in_group("rangers")
	for ranger in rangers:
		if ranger.has_signal("collision_stumble_started"):
			ranger.collision_stumble_started.connect(
				_on_stumble.bind(ranger)
			)
	print("capture_collision_comedy: connected to %d ranger(s)" % rangers.size())

func _on_stumble(collider_type: StringName, origin: Vector3, ranger: Node) -> void:
	_event_count += 1
	var elapsed := (Time.get_ticks_msec() - _start_ms) / 1000.0
	var stumble_count := int(ranger.get("collision_stumble_count")) if ranger.get("collision_stumble_count") != null else -1
	print(
		"COLLISION_STUMBLE: t=%.2fs  type=%s  origin=(%.2f,%.2f,%.2f)  ranger_total=%d  session_total=%d"
		% [elapsed, collider_type, origin.x, origin.y, origin.z, stumble_count, _event_count]
	)
