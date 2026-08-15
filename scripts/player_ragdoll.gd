extends Node

const SKELETON_PATH := NodePath("../ET/Armature/Skeleton3D")
const LEFT_HIP_BONE := "Hips.L"
const RIGHT_HIP_BONE := "Hips.R"
const ROOT_BONE := "HipsRoot"

@export var impact_impulse : float = 0.8

var _skeleton : Skeleton3D
var _simulator : PhysicalBoneSimulator3D
var _physical_bones : Dictionary = {}
var _active : bool = false


func _ready() -> void:
	_skeleton = get_node_or_null(SKELETON_PATH) as Skeleton3D

	if _skeleton == null:
		push_warning("PlayerRagdoll could not find the ET skeleton.")


func start_ragdoll(impact_direction : Vector3 = Vector3.ZERO) -> void:
	if _active or _skeleton == null:
		return

	_active = true
	_connect_leg_roots()
	_build_ragdoll()

	for child : Node in _skeleton.get_children():
		if child is SkeletonModifier3D and child != _simulator:
			(child as SkeletonModifier3D).active = false

	_start_physics.call_deferred(impact_direction)


func is_active() -> bool:
	return _active


func _connect_leg_roots() -> void:
	var root_id : int = _skeleton.find_bone(ROOT_BONE)

	if root_id < 0:
		return

	for hip_name : String in [LEFT_HIP_BONE, RIGHT_HIP_BONE]:
		var hip_id : int = _skeleton.find_bone(hip_name)

		if hip_id < 0 or _skeleton.get_bone_parent(hip_id) == root_id:
			continue

		var global_rest : Transform3D = _skeleton.get_bone_global_rest(hip_id)
		var global_pose : Transform3D = _skeleton.get_bone_global_pose(hip_id)
		var parent_global_rest : Transform3D = (
			_skeleton.get_bone_global_rest(root_id)
		)
		var parent_global_pose : Transform3D = (
			_skeleton.get_bone_global_pose(root_id)
		)
		_skeleton.set_bone_parent(hip_id, root_id)
		_skeleton.set_bone_rest(
			hip_id,
			parent_global_rest.affine_inverse() * global_rest
		)
		_skeleton.set_bone_pose(
			hip_id,
			parent_global_pose.affine_inverse() * global_pose
		)


func _build_ragdoll() -> void:
	_simulator = PhysicalBoneSimulator3D.new()
	_simulator.name = "DeathRagdoll"
	_skeleton.add_child(_simulator)

	_add_sphere_bone(ROOT_BONE, 0.14, 2.4)
	_add_sphere_bone("Chest", 0.16, 1.8)
	_add_sphere_bone("Head", 0.14, 0.7)

	_add_capsule_bone("Arm.L", "Forearm.L", 0.052, 0.5)
	_add_capsule_bone("Forearm.L", "Hand.L", 0.045, 0.4)
	_add_sphere_bone("Hand.L", 0.055, 0.25)
	_add_capsule_bone("Arm.R", "Forearm.R", 0.052, 0.5)
	_add_capsule_bone("Forearm.R", "Hand.R", 0.045, 0.4)
	_add_sphere_bone("Hand.R", 0.055, 0.25)

	_add_sphere_bone(LEFT_HIP_BONE, 0.075, 0.45)
	_add_capsule_bone("Femur.L", "Shin.L", 0.06, 0.7)
	_add_capsule_bone("Shin.L", "Foot.L", 0.052, 0.55)
	_add_sphere_bone("Foot.L", 0.065, 0.3)
	_add_sphere_bone(RIGHT_HIP_BONE, 0.075, 0.45)
	_add_capsule_bone("Femur.R", "Shin.R", 0.06, 0.7)
	_add_capsule_bone("Shin.R", "Foot.R", 0.052, 0.55)
	_add_sphere_bone("Foot.R", 0.065, 0.3)


func _add_sphere_bone(
	bone_name : String,
	radius : float,
	mass : float
) -> void:
	var physical_bone := _create_physical_bone(bone_name, mass)

	if physical_bone == null:
		return

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
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

	var physical_bone := _create_physical_bone(bone_name, mass)

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

	var body_basis := _basis_with_y_axis(segment.normalized())
	physical_bone.body_offset = Transform3D(body_basis, segment * 0.5)

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
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

	var physical_bone := PhysicalBone3D.new()
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


func _start_physics(impact_direction : Vector3) -> void:
	if _simulator == null:
		return

	_simulator.physical_bones_start_simulation()

	if impact_direction.length_squared() > 0.0001:
		var impulse := impact_direction.normalized() * impact_impulse
		_apply_impact.call_deferred(impulse)


func _basis_with_y_axis(y_axis : Vector3) -> Basis:
	var reference_axis := Vector3.FORWARD

	if absf(y_axis.dot(reference_axis)) > 0.95:
		reference_axis = Vector3.RIGHT

	var x_axis : Vector3 = y_axis.cross(reference_axis).normalized()
	var z_axis : Vector3 = x_axis.cross(y_axis).normalized()
	return Basis(x_axis, y_axis, z_axis)


func _apply_impact(impulse : Vector3) -> void:
	var chest := _physical_bones.get("Chest") as PhysicalBone3D

	if chest != null:
		chest.apply_central_impulse(impulse)
