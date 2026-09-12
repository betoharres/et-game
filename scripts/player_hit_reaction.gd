class_name PlayerHitReaction
extends SkeletonModifier3D

@export_range(0.1, 0.6, 0.01) var duration : float = 0.32
@export_range(0.0, 20.0, 0.5) var recoil_degrees : float = 10.0

var _spine_bone : int = -1
var _head_bone : int = -1
var _elapsed : float = 0.0
var _running : bool = false
var _recoil : Vector3 = Vector3.ZERO
var _start_recoil : Vector3 = Vector3.ZERO
var _target_recoil : Vector3 = Vector3.ZERO


func _ready() -> void:
	var skeleton : Skeleton3D = get_skeleton()
	if skeleton != null:
		_spine_bone = skeleton.find_bone("mixamorig_Spine2")
		_head_bone = skeleton.find_bone("mixamorig_Head")


func trigger(world_direction : Vector3) -> void:
	var skeleton : Skeleton3D = get_skeleton()
	if skeleton == null:
		return

	var direction : Vector3 = skeleton.global_basis.inverse() * world_direction
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		direction = Vector3.FORWARD
	_start_recoil = _recoil
	_target_recoil = Vector3.UP.cross(direction.normalized()) * deg_to_rad(recoil_degrees)
	_elapsed = 0.0
	_running = true


func clear() -> void:
	_running = false
	_recoil = Vector3.ZERO


func is_running() -> bool:
	return _running


func _process_modification_with_delta(delta : float) -> void:
	if not _running:
		return

	_elapsed += delta
	var progress : float = _elapsed / maxf(duration, 0.01)
	if progress >= 1.0:
		clear()
		return

	if progress < 0.12:
		_recoil = _start_recoil.lerp(_target_recoil, smoothstep(0.0, 0.12, progress))
	else:
		_recoil = _target_recoil * (1.0 - smoothstep(0.12, 1.0, progress))
	_apply_recoil(_spine_bone, 1.0)
	_apply_recoil(_head_bone, 0.4)


func _apply_recoil(bone : int, weight : float) -> void:
	var angle : float = _recoil.length() * weight
	if bone < 0 or angle <= 0.00001:
		return

	var skeleton : Skeleton3D = get_skeleton()
	var axis : Vector3 = _recoil.normalized()
	var parent_bone : int = skeleton.get_bone_parent(bone)
	if parent_bone >= 0:
		# Convert the direction into the animated parent's frame; authored turns
		# and character proportions must not change which way the impact bends.
		axis = skeleton.get_bone_global_pose(parent_bone).basis.orthonormalized().inverse() * axis
	skeleton.set_bone_pose_rotation(
		bone,
		Quaternion(axis.normalized(), angle) * skeleton.get_bone_pose_rotation(bone)
	)
