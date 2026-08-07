extends SceneTree

# Visual QA monitor for Phase 24.
# Logs blend and chaos bonuses as they fire so you can verify the decision
# system rewards skillful play during playtesting.
#
# Run alongside a normal game session:
#   --path . --script res://tools/capture_objective_decisions.gd
#
# Output lines tagged BONUS: are parseable for post-run analysis.

var _start_ms: int = 0
var _blend_total: int = 0
var _chaos_total: int = 0

func _init() -> void:
	_start_ms = Time.get_ticks_msec()
	call_deferred("_connect_session")
	print("capture_objective_decisions: monitoring started")

func _connect_session() -> void:
	var sessions := get_nodes_in_group("game_sessions")
	if sessions.is_empty():
		# GameTimer is not in a group; find by class name
		var root := get_root()
		for child in root.get_children():
			_scan_for_session(child)
	else:
		for s in sessions:
			_hook_session(s)

func _scan_for_session(node: Node) -> void:
	if node.get_script() != null and node.has_signal("blend_pickup_earned"):
		_hook_session(node)
		return
	for child in node.get_children():
		_scan_for_session(child)

func _hook_session(session: Node) -> void:
	if session.has_signal("blend_pickup_earned"):
		session.blend_pickup_earned.connect(_on_blend_pickup)
	if session.has_signal("chaos_pickup_earned"):
		session.chaos_pickup_earned.connect(_on_chaos_pickup)
	print("capture_objective_decisions: connected to session node '%s'" % session.name)

func _on_blend_pickup(origin: Vector3, bonus_seconds: float) -> void:
	_blend_total += 1
	var elapsed := (Time.get_ticks_msec() - _start_ms) / 1000.0
	print(
		"BONUS: t=%.2fs  BLEND  origin=(%.1f,%.1f,%.1f)  +%.0fs  session_blend_total=%d"
		% [elapsed, origin.x, origin.y, origin.z, bonus_seconds, _blend_total]
	)

func _on_chaos_pickup(origin: Vector3, bonus_seconds: float) -> void:
	_chaos_total += 1
	var elapsed := (Time.get_ticks_msec() - _start_ms) / 1000.0
	print(
		"BONUS: t=%.2fs  CHAOS  origin=(%.1f,%.1f,%.1f)  +%.0fs  session_chaos_total=%d"
		% [elapsed, origin.x, origin.y, origin.z, bonus_seconds, _chaos_total]
	)
