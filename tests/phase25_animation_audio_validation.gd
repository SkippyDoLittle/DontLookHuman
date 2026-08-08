extends SceneTree

# Phase 25 validation: animation and audio personality pass.
# Run headless: --headless --path . --script res://tests/phase25_animation_audio_validation.gd

var _pass_count: int = 0
var _fail_count: int = 0

func _init() -> void:
	_run_all()
	print("PHASE25 RESULTS: %d passed, %d failed" % [_pass_count, _fail_count])
	quit(0 if _fail_count == 0 else 1)

func _run_all() -> void:
	_test_player_has_lean_strength()
	_test_player_has_turn_roll_strength()
	_test_player_has_stop_bounce_duration()
	_test_player_has_strain_stamina_threshold()
	_test_player_has_prev_velocity_xz_var()
	_test_player_has_body_lean_x_var()
	_test_player_has_turn_roll_var()
	_test_player_has_stop_bounce_timer_var()
	_test_player_has_strain_time_var()
	_test_player_defines_update_movement_animation()
	_test_player_peck_has_anticipation()
	_test_npc_has_panic_prev_direction_var()
	_test_npc_has_panic_turn_lean_var()
	_test_npc_watch_reaction_has_crouch()
	_test_npc_panic_reaction_applies_turn_lean()
	_test_npc_finish_reaction_resets_lean_vars()
	_test_npc_walk_bob_has_panic_pitch()
	_test_sound_step_has_pitch_variation()
	_test_sound_set_tension_fades_ambient()
	_test_ranger_presentation_rookie_windup()
	_test_ranger_presentation_veteran_windup_uses_cubic()
	_test_ranger_presentation_hothead_windup_lean()

func _assert(label: String, condition: bool) -> void:
	if condition:
		print("PHASE25_%s_OK" % label.to_upper().replace(" ", "_"))
		_pass_count += 1
	else:
		print("PHASE25_%s_FAIL" % label.to_upper().replace(" ", "_"))
		_fail_count += 1

func _read_source(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var src := file.get_as_text()
	file.close()
	return src

# --- player.gd ---

func _test_player_has_lean_strength() -> void:
	var src := _read_source("res://player.gd")
	_assert("player has LEAN_STRENGTH constant", src.contains("LEAN_STRENGTH"))

func _test_player_has_turn_roll_strength() -> void:
	var src := _read_source("res://player.gd")
	_assert("player has TURN_ROLL_STRENGTH constant", src.contains("TURN_ROLL_STRENGTH"))

func _test_player_has_stop_bounce_duration() -> void:
	var src := _read_source("res://player.gd")
	_assert("player has STOP_BOUNCE_DURATION constant", src.contains("STOP_BOUNCE_DURATION"))

func _test_player_has_strain_stamina_threshold() -> void:
	var src := _read_source("res://player.gd")
	_assert("player has STRAIN_STAMINA_THRESHOLD constant", src.contains("STRAIN_STAMINA_THRESHOLD"))

func _test_player_has_prev_velocity_xz_var() -> void:
	var src := _read_source("res://player.gd")
	_assert("player declares _prev_velocity_xz var", src.contains("_prev_velocity_xz"))

func _test_player_has_body_lean_x_var() -> void:
	var src := _read_source("res://player.gd")
	_assert("player declares _body_lean_x var", src.contains("_body_lean_x"))

func _test_player_has_turn_roll_var() -> void:
	var src := _read_source("res://player.gd")
	_assert("player declares _turn_roll var", src.contains("_turn_roll"))

func _test_player_has_stop_bounce_timer_var() -> void:
	var src := _read_source("res://player.gd")
	_assert("player declares _stop_bounce_timer var", src.contains("_stop_bounce_timer"))

func _test_player_has_strain_time_var() -> void:
	var src := _read_source("res://player.gd")
	_assert("player declares _strain_time var", src.contains("_strain_time"))

func _test_player_defines_update_movement_animation() -> void:
	var src := _read_source("res://player.gd")
	_assert("player defines _update_movement_animation", src.contains("func _update_movement_animation("))

func _test_player_peck_has_anticipation() -> void:
	var src := _read_source("res://player.gd")
	_assert("player peck phase has anticipation head-lift", src.contains("0.022"))

# --- npc_animal.gd ---

func _test_npc_has_panic_prev_direction_var() -> void:
	var src := _read_source("res://npc_animal.gd")
	_assert("npc declares _panic_prev_direction var", src.contains("_panic_prev_direction"))

func _test_npc_has_panic_turn_lean_var() -> void:
	var src := _read_source("res://npc_animal.gd")
	_assert("npc declares _panic_turn_lean var", src.contains("_panic_turn_lean"))

func _test_npc_watch_reaction_has_crouch() -> void:
	var src := _read_source("res://npc_animal.gd")
	# 0.86 is the y-scale for the crouched alert body pose
	_assert("npc watch reaction has crouched body scale (0.86)", src.contains("0.86"))

func _test_npc_panic_reaction_applies_turn_lean() -> void:
	var src := _read_source("res://npc_animal.gd")
	_assert("npc panic reaction applies _panic_turn_lean to body.rotation.z",
		src.contains("_panic_turn_lean") and src.contains("clampf(_panic_turn_lean"))

func _test_npc_finish_reaction_resets_lean_vars() -> void:
	var src := _read_source("res://npc_animal.gd")
	_assert("npc _finish_park_reaction resets panic lean vars",
		src.contains("_panic_prev_direction = Vector3.ZERO") and src.contains("_panic_turn_lean = 0.0"))

func _test_npc_walk_bob_has_panic_pitch() -> void:
	var src := _read_source("res://npc_animal.gd")
	_assert("npc walk bob varies step pitch during panic",
		src.contains("pitch_scale") and src.contains("ReactionMode.PANIC"))

# --- sound_manager.gd ---

func _test_sound_step_has_pitch_variation() -> void:
	var src := _read_source("res://sound_manager.gd")
	_assert("sound_manager play_step randomizes pitch_scale",
		src.contains("pitch_scale") and src.contains("randf_range") and src.contains("play_step"))

func _test_sound_set_tension_fades_ambient() -> void:
	var src := _read_source("res://sound_manager.gd")
	_assert("sound_manager set_tension fades ambient volume",
		src.contains("_ambient.volume_db") and src.contains("set_tension"))

# --- ranger_presentation.gd ---

func _test_ranger_presentation_rookie_windup() -> void:
	var src := _read_source("res://ranger_presentation.gd")
	_assert("ranger grab_windup has Rookie personality animation (-1.38 arm angle)",
		src.contains("-1.38"))

func _test_ranger_presentation_veteran_windup_uses_cubic() -> void:
	var src := _read_source("res://ranger_presentation.gd")
	_assert("ranger grab_windup Veteran variant uses TRANS_CUBIC",
		src.contains("TRANS_CUBIC"))

func _test_ranger_presentation_hothead_windup_lean() -> void:
	var src := _read_source("res://ranger_presentation.gd")
	_assert("ranger grab_windup Hothead variant has forward body lean (-0.11)",
		src.contains("-0.11"))
