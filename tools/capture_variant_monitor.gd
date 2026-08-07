extends SceneTree

# Visual QA monitor for Phase 23.
# Logs personality capture variants, near-exit flags, and secondary actor reactions
# so you can verify differentiation is firing and readable during playtesting.
#
# Run alongside a normal game session:
#   --path . --script res://tools/capture_variant_monitor.gd
#
# Output lines tagged CAPTURE_VARIANT: are parseable for post-run analysis.

var _event_count: int = 0
var _start_ms: int = 0

func _init() -> void:
	_start_ms = Time.get_ticks_msec()
	call_deferred("_connect_actors")
	print("capture_variant_monitor: monitoring started")

func _connect_actors() -> void:
	var rangers := get_nodes_in_group("rangers")
	for ranger in rangers:
		if ranger.has_signal("capture_variant_started"):
			ranger.capture_variant_started.connect(
				_on_capture_variant_started.bind(ranger)
			)
		if ranger.has_signal("teammate_reaction_started"):
			ranger.teammate_reaction_started.connect(
				_on_teammate_reaction.bind(ranger)
			)
	print("capture_variant_monitor: connected to %d ranger(s)" % rangers.size())

func _on_capture_variant_started(
	personality: String,
	near_exit: bool,
	ranger: Node
) -> void:
	_event_count += 1
	var elapsed := (Time.get_ticks_msec() - _start_ms) / 1000.0
	var pos := (ranger as Node3D).global_position if ranger is Node3D else Vector3.ZERO
	print(
		"CAPTURE_VARIANT: t=%.2fs  personality=%s  near_exit=%s  pos=(%.1f,%.1f,%.1f)  session_total=%d"
		% [elapsed, personality, str(near_exit), pos.x, pos.y, pos.z, _event_count]
	)

func _on_teammate_reaction(callout: String, ranger: Node) -> void:
	var elapsed := (Time.get_ticks_msec() - _start_ms) / 1000.0
	var personality := str(ranger.get("capture_personality")) if ranger.get("capture_personality") != null else "?"
	print(
		"TEAMMATE_REACTION: t=%.2fs  observer_personality=%s  callout=\"%s\""
		% [elapsed, personality, callout]
	)
