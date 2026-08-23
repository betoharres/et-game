extends SceneTree

var _failed : bool = false


func _init() -> void:
	run.call_deferred()


func run() -> void:
	var packed := load("res://scenes/Player.tscn") as PackedScene
	var player := packed.instantiate() as CharacterBody3D
	root.add_child(player)
	await process_frame
	player.set_physics_process(false)

	var controller := player.get_node(
		"PlayerAnimationController"
	) as PlayerAnimationController
	var tree := player.get_node("AnimationTree") as AnimationTree
	var animation_player := player.get_node("ET/AnimationPlayer") as AnimationPlayer

	await physics_frame
	check(
		player.find_children("*", "Skeleton3D", true, false).size() == 1,
		"Single visual Skeleton3D"
	)
	check(looping_animations_are_in_place(animation_player), "Looping clips in-place")
	check(turn_clips_have_no_root_yaw(animation_player), "Turn clips have no root yaw")
	check(
		animation_player.has_animation("walk_turn_180")
		and animation_player.has_animation("run_turn_180")
		and animation_player.has_animation("run_turn_right"),
		"Moving turn clips imported"
	)
	check(controller.get_current_state() == &"Idle", "Idle")

	controller.set_motion_state(Vector3(0.0, 0.0, 3.0), true, false, false, 0)
	await physics_frame
	check(controller.get_current_state() == &"Walk", "Walk")
	check(
		animation_player.speed_scale > 1.7
		and animation_player.speed_scale < 1.9,
		"Walk playback calibrated"
	)

	controller.set_motion_state(Vector3(0.0, 0.0, 5.5), true, true, false, 0)
	await physics_frame
	check(controller.get_current_state() == &"Run", "Run")
	check(
		animation_player.speed_scale > 1.5
		and animation_player.speed_scale < 1.8,
		"Run playback calibrated"
	)

	controller.set_motion_state(Vector3(-3.0, 0.0, 0.0), true, false, false, 0)
	await physics_frame
	check(controller.get_current_state() == &"StrafeLeftWalk", "Strafe left")

	controller.set_motion_state(Vector3.ZERO, true, false, true, 0)
	await physics_frame
	check(controller.get_current_state() == &"CrouchIdle", "Crouch idle")

	controller.set_motion_state(Vector3(0.0, 0.0, 1.6), true, false, true, 0)
	await physics_frame
	check(controller.get_current_state() == &"CrouchWalk", "Crouch walk")

	controller.set_motion_state(Vector3(1.6, 0.0, 0.0), true, false, true, 0)
	await physics_frame
	check(controller.get_current_state() == &"CrouchRight", "Crouch strafe")

	controller.set_motion_state(Vector3(0.0, 2.0, 0.0), false, false, false, 1)
	await physics_frame
	check(controller.get_current_state() == &"Jump", "Jump ascent")

	controller.set_motion_state(Vector3(0.0, -2.0, 0.0), false, false, false, 1)
	await physics_frame
	check(controller.get_current_state() == &"Fall", "Fall")

	controller.set_motion_state(Vector3.ZERO, true, false, false, 0)
	controller.trigger_turn(deg_to_rad(130.0))
	check(controller.get_current_state() == &"TurnLeftWide", "Wide turn")

	controller.trigger_hit(Vector3.RIGHT)
	check(controller.get_current_state() == &"HitSide", "Side hit")

	controller.trigger_stumble(Vector3(0.0, 0.0, -1.0))
	check(controller.get_current_state() == &"StumbleBack", "Stumble")

	controller.trigger_landing(8.0)
	check(controller.get_current_state() == &"Landing", "Hard landing")

	controller.set_ragdoll_active(true)
	check(not tree.active, "Ragdoll disables AnimationTree")
	var get_up_duration := controller.begin_get_up(true)
	check(tree.active, "Get up enables AnimationTree")
	check(controller.get_current_state() == &"GetUpBack", "Get up")
	check(not controller.is_get_up_ready_for_control(), "Get up starts locked")
	controller._physics_process(
		maxf(
			get_up_duration - controller.get_up_control_release_lead - 0.05,
			0.0
		)
	)
	check(
		not controller.is_get_up_ready_for_control(),
		"Get up stays locked before standing tail"
	)
	controller._physics_process(0.06)
	check(
		controller.is_get_up_ready_for_control(),
		"Get up releases control during standing tail"
	)
	controller.finish_get_up()
	var front_duration := controller.begin_get_up(false)
	var front_initial_speed := animation_player.speed_scale
	controller._physics_process(front_duration * 0.24)
	check(
		animation_player.speed_scale < front_initial_speed,
		"Front get up eases from arms into standing"
	)

	player.queue_free()
	await process_frame
	if _failed:
		quit(1)
	else:
		print("PLAYER_ANIMATION_TEST|PASS")
		quit()


func check(condition : bool, label : String) -> void:
	if condition:
		print("CHECK|PASS|%s" % label)
		return
	_failed = true
	push_error("CHECK|FAIL|%s" % label)


func looping_animations_are_in_place(animation_player : AnimationPlayer) -> bool:
	for animation_name : StringName in PlayerAnimationController.LOOPING_ANIMATIONS:
		var animation := animation_player.get_animation(animation_name)
		if animation == null:
			return false
		for track_index : int in animation.get_track_count():
			if animation.track_get_type(track_index) != Animation.TYPE_POSITION_3D:
				continue
			if not String(animation.track_get_path(track_index)).ends_with(
				":mixamorig_Hips"
			):
				continue
			var first := animation.track_get_key_value(track_index, 0) as Vector3
			for key_index : int in animation.track_get_key_count(track_index):
				var value := animation.track_get_key_value(
					track_index,
					key_index
				) as Vector3
				if absf(value.x - first.x) > 0.0001:
					return false
				if absf(value.z - first.z) > 0.0001:
					return false
	return true


func turn_clips_have_no_root_yaw(animation_player : AnimationPlayer) -> bool:
	for animation_name : StringName in [
		&"turn_left",
		&"turn_right",
		&"turn_left_wide",
		&"turn_right_wide",
		&"walk_turn_180",
		&"run_turn_180",
		&"run_turn_right",
	]:
		var animation := animation_player.get_animation(animation_name)
		if animation == null:
			return false
		for track_index : int in animation.get_track_count():
			if animation.track_get_type(track_index) != Animation.TYPE_ROTATION_3D:
				continue
			if not String(animation.track_get_path(track_index)).ends_with(
				":mixamorig_Hips"
			):
				continue
			var start := animation.rotation_track_interpolate(track_index, 0.0)
			var finish := animation.rotation_track_interpolate(
				track_index,
				animation.length
			)
			var start_forward : Vector3 = start * Vector3.FORWARD
			var finish_forward : Vector3 = finish * Vector3.FORWARD
			start_forward.y = 0.0
			finish_forward.y = 0.0
			if start_forward.normalized().angle_to(
				finish_forward.normalized()
			) > deg_to_rad(5.0):
				return false
	return true
