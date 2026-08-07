# session_telemetry.gd — Debug-only event frequency tracker for Phase 20 playtesting.
# Counts how often each chaos system fires during ordinary play and reports at session end.
# Does nothing in release builds. Add playtest counters here; do not grow ParkChaosController.

class_name SessionTelemetry
extends Node

const DEAD_ZONE_THRESHOLD: float = 30.0
const OVERLAP_WINDOW: float = 0.5

var grab_attempts: int = 0
var dead_zone_count: int = 0
var overlap_count: int = 0
var collision_stumble_total: int = 0
var visitor_startle_total: int = 0
var capture_near_exit_total: int = 0
var blend_bonus_total: int = 0
var chaos_bonus_total: int = 0

var _active: bool = false
var _level_root: Node
var _dead_zone_timer: float = 0.0
var _session_active: bool = false
var _recent_events: Array = []
var _connected_rangers: Dictionary = {}

func _ready() -> void:
	if not OS.is_debug_build():
		set_process(false)
		return
	_active = true
	add_to_group("session_telemetry")
	_level_root = get_parent()
	call_deferred("_connect_signals")

func _connect_signals() -> void:
	var session := _level_root.get_node_or_null("GameTimer")
	if session != null and session.has_signal("session_state_changed"):
		session.session_state_changed.connect(_on_session_state_changed)
	if session != null:
		if session.has_signal("blend_pickup_earned"):
			session.blend_pickup_earned.connect(
				func(_o: Vector3, _s: float) -> void: blend_bonus_total += 1
			)
		if session.has_signal("chaos_pickup_earned"):
			session.chaos_pickup_earned.connect(
				func(_o: Vector3, _s: float) -> void: chaos_bonus_total += 1
			)

	var chaos := _level_root.get_node_or_null("ParkChaosController")
	if chaos != null:
		if chaos.has_signal("signature_event_started"):
			chaos.signature_event_started.connect(
				func(_n: StringName, _o: Vector3) -> void: _on_notable_event()
			)
		if chaos.has_signal("exposure_cascade_started"):
			chaos.exposure_cascade_started.connect(
				func(_o: Vector3) -> void: _on_notable_event()
			)
		if chaos.has_signal("close_call_cinematic_started"):
			chaos.close_call_cinematic_started.connect(
				func(_d: float, _o: Vector3) -> void: _on_notable_event()
			)
		if chaos.has_signal("flock_sync_started"):
			chaos.flock_sync_started.connect(
				func(_c: int, _o: Vector3) -> void: _on_notable_event()
			)

	for ranger in get_tree().get_nodes_in_group("rangers"):
		_connect_ranger(ranger)
	for visitor in get_tree().get_nodes_in_group("visitors"):
		_connect_visitor(visitor)

func _connect_visitor(visitor: Node) -> void:
	if visitor.has_signal("visitor_startled"):
		visitor.visitor_startled.connect(
			func(_o: Vector3) -> void:
				visitor_startle_total += 1
				_on_notable_event()
		)

func _connect_ranger(ranger: Node) -> void:
	var id := ranger.get_instance_id()
	if _connected_rangers.has(id):
		return
	_connected_rangers[id] = true
	if ranger.has_signal("grab_started"):
		ranger.grab_started.connect(_on_grab_started)
	if ranger.has_signal("grab_missed"):
		ranger.grab_missed.connect(func() -> void: _on_notable_event())
	if ranger.has_signal("player_caught"):
		ranger.player_caught.connect(func() -> void: _on_notable_event())
	if ranger.has_signal("wrong_pigeon_grabbed"):
		ranger.wrong_pigeon_grabbed.connect(func(_p: Node) -> void: _on_notable_event())
	if ranger.has_signal("panic_pigeon_near_miss"):
		ranger.panic_pigeon_near_miss.connect(func(_p: Node) -> void: _on_notable_event())
	if ranger.has_signal("collision_stumble_started"):
		ranger.collision_stumble_started.connect(
			func(_t: StringName, _o: Vector3) -> void:
				collision_stumble_total += 1
				_on_notable_event()
		)
	if ranger.has_signal("capture_variant_started"):
		ranger.capture_variant_started.connect(
			func(_p: String, near_exit: bool) -> void:
				if near_exit:
					capture_near_exit_total += 1
		)

func _process(delta: float) -> void:
	if not _session_active:
		return
	_dead_zone_timer += delta
	if _dead_zone_timer >= DEAD_ZONE_THRESHOLD:
		dead_zone_count += 1
		_dead_zone_timer = 0.0

