class_name PlayerRagdoll
extends Node

## Physically simulated fall for the ET.
##
## Two entry points share the same rig setup:
##
##   * start_ragdoll() is the permanent death fall;
##   * start_comic_fall() is the exaggerated pratfall used when the balance
##     system in player.gd runs out of balance. It is reversible through
##     stop_ragdoll() followed by apply_recovery(), which blends the skeleton
##     from the fallen pose back to the IK pose.
##
## Entering the ragdoll deactivates every SkeletonModifier3D so IK and LookAt
## stop fighting the simulation. stop_ragdoll() captures the physical pose and
## hands it to RagdollRecoveryModifier for a short blend into Get Up.

const SKELETON_PATH := NodePath("../ET/ETArmature/Skeleton3D")
const ROOT_BONE := "mixamorig_Hips"
const CHEST_BONE := "mixamorig_Spine2"
const HEAD_BONE := "mixamorig_Head"
const LEFT_ARM_BONE := "mixamorig_LeftArm"
const RIGHT_ARM_BONE := "mixamorig_RightArm"
const FOOT_BONES : PackedStringArray = [
	"mixamorig_LeftFoot",
	"mixamorig_RightFoot",
]
const HAND_BONES : PackedStringArray = [
	"mixamorig_LeftHand",
	"mixamorig_RightHand",
]

@export var impact_impulse : float = 0.8

@export_category("Comic Fall")
@export_range(0.0, 20.0, 0.1) var comic_impulse : float = 4.5
@export_range(0.0, 12.0, 0.1) var comic_lift_impulse : float = 2.4
@export_range(0.0, 20.0, 0.1) var comic_sweep_impulse : float = 3.2
@export_range(0.0, 10.0, 0.1) var comic_flail_impulse : float = 1.6

var _skeleton : Skeleton3D
var _simulator : PhysicalBoneSimulator3D
var _physical_bones : Dictionary = {}
var _active : bool = false
var _recovering : bool = false
var _suspended_modifiers : Array[SkeletonModifier3D] = []
var _suspended_influences : PackedFloat32Array = PackedFloat32Array()
var _recovery_modifier : RagdollRecoveryModifier
var _random : RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_random.randomize()
	_skeleton = get_node_or_null(SKELETON_PATH) as Skeleton3D

	if _skeleton == null:
		push_warning("PlayerRagdoll could not find the ET skeleton.")
		return

	for child : Node in _skeleton.get_children():
		if child is RagdollRecoveryModifier:
			_recovery_modifier = child as RagdollRecoveryModifier
			break

	if _recovery_modifier == null:
		push_warning("PlayerRagdoll could not find RagdollRecoveryModifier.")


func start_ragdoll(impact_direction : Vector3 = Vector3.ZERO) -> void:
	if not _enter_ragdoll():
		return

	_start_physics.call_deferred(impact_direction, false, 1.0)


## Exaggerated, recoverable fall. Strength scales the impulses so a barely
## failed balance check tips the ET over and a full-speed crash sends it flying.
func start_comic_fall(impact_direction : Vector3 = Vector3.ZERO,
	strength : float = 1.0) -> void:
	if not _enter_ragdoll():
		return

	_start_physics.call_deferred(
		impact_direction,
		true,
		clampf(strength, 0.2, 2.0)
	)


## Ends the simulation while keeping the fallen pose, so the caller can blend
## back to the standing pose through apply_recovery().
func stop_ragdoll() -> void:
	if not _active or _skeleton == null:
		return

	var fallen_globals : Array[Transform3D] = _capture_fallen_global_poses()

	if _simulator != null:
		_simulator.physical_bones_stop_simulation()
		_skeleton.remove_child(_simulator)
		_simulator.queue_free()
		_simulator = null

	_physical_bones.clear()
	# The IK comes back at full strength right away. What makes the stand up
	# gradual is RagdollRecoveryModifier holding the fallen pose over its output.
	_resume_modifiers()

	var bone_count : int = _skeleton.get_bone_count()
	var fallen_rotations : Array[Quaternion] = []
	fallen_rotations.resize(bone_count)
	var root_bones : PackedInt32Array = PackedInt32Array()
	var root_positions : PackedVector3Array = PackedVector3Array()

	for bone : int in bone_count:
		var parent : int = _skeleton.get_bone_parent(bone)
		var parent_global : Transform3D = Transform3D.IDENTITY

		if parent >= 0:
			parent_global = fallen_globals[parent]

		var local_pose : Transform3D = (
			parent_global.affine_inverse() * fallen_globals[bone]
		)
		fallen_rotations[bone] = local_pose.basis.get_rotation_quaternion()

		# Only the bones without a parent carry the body around; every other
		# bone keeps the position the modifier stack gives it.
		if parent < 0:
			root_bones.append(bone)
			root_positions.append(local_pose.origin)

	if _recovery_modifier != null:
		_recovery_modifier.begin(fallen_rotations, root_bones, root_positions)

	_active = false
	_recovering = true


