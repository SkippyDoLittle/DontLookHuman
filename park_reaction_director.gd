class_name ParkReactionDirector
extends RefCounted

## Lightweight dispatcher for visible cause-and-effect across the park.
## Actors own their reactions; this class only tells nearby systems what happened.

const EVENT_GRAB_WINDUP: StringName = &"ranger_grab_windup"
const EVENT_GRAB_MISSED: StringName = &"ranger_grab_missed"
const EVENT_PLAYER_CAUGHT: StringName = &"player_caught"
const EVENT_FOOD_FRENZY: StringName = &"food_frenzy"
const EVENT_SWING_CHAOS: StringName = &"swing_chaos"
const EVENT_WATER_SPLASH: StringName = &"water_splash"
const EVENT_FESTIVAL_FRENZY: StringName = &"festival_frenzy"
const EVENT_SPRINKLER_BURST: StringName = &"sprinkler_burst"
const EVENT_PLAYER_EXPOSED: StringName = &"player_exposed"
const EVENT_VISITOR_STARTLED: StringName = &"visitor_startled"
const EVENT_LOCAL_COMMOTION: StringName = &"local_commotion"

const MAX_CHAIN_DEPTH: int = 3
const MAX_CHAIN_ACTORS: int = 5
const CHAIN_LOCAL_RADIUS: float = 8.0

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

func broadcast_chain(
	tree: SceneTree,
	event_name: StringName,
	origin: Vector3,
	chain_depth: int,
	chain_actor_count: int,
	source: Node = null
) -> int:
	if tree == null or chain_depth >= MAX_CHAIN_DEPTH or chain_actor_count >= MAX_CHAIN_ACTORS:
		return chain_actor_count
	var affected := chain_actor_count
	for group_name in _chain_groups_for(event_name):
		for actor in tree.get_nodes_in_group(group_name):
			if actor == source or not is_instance_valid(actor):
				continue
			if affected >= MAX_CHAIN_ACTORS:
				break
			if not actor is Node3D:
				continue
			if (actor as Node3D).global_position.distance_to(origin) > CHAIN_LOCAL_RADIUS:
				continue
			if not actor.has_method("react_to_chain_event"):
				continue
			if bool(actor.call("react_to_chain_event", event_name, origin, chain_depth, affected)):
				affected += 1
	return affected

func _chain_groups_for(event_name: StringName) -> Array[StringName]:
	match event_name:
		EVENT_VISITOR_STARTLED:
			return [&"rangers"]
		EVENT_LOCAL_COMMOTION:
			return [&"pigeons"]
	return []
