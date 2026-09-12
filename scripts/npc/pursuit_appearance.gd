class_name PursuitAppearance
extends Node3D

const LASER_SHOT_DURATION: float = 0.14

var muzzle: Marker3D
var _skeleton: Skeleton3D
var _weapon: Node3D
var _flash: OmniLight3D
var _tracer: MeshInstance3D
var _tracer_material: StandardMaterial3D
var _flash_time: float = 0.0
var _stride: float = 0.0
var _motion_weight: float = 0.0
var _bones: Dictionary[StringName, int] = {}

@onready var _npc: PursuitNPC = get_parent() as PursuitNPC


func _ready() -> void:
	var profile: PursuitProfile = _npc.profile
	var model: Node3D = profile.character_scene.instantiate() as Node3D
	add_child(model)
	_skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		mesh.material_override = profile.character_material
		mesh.layers = 16
	for bone_name: StringName in [&"Thigh_L", &"Thigh_R", &"calf_l", &"calf_r", &"UpperArm_L", &"UpperArm_R", &"lowerarm_l", &"lowerarm_r", &"Hand_L", &"Hand_R"]:
		_bones[bone_name] = _skeleton.find_bone(bone_name)
	_weapon = Node3D.new()
	_weapon.name = "Weapon"
	_weapon.position = Vector3(-0.18, 1.22, 0.36)
	add_child(_weapon)
	var weapon_mesh: MeshInstance3D = MeshInstance3D.new()
	weapon_mesh.mesh = profile.weapon_mesh
	weapon_mesh.material_override = profile.weapon_material
	weapon_mesh.layers = 16
	_weapon.add_child(weapon_mesh)
	muzzle = Marker3D.new()
	muzzle.position = profile.muzzle_offset
	_weapon.add_child(muzzle)
	_flash = OmniLight3D.new()
	_flash.light_color = profile.shot_color
	_flash.light_energy = 2.0
	_flash.omni_range = 3.0
	_flash.visible = false
	muzzle.add_child(_flash)
	var beam: CylinderMesh = CylinderMesh.new()
	beam.top_radius = 0.012
	beam.bottom_radius = 0.012
	beam.height = 1.0
	beam.radial_segments = 6
	_tracer_material = StandardMaterial3D.new()
	_tracer_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tracer_material.albedo_color = profile.shot_color
	_tracer_material.emission_enabled = true
	_tracer_material.emission = profile.shot_color
	_tracer_material.emission_energy_multiplier = 3.0
	if profile.laser_shots:
		_tracer_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_tracer = MeshInstance3D.new()
	_tracer.mesh = beam
	_tracer.material_override = _tracer_material
	_tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_tracer)
	_tracer.top_level = true
	_tracer.visible = false


func _process(delta: float) -> void:
	_flash_time = maxf(_flash_time - delta, 0.0)
	_flash.visible = _flash_time > 0.0
	_tracer.visible = _flash_time > 0.0
	if _npc.profile.laser_shots:
		_tracer_material.albedo_color.a = clampf(_flash_time / LASER_SHOT_DURATION, 0.0, 1.0)
	if _npc.vision != null and _npc.vision.is_currently_visible and _npc.is_player_alive():
		var target: Vector3 = _npc.player.global_position + Vector3.UP * _npc.vision.player_target_height
		var local_target: Vector3 = to_local(target) - _weapon.position
		_weapon.rotation.x = -atan2(local_target.y, Vector2(local_target.x, local_target.z).length())
	else:
		_weapon.rotation.x = 0.0
	var speed: float = Vector2(_npc.get_real_velocity().x, _npc.get_real_velocity().z).length()
	_motion_weight = move_toward(_motion_weight, minf(speed / 2.0, 1.0), delta * 6.0)
	_stride += delta * maxf(speed, 1.0) * 3.0
	# Estes SK_Character usam ossos/eixos em centímetros, incompatíveis com os
	# clipes Synty em metros. A pose armada usa o rest original, sem retarget cego.
	for bone: int in _bones.values():
		if bone >= 0:
			_skeleton.set_bone_pose_rotation(bone, _skeleton.get_bone_rest(bone).basis.get_rotation_quaternion())
	for side: int in range(2):
		var phase: float = _stride + PI * side
		_rotate_bone(_bones[&"Thigh_L" if side == 0 else &"Thigh_R"], sin(phase) * 0.42 * _motion_weight)
		_rotate_bone(_bones[&"calf_l" if side == 0 else &"calf_r"], maxf(-sin(phase), 0.0) * 0.7 * _motion_weight)
	_pose_arm(&"UpperArm_R", &"lowerarm_r", &"Hand_R", _weapon.global_position, Vector3(-1.0, -1.0, 0.0))
	_pose_arm(&"UpperArm_L", &"lowerarm_l", &"Hand_L", _weapon.to_global(_npc.profile.support_hand_offset), Vector3(1.0, -1.0, 0.0))


