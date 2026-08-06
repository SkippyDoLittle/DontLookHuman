class_name ParkChaosController
extends Node

## Turns familiar level props into one authored, player-triggered surprise per park.
## Events are deterministic, strongly telegraphed, and only fire once per run.

const PARK_REACTIONS = preload("res://park_reaction_director.gd")

signal signature_event_started(event_name: StringName, origin: Vector3)
signal exposure_cascade_started(origin: Vector3)

var signature_event_count: int = 0
var last_event_name: StringName = &""
var last_reaction_counts: Dictionary = {}
var affected_rangers: int = 0
var exposure_event_count: int = 0
var exposure_reaction_counts: Dictionary = {}

var _level: BaseLevel
var _level_id: StringName = &""
var _initial_collectible_count: int = 0
var _collected_count: int = 0
var _signature_triggered: bool = false
var _reaction_director := PARK_REACTIONS.new()
var _banner: Label
var _sprinkler_rig: Node3D
var _sprinkler_lifetime: float = 0.0
var _sprinkler_pulse_timer: float = 0.0
var _exposure_latched: bool = false
var _exposure_cooldown: float = 0.0

func _ready() -> void:
	add_to_group("chaos_controllers")
	call_deferred("_initialize")

func _initialize() -> void:
	_level = get_parent() as BaseLevel
	if _level == null or _level.level_config == null:
		return
	_level_id = _level.level_config.level_id
	var collectibles := get_tree().get_nodes_in_group("collectibles")
	_initial_collectible_count = collectibles.size()
	for food in collectibles:
		if food.has_signal("food_collected") and not food.is_connected(
			"food_collected",
			_on_food_collected
		):
			food.connect("food_collected", _on_food_collected)
	for area in _level.find_children("*", "Area3D", true, false):
		if area.has_signal("player_splashed") and not area.is_connected(
			"player_splashed",
			_on_player_splashed
		):
			area.connect("player_splashed", _on_player_splashed)
	for ranger in get_tree().get_nodes_in_group("rangers"):
		if ranger.has_signal("state_changed"):
			var state_callback := _on_ranger_state_changed.bind(ranger)
			if not ranger.is_connected("state_changed", state_callback):
				ranger.connect("state_changed", state_callback)
		if ranger.has_signal("suspicion_changed"):
			var suspicion_callback := _on_ranger_suspicion_changed.bind(ranger)
			if not ranger.is_connected("suspicion_changed", suspicion_callback):
				ranger.connect("suspicion_changed", suspicion_callback)
	_create_banner()

func _process(delta: float) -> void:
	_exposure_cooldown = maxf(_exposure_cooldown - delta, 0.0)
	if _sprinkler_lifetime <= 0.0 or not is_instance_valid(_sprinkler_rig):
		return
	_sprinkler_lifetime = maxf(_sprinkler_lifetime - delta, 0.0)
	_sprinkler_pulse_timer = maxf(_sprinkler_pulse_timer - delta, 0.0)
	_sprinkler_rig.rotation.y += delta * 1.8
	if _sprinkler_pulse_timer <= 0.0:
		_sprinkler_pulse_timer = 1.15
		var origin := _sprinkler_rig.global_position
		last_reaction_counts = _reaction_director.broadcast(
			get_tree(),
			PARK_REACTIONS.EVENT_SPRINKLER_BURST,
			origin,
			self
		)
		_affect_rangers(origin, 9.5, 0.65, 7.0, 2.8, "SPRINKLERS?!")
	if _sprinkler_lifetime <= 0.0:
		var fade := create_tween()
		fade.tween_property(_sprinkler_rig, "scale", Vector3.ZERO, 0.3)
		fade.tween_callback(_sprinkler_rig.queue_free)

func _on_ranger_state_changed(new_state: int, _ranger: Node) -> void:
	if new_state != RangerStateMachine.State.CHASE:
		return
	if _exposure_latched or _exposure_cooldown > 0.0:
		return
	_trigger_exposure_cascade()

