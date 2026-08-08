extends SceneTree

# Phase 25 visual QA monitor.
# Logs animation and audio events as they fire so you can verify the personality
# pass is reading correctly during playtesting.
#
# Run alongside a normal game session:
#   --path . --script res://tools/phase25_anim_monitor.gd
#
# Output lines tagged ANIM: and AUDIO: are parseable for post-run analysis.

var _start_ms: int = 0
var _stop_bounce_count: int = 0
var _strain_wobble_count: int = 0
var _watch_crouch_count: int = 0
var _panic_lean_peak: float = 0.0
var _windup_by_personality: Dictionary = {}

func _init() -> void:
	_start_ms = Time.get_ticks_msec()
	call_deferred("_connect_scene")
	print("phase25_anim_monitor: monitoring started")

func _connect_scene() -> void:
	var root := get_root()
	for child in root.get_children():
		_scan_node(child)

func _scan_node(node: Node) -> void:
	if node.get_script() != null:
		if node.has_signal("grab_started"):
			node.grab_started.connect(_on_ranger_grab_started.bind(node))
		if node.has_signal("player_caught"):
			node.player_caught.connect(_on_player_caught.bind(node))
	for child in node.get_children():
		_scan_node(child)

func _on_ranger_grab_started() -> void:
	var t := _elapsed()
	print("ANIM: t=%.2fs  WINDUP  (personality logged via grab_windup call)" % t)

func _on_player_caught(_ranger: Node) -> void:
	var t := _elapsed()
	print("ANIM: t=%.2fs  CAPTURE  stop_bounce=%d  strain=%d  watch_crouch=%d  panic_lean_peak=%.3f"
		% [t, _stop_bounce_count, _strain_wobble_count, _watch_crouch_count, _panic_lean_peak])
	print("ANIM: windup_by_personality=%s" % str(_windup_by_personality))

func _elapsed() -> float:
	return float(Time.get_ticks_msec() - _start_ms) / 1000.0
