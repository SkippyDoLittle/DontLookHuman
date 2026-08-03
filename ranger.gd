# ranger.gd — Scene-facing ranger coordinator.
# Detection, state selection, movement, and presentation are delegated to focused
# components. The exported tuning API remains stable for every existing level.

extends CharacterBody3D

signal suspicion_changed(value: float)
signal state_changed(new_state: int)
signal player_caught
signal observation_changed(reason: String, is_nearby: bool, active_gain: float)

enum RangerState { PATROL, INVESTIGATE, CHASE }

@export var notice_distance: float = 6.5
@export var suspicious_speed: float = 2.0
@export var suspicion_gain_per_second: float = 30.0
@export var suspicion_loss_per_second: float = 22.0
@export var peck_loss_per_second: float = 20.0
@export var patrol_speed: float = 1.1
@export var patrol_radius: float = 9.5
@export var investigate_threshold: float = 65.0
@export var investigate_speed: float = 1.8
@export var chase_threshold: float = 90.0
@export var chase_speed: float = 3.5
@export var approach_stop_distance: float = 1.8
@export var food_aim_threshold: float = 0.9
@export var food_aim_delay: float = 0.8
@export var food_aim_gain_per_second: float = 18.0
@export var stare_threshold: float = 0.85
@export var stare_delay: float = 0.9
@export var stare_gain_per_second: float = 16.0
@export var separation_distance: float = 5.0
@export var separation_gain_per_second: float = 10.0
@export var straight_line_threshold: float = 2.5
@export var straight_line_dot: float = 0.97
@export var straight_line_gain_per_second: float = 10.0
@export var still_threshold: float = 3.5
@export var still_gain_per_second: float = 8.0
@export var is_primary: bool = true

@onready var player: CharacterBody3D = get_node("../Player")
@onready var pigeon_visual: Node3D = get_node("../Player/PigeonVisual")
@onready var _alert_label: Label3D = $AlertLabel
@onready var _sound_manager: Node = get_node("/root/SoundManager")

var suspicion: float = 0.0
var caught: bool = false
var state: int = RangerState.PATROL

var _suspicion_model := RangerSuspicion.new()
var _state_machine := RangerStateMachine.new()
var _movement := RangerMovement.new()
var _presentation := RangerPresentation.new()

func _ready() -> void:
	add_to_group("rangers")
	_suspicion_model.configure(self, player, pigeon_visual, _suspicion_config())
	_movement.configure(self, player, _movement_config())
	_presentation.configure(self, _alert_label, _sound_manager)

func _process(delta: float) -> void:
	if caught:
		_movement.stop()
		return

	var previous_suspicion := suspicion
	var observation := _suspicion_model.update(delta)
	suspicion = _suspicion_model.suspicion
	if not is_equal_approx(suspicion, previous_suspicion):
		suspicion_changed.emit(suspicion)

	if _suspicion_model.caught:
		caught = true
		_movement.stop()
		player_caught.emit()
		return

	var new_state := int(_state_machine.update(
		suspicion,
		investigate_threshold,
		chase_threshold
	))
	if new_state != state:
		state = new_state
		_presentation.state_changed(state)
		state_changed.emit(state)

	_movement.update(delta, state)
	_presentation.update(delta, state)
	observation_changed.emit(
		String(observation.reason),
		bool(observation.is_nearby),
		float(observation.active_gain)
	)

func _physics_process(delta: float) -> void:
	_movement.physics_step(delta)

func choose_new_patrol_direction() -> void:
	_movement.choose_new_patrol_direction()

func _suspicion_config() -> Dictionary:
	return {
		"notice_distance": notice_distance,
		"suspicious_speed": suspicious_speed,
		"suspicion_gain_per_second": suspicion_gain_per_second,
		"suspicion_loss_per_second": suspicion_loss_per_second,
		"peck_loss_per_second": peck_loss_per_second,
		"investigate_threshold": investigate_threshold,
		"chase_threshold": chase_threshold,
		"food_aim_threshold": food_aim_threshold,
		"food_aim_delay": food_aim_delay,
		"food_aim_gain_per_second": food_aim_gain_per_second,
		"stare_threshold": stare_threshold,
		"stare_delay": stare_delay,
		"stare_gain_per_second": stare_gain_per_second,
		"separation_distance": separation_distance,
		"separation_gain_per_second": separation_gain_per_second,
		"straight_line_threshold": straight_line_threshold,
		"straight_line_dot": straight_line_dot,
		"straight_line_gain_per_second": straight_line_gain_per_second,
		"still_threshold": still_threshold,
		"still_gain_per_second": still_gain_per_second,
	}

func _movement_config() -> Dictionary:
	return {
		"patrol_speed": patrol_speed,
		"patrol_radius": patrol_radius,
		"investigate_speed": investigate_speed,
		"chase_speed": chase_speed,
		"approach_stop_distance": approach_stop_distance,
	}
