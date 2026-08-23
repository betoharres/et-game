class_name RagdollRecoveryModifier
extends SkeletonModifier3D

## Briefly aligns the pose the ET had when ragdoll stopped with the beginning
## of an authored Mixamo get-up clip. It is not the get-up animation itself.
##
## This has to be a SkeletonModifier3D, and the last one in the stack. Skeleton3D
## backs up the bone poses before running the stack and restores them right
## after, so a normal script reading get_bone_pose() sees the pose from before
## the modifiers, never the posed skeleton. Only inside _process_modification is
## the real pose readable and writable.
##
## Blending the captured pose explicitly is required because changing a
## modifier's own influence interpolates a fraction of the remaining distance
## every frame and converges too quickly for a predictable handoff.

var _blend : float = -1.0
var _fallen_rotations : Array[Quaternion] = []
var _root_bones : PackedInt32Array = PackedInt32Array()
var _root_positions : PackedVector3Array = PackedVector3Array()


## Starts holding the fallen pose. Blend 0.0 is fully fallen, 1.0 is fully
## handed back to the rest of the stack.
##
## Only bones without a parent carry a position. On the Mixamo hierarchy that
## normally means mixamorig:Hips; rotations are retained for the complete rig.
func begin(fallen_rotations : Array[Quaternion], root_bones : PackedInt32Array,
	root_positions : PackedVector3Array) -> void:
	_fallen_rotations = fallen_rotations
	_root_bones = root_bones
	_root_positions = root_positions
	_blend = 0.0


func set_blend(value : float) -> void:
	if _blend < 0.0:
		return

	_blend = clampf(value, 0.0, 1.0)


func finish() -> void:
	_blend = -1.0
	_fallen_rotations.clear()
	_root_bones.clear()
	_root_positions.clear()


func is_running() -> bool:
	return _blend >= 0.0


func _process_modification_with_delta(_delta : float) -> void:
	if _blend < 0.0:
		return

	var skeleton : Skeleton3D = get_skeleton()

	if skeleton == null:
		return

	var bone_count : int = mini(
		skeleton.get_bone_count(),
		_fallen_rotations.size()
	)

	for bone : int in bone_count:
		skeleton.set_bone_pose_rotation(
			bone,
			_fallen_rotations[bone].slerp(
				skeleton.get_bone_pose_rotation(bone),
				_blend
			)
		)

	for index : int in _root_bones.size():
		var root_bone : int = _root_bones[index]

		if root_bone < 0 or root_bone >= bone_count:
			continue

		skeleton.set_bone_pose_position(
			root_bone,
			_root_positions[index].lerp(
				skeleton.get_bone_pose_position(root_bone),
				_blend
			)
		)