func _on_ranger_suspicion_changed(_value: float, _ranger: Node) -> void:
	if not _exposure_latched:
		return
	var maximum := 0.0
	for ranger in get_tree().get_nodes_in_group("rangers"):
		maximum = maxf(maximum, float(ranger.get("suspicion")))
	if maximum < 55.0:
		_exposure_latched = false

func _trigger_exposure_cascade() -> void:
	var player := _level.get_node_or_null("Player") as Node3D
	if player == null:
		return
	var origin := player.global_position
	_exposure_latched = true
	_exposure_cooldown = 4.5
	exposure_event_count += 1
	exposure_reaction_counts = _reaction_director.broadcast(
		get_tree(),
		PARK_REACTIONS.EVENT_PLAYER_EXPOSED,
		origin,
		self
	)
	_play_sound("play_exposed_sting")
	_play_sound("play_flock_panic")
	if player.has_method("add_camera_trauma"):
		player.call("add_camera_trauma", 0.17, 0.44)
	var hud := _level.get_node_or_null("HUD")
	if hud != null and hud.has_method("trigger_exposure_feedback"):
		hud.call("trigger_exposure_feedback")
	_spawn_world_burst(origin + Vector3.UP * 0.15, Color(1.0, 0.12, 0.04, 0.9), 24, 5.0)
	exposure_cascade_started.emit(origin)

func _on_food_collected(food: Node3D, origin: Vector3) -> void:
	_collected_count += 1
	match _level_id:
		&"level_01":
			_trigger_food_frenzy(origin, false)
		&"level_02":
			if food.name == &"PicnicFood2":
				_trigger_swing_chaos()
		&"level_04":
			if food.name == &"PicnicFood4":
				_trigger_food_frenzy(origin, true)
		&"level_05":
			if _collected_count >= _initial_collectible_count:
				_trigger_sprinkler_finale()

func _on_player_splashed(origin: Vector3) -> void:
	if _level_id != &"level_03" or _signature_triggered:
		return
	_register_event(PARK_REACTIONS.EVENT_WATER_SPLASH, origin)
	_show_banner("SPLASH!", Color(0.35, 0.85, 1.0, 1.0))
	_play_sound("play_water_splash")
	_play_sound("play_flock_panic")
	_spawn_world_burst(origin + Vector3.UP * 0.12, Color(0.35, 0.8, 1.0, 0.9), 30, 4.7)
	_affect_rangers(origin, 13.0, 0.75, 0.0, 2.4, "SPLASH?!")

func _trigger_food_frenzy(origin: Vector3, festival: bool) -> void:
	if _signature_triggered:
		return
	var event_name := (
		PARK_REACTIONS.EVENT_FESTIVAL_FRENZY
		if festival
		else PARK_REACTIONS.EVENT_FOOD_FRENZY
	)
	_register_event(event_name, origin)
	_show_banner(
		"POPCORN PANIC!" if festival else "FEEDING FRENZY!",
		Color(1.0, 0.78, 0.18, 1.0)
	)
	_play_sound("play_food_frenzy")
	_play_sound("play_flock_panic")
	_spawn_world_burst(origin + Vector3.UP * 0.16, Color(1.0, 0.72, 0.18, 1.0), 26 if festival else 18, 4.2)
	_affect_rangers(
		origin,
		16.0 if festival else 9.0,
		1.15 if festival else 0.85,
		18.0 if festival else 10.0,
		0.0,
		"THE BIRDS!" if festival else "HEY!"
	)

