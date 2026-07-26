# ranger.gd — Attached to the Ranger node in Main.tscn
# AI enemy with three states (PATROL → INVESTIGATE → CHASE) driven by a suspicion meter.
# Six player behaviours raise suspicion; pecking and blending in lower it.

extends CharacterBody3D

enum RangerState { PATROL, INVESTIGATE, CHASE }

# ── Inspector tuning values ──────────────────────────────────────────────────────
@export var notice_distance:         float = 6.5    # base detection radius
@export var suspicious_speed:        float = 2.0    # player speed above this = "sprinting"
@export var suspicion_gain_per_second: float = 30.0  # gain/s from sprinting nearby
@export var suspicion_loss_per_second: float = 22.0  # loss/s when nothing suspicious
@export var peck_loss_per_second:    float = 20.0    # bonus loss/s while player is pecking
@export var patrol_speed:            float = 1.1
@export var patrol_radius:           float = 9.5
@export var investigate_threshold:   float = 65.0   # suspicion level that triggers INVESTIGATE
@export var investigate_speed:       float = 1.8
@export var chase_threshold:         float = 90.0   # suspicion level that triggers CHASE
@export var chase_speed:             float = 3.5
@export var approach_stop_distance:  float = 1.8    # ranger stops this close to the player
@export var food_aim_threshold:      float = 0.9    # dot product — ~26° cone toward food
@export var food_aim_delay:          float = 0.5    # seconds of aiming before suspicion rises
@export var food_aim_gain_per_second: float = 25.0
@export var stare_threshold:         float = 0.85   # dot product — ~32° cone toward ranger
@export var stare_delay:             float = 0.6    # seconds staring before suspicion rises
@export var stare_gain_per_second:   float = 20.0
@export var separation_distance:     float = 4.0    # NPC must be within this to count as "blending in"
@export var separation_gain_per_second: float = 15.0
@export var straight_line_threshold: float = 2.5    # seconds of straight walking before suspicion rises
@export var straight_line_dot:       float = 0.97   # ~14° — tighter than this = "too straight"
@export var straight_line_gain_per_second: float = 10.0
@export var still_threshold:           float = 3.5    # seconds motionless before suspicion rises
@export var still_gain_per_second:     float = 8.0

# ── Node references ──────────────────────────────────────────────────────────────
@onready var player:        CharacterBody3D = get_node("../Player")
@onready var status_label:  Label           = get_node("../HUD/RangerStatus")
@onready var suspicion_bar: ProgressBar     = get_node("../HUD/SuspicionBar")
@onready var pigeon_visual: Node3D          = get_node("../Player/PigeonVisual")
@onready var _vignette_mat: ShaderMaterial  = get_node("../HUD/VignetteRect").material
@onready var _warn_label:   Label           = get_node("../HUD/WarnLabel")
@onready var _alert_label:  Label3D         = get_node("AlertLabel")   # floating "!" above ranger head

# ── Runtime state ────────────────────────────────────────────────────────────────
var suspicion:     float       = 0.0
var caught:        bool        = false
var state:         RangerState = RangerState.PATROL
var _prev_state:   RangerState = RangerState.PATROL
var _pulse_time:   float       = 0.0
var _warn_timer:   float       = 0.0
var _desired_move: Vector3     = Vector3.ZERO   # set by AI, applied by _physics_process
var _prev_suspicion: float     = 0.0

var _alert_tween: Tween

var patrol_direction: Vector3 = Vector3.FORWARD
var time_until_turn:  float   = 0.0
var stare_time:       float   = 0.0
var food_aim_time:    float   = 0.0
var _straight_time:   float   = 0.0
var _last_move_dir:   Vector2  = Vector2.ZERO   # player's movement direction last frame
var _still_time:      float   = 0.0

var npc_animals: Array = []

func _ready() -> void:
	choose_new_patrol_direction()
	_alert_label.visible = false

	for npc_name in ["NPC_Animal", "NPC_Animal2", "NPC_Animal3", "NPC_Animal4", "NPC_Animal5"]:
		var npc := get_node_or_null("../" + npc_name)
		if npc:
			npc_animals.append(npc)