## Reads the fallen pose from the physical bones instead of from the skeleton.
## Skeleton3D restores the bone poses right after the modifier stack runs, so
## get_bone_global_pose() called from a normal script returns the pose from
## before the simulation, not the ragdoll.
func _capture_fallen_global_poses() -> Array[Transform3D]:
	var bone_count : int = _skeleton.get_bone_count()
	var fallen_globals : Array[Transform3D] = []
	fallen_globals.resize(bone_count)

	var reference : Node3D = _simulator if _simulator != null else _skeleton
	var reference_inverse : Transform3D = (
		reference.global_transform.affine_inverse()
	)

	for bone : int in bone_count:
		var physical_bone : PhysicalBone3D = _physical_bones.get(
			_skeleton.get_bone_name(bone)
		) as PhysicalBone3D

		if physical_bone != null:
			fallen_globals[bone] = (
				reference_inverse
				* physical_bone.global_transform
				* physical_bone.body_offset.affine_inverse()
			)
			continue

		# Bones without a physical body kept the local pose they already had.
		var parent : int = _skeleton.get_bone_parent(bone)
		var parent_global : Transform3D = Transform3D.IDENTITY

		if parent >= 0:
			parent_global = fallen_globals[parent]

		fallen_globals[bone] = parent_global * _skeleton.get_bone_pose(bone)

	return fallen_globals


## Blends the skeleton from the fallen pose (0.0) back to the pose the modifier
## stack produces (1.0). The interpolation itself happens inside
## RagdollRecoveryModifier, which is the only place the posed skeleton exists.
func apply_recovery(ratio : float) -> void:
	if not _recovering:
		return

	var blend : float = clampf(ratio, 0.0, 1.0)

	if _recovery_modifier != null:
		_recovery_modifier.set_blend(blend)

	if blend < 1.0:
		return

	if _recovery_modifier != null:
		_recovery_modifier.finish()

	_recovering = false
	_suspended_modifiers.clear()
	_suspended_influences.clear()


func is_active() -> bool:
	return _active


func is_recovering() -> bool:
	return _recovering


## World position of the hips, used by player.gd to keep the character body and
## the camera following the falling ET.
func get_body_global_position() -> Vector3:
	if _skeleton == null:
		return Vector3.ZERO

	var root_id : int = _skeleton.find_bone(ROOT_BONE)

	if root_id < 0:
		return _skeleton.global_position

	return _skeleton.to_global(_skeleton.get_bone_global_pose(root_id).origin)


## Uses the shoulder/spine plane instead of a single bone axis, which remains
## reliable even when the ragdoll twists individual joints.
func is_face_up() -> bool:
	if _skeleton == null:
		return true

	var left_shoulder : Vector3 = _bone_global_position(LEFT_ARM_BONE)
	var right_shoulder : Vector3 = _bone_global_position(RIGHT_ARM_BONE)
	var hips : Vector3 = _bone_global_position(ROOT_BONE)
	var head : Vector3 = _bone_global_position(HEAD_BONE)
	var shoulder_axis : Vector3 = right_shoulder - left_shoulder
	var spine_axis : Vector3 = head - hips

	if (
		shoulder_axis.length_squared() <= 0.0001
		or spine_axis.length_squared() <= 0.0001
	):
		return true

	var body_front : Vector3 = shoulder_axis.cross(spine_axis).normalized()
	var visual_forward : Vector3 = _skeleton.global_transform.basis.z.normalized()
	if body_front.dot(visual_forward) < 0.0:
		body_front = -body_front
	return body_front.dot(Vector3.UP) >= 0.0


func _bone_global_position(bone_name : String) -> Vector3:
	var physical_bone : PhysicalBone3D = _physical_bones.get(bone_name) as PhysicalBone3D
	if physical_bone != null and is_instance_valid(physical_bone):
		return physical_bone.global_position

	var bone : int = _skeleton.find_bone(bone_name)
	if bone < 0:
		return _skeleton.global_position
	return _skeleton.to_global(_skeleton.get_bone_global_pose(bone).origin)


