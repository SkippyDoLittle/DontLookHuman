class_name RangerStateMachine
extends RefCounted

enum State { PATROL, INVESTIGATE, CHASE }

var state: State = State.PATROL

func update(suspicion: float, investigate_threshold: float, chase_threshold: float) -> State:
	if suspicion >= chase_threshold:
		state = State.CHASE
	elif suspicion >= investigate_threshold:
		state = State.INVESTIGATE
	else:
		state = State.PATROL
	return state
