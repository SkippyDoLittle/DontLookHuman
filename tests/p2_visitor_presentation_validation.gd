extends SceneTree

# P2.3 visitor-only presentation regression checks.
# Run headless: --headless --path . --script res://tests/p2_visitor_presentation_validation.gd

const PARK_REACTIONS = preload("res://park_reaction_director.gd")
const VISITOR_SCENE = preload("res://scenes/actors/Visitor.tscn")
const POSE_PATHS: Array[NodePath] = [
	^"VisitorBody",
	^"VisitorPants",
	^"VisitorHead",
	^"LeftArm",
	^"RightArm",
	^"LeftLeg",
	^"RightLeg",
]

var _failures: int = 0

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	Engine.time_scale = 1.0
	var visitor := VISITOR_SCENE.instantiate() as CharacterBody3D
	var second_visitor := VISITOR_SCENE.instantiate() as CharacterBody3D
	root.add_child(visitor)
	root.add_child(second_visitor)
	await process_frame
	await process_frame
	visitor.set_process(false)
	visitor.set_physics_process(false)
	second_visitor.set_process(false)
	second_visitor.set_physics_process(false)

	_validate_shared_limb_resources(visitor)
	_validate_per_instance_phase(visitor, second_visitor)
	_validate_visual_only_locomotion(visitor)
	_validate_reaction_precedence_and_restore(visitor)
	_validate_capture_variants_use_arms(visitor)
	_validate_update_paths_reuse_resources(visitor)
	_validate_presentation_source_is_allocation_free()
	await _validate_legacy_scene_compatibility()

	visitor.queue_free()
	second_visitor.queue_free()
	await process_frame
	if _failures == 0:
		print("P2_VISITOR_PRESENTATION_VALIDATION_OK")
	quit(_failures)

func _validate_shared_limb_resources(visitor: CharacterBody3D) -> void:
	for path in POSE_PATHS:
		_check(visitor.has_node(path), "Visitor has presentation node %s" % path)
	for path in [^"LeftArm/Mesh", ^"RightArm/Mesh", ^"LeftLeg/Mesh", ^"RightLeg/Mesh"]:
		_check(visitor.has_node(path), "Visitor has low-poly limb mesh %s" % path)

	var body := visitor.get_node("VisitorBody") as MeshInstance3D
	var pants := visitor.get_node("VisitorPants") as MeshInstance3D
	var left_arm := visitor.get_node("LeftArm/Mesh") as MeshInstance3D
	var right_arm := visitor.get_node("RightArm/Mesh") as MeshInstance3D
	var left_leg := visitor.get_node("LeftLeg/Mesh") as MeshInstance3D
	var right_leg := visitor.get_node("RightLeg/Mesh") as MeshInstance3D
	_check(left_arm.mesh == right_arm.mesh, "Left and right arms share one mesh resource")
	_check(left_leg.mesh == right_leg.mesh, "Left and right legs share one mesh resource")
	_check(
		body.get_surface_override_material(0) == left_arm.get_surface_override_material(0)
		and body.get_surface_override_material(0) == right_arm.get_surface_override_material(0),
		"Both arms reuse the visitor's one per-instance shirt material"
	)
	_check(
		pants.get_surface_override_material(0) == left_leg.get_surface_override_material(0)
		and pants.get_surface_override_material(0) == right_leg.get_surface_override_material(0),
		"Both legs reuse the visitor's one per-instance pants material"
	)

func _validate_per_instance_phase(visitor: CharacterBody3D, second_visitor: CharacterBody3D) -> void:
	var first_phase := float(visitor.get("_presentation_phase"))
	var second_phase := float(second_visitor.get("_presentation_phase"))
	_check(not is_equal_approx(first_phase, second_phase), "Visitors receive distinct presentation phases")
	visitor.set("_desired_move", Vector3.ZERO)
	second_visitor.set("_desired_move", Vector3.ZERO)
	visitor.call("_update_locomotion_presentation", 0.16)
	second_visitor.call("_update_locomotion_presentation", 0.16)
	var first_idle := (visitor.get_node("LeftArm") as Node3D).rotation.x
	var second_idle := (second_visitor.get_node("LeftArm") as Node3D).rotation.x
	_check(not is_equal_approx(first_idle, second_idle), "Idle sway is phase-offset per visitor")