func show_shot(end: Vector3) -> void:
	var start: Vector3 = muzzle.global_position
	var direction: Vector3 = end - start
	if direction.length_squared() < 0.0001:
		return
	_tracer.global_transform = Transform3D(
		Basis(Quaternion(Vector3.UP, direction.normalized())).scaled_local(Vector3(1.0, direction.length(), 1.0)),
		(start + end) * 0.5
	)
	_flash_time = LASER_SHOT_DURATION if _npc.profile.laser_shots else 0.075
	_tracer_material.albedo_color = _npc.profile.shot_color
	_flash.visible = true
	_tracer.visible = true


func _rotate_bone(bone: int, angle: float) -> void:
	if bone < 0:
		return
	_set_global_basis(bone, Basis(Vector3.RIGHT, angle) * _skeleton.get_bone_global_pose(bone).basis)


func _pose_arm(upper_name: StringName, lower_name: StringName, hand_name: StringName, goal: Vector3, bend: Vector3) -> void:
	var upper: int = _bones[upper_name]
	var lower: int = _bones[lower_name]
	var hand: int = _bones[hand_name]
	if mini(upper, mini(lower, hand)) < 0:
		return
	var shoulder: Vector3 = _skeleton.get_bone_global_pose(upper).origin
	var elbow: Vector3 = _skeleton.get_bone_global_pose(lower).origin
	var wrist: Vector3 = _skeleton.get_bone_global_pose(hand).origin
	var target: Vector3 = _skeleton.to_local(goal)
	var upper_length: float = shoulder.distance_to(elbow)
	var lower_length: float = elbow.distance_to(wrist)
	var distance: float = clampf(shoulder.distance_to(target), 0.01, upper_length + lower_length - 0.01)
	var direction: Vector3 = (target - shoulder).normalized()
	var along: float = (upper_length * upper_length - lower_length * lower_length + distance * distance) / (2.0 * distance)
	var perpendicular: Vector3 = bend.slide(direction).normalized()
	var joint: Vector3 = shoulder + direction * along + perpendicular * sqrt(maxf(upper_length * upper_length - along * along, 0.0))
	_point_bone(upper, lower, joint)
	_point_bone(lower, hand, target)


func _point_bone(bone: int, child: int, target: Vector3) -> void:
	var pose: Transform3D = _skeleton.get_bone_global_pose(bone)
	var from: Vector3 = (_skeleton.get_bone_global_pose(child).origin - pose.origin).normalized()
	var to: Vector3 = (target - pose.origin).normalized()
	_set_global_basis(bone, Basis(Quaternion(from, to)) * pose.basis)


func _set_global_basis(bone: int, basis: Basis) -> void:
	var parent: int = _skeleton.get_bone_parent(bone)
	var parent_basis: Basis = _skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	_skeleton.set_bone_pose_rotation(bone, (parent_basis.inverse() * basis).orthonormalized().get_rotation_quaternion())
