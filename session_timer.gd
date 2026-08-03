class_name SessionTimer
extends RefCounted

signal time_changed(remaining: float)
signal urgency_tick
signal expired
signal countdown_changed(value: int)
signal countdown_finished

var time_limit: float = 60.0
var time_remaining: float = 60.0
var countdown_active: bool = false

var _tick_timer: float = 0.0
var _expired_emitted: bool = false
var _countdown_value: int = 3
var _countdown_timer: float = 0.0

func reset(limit: float) -> void:
	time_limit = maxf(limit, 0.0)
	time_remaining = time_limit
	_tick_timer = 0.0
	_expired_emitted = false
	countdown_active = false
	time_changed.emit(time_remaining)

func start_countdown(from_value: int = 3) -> void:
	_countdown_value = maxi(from_value, 1)
	_countdown_timer = 0.0
	countdown_active = true
	countdown_changed.emit(_countdown_value)

func advance_countdown(delta: float) -> void:
	if not countdown_active:
		return

	_countdown_timer += delta
	while _countdown_timer >= 1.0 and countdown_active:
		_countdown_timer -= 1.0
		_countdown_value -= 1
		if _countdown_value > 0:
			countdown_changed.emit(_countdown_value)
		else:
			countdown_active = false
			countdown_finished.emit()

func advance(delta: float) -> void:
	if _expired_emitted:
		return

	time_remaining = maxf(time_remaining - delta, 0.0)
	time_changed.emit(time_remaining)

	if time_remaining > 0.0 and time_remaining < 20.0:
		_tick_timer -= delta
		if _tick_timer <= 0.0:
			urgency_tick.emit()
			_tick_timer = 1.0 if time_remaining < 10.0 else 2.0

	if time_remaining <= 0.0:
		_expired_emitted = true
		expired.emit()

func elapsed_time() -> float:
	return time_limit - time_remaining