func _on_session_state_changed(new_state: GameSession.SessionState) -> void:
	_session_active = (new_state == GameSession.SessionState.ACTIVE)
	if new_state == GameSession.SessionState.FINISHED:
		_print_summary()

func _on_grab_started() -> void:
	grab_attempts += 1
	_on_notable_event()

func _on_notable_event() -> void:
	_dead_zone_timer = 0.0
	var now := float(Time.get_ticks_msec())
	var cutoff := now - OVERLAP_WINDOW * 1000.0
	while not _recent_events.is_empty() and float(_recent_events.front()) < cutoff:
		_recent_events.pop_front()
	if not _recent_events.is_empty():
		overlap_count += 1
	_recent_events.append(now)

func _print_summary() -> void:
	var chaos := _level_root.get_node_or_null("ParkChaosController") if _level_root else null
	var grabs_missed := 0
	var grabs_caught := 0
	var wrong_pigeon := 0
	var panic_flyby := 0
	for ranger in get_tree().get_nodes_in_group("rangers"):
		grabs_missed += int(ranger.get("missed_grabs"))
		grabs_caught += int(ranger.get("successful_grabs"))
		wrong_pigeon += int(ranger.get("wrong_pigeon_grab_count"))
		panic_flyby += int(ranger.get("panic_pigeon_reaction_count"))
	print("=== PHASE 20 SESSION TELEMETRY ===")
	print("Grab attempts (wind-ups):  %d" % grab_attempts)
	print("  Missed grabs:            %d" % grabs_missed)
	print("  Successful catches:      %d" % grabs_caught)
	print("  Wrong-pigeon grabs:      %d" % wrong_pigeon)
	print("Cinematic close calls:     %d" % (int(chaos.get("close_call_event_count")) if chaos else 0))
	print("Panic flybys accepted:     %d" % panic_flyby)
	print("Chase collision stumbles:  %d" % collision_stumble_total)
	print("Visitor startles:          %d" % visitor_startle_total)
	print("Near-exit captures:        %d" % capture_near_exit_total)
	print("Blend bonus pickups:       %d" % blend_bonus_total)
	print("Chaos window pickups:      %d" % chaos_bonus_total)
	print("Exposure cascades:         %d" % (int(chaos.get("exposure_event_count")) if chaos else 0))
	print("Flock-sync waves:          %d" % (int(chaos.get("flock_sync_event_count")) if chaos else 0))
	print("Signature events:          %d" % (int(chaos.get("signature_event_count")) if chaos else 0))
	print("Dead zones (>30s quiet):   %d" % dead_zone_count)
	print("Effect overlaps (0.5s):    %d" % overlap_count)
	print("==================================")

func get_overlay_lines() -> Array[String]:
	if not _active or _level_root == null:
		return []
	var chaos := _level_root.get_node_or_null("ParkChaosController")
	var grabs_missed := 0
	var grabs_caught := 0
	var wrong_pigeon := 0
	var panic_flyby := 0
	for ranger in get_tree().get_nodes_in_group("rangers"):
		grabs_missed += int(ranger.get("missed_grabs"))
		grabs_caught += int(ranger.get("successful_grabs"))
		wrong_pigeon += int(ranger.get("wrong_pigeon_grab_count"))
		panic_flyby += int(ranger.get("panic_pigeon_reaction_count"))
	return [
		"— Telemetry —",
		"Grabs: %d att / %d miss / %d catch" % [grab_attempts, grabs_missed, grabs_caught],
		"Wrong bird: %d  Flyby: %d  Stumble: %d  Startle: %d" % [wrong_pigeon, panic_flyby, collision_stumble_total, visitor_startle_total],
		"Close calls: %d  Flock sync: %d" % [
			int(chaos.get("close_call_event_count")) if chaos else 0,
			int(chaos.get("flock_sync_event_count")) if chaos else 0,
		],
		"Exposure: %d  Sig event: %d" % [
			int(chaos.get("exposure_event_count")) if chaos else 0,
			int(chaos.get("signature_event_count")) if chaos else 0,
		],
		"Dead zones: %d  Overlaps: %d" % [dead_zone_count, overlap_count],
		"Near-exit: %d  Blend: %d  Chaos: %d" % [capture_near_exit_total, blend_bonus_total, chaos_bonus_total],
	]
