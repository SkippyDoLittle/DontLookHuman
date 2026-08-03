class_name DebugOverlay
extends PanelContainer

const RANGER_STATE_NAMES: Array[String] = ["PATROL", "INVESTIGATE", "CHASE"]
const SESSION_STATE_NAMES: Array[String] = ["TITLE", "COUNTDOWN", "ACTIVE", "PAUSED", "FINISHED"]

@export_range(0.05, 2.0, 0.05) var update_interval: float = 0.20

@onready var _label: Label = $MarginContainer/DebugText

var _level_root: Node
var _elapsed: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_level_root = get_parent().get_parent()
	visible = false

func _unhandled_input(event: InputEvent) -> void:
	if (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and event.keycode == KEY_F3
	):
		visible = not visible
		if visible:
			refresh_now()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not visible:
		return
	_elapsed += delta
	if _elapsed >= update_interval:
		_elapsed = 0.0
		refresh_now()

func refresh_now() -> void:
	if not is_instance_valid(_level_root):
		return

	var session := _level_root.get_node_or_null("GameTimer") as GameSession
	var player := _level_root.get_node_or_null("Player") as CharacterBody3D
	var level_name := "unknown"
	var session_name := "unknown"
	var total_collectibles: int = 0
	if session != null:
		level_name = String(session.level_id)
		session_name = _enum_name(SESSION_STATE_NAMES, session.state)
		total_collectibles = session.items_total

	var remaining_collectibles := _nodes_in_level_group("collectibles").size()
	var water_status := "yes" if player != null and bool(player.get("in_water")) else "no"
	var lines: Array[String] = [
		"DEBUG — F3 to hide",
		"Level: %s" % level_name,
		"Session: %s" % session_name,
		"Collectibles: %d / %d remaining" % [remaining_collectibles, total_collectibles],
		"Player in water: %s" % water_status,
		"FPS: %d" % Engine.get_frames_per_second(),
		"Rangers:",
	]

	var rangers := _nodes_in_level_group("rangers")
	rangers.sort_custom(func(a: Node, b: Node): return a.name.naturalnocasecmp_to(b.name) < 0)
	if rangers.is_empty():
		lines.append("  none")
	else:
		for ranger in rangers:
			lines.append(
				"  %s: %s  suspicion %.1f"
				% [
					ranger.name,
					_enum_name(RANGER_STATE_NAMES, int(ranger.get("state"))),
					float(ranger.get("suspicion")),
				]
			)
	_label.text = "\n".join(lines)

func _nodes_in_level_group(group_name: StringName) -> Array[Node]:
	var matches: Array[Node] = []
	for node in get_tree().get_nodes_in_group(group_name):
		if node == _level_root or _level_root.is_ancestor_of(node):
			matches.append(node)
	return matches

func _enum_name(names: Array[String], value: int) -> String:
	return names[value] if value >= 0 and value < names.size() else "UNKNOWN"