func _validate_visual_only_locomotion(visitor: CharacterBody3D) -> void:
	visitor.call("_restore_presentation_pose")
	var root_before := visitor.global_transform
	var target_before: Vector3 = visitor.get("_target")
	var waiting_before := bool(visitor.get("_is_waiting"))
	var wait_timer_before := float(visitor.get("_wait_timer"))
	var collider := visitor.get_node("CollisionShape3D") as CollisionShape3D
	var collider_transform_before := collider.transform
	var collider_shape_before := collider.shape
	var left_arm_before := (visitor.get_node("LeftArm") as Node3D).transform
	var left_leg_before := (visitor.get_node("LeftLeg") as Node3D).transform
	visitor.set("_desired_move", Vector3.RIGHT * float(visitor.get("walk_speed")))
	visitor.call("_update_locomotion_presentation", 0.19)
	_check(
		(visitor.get_node("LeftArm") as Node3D).transform != left_arm_before,
		"Walking animates an arm"
	)
	_check(
		(visitor.get_node("LeftLeg") as Node3D).transform != left_leg_before,
		"Walking animates an opposing leg"
	)
	_check(visitor.global_transform == root_before, "Gait never changes the visitor physics root")
	_check(visitor.get("_target") == target_before, "Gait never changes the AI target")
	_check(bool(visitor.get("_is_waiting")) == waiting_before, "Gait never changes wait state")
	_check(
		is_equal_approx(float(visitor.get("_wait_timer")), wait_timer_before),
		"Gait never changes the wait timer"
	)
	_check(
		collider.transform == collider_transform_before and collider.shape == collider_shape_before,
		"Gait never changes collision"
	)

func _validate_reaction_precedence_and_restore(visitor: CharacterBody3D) -> void:
	visitor.call("_restore_presentation_pose")
	var rest_pose := _snapshot_pose(visitor)
	var root_position_before := visitor.global_position
	var target_before: Vector3 = visitor.get("_target")
	var waiting_before := bool(visitor.get("_is_waiting"))
	var wait_timer_before := float(visitor.get("_wait_timer"))
	visitor.set("_desired_move", Vector3.RIGHT * float(visitor.get("walk_speed")))
	var accepted := bool(visitor.call(
		"react_to_park_event",
		PARK_REACTIONS.EVENT_VISITOR_STARTLED,
		visitor.global_position + Vector3.FORWARD
	))
	_check(accepted, "Pigeon flyby starts the existing visitor reaction")
	_check(
		(visitor.get("_desired_move") as Vector3).is_zero_approx(),
		"Reaction immediately suppresses locomotion"
	)
	visitor.call("_update_park_reaction", 0.1)
	visitor.call("_update_park_reaction", 0.08)
	var left_arm := visitor.get_node("LeftArm") as Node3D
	var right_arm := visitor.get_node("RightArm") as Node3D
	_check(
		absf(left_arm.rotation.z) > 0.8 and absf(right_arm.rotation.z) > 0.8,
		"Flyby flings both arms into a readable startle silhouette"
	)
	_check(visitor.global_position == root_position_before, "Reaction pose never translates the root")
	_check(visitor.get("_target") == target_before, "Active reaction does not change the AI target")
	_check(bool(visitor.get("_is_waiting")) == waiting_before, "Active reaction preserves wait state")
	_check(
		is_equal_approx(float(visitor.get("_wait_timer")), wait_timer_before),
		"Active reaction preserves the wait timer"
	)
	visitor.call("_restore_presentation_pose")
	_check(_pose_matches(visitor, rest_pose), "Reaction restoration resets every visual transform")
	visitor.set("_reaction_event", &"")

func _validate_capture_variants_use_arms(visitor: CharacterBody3D) -> void:
	visitor.set("_reaction_origin", visitor.global_position + Vector3.FORWARD)

	visitor.call("_restore_presentation_pose")
	visitor.set("_capture_reaction_variant", 0)
	visitor.set("_reaction_time", 0.11)
	visitor.call("_update_captured_reaction")
	_check(
		absf((visitor.get_node("LeftArm") as Node3D).rotation.z) > 2.0
		and absf((visitor.get_node("RightArm") as Node3D).rotation.z) > 2.0,
		"Cheer raises both arms"
	)

	visitor.call("_restore_presentation_pose")
	visitor.set("_capture_reaction_variant", 1)
	visitor.set("_reaction_time", 0.14)
	visitor.call("_update_captured_reaction")
	_check(
		absf((visitor.get_node("LeftArm") as Node3D).rotation.x) > 0.9
		and absf((visitor.get_node("RightArm") as Node3D).rotation.x) > 0.9,
		"Gasp brings both arms forward"
	)

	visitor.call("_restore_presentation_pose")
	visitor.set("_capture_reaction_variant", 2)
	visitor.set("_reaction_time", 0.18)
	visitor.call("_update_captured_reaction")
	_check(
		absf((visitor.get_node("LeftArm") as Node3D).rotation.z)
		> absf((visitor.get_node("RightArm") as Node3D).rotation.z) + 0.3,
		"Confused reaction uses an asymmetric arm pose"
	)
	visitor.call("_restore_presentation_pose")

