extends SceneTree

const LEG_NAMES: Array[StringName] = [
	&"UpperLeg_L", &"LowerLeg_L", &"Ankle_L", &"Ball_L", &"Toes_L",
	&"UpperLeg_R", &"LowerLeg_R", &"Ankle_R", &"Ball_R", &"Toes_R",
]
var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var npc: CharacterBody3D = load("res://scenes/NPCs/SmellyFarmer.tscn").instantiate() as CharacterBody3D
	root.add_child(npc)
	npc.set_physics_process(false)
	var skeleton: Skeleton3D = npc.get_node("FarmerOld2/Armature/Skeleton3D") as Skeleton3D
	var player: AnimationPlayer = npc.get_node("AnimationPlayer") as AnimationPlayer
	var controller: NPCAnimation = npc.get_node("NPCAnimation") as NPCAnimation
	_check(npc.get_node("IKcontainer").get_script() == null, "Procedural foot script still attached")
	var arm_count: int = 0
	for child: Node in skeleton.get_children():
		if child is TwoBoneIK3D:
			_check("#Hand" in child.name and child.active, "Unexpected or inactive IK: " + child.name)
			arm_count += 1
		if child is SkeletonModifier3D:
			# Inspect animation poses independently of head/arm post-processing.
			child.active = false
	_check(arm_count == 2, "Both gun arm solvers must remain")
	controller.set_moving(true)
	_check(player.current_animation == "Walk", "Moving did not select Walk")
	controller.set_moving(false)
	_check(player.current_animation == "Idle", "Stopping did not select Idle")
	for clip_name: StringName in [&"Idle", &"Walk"]:
		_check(player.has_animation(clip_name), "Missing " + clip_name)
		if not player.has_animation(clip_name):
			continue
		var clip: Animation = player.get_animation(clip_name)
		_check(clip.loop_mode == Animation.LOOP_LINEAR, "Clip does not loop")
		_check(clip.get_track_count() == 10, "Expected ten leg rotation tracks")
		for track: int in range(clip.get_track_count()):
			var path: NodePath = clip.track_get_path(track)
			_check(String(path.get_concatenated_names()) == "Armature/Skeleton3D", "Wrong skeleton path")
			_check(path.get_subname(0) in LEG_NAMES, "Animation changes upper body")
			_check(clip.track_get_type(track) == Animation.TYPE_ROTATION_3D, "Animation changes bone lengths")
		var first_feet: Array[Vector3] = []
		var excursion: Vector2 = Vector2.ZERO
		var source_clip: PackedScene = controller.idle_clip if clip_name == &"Idle" else controller.walk_clip
		var source_model: Node = source_clip.instantiate()
		root.add_child(source_model)
		var source_skeleton: Skeleton3D = source_model.get_node("Skeleton3D") as Skeleton3D
		var source_player: AnimationPlayer = source_model.get_node("AnimationPlayer") as AnimationPlayer
		source_player.play(source_player.get_animation_list()[0])
		player.play(clip_name)
		for sample: int in range(61):
			player.seek(clip.length * float(sample) / 60.0, true)
			source_player.seek(clip.length * float(sample) / 60.0, true)
			for bone: int in range(skeleton.get_bone_count()):
				var pose: Transform3D = skeleton.get_bone_pose(bone)
				var rest: Transform3D = skeleton.get_bone_rest(bone)
				_check(pose.origin.is_equal_approx(rest.origin), "Bone length changed")
				_check(pose.basis.is_finite() and absf(pose.basis.determinant() - 1.0) < 0.001, "Invalid bone rotation")
				if skeleton.get_bone_name(bone) not in LEG_NAMES:
					_check(pose.is_equal_approx(rest), "Upper-body pose changed")
			for side: int in range(2):
				var suffix: String = "_L" if side == 0 else "_R"
				var hip: Vector3 = _bone_position(skeleton, "UpperLeg" + suffix)
				var knee: Vector3 = _bone_position(skeleton, "LowerLeg" + suffix)
				var ankle: Vector3 = _bone_position(skeleton, "Ankle" + suffix)
				var ball: Vector3 = _bone_position(skeleton, "Ball" + suffix)
				_check(hip.y > knee.y and knee.y > ankle.y, "%s: inverted leg at sample %d" % [clip_name, sample])
				var straight_knee: Vector3 = hip.lerp(ankle, (hip.y - knee.y) / (hip.y - ankle.y))
				_check(knee.z > straight_knee.z - 0.03, "%s: backward knee at sample %d" % [clip_name, sample])
				# The source walk points toes down and slightly back during toe-off.
				var foot_direction: Vector3 = (ball - ankle).normalized()
				var source_foot: Vector3 = (_bone_position(source_skeleton, "Ball" + suffix) - _bone_position(source_skeleton, "Ankle" + suffix)).normalized()
				_check(foot_direction.angle_to(source_foot) < 0.15, "%s: foot differs from source at sample %d" % [clip_name, sample])
				_check(ankle.y > -0.15 and ankle.y < 0.65, "%s: ankle outside expected height: %s" % [clip_name, ankle])
				if sample == 0:
					first_feet.append(ankle)
				excursion[side] = maxf(excursion[side], ankle.distance_to(first_feet[side]))
		print(clip_name, ": foot excursions (m) = ", excursion)
		if clip_name == &"Walk":
			_check(excursion.x > 0.2 and excursion.y > 0.2, "Walk does not move both legs")
		source_model.free()
	player.play(&"Walk")
	player.seek(0.4, true)
	player.play(&"Idle")
	player.seek(0.0, true)
	var left_ball: int = skeleton.find_bone("Ball_L")
	_check(skeleton.get_bone_pose(left_ball).is_equal_approx(skeleton.get_bone_rest(left_ball)), "Idle retained Walk's left foot rotation")
	npc.free()
	for failure: String in _failures:
		push_error(failure)
	if _failures.is_empty():
		print("OK: SmellyFarmer leg animation, rotations, state switches and retained arm IK")
	quit(0 if _failures.is_empty() else 1)


func _bone_position(skeleton: Skeleton3D, bone_name: String) -> Vector3:
	return skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone_name)).origin


func _check(condition: bool, message: String) -> void:
	if not condition and message not in _failures:
		_failures.append(message)