func _enter_ragdoll() -> bool:
	if _active or _skeleton == null:
		return false

	# Finish a pending recovery first, otherwise the mid-blend influences would
	# be recorded as the originals and the IK would never come back fully.
	apply_recovery(1.0)

	_active = true
	_build_ragdoll()
	_suspend_modifiers()
	return true


func _suspend_modifiers() -> void:
	_suspended_modifiers.clear()
	_suspended_influences.clear()

	for child : Node in _skeleton.get_children():
		if not (child is SkeletonModifier3D) or child == _simulator:
			continue

		if child is RagdollRecoveryModifier:
			continue

		var modifier : SkeletonModifier3D = child as SkeletonModifier3D
		_suspended_modifiers.append(modifier)
		_suspended_influences.append(modifier.influence)
		modifier.active = false


func _resume_modifiers() -> void:
	for index : int in _suspended_modifiers.size():
		var modifier : SkeletonModifier3D = _suspended_modifiers[index]

		if not is_instance_valid(modifier):
			continue

		modifier.influence = _suspended_influences[index]
		modifier.active = true


func _build_ragdoll() -> void:
	_simulator = PhysicalBoneSimulator3D.new()
	_simulator.name = "DeathRagdoll"
	_skeleton.add_child(_simulator)

	_add_sphere_bone(ROOT_BONE, 0.14, 2.4)
	_add_sphere_bone(CHEST_BONE, 0.16, 1.8)
	_add_sphere_bone(HEAD_BONE, 0.14, 0.7)

	_add_capsule_bone(LEFT_ARM_BONE, "mixamorig_LeftForeArm", 0.052, 0.5)
	_add_capsule_bone("mixamorig_LeftForeArm", "mixamorig_LeftHand", 0.045, 0.4)
	_add_sphere_bone("mixamorig_LeftHand", 0.055, 0.25)
	_add_capsule_bone(RIGHT_ARM_BONE, "mixamorig_RightForeArm", 0.052, 0.5)
	_add_capsule_bone("mixamorig_RightForeArm", "mixamorig_RightHand", 0.045, 0.4)
	_add_sphere_bone("mixamorig_RightHand", 0.055, 0.25)

	_add_capsule_bone("mixamorig_LeftUpLeg", "mixamorig_LeftLeg", 0.06, 0.7)
	_add_capsule_bone("mixamorig_LeftLeg", "mixamorig_LeftFoot", 0.052, 0.55)
	_add_sphere_bone("mixamorig_LeftFoot", 0.065, 0.3)
	_add_capsule_bone("mixamorig_RightUpLeg", "mixamorig_RightLeg", 0.06, 0.7)
	_add_capsule_bone("mixamorig_RightLeg", "mixamorig_RightFoot", 0.052, 0.55)
	_add_sphere_bone("mixamorig_RightFoot", 0.065, 0.3)


func _add_sphere_bone(
	bone_name : String,
	radius : float,
	mass : float
) -> void:
	var physical_bone : PhysicalBone3D = _create_physical_bone(bone_name, mass)

	if physical_bone == null:
		return

	var shape : CollisionShape3D = CollisionShape3D.new()
	var sphere : SphereShape3D = SphereShape3D.new()
	sphere.radius = radius
	shape.shape = sphere
	physical_bone.add_child(shape)


func _add_capsule_bone(
	bone_name : String,
	end_bone_name : String,
	radius : float,
	mass : float
) -> void:
	var bone_id : int = _skeleton.find_bone(bone_name)
	var end_bone_id : int = _skeleton.find_bone(end_bone_name)

	if bone_id < 0 or end_bone_id < 0:
		return

	var physical_bone : PhysicalBone3D = _create_physical_bone(bone_name, mass)

	if physical_bone == null:
		return

	var bone_origin : Vector3 = (
		_skeleton.get_bone_global_rest(bone_id).origin
	)
	var end_origin : Vector3 = (
		_skeleton.get_bone_global_rest(end_bone_id).origin
	)
	var segment : Vector3 = end_origin - bone_origin
	var length : float = segment.length()

	if length <= 0.001:
		return

	var body_basis : Basis = _basis_with_y_axis(segment.normalized())
	physical_bone.body_offset = Transform3D(body_basis, segment * 0.5)

	var shape : CollisionShape3D = CollisionShape3D.new()
	var capsule : CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = minf(radius, length * 0.45)
	capsule.height = maxf(length, capsule.radius * 2.0)
	shape.shape = capsule
	physical_bone.add_child(shape)


