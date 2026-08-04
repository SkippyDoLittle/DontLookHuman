class_name ParkReactionDirector
extends RefCounted

## Lightweight dispatcher for visible cause-and-effect across the park.
## Actors own their reactions; this class only tells nearby systems what happened.

const EVENT_GRAB_WINDUP: StringName = &"ranger_grab_windup"
const EVENT_GRAB_MISSED: StringName = &"ranger_grab_missed"
const EVENT_PLAYER_CAUGHT: StringName = &"player_caught"

const REACTION_GROUPS: Array[StringName] = [&"pigeons", &"visitors"]

func broadcast(
	tree: SceneTree,
	event_name: StringName,
	origin: Vector3,
	source: Node = null
) -> Dictionary:
	var reaction_counts := {"pigeons": 0, "visitors": 0}
	if tree == null:
		return reaction_counts

	for group_name in REACTION_GROUPS:
		for actor in tree.get_nodes_in_group(group_name):
			if actor == source or not is_instance_valid(actor):
				continue
			if not actor.has_method("react_to_park_event"):
				continue
			if bool(actor.call("react_to_park_event", event_name, origin)):
				reaction_counts[String(group_name)] += 1

	return reaction_counts