func _process(delta: float) -> void:
	_desired_move = Vector3.ZERO

	# ── CAUGHT STATE ─────────────────────────────────────────────────────────────
	if caught:
		suspicion_bar.value = 100.0
		status_label.text   = "CAUGHT!"
		return

	# ── DISTANCE & SPEED ─────────────────────────────────────────────────────────
	var distance_to_player: float = global_position.distance_to(player.global_position)
	var player_speed: float = Vector2(player.velocity.x, player.velocity.z).length()

	# ── EFFECTIVE NOTICE RANGE ───────────────────────────────────────────────────
	# The ranger's awareness radius expands when already alert.
	var effective_notice: float
	if suspicion >= chase_threshold:
		effective_notice = 20.0
	elif suspicion >= investigate_threshold:
		effective_notice = notice_distance * 2.0
	else:
		effective_notice = notice_distance

	var is_nearby: bool = distance_to_player <= effective_notice

	# ── SUSPICION GAIN ───────────────────────────────────────────────────────────
	# Accumulate gain from all suspicious behaviours this frame.
	var active_gain: float = 0.0
	var reason: String     = ""

	# 1. Sprinting nearby
	if is_nearby and player_speed > suspicious_speed:
		active_gain += suspicion_gain_per_second
		reason = "Too fast!"

	# 2. Moving directly toward food (dot product against nearest food direction)
	if is_nearby and _is_aiming_at_food(player_speed):
		food_aim_time += delta
		if food_aim_time >= food_aim_delay:
			active_gain += food_aim_gain_per_second
			if reason == "": reason = "Moving suspiciously"
	else:
		food_aim_time = maxf(food_aim_time - delta * 2.0, 0.0)

	# 3. Staring at the ranger while moving (only while moving — stationary facing is unreliable)
	if is_nearby and player_speed > 0.1 and _is_facing_ranger():
		stare_time += delta
		if stare_time >= stare_delay:
			active_gain += stare_gain_per_second
			if reason == "": reason = "Staring..."
	else:
		stare_time = maxf(stare_time - delta * 2.0, 0.0)

	# 4. Isolated from the NPC flock
	if is_nearby and _is_isolated():
		active_gain += separation_gain_per_second
		if reason == "": reason = "Acting alone"

	# 5. Wading in the pond
	if is_nearby and player.get("in_water"):
		active_gain += 12.0
		if reason == "": reason = "In the water!"

	# 6. Walking in a straight line
	# Real pigeons constantly veer and bob — sustained straight walking looks controlled.
	# Compare movement direction frame-to-frame using dot product; accumulate time when
	# the angle barely changes (dot >= straight_line_dot ≈ within 14° per frame).
	if is_nearby and player_speed > 0.3:
		var cur_dir := Vector2(player.velocity.x, player.velocity.z).normalized()
		if _last_move_dir.length() > 0.5:
			var dot := cur_dir.dot(_last_move_dir)
			if dot >= straight_line_dot:
				_straight_time += delta
				if _straight_time >= straight_line_threshold:
					active_gain += straight_line_gain_per_second
					if reason == "": reason = "Moving too straight"
			else:
				_straight_time = maxf(_straight_time - delta * 2.0, 0.0)
		_last_move_dir = cur_dir
	else:
		_straight_time = maxf(_straight_time - delta * 3.0, 0.0)
		if player_speed <= 0.1:
			_last_move_dir = Vector2.ZERO   # reset so the next movement starts fresh

	# 7. Standing completely still
	# Real pigeons constantly shift weight and bob — sustained motionlessness looks deliberate.
	# Exempt while pecking: that's visibly natural behaviour and already reduces suspicion.
	if is_nearby and player_speed < 0.1 and not player.get("is_pecking"):
		_still_time += delta
		if _still_time >= still_threshold:
			active_gain += still_gain_per_second
			if reason == "": reason = "Standing still"
	else:
		_still_time = maxf(_still_time - delta * 1.5, 0.0)

	# ── UPDATE SUSPICION ─────────────────────────────────────────────────────────
	if active_gain > 0.0:
		suspicion = minf(suspicion + active_gain * delta, 100.0)
	else:
		var loss_rate := suspicion_loss_per_second
		if player.get("is_pecking"):
			loss_rate += peck_loss_per_second
		suspicion = maxf(suspicion - loss_rate * delta, 0.0)

	# ── UI UPDATE ────────────────────────────────────────────────────────────────
	suspicion_bar.value = suspicion
	_vignette_mat.set_shader_parameter("intensity", suspicion / 100.0 * 0.65)

	# ── CAUGHT CHECK ─────────────────────────────────────────────────────────────
	if suspicion >= 100.0:
		caught = true
		return

	# ── STATE MACHINE ────────────────────────────────────────────────────────────
	if suspicion >= chase_threshold:
		state = RangerState.CHASE
	elif suspicion >= investigate_threshold:
		state = RangerState.INVESTIGATE
	else:
		state = RangerState.PATROL

	if state != _prev_state:
		if state == RangerState.INVESTIGATE or state == RangerState.CHASE:
			SoundManager.play_alert()

		if _alert_tween:
			_alert_tween.kill()

		match state:
			RangerState.PATROL:
				_alert_label.visible = false
				_alert_label.text    = ""

			RangerState.INVESTIGATE:
				_alert_label.text     = "!"
				_alert_label.modulate = Color(1.0, 0.85, 0.1, 1.0)
				_alert_label.scale    = Vector3.ZERO
				_alert_label.visible  = true
				_alert_tween = create_tween()
				_alert_tween.tween_property(_alert_label, "scale", Vector3(1.3, 1.3, 1.3), 0.10)
				_alert_tween.tween_property(_alert_label, "scale", Vector3(1.0, 1.0, 1.0), 0.12)

			RangerState.CHASE:
				_alert_label.text     = "!!"
				_alert_label.modulate = Color(1.0, 0.2, 0.2, 1.0)
				_alert_label.scale    = Vector3.ZERO
				_alert_label.visible  = true
				_alert_tween = create_tween()
				_alert_tween.tween_property(_alert_label, "scale", Vector3(1.6, 1.6, 1.6), 0.08)
				_alert_tween.tween_property(_alert_label, "scale", Vector3(1.0, 1.0, 1.0), 0.14)

		_prev_state = state

	# ── MOVEMENT ─────────────────────────────────────────────────────────────────
	match state:
		RangerState.PATROL:     _do_patrol(delta)
		RangerState.INVESTIGATE: _move_toward_player(delta, investigate_speed)
		RangerState.CHASE:      _move_toward_player(delta, chase_speed)

	# ── SUSPICION BAR COLOR PULSE ─────────────────────────────────────────────────
	match state:
		RangerState.PATROL:
			_pulse_time = 0.0
			suspicion_bar.modulate = Color.WHITE

		RangerState.INVESTIGATE:
			_pulse_time += delta
			var p: float = sin(_pulse_time * TAU * 2.5) * 0.5 + 0.5
			suspicion_bar.modulate = Color(1.0, lerp(0.35, 0.75, p), p * 0.1)
			_alert_label.modulate  = Color(1.0, 0.85, 0.1, lerp(0.6, 1.0, p))

		RangerState.CHASE:
			_pulse_time += delta
			var p: float = sin(_pulse_time * TAU * 6.0) * 0.5 + 0.5
			suspicion_bar.modulate = Color(1.0, lerp(0.0, 0.3, p), 0.0)
			_alert_label.modulate  = Color(1.0, 0.2, 0.2, lerp(0.5, 1.0, p))

	# ── THRESHOLD WARNING LABELS ──────────────────────────────────────────────────
	# Detect threshold crossings by comparing this frame to last frame.
	if suspicion >= chase_threshold and _prev_suspicion < chase_threshold:
		_warn_label.text     = "DANGER!"
		_warn_label.modulate = Color(1.0, 0.15, 0.15, 1.0)
		_warn_label.visible  = true
		_warn_timer          = 1.8
	elif suspicion >= investigate_threshold and _prev_suspicion < investigate_threshold:
		_warn_label.text     = "!"
		_warn_label.modulate = Color(1.0, 0.8, 0.1, 1.0)
		_warn_label.visible  = true
		_warn_timer          = 1.5

	if _warn_timer > 0.0:
		_warn_timer -= delta
		# Fade out during the last 0.5 seconds.
		_warn_label.modulate.a = clampf(_warn_timer / 0.5, 0.0, 1.0)
		if _warn_timer <= 0.0:
			_warn_label.visible = false

	_prev_suspicion = suspicion

	# ── STATUS LABEL ─────────────────────────────────────────────────────────────
	match state:
		RangerState.CHASE:
			status_label.text = "Ranger: Alert!"
		RangerState.INVESTIGATE:
			if active_gain > 0.0:
				status_label.text = "Ranger: Suspicious — %s" % reason
			else:
				status_label.text = "Ranger: Investigating..."
		RangerState.PATROL:
			if active_gain > 0.0:
				status_label.text = "Ranger: Suspicious — %s" % reason
			elif is_nearby:
				status_label.text = "Ranger: Watching"
			else:
				status_label.text = "Ranger: Calm"

