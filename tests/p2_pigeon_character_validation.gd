extends SceneTree

# P2.1 character-only regression checks.
# Run headless: --headless --path . --script res://tests/p2_pigeon_character_validation.gd

var _failures: int = 0

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	Engine.time_scale = 1.0
	var level := (
		load("res://scenes/levels/Level01_Park.tscn") as PackedScene
	).instantiate() as BaseLevel
	root.add_child(level)
	await process_frame
	await process_frame
	paused = false

	var player := level.get_node("Player") as CharacterBody3D
	var pigeons := get_nodes_in_group("pigeons")
	_check(pigeons.size() >= 2, "Level 1 supplies two pigeons for phase variation")
	var pigeon := pigeons[0] as CharacterBody3D
	var second_pigeon := pigeons[1] as CharacterBody3D
	player.set_process(false)
	player.set_physics_process(false)
	for actor in pigeons:
		actor.set_process(false)
		actor.set_physics_process(false)

	_validate_identity_nodes(player, "Player")
	_validate_identity_nodes(pigeon, "NPC")
	_validate_shared_wings(player, "Player")
	_validate_shared_wings(pigeon, "NPC")
	_check(
		not is_equal_approx(
			float(pigeon.get("_presentation_phase")),
			float(second_pigeon.get("_presentation_phase"))
		),
		"NPC pigeons receive distinct presentation phases"
	)

	_validate_npc_visual_only_motion(pigeon)
	_validate_npc_reaction_cues(pigeon)
	_validate_player_action_precedence(player)

	level.queue_free()
	await process_frame
	if _failures == 0:
		print("P2_PIGEON_CHARACTER_VALIDATION_OK")
	quit(_failures)

func _validate_identity_nodes(actor: Node, label: String) -> void:
	for path in [
		"PigeonVisual/Head/LeftEye",
		"PigeonVisual/Head/LeftEye/LeftPupil",
		"PigeonVisual/Head/RightEye",
		"PigeonVisual/Head/RightEye/RightPupil",
		"PigeonVisual/NeckAccent",
		"PigeonVisual/LeftWing",
		"PigeonVisual/RightWing",
		"PigeonVisual/LeftFoot",
		"PigeonVisual/RightFoot",
	]:
		_check(actor.has_node(path), "%s has %s" % [label, path])

func _validate_shared_wings(actor: Node, label: String) -> void:
	var left := actor.get_node("PigeonVisual/LeftWing") as MeshInstance3D
	var right := actor.get_node("PigeonVisual/RightWing") as MeshInstance3D
	_check(left.mesh == right.mesh, "%s wings share one mesh resource" % label)
	_check(
		left.get_surface_override_material(0) == right.get_surface_override_material(0),
		"%s wings share one material resource" % label
	)

func _validate_npc_visual_only_motion(pigeon: CharacterBody3D) -> void:
	pigeon.set("_reaction_mode", 0)
	pigeon.set("is_pecking", false)
	pigeon.set("_desired_move", Vector3.RIGHT * float(pigeon.get("speed")))
	var root_before := pigeon.global_transform
	var phase_before := float(pigeon.get("bob_time"))
	var foot_before := (pigeon.get_node("PigeonVisual/LeftFoot") as Node3D).position
	pigeon.call("_update_walk_bob", 0.14)
	_check(float(pigeon.get("bob_time")) != phase_before, "NPC cadence advances from desired movement")
	_check(
		(pigeon.get_node("PigeonVisual/LeftFoot") as Node3D).position != foot_before,
		"NPC desired movement animates an alternating foot"
	)
	_check(pigeon.global_transform == root_before, "NPC locomotion presentation never moves its physics root")

func _validate_npc_reaction_cues(pigeon: CharacterBody3D) -> void:
	var left_wing := pigeon.get_node("PigeonVisual/LeftWing") as Node3D
	var wing_rest: Vector3 = pigeon.get("_left_wing_rest_rotation")
	var root_before := pigeon.global_transform
	pigeon.call("_reset_identity_pose")
	pigeon.set("_reaction_mode", 1)
	pigeon.set("_desired_move", Vector3.ZERO)
	pigeon.call("_update_walk_bob", 0.12)
	_check(
		absf(left_wing.rotation.z - wing_rest.z) > 0.01,
		"WATCH opens the normal wing silhouette"
	)
	pigeon.call("_reset_identity_pose")
	pigeon.set("_reaction_mode", 2)
	pigeon.set("_reaction_time", 0.08)
	pigeon.set("_reaction_active_time", 0.08)
	pigeon.set("_desired_move", Vector3.RIGHT * float(pigeon.get("flee_speed")))
	pigeon.call("_update_walk_bob", 0.08)
	_check(
		absf(left_wing.rotation.z - wing_rest.z) > 0.12,
		"PANIC produces a readable opening wing burst"
	)
	_check(pigeon.global_transform == root_before, "NPC reaction cues never move its physics root")
	pigeon.call("_ensure_mistaken_capture_wings")
	_check(
		pigeon.has_node("PigeonVisual/MistakenLeftWing")
		and pigeon.has_node("PigeonVisual/MistakenRightWing"),
		"Temporary mistaken-capture wing paths remain intact"
	)

func _validate_player_action_precedence(player: CharacterBody3D) -> void:
	var root_before := player.global_transform
	var left_wing := player.get_node("PigeonVisual/LeftWing") as Node3D
	var right_wing := player.get_node("PigeonVisual/RightWing") as Node3D
	player.call("play_food_snatch_reaction")
	player.call("_update_food_snatch_reaction", 0.12)
	var snatch_left := left_wing.rotation
	var snatch_right := right_wing.rotation
	player.call("_update_character_presentation", 0.08, float(player.get("run_speed")), true)
	_check(
		left_wing.rotation == snatch_left and right_wing.rotation == snatch_right,
		"Food-snatch wings outrank locomotion wings"
	)
	player.call("_reset_food_snatch_pose")
	player.call("start_capture_reaction", player.global_position + Vector3.RIGHT)
	var captured_left := left_wing.rotation
	var captured_right := right_wing.rotation
	player.call("_update_character_presentation", 0.12, float(player.get("run_speed")), true)
	_check(
		left_wing.rotation == captured_left and right_wing.rotation == captured_right,
		"Capture pose blocks ambient locomotion animation"
	)
	_check(player.global_transform == root_before, "Player character presentation never moves its physics root")

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("P2.1 pigeon character validation failed: %s" % message)