func _create_physical_bone(
	bone_name : String,
	mass : float
) -> PhysicalBone3D:
	var bone_id : int = _skeleton.find_bone(bone_name)

	if bone_id < 0:
		push_warning("Ragdoll bone not found: %s" % bone_name)
		return null

	var physical_bone : PhysicalBone3D = PhysicalBone3D.new()
	physical_bone.name = "Physical_%s" % bone_name.replace(".", "_")
	physical_bone.mass = mass
	physical_bone.collision_layer = 0
	physical_bone.collision_mask = 1
	_simulator.add_child(physical_bone)
	physical_bone.bone_name = bone_name
	physical_bone.position = _skeleton.get_bone_global_rest(bone_id).origin
	_physical_bones[bone_name] = physical_bone

	if bone_name != ROOT_BONE:
		_configure_joint.call_deferred(physical_bone)

	return physical_bone


func _configure_joint(physical_bone : PhysicalBone3D) -> void:
	if physical_bone.get_bone_id() < 0:
		push_warning("Ragdoll joint could not bind to %s." % physical_bone.bone_name)
		return

	physical_bone.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
	physical_bone.set("joint_constraints/swing_span", 55.0)
	physical_bone.set("joint_constraints/twist_span", 35.0)


func _start_physics(impact_direction : Vector3, comic : bool,
	strength : float) -> void:
	if _simulator == null:
		return

	_simulator.physical_bones_start_simulation()

	if comic:
		_apply_comic_impact.call_deferred(impact_direction, strength)
		return

	if impact_direction.length_squared() > 0.0001:
		var impulse : Vector3 = impact_direction.normalized() * impact_impulse
		_apply_impact.call_deferred(impulse)


func _basis_with_y_axis(y_axis : Vector3) -> Basis:
	var reference_axis : Vector3 = Vector3.FORWARD

	if absf(y_axis.dot(reference_axis)) > 0.95:
		reference_axis = Vector3.RIGHT

	var x_axis : Vector3 = y_axis.cross(reference_axis).normalized()
	var z_axis : Vector3 = x_axis.cross(y_axis).normalized()
	return Basis(x_axis, y_axis, z_axis)


func _apply_impact(impulse : Vector3) -> void:
	var chest : PhysicalBone3D = _physical_bones.get(CHEST_BONE) as PhysicalBone3D

	if chest != null:
		chest.apply_central_impulse(impulse)


## Sweeps the feet out from under the ET while throwing the chest and the head
## the other way, which reads as a pratfall instead of a limp collapse.
func _apply_comic_impact(impact_direction : Vector3, strength : float) -> void:
	var push : Vector3 = Vector3.ZERO

	if impact_direction.length_squared() > 0.0001:
		push = Vector3(impact_direction.x, 0.0, impact_direction.z)

	if push.length_squared() > 0.0001:
		push = push.normalized()
	else:
		push = Vector3(
			_random.randf_range(-1.0, 1.0),
			0.0,
			_random.randf_range(-1.0, 1.0)
		).normalized()

	var chest : PhysicalBone3D = _physical_bones.get(CHEST_BONE) as PhysicalBone3D

	if chest != null:
		chest.apply_central_impulse(
			push * comic_impulse * strength
			+ Vector3.UP * comic_lift_impulse * strength
		)

	var head : PhysicalBone3D = _physical_bones.get(HEAD_BONE) as PhysicalBone3D

	if head != null:
		head.apply_central_impulse(
			(push + Vector3.UP * 0.35).normalized()
			* comic_impulse
			* strength
			* 0.5
		)

	for foot_name : String in FOOT_BONES:
		var foot : PhysicalBone3D = _physical_bones.get(foot_name) as PhysicalBone3D

		if foot == null:
			continue

		foot.apply_central_impulse(
			(-push + Vector3.UP * 0.9).normalized()
			* comic_sweep_impulse
			* strength
			* _random.randf_range(0.7, 1.3)
		)

	for hand_name : String in HAND_BONES:
		var hand : PhysicalBone3D = _physical_bones.get(hand_name) as PhysicalBone3D

		if hand == null:
			continue

		hand.apply_central_impulse(
			_random_flail_direction() * comic_flail_impulse * strength
		)


func _random_flail_direction() -> Vector3:
	var direction : Vector3 = Vector3(
		_random.randf_range(-1.0, 1.0),
		_random.randf_range(0.3, 1.0),
		_random.randf_range(-1.0, 1.0)
	)

	if direction.length_squared() <= 0.0001:
		return Vector3.UP

	return direction.normalized()