func _trigger_swing_chaos() -> void:
	if _signature_triggered:
		return
	var swing_bar := _level.find_child("SwingBar", true, false) as Node3D
	var origin := swing_bar.global_position if swing_bar != null else Vector3(0.0, 1.0, -7.0)
	_register_event(PARK_REACTIONS.EVENT_SWING_CHAOS, origin)
	_show_banner("SWING OUT!", Color(1.0, 0.42, 0.18, 1.0))
	_play_sound("play_swing_chaos")
	_play_sound("play_flock_panic")
	_animate_swings()
	_spawn_world_burst(origin, Color(1.0, 0.45, 0.15, 0.9), 14, 3.4)
	_affect_rangers(origin, 7.0, 0.8, 6.0, 4.2, "WHOA!")

func _trigger_sprinkler_finale() -> void:
	if _signature_triggered:
		return
	var fountain := _level.find_child("Fountain", true, false) as Node3D
	var origin := fountain.global_position + Vector3.UP * 1.3 if fountain != null else Vector3.UP
	_register_event(PARK_REACTIONS.EVENT_SPRINKLER_BURST, origin)
	_show_banner("SPRINKLERS!", Color(0.3, 0.9, 1.0, 1.0))
	_play_sound("play_sprinkler_burst")
	_play_sound("play_flock_panic")
	_spawn_world_burst(origin, Color(0.25, 0.78, 1.0, 0.82), 42, 5.5)
	_create_sprinkler_rig(origin)
	_affect_rangers(origin, 10.0, 1.0, 12.0, 3.3, "SPRINKLERS?!")

func _register_event(event_name: StringName, origin: Vector3) -> void:
	_signature_triggered = true
	signature_event_count += 1
	last_event_name = event_name
	last_reaction_counts = _reaction_director.broadcast(
		get_tree(),
		event_name,
		origin,
		self
	)
	signature_event_started.emit(event_name, origin)

func _play_sound(method_name: StringName) -> void:
	var sound_manager := get_node_or_null("/root/SoundManager")
	if sound_manager != null and sound_manager.has_method(method_name):
		sound_manager.call(method_name)

func _affect_rangers(
	origin: Vector3,
	radius: float,
	duration: float,
	suspicion_drop: float,
	stumble_radius: float,
	callout: String
) -> void:
	for candidate in get_tree().get_nodes_in_group("rangers"):
		if not candidate is Node3D:
			continue
		var ranger := candidate as Node3D
		var distance := ranger.global_position.distance_to(origin)
		if distance > radius:
			continue
		var reacted := false
		if stumble_radius > 0.0 and distance <= stumble_radius and ranger.has_method("stumble_from_environment"):
			reacted = bool(ranger.call("stumble_from_environment", origin, callout))
		elif ranger.has_method("apply_chaos_distraction"):
			reacted = bool(ranger.call(
				"apply_chaos_distraction",
				origin,
				duration,
				suspicion_drop,
				callout
			))
		if reacted:
			affected_rangers += 1

func _animate_swings() -> void:
	for node_name in [&"SwingChainL", &"SwingSeatL", &"SwingChainR", &"SwingSeatR"]:
		var swing_part := _level.find_child(node_name, true, false) as Node3D
		if swing_part == null:
			continue
		var start_rotation := swing_part.rotation.x
		var swing := swing_part.create_tween().set_loops(4)
		swing.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		swing.tween_property(swing_part, "rotation:x", start_rotation + 0.65, 0.28)
		swing.tween_property(swing_part, "rotation:x", start_rotation - 0.65, 0.56)
		swing.tween_property(swing_part, "rotation:x", start_rotation, 0.28)