func _move_toward_player(_delta: float, spd: float) -> void:
	var to_player := player.global_position - global_position
	to_player.y = 0.0
	if to_player.length() < 0.1:
		return
	var look_target := Vector3(player.global_position.x, global_position.y, player.global_position.z)
	look_at(look_target, Vector3.UP)
	if to_player.length() > approach_stop_distance:
		_desired_move = to_player.normalized() * spd

func _get_nearest_food() -> Node3D:
	var nearest: Node3D  = null
	var nearest_dist: float = INF
	for item in get_tree().get_nodes_in_group("collectibles"):
		var food_node := item as Node3D
		if food_node == null:
			continue
		var d: float = player.global_position.distance_to(food_node.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest      = food_node
	return nearest

func _is_aiming_at_food(player_speed: float) -> bool:
	if player_speed < 0.3:
		return false
	var food_item: Node3D = _get_nearest_food()
	if food_item == null:
		return false
	var to_food := food_item.global_position - player.global_position
	to_food.y = 0.0
	if to_food.length() < 0.5:
		return false   # already on top of it — don't penalise
	var move_dir := Vector2(player.velocity.x, player.velocity.z).normalized()
	var food_dir := Vector2(to_food.x, to_food.z).normalized()
	# dot product of two unit vectors = cos(angle). >= 0.9 means within ~26°.
	return move_dir.dot(food_dir) >= food_aim_threshold

func _is_facing_ranger() -> bool:
	var to_ranger := global_position - player.global_position
	to_ranger.y = 0.0
	if to_ranger.length() < 0.5:
		return false
	# pigeon_visual.basis.z = the direction the pigeon is facing in world space.
	var forward := pigeon_visual.global_transform.basis.z
	forward.y = 0.0
	return forward.normalized().dot(to_ranger.normalized()) >= stare_threshold

func _is_isolated() -> bool:
	for npc in npc_animals:
		if is_instance_valid(npc) and player.global_position.distance_to(npc.global_position) <= separation_distance:
			return false   # at least one NPC is close enough — not isolated
	return true

func _do_patrol(delta: float) -> void:
	time_until_turn -= delta

	var is_outside_bounds: bool = (absf(position.x) > patrol_radius or absf(position.z) > patrol_radius)

	if is_outside_bounds:
		patrol_direction = Vector3(-position.x, 0.0, -position.z).normalized()
		time_until_turn  = 1.0
	elif time_until_turn <= 0.0:
		choose_new_patrol_direction()

	if patrol_direction.length() > 0.001:
		look_at(global_position + patrol_direction, Vector3.UP)

	_desired_move = patrol_direction * patrol_speed

func choose_new_patrol_direction() -> void:
	var angle: float = randf_range(0.0, TAU)
	patrol_direction = Vector3(sin(angle), 0.0, cos(angle))
	time_until_turn  = randf_range(2.0, 4.0)

func _physics_process(delta: float) -> void:
	velocity.x = _desired_move.x
	velocity.z = _desired_move.z
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	else:
		velocity.y = 0.0
	move_and_slide()
