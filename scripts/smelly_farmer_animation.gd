extends "res://scripts/npc/npc_animation.gd"

const REFERENCE_RIG: PackedScene = preload(
	"res://Temporarios/Animations/Meshes/PolygonSyntyCharacter.fbx"
)
const LEG_BONES: Array[StringName] = [
	&"UpperLeg_L", &"LowerLeg_L", &"Ankle_L", &"Ball_L", &"Toes_L",
	&"UpperLeg_R", &"LowerLeg_R", &"Ankle_R", &"Ball_R", &"Toes_R",
]


func _add_clip(library: AnimationLibrary, animation_name: StringName, clip: PackedScene) -> void:
	var source_library: AnimationLibrary = AnimationLibrary.new()
	super._add_clip(source_library, animation_name, clip)
	if not source_library.has_animation(animation_name):
		return
	var source_animation: Animation = source_library.get_animation(animation_name)
	var animation: Animation = source_animation.duplicate(true) as Animation
	var target: Skeleton3D = get_node("../FarmerOld2/Armature/Skeleton3D") as Skeleton3D
	# Clip-only FBX files use a sampled pose as rest; use the mesh's bind rig.
	var reference: Node3D = REFERENCE_RIG.instantiate() as Node3D
	var source: Skeleton3D = reference.get_node("Skeleton3D") as Skeleton3D
	var target_basis: Basis = (target.get_parent() as Node3D).transform.basis.orthonormalized()
	var hips_track: int = source_animation.find_track(NodePath("Skeleton3D:Hips"), Animation.TYPE_ROTATION_3D)
	var source_hips_rest: Quaternion = source.get_bone_global_rest(source.find_bone("Hips")).basis.get_rotation_quaternion()
	var target_hips_rest: Quaternion = (
		target_basis * target.get_bone_global_rest(target.find_bone("Hips")).basis
	).get_rotation_quaternion()

	for track: int in range(animation.get_track_count() - 1, -1, -1):
		var path: NodePath = animation.track_get_path(track)
		var bone_name: StringName = path.get_subname(0) if path.get_subname_count() == 1 else &""
		# Keep the hips, torso, gun grip and all bone lengths in their existing pose.
		if animation.track_get_type(track) != Animation.TYPE_ROTATION_3D or bone_name not in LEG_BONES:
			animation.remove_track(track)
			continue
		var source_bone: int = source.find_bone(bone_name)
		var target_bone: int = target.find_bone(bone_name)
		var source_rest: Quaternion = source.get_bone_rest(source_bone).basis.get_rotation_quaternion()
		var target_rest: Quaternion = target.get_bone_rest(target_bone).basis.get_rotation_quaternion()
		var source_global: Quaternion = source.get_bone_global_rest(source_bone).basis.get_rotation_quaternion()
		var target_global: Quaternion = (
			target_basis * target.get_bone_global_rest(target_bone).basis
		).get_rotation_quaternion()
		# FarmerOld2 has different bone rolls and a rotated, centimeter-scale Armature.
		var correction: Quaternion = source_global.inverse() * target_global
		for key: int in range(animation.track_get_key_count(track)):
			var rotation: Quaternion = animation.track_get_key_value(track, key)
			var delta: Quaternion = source_rest.inverse() * rotation
			var retargeted: Quaternion = (
				target_rest * correction.inverse() * delta * correction
			).normalized()
			if String(bone_name).begins_with("UpperLeg_") and hips_track >= 0:
				# Fold the clip's hip rotation into the thighs: feet keep the authored
				# orientation while the actual hips and gun-bearing torso stay still.
				var time: float = animation.track_get_key_time(track, key)
				var hips_pose: Quaternion = source_animation.rotation_track_interpolate(hips_track, time)
				retargeted = target_hips_rest.inverse() * hips_pose * source_hips_rest.inverse() * target_hips_rest * retargeted
			animation.track_set_key_value(track, key, retargeted.normalized())
		animation.track_set_path(track, NodePath("Armature/Skeleton3D:" + String(bone_name)))
		target.reset_bone_pose(target_bone)

	# Import strips constant tracks (Idle omits Ball_L); key rest explicitly so
	# switching back from Walk cannot leave a foot in the previous clip's pose.
	for bone_name: StringName in LEG_BONES:
		var path: NodePath = NodePath("Armature/Skeleton3D:" + String(bone_name))
		if animation.find_track(path, Animation.TYPE_ROTATION_3D) >= 0:
			continue
		var bone: int = target.find_bone(bone_name)
		var track: int = animation.add_track(Animation.TYPE_ROTATION_3D)
		animation.track_set_path(track, path)
		animation.rotation_track_insert_key(track, 0.0, target.get_bone_rest(bone).basis.get_rotation_quaternion())
		target.reset_bone_pose(bone)

	reference.free()
	library.add_animation(animation_name, animation)