func _create_sprinkler_rig(origin: Vector3) -> void:
	_sprinkler_rig = Node3D.new()
	_sprinkler_rig.name = "SprinklerChaosRig"
	_level.add_child(_sprinkler_rig)
	_sprinkler_rig.global_position = origin
	for index in 6:
		var arm := Node3D.new()
		arm.rotation.y = float(index) / 6.0 * TAU
		_sprinkler_rig.add_child(arm)
		var stream := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.018
		mesh.bottom_radius = 0.035
		mesh.height = 4.2
		mesh.radial_segments = 6
		mesh.rings = 1
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.25, 0.78, 1.0, 0.34)
		material.emission_enabled = true
		material.emission = Color(0.12, 0.58, 1.0, 1.0)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.material = material
		stream.mesh = mesh
		stream.rotation.z = PI * 0.5
		stream.position.x = 2.0
		arm.add_child(stream)
		var spray := CPUParticles3D.new()
		spray.amount = 26
		spray.lifetime = 0.95
		spray.local_coords = false
		spray.direction = Vector3(1.0, 0.42, 0.0)
		spray.spread = 7.0
		spray.gravity = Vector3(0.0, -4.5, 0.0)
		spray.initial_velocity_min = 3.4
		spray.initial_velocity_max = 4.8
		spray.scale_amount_min = 0.7
		spray.scale_amount_max = 1.25
		var droplet_mesh := SphereMesh.new()
		droplet_mesh.radius = 0.035
		droplet_mesh.height = 0.07
		droplet_mesh.radial_segments = 4
		droplet_mesh.rings = 2
		var droplet_material := StandardMaterial3D.new()
		droplet_material.albedo_color = Color(0.45, 0.88, 1.0, 0.86)
		droplet_material.emission_enabled = true
		droplet_material.emission = Color(0.15, 0.58, 1.0, 1.0)
		droplet_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		droplet_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		droplet_mesh.material = droplet_material
		spray.mesh = droplet_mesh
		arm.add_child(spray)
		spray.emitting = true
	_sprinkler_rig.scale = Vector3.ZERO
	create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(
		_sprinkler_rig,
		"scale",
		Vector3.ONE,
		0.35
	)
	_sprinkler_lifetime = 6.5
	_sprinkler_pulse_timer = 1.15

func _spawn_world_burst(
	origin: Vector3,
	color: Color,
	amount: int,
	speed: float
) -> void:
	var burst := CPUParticles3D.new()
	burst.name = "ChaosBurst"
	burst.amount = amount
	burst.lifetime = 0.9
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.direction = Vector3.UP
	burst.spread = 165.0
	burst.gravity = Vector3(0.0, -4.8, 0.0)
	burst.initial_velocity_min = speed * 0.55
	burst.initial_velocity_max = speed
	burst.color = color
	var mesh := SphereMesh.new()
	mesh.radius = 0.045
	mesh.height = 0.09
	mesh.radial_segments = 4
	mesh.rings = 2
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.WHITE
	material.vertex_color_use_as_albedo = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	burst.mesh = mesh
	_level.add_child(burst)
	burst.global_position = origin
	burst.emitting = true
	get_tree().create_timer(1.2).timeout.connect(burst.queue_free)

func _create_banner() -> void:
	var hud := _level.get_node_or_null("HUD")
	if hud == null:
		return
	_banner = Label.new()
	_banner.name = "ChaosEventLabel"
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.position = Vector2(-250.0, 128.0)
	_banner.size = Vector2(500.0, 64.0)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 34)
	_banner.add_theme_color_override("font_shadow_color", Color(0.02, 0.04, 0.05, 0.95))
	_banner.add_theme_constant_override("shadow_offset_x", 4)
	_banner.add_theme_constant_override("shadow_offset_y", 4)
	_banner.visible = false
	_banner.pivot_offset = _banner.size * 0.5
	hud.add_child(_banner)

func _show_banner(text: String, color: Color) -> void:
	if not is_instance_valid(_banner):
		return
	_banner.text = text
	_banner.modulate = Color(color.r, color.g, color.b, 0.0)
	_banner.scale = Vector2(0.45, 0.45)
	_banner.visible = true
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_banner, "scale", Vector2.ONE, 0.2)
	tween.parallel().tween_property(_banner, "modulate:a", 1.0, 0.12)
	tween.tween_interval(1.15)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(_banner, "position:y", 105.0, 0.28)
	tween.parallel().tween_property(_banner, "modulate:a", 0.0, 0.28)
	tween.tween_callback(_banner.hide)
