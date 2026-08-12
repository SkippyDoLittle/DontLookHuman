extends SceneTree

# P2.4 visual staging checks. Capture polish may move visual children, but it
# must not change gameplay roots, timers, collision contracts, or held anchors.

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
	var pigeon := level.get_node("NPC_Animal") as CharacterBody3D
	player.set_process(false)
	player.set_physics_process(false)
	pigeon.set_process(false)
	pigeon.set_physics_process(false)

	_validate_player_capture_beats(player)
	_validate_mistaken_capture_beats(pigeon, level)

	level.queue_free()
	await process_frame
	if _failures == 0:
		print("P2_CAPTURE_STAGING_VALIDATION_OK")
	quit(_failures)

func _validate_player_capture_beats(player: CharacterBody3D) -> void:
	var root_before := player.global_transform
	var left_wing := player.get_node("PigeonVisual/LeftWing") as Node3D
	player.call("start_capture_reaction", player.global_position + Vector3.RIGHT)
	player.call("_update_capture_reaction", 0.08)
	var impact_wing := left_wing.rotation.z
	var impact_scale := (player.get_node("PigeonVisual") as Node3D).scale
	player.call("_update_capture_reaction", 0.18)
	var fight_wing := left_wing.rotation.z
	player.call("_update_capture_reaction", 0.76)
	var settled_wing := left_wing.rotation.z
	_check(absf(impact_scale.x - impact_scale.y) > 0.08, "Player capture starts with a readable impact squash")
	_check(absf(fight_wing - impact_wing) > 0.05, "Player capture advances into a distinct frantic fight beat")
	_check(absf(settled_wing - fight_wing) > 0.03, "Player capture resolves into a separate struggling-burst beat")
	_check(player.global_transform == root_before, "Player capture staging never moves the gameplay root")

func _validate_mistaken_capture_beats(pigeon: CharacterBody3D, level: Node) -> void:
	pigeon.set("_reaction_mode", 0)
	pigeon.set("is_pecking", false)
	var carrier := Node3D.new()
	carrier.name = "CaptureStagingCarrier"
	level.add_child(carrier)
	carrier.global_position = Vector3(2.0, 0.525, 1.0)
	var duration := 1.0
	_check(bool(pigeon.call("start_mistaken_capture", carrier, duration)), "Mistaken capture staging begins normally")
	_check(is_equal_approx(float(pigeon.get("_mistaken_capture_duration")), duration), "Visual staging preserves the requested hold duration")
	pigeon.call("_update_mistaken_capture", 0.1)
	var impact_wing := (pigeon.get_node("PigeonVisual/MistakenLeftWing") as Node3D).rotation.z
	var expected_anchor := carrier.global_position + Vector3.UP * 0.92 - carrier.global_transform.basis.z * 0.22
	_check(pigeon.global_position.distance_to(expected_anchor) < 0.02, "Every visual beat preserves the established held anchor")
	pigeon.call("_update_mistaken_capture", 0.4)
	var fight_wing := (pigeon.get_node("PigeonVisual/MistakenLeftWing") as Node3D).rotation.z
	pigeon.call("_update_mistaken_capture", 0.4)
	var release_wing := (pigeon.get_node("PigeonVisual/MistakenLeftWing") as Node3D).rotation.z
	_check(absf(fight_wing - impact_wing) > 0.05, "Wrong-bird capture has a distinct struggle beat")
	_check(absf(release_wing - fight_wing) > 0.03, "Wrong-bird capture pauses before the comic release")
	_check(bool(pigeon.get("_mistaken_capture_active")), "Presentation beats do not release the pigeon early")
	pigeon.call("_update_mistaken_capture", 0.11)
	_check(not bool(pigeon.get("_mistaken_capture_active")), "Pigeon releases at the original hold deadline")

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("P2 capture staging validation failed: %s" % message)
