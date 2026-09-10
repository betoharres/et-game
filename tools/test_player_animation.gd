extends SceneTree

var _failed : bool = false


func _init() -> void:
	run.call_deferred()


func run() -> void:
	var packed : PackedScene = load("res://scenes/Player.tscn") as PackedScene
	var player : CharacterBody3D = packed.instantiate() as CharacterBody3D
	root.add_child(player)
	player.set_physics_process(false)
	await process_frame

	var controller : PlayerAnimationController = player.get_node(
		"PlayerAnimationController"
	) as PlayerAnimationController
	var tree : AnimationTree = player.get_node("AnimationTree") as AnimationTree
	var animation_player : AnimationPlayer = player.get_node("ET/AnimationPlayer") as AnimationPlayer

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
	var skeleton : Skeleton3D = player.get_node("ET/ETArmature/Skeleton3D") as Skeleton3D
	tree.advance(0.3)
	var walk_pose : Array[Quaternion] = bone_rotations(skeleton)
	tree.advance(0.2)
	check(bones_moved(skeleton, walk_pose), "Walk state animates the visual skeleton")

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
	var get_up_duration : float = controller.begin_get_up(true)
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
	var front_duration : float = controller.begin_get_up(false)
	var front_initial_speed : float = animation_player.speed_scale
	controller._physics_process(front_duration * 0.24)
	check(
		animation_player.speed_scale < front_initial_speed,
		"Front get up eases from arms into standing"
	)
	controller.set_physics_process(false)
	tree.active = false
	check_model_clips(player.get_node("ET"), "Player")

	var crew_scene : PackedScene = load("res://scenes/NPCs/ShipCrewAlien.tscn") as PackedScene
	var crew : Node = crew_scene.instantiate()
	root.add_child(crew)
	crew.set_physics_process(false)
	crew.get_node("PlayerAnimationController").set_physics_process(false)
	(crew.get_node("AnimationTree") as AnimationTree).active = false
	check_model_clips(crew.get_node("ET"), "ShipCrewAlien")
	crew.queue_free()

	var creator_scene : PackedScene = load("res://scenes/Menu/CharacterCreator.tscn") as PackedScene
	var creator : Node = creator_scene.instantiate()
	root.add_child(creator)
	var preview_pivot : Node = creator.get_node("%PreviewPivot")
	check_model_clips(preview_pivot.get_node("ET"), "CharacterCreator")
	creator.queue_free()

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


func check_model_clips(model : Node, label : String) -> void:
	var animation_player : AnimationPlayer = model.get_node("AnimationPlayer") as AnimationPlayer
	var skeleton : Skeleton3D = model.get_node("ETArmature/Skeleton3D") as Skeleton3D
	var mesh : MeshInstance3D = skeleton.get_node("ET") as MeshInstance3D
	check(mesh.get_node(mesh.skeleton) == skeleton and mesh.skin != null,
		"%s mesh bound to the animated skeleton" % label)
	var shape_weights : PackedFloat32Array = []
	check(mesh.mesh.get_blend_shape_count() == 3, "%s retains three blend shapes" % label)
	for shape_index : int in mesh.mesh.get_blend_shape_count():
		var weight : float = 0.2 + 0.3 * shape_index
		mesh.set_blend_shape_value(shape_index, weight)
		shape_weights.append(weight)
	var animation_names : Array[StringName] = []
	for name_value : String in PlayerAnimationController.STATE_ANIMATIONS.values():
		animation_names.append(StringName(name_value))
	animation_names.append_array([&"jump_start", &"carried_idle", &"carried_from_ground"])
	var all_move : bool = true
	for animation_name : StringName in animation_names:
		if not animation_player.has_animation(animation_name):
			check(false, "%s missing %s" % [label, animation_name])
			all_move = false
			continue
		var animation : Animation = animation_player.get_animation(animation_name)
		animation_player.play(animation_name)
		animation_player.seek(animation.length * 0.15, true)
		var first_pose : Array[Quaternion] = bone_rotations(skeleton)
		animation_player.seek(animation.length * 0.55, true)
		if not bones_moved(skeleton, first_pose):
			check(false, "%s clip %s has no visible bone motion" % [label, animation_name])
			all_move = false
	check(all_move, "%s: all 37 clips move the actual skeleton" % label)
	for shape_index : int in shape_weights.size():
		check(is_equal_approx(mesh.get_blend_shape_value(shape_index), shape_weights[shape_index]),
			"%s animation preserves %s" % [label, mesh.mesh.get_blend_shape_name(shape_index)])
	animation_player.stop()


func bone_rotations(skeleton : Skeleton3D) -> Array[Quaternion]:
	var result : Array[Quaternion] = []
	for bone : int in skeleton.get_bone_count():
		result.append(skeleton.get_bone_pose_rotation(bone))
	return result


func bones_moved(skeleton : Skeleton3D, previous : Array[Quaternion]) -> bool:
	for bone : int in skeleton.get_bone_count():
		if not previous[bone].is_equal_approx(skeleton.get_bone_pose_rotation(bone)):
			return true
	return false


func looping_animations_are_in_place(animation_player : AnimationPlayer) -> bool:
	for animation_name : StringName in PlayerAnimationController.LOOPING_ANIMATIONS:
		var animation : Animation = animation_player.get_animation(animation_name)
		if animation == null:
			return false
		for track_index : int in animation.get_track_count():
			if animation.track_get_type(track_index) != Animation.TYPE_POSITION_3D:
				continue
			if not String(animation.track_get_path(track_index)).ends_with(
				":mixamorig_Hips"
			):
				continue
			var first : Vector3 = animation.track_get_key_value(track_index, 0) as Vector3
			for key_index : int in animation.track_get_key_count(track_index):
				var value : Vector3 = animation.track_get_key_value(
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
		var animation : Animation = animation_player.get_animation(animation_name)
		if animation == null:
			return false
		for track_index : int in animation.get_track_count():
			if animation.track_get_type(track_index) != Animation.TYPE_ROTATION_3D:
				continue
			if not String(animation.track_get_path(track_index)).ends_with(
				":mixamorig_Hips"
			):
				continue
			var start : Quaternion = animation.rotation_track_interpolate(track_index, 0.0)
			var finish : Quaternion = animation.rotation_track_interpolate(
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