func _validate_update_paths_reuse_resources(visitor: CharacterBody3D) -> void:
	var body := visitor.get_node("VisitorBody") as MeshInstance3D
	var pants := visitor.get_node("VisitorPants") as MeshInstance3D
	var shirt_material := body.get_surface_override_material(0)
	var pants_material := pants.get_surface_override_material(0)
	var arm_mesh := (visitor.get_node("LeftArm/Mesh") as MeshInstance3D).mesh
	var leg_mesh := (visitor.get_node("LeftLeg/Mesh") as MeshInstance3D).mesh
	visitor.set("_desired_move", Vector3.RIGHT * float(visitor.get("walk_speed")))
	for _frame in 120:
		visitor.call("_update_locomotion_presentation", 1.0 / 60.0)
	_check(body.get_surface_override_material(0) == shirt_material, "Gait reuses shirt material")
	_check(pants.get_surface_override_material(0) == pants_material, "Gait reuses pants material")
	_check(
		(visitor.get_node("LeftArm/Mesh") as MeshInstance3D).mesh == arm_mesh,
		"Gait reuses the shared arm mesh"
	)
	_check(
		(visitor.get_node("LeftLeg/Mesh") as MeshInstance3D).mesh == leg_mesh,
		"Gait reuses the shared leg mesh"
	)

func _validate_presentation_source_is_allocation_free() -> void:
	var file := FileAccess.open("res://park_visitor.gd", FileAccess.READ)
	var source := ""
	if file != null:
		source = file.get_as_text()
		file.close()
	var locomotion_block := _function_block(source, "_update_locomotion_presentation")
	var reaction_block := _function_block(source, "_update_park_reaction")
	var capture_block := _function_block(source, "_update_captured_reaction")
	var hot_paths := locomotion_block + reaction_block + capture_block
	_check(not hot_paths.contains("create_tween"), "Presentation hot paths allocate no tweens")
	_check(not hot_paths.contains("Material3D.new"), "Presentation hot paths allocate no materials")
	_check(not hot_paths.contains("Mesh.new"), "Presentation hot paths allocate no meshes")

func _validate_legacy_scene_compatibility() -> void:
	# Main.tscn still owns an older visitor layout with torso/head but no limbs.
	# This minimal equivalent makes the optional-node contract explicit here.
	var legacy := CharacterBody3D.new()
	legacy.name = "LegacyParkVisitor"
	legacy.set_script(load("res://park_visitor.gd"))
	for node_name in ["VisitorBody", "VisitorPants", "VisitorHead"]:
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = node_name
		mesh_instance.mesh = BoxMesh.new()
		legacy.add_child(mesh_instance)
	root.add_child(legacy)
	await process_frame
	legacy.set_process(false)
	legacy.set_physics_process(false)
	_check(not bool(legacy.get("_has_presentation_limbs")), "Legacy visitor safely disables optional limb presentation")
	var legacy_body := legacy.get_node("VisitorBody") as MeshInstance3D
	var legacy_head := legacy.get_node("VisitorHead") as MeshInstance3D
	legacy.call("_restore_presentation_pose")
	var body_rest := legacy_body.transform
	var head_rest := legacy_head.transform
	var accepted := bool(legacy.call(
		"react_to_park_event",
		PARK_REACTIONS.EVENT_VISITOR_STARTLED,
		legacy.global_position + Vector3.FORWARD
	))
	legacy.call("_update_park_reaction", 0.04)
	legacy.call("_update_park_reaction", 0.1)
	_check(accepted, "Legacy visitor still accepts its existing reaction events")
	_check(
		legacy_body.transform != body_rest or legacy_head.transform != head_rest,
		"Legacy visitor retains torso/head reaction motion without limbs"
	)
	legacy.call("_restore_presentation_pose")
	_check(
		legacy_body.transform == body_rest and legacy_head.transform == head_rest,
		"Legacy visitor torso/head restore safely without limbs"
	)
	legacy.queue_free()
	await process_frame

func _snapshot_pose(visitor: CharacterBody3D) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for path in POSE_PATHS:
		result.append((visitor.get_node(path) as Node3D).transform)
	return result

func _pose_matches(visitor: CharacterBody3D, expected: Array[Transform3D]) -> bool:
	for index in POSE_PATHS.size():
		if (visitor.get_node(POSE_PATHS[index]) as Node3D).transform != expected[index]:
			return false
	return true

func _function_block(source: String, method_name: String) -> String:
	var start := source.find("func %s(" % method_name)
	if start < 0:
		return ""
	var finish := source.find("\nfunc ", start + 1)
	return source.substr(start) if finish < 0 else source.substr(start, finish - start)

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("P2.3 visitor presentation validation failed: %s" % message)
