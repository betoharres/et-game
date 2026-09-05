extends SkeletonModifier3D

const EYE_SHADER : Shader = preload("res://shaders/character_eyes.gdshader")
const BODY_SHADER : Shader = preload("res://shaders/character_body.gdshader")
const BELLY_SHADER : Shader = preload("res://shaders/character_belly.gdshader")
const FEATURE_DEFAULT : float = 0.5
const LEG_GROUND_OFFSET : float = 0.42
const BELLY_LATITUDE_SEGMENTS : int = 18
const BELLY_ARC_SEGMENTS : int = 36
const BELLY_BACK_DEPTH : float = 0.18
const BELLY_LEGACY_MAX_INPUT : float = 0.86

const DEFAULT_PROFILE : Dictionary = {
	"head_size": FEATURE_DEFAULT,
	"belly_size": FEATURE_DEFAULT,
	"leg_length": FEATURE_DEFAULT,
	"arm_length": FEATURE_DEFAULT,
	"shoulder_width": FEATURE_DEFAULT,
	"overall_height": FEATURE_DEFAULT,
	"eye_size": FEATURE_DEFAULT,
}

const BONE_ALIASES : Dictionary = {
	"hips": ["mixamorig_Hips", "HipsRoot"],
	"head": ["mixamorig_Head", "Head"],
	"neck": ["mixamorig_Neck", "Neck"],
	"belly": ["mixamorig_Spine", "Stomach"],
	"chest": ["mixamorig_Spine1", "Ribs"],
	"upper_chest": ["mixamorig_Spine2", "Chest"],
	"left_shoulder": ["mixamorig_LeftShoulder", "Shoulder.L"],
	"right_shoulder": ["mixamorig_RightShoulder", "Shoulder.R"],
	"left_arm": ["mixamorig_LeftArm", "Arm.L"],
	"right_arm": ["mixamorig_RightArm", "Arm.R"],
	"left_forearm": ["mixamorig_LeftForeArm", "Forearm.L"],
	"right_forearm": ["mixamorig_RightForeArm", "Forearm.R"],
	"left_hand": ["mixamorig_LeftHand", "Hand.L"],
	"right_hand": ["mixamorig_RightHand", "Hand.R"],
	"left_leg": ["mixamorig_LeftUpLeg", "Femur.L"],
	"right_leg": ["mixamorig_RightUpLeg", "Femur.R"],
	"left_lower_leg": ["mixamorig_LeftLeg", "Shin.L"],
	"right_lower_leg": ["mixamorig_RightLeg", "Shin.R"],
	"left_foot": ["mixamorig_LeftFoot", "Foot.L"],
	"right_foot": ["mixamorig_RightFoot", "Foot.R"],
}

@export var use_saved_appearance : bool = true
@export var keep_feet_grounded : bool = true
@export var visual_root_path : NodePath = NodePath("../../..")
@export var character_mesh_path : NodePath = NodePath("../ET")

var _profile : Dictionary = DEFAULT_PROFILE.duplicate(true)
var _bone_ids : Dictionary = {}
var _visual_root : Node3D
var _character_mesh : MeshInstance3D
var _base_visual_scale : Vector3 = Vector3.ONE
var _base_visual_position : Vector3 = Vector3.ZERO
var _body_material : ShaderMaterial
var _eye_material : ShaderMaterial
var _belly_attachment : BoneAttachment3D
var _belly_mesh_instance : MeshInstance3D
var _belly_material : ShaderMaterial


func _ready() -> void:
	_visual_root = get_node_or_null(visual_root_path) as Node3D
	_character_mesh = get_node_or_null(character_mesh_path) as MeshInstance3D
	if _visual_root != null:
		_base_visual_scale = _visual_root.scale
		_base_visual_position = _visual_root.position
	_cache_bones()
	_setup_body_material()
	_setup_eye_material()
	_setup_procedural_belly.call_deferred()

	if use_saved_appearance:
		var appearance : Node = get_node_or_null("/root/CharacterAppearance")
		if appearance != null and appearance.has_method("get_profile"):
			_profile = _sanitize_profile(appearance.call("get_profile") as Dictionary)
			appearance.connect("appearance_changed", _on_global_appearance_changed)
	_apply_static_visuals()


func set_profile(profile : Dictionary, follow_global_profile : bool = false) -> void:
	use_saved_appearance = follow_global_profile
	_profile = _sanitize_profile(profile)
	_apply_static_visuals()


func get_profile() -> Dictionary:
	return _profile.duplicate(true)


func get_collision_height_factor() -> float:
	var height_factor : float = _feature_factor("overall_height", 0.82, 1.18)
	var leg_factor : float = _feature_factor("leg_length", 0.75, 1.25)
	var head_factor : float = _feature_factor("head_size", 0.70, 1.30)
	return height_factor * (1.0 + (leg_factor - 1.0) * 0.40 + (head_factor - 1.0) * 0.16)


func _on_global_appearance_changed(profile : Dictionary) -> void:
	if use_saved_appearance:
		_profile = _sanitize_profile(profile)
		_apply_static_visuals()


func _sanitize_profile(profile : Dictionary) -> Dictionary:
	var sanitized : Dictionary = {}
	for key : String in DEFAULT_PROFILE:
		var raw_value : Variant = profile.get(key, FEATURE_DEFAULT)
		var value : float = float(raw_value) if raw_value is float or raw_value is int else FEATURE_DEFAULT
		sanitized[key] = clampf(value, 0.0, 1.0)
	return sanitized


## Keeps the middle of every slider gentle while leaving playful extremes at
## both ends. All factors evaluate to exactly 1.0 at the normalized default.
func _feature_factor(key : String, minimum : float, maximum : float) -> float:
	var value : float = float(_profile.get(key, FEATURE_DEFAULT))
	var distance : float = absf(value - 0.5) * 2.0
	var shaped_distance : float = pow(distance, 1.25)
	if value < 0.5:
		return 1.0 - shaped_distance * (1.0 - minimum)
	return 1.0 + shaped_distance * (maximum - 1.0)


## The profile remains normalized from 0 to 1, but the upper half is visually
## remapped so the new maximum matches the previous, readable 86% silhouette.
## This avoids a dead zone while preventing the unstable old final extreme.
func _limited_belly_input() -> float:
	var value : float = float(_profile.get("belly_size", FEATURE_DEFAULT))
	if value <= FEATURE_DEFAULT:
		return value
	var upper_amount : float = (value - FEATURE_DEFAULT) / (1.0 - FEATURE_DEFAULT)
	return lerpf(FEATURE_DEFAULT, BELLY_LEGACY_MAX_INPUT, upper_amount)


func _fat_exaggeration() -> float:
	var value : float = _limited_belly_input()
	if value <= 0.5:
		return 0.0
	if value <= 0.8:
		var moderate : float = (value - 0.5) / 0.3
		return 0.34 * pow(moderate, 1.6)
	var extreme : float = (value - 0.8) / 0.2
	return 0.34 + 0.66 * pow(extreme, 1.45)


## Posture starts reacting earlier than the grotesque mesh growth. This keeps
## 0.5 practically authored, makes 0.6-0.8 readable, and reserves the broad
## arm arc for the last fifth of the slider.
func _fat_posture_amount() -> float:
	var value : float = _limited_belly_input()
	if value <= 0.5:
		return 0.0
	if value <= 0.8:
		var moderate : float = (value - 0.5) / 0.3
		return 0.48 * pow(moderate, 1.25)
	var extreme : float = (value - 0.8) / 0.2
	return 0.48 + 0.52 * pow(extreme, 1.35)


func _cache_bones() -> void:
	var skeleton : Skeleton3D = get_skeleton()
	if skeleton == null:
		return
	for role : String in BONE_ALIASES:
		var bone_index : int = -1
		var aliases : Array = BONE_ALIASES[role] as Array
		for alias_value : Variant in aliases:
			var alias : String = String(alias_value)
			bone_index = skeleton.find_bone(alias)
			if bone_index >= 0:
				break
		_bone_ids[role] = bone_index


func _setup_eye_material() -> void:
	if _character_mesh == null or _character_mesh.mesh == null:
		return

	var eye_surface : int = -1
	for surface_index : int in _character_mesh.mesh.get_surface_count():
		var material : Material = _character_mesh.mesh.surface_get_material(surface_index)
		if material != null and material.resource_name.to_lower() == "eyes":
			eye_surface = surface_index
			break
	if eye_surface < 0 and _character_mesh.mesh.get_surface_count() > 1:
		eye_surface = 1
	if eye_surface < 0:
		return

	_eye_material = ShaderMaterial.new()
	_eye_material.shader = EYE_SHADER
	_character_mesh.set_surface_override_material(eye_surface, _eye_material)


func _setup_body_material() -> void:
	if _character_mesh == null or _character_mesh.mesh == null:
		return

	var body_surface : int = -1
	for surface_index : int in _character_mesh.mesh.get_surface_count():
		var material : Material = _character_mesh.mesh.surface_get_material(surface_index)
		if material != null and material.resource_name.to_lower() == "skin":
			body_surface = surface_index
			break
	if body_surface < 0 and _character_mesh.mesh.get_surface_count() > 0:
		body_surface = 0
	if body_surface < 0:
		return

	var skin_color : Color = Color(0.68, 0.68, 0.68, 1.0)
	var source_material : Material = _character_mesh.get_active_material(body_surface)
	if source_material is BaseMaterial3D:
		var base_material : BaseMaterial3D = source_material as BaseMaterial3D
		skin_color = base_material.albedo_color

	_body_material = ShaderMaterial.new()
	_body_material.shader = BODY_SHADER
	_body_material.set_shader_parameter("skin_albedo", skin_color)
	_character_mesh.set_surface_override_material(body_surface, _body_material)


func _setup_procedural_belly() -> void:
	var skeleton : Skeleton3D = get_skeleton()
	var belly_bone : int = int(_bone_ids.get("belly", -1))
	if skeleton == null or belly_bone < 0:
		return

	_belly_attachment = BoneAttachment3D.new()
	_belly_attachment.name = "ProceduralBellyAttachment"
	_belly_attachment.bone_name = skeleton.get_bone_name(belly_bone)
	_belly_attachment.position = Vector3(0.0, -0.035, 0.014)
	skeleton.add_child(_belly_attachment)

	_belly_mesh_instance = MeshInstance3D.new()
	_belly_mesh_instance.name = "ProceduralBelly"
	_belly_mesh_instance.mesh = _build_belly_dome_mesh()
	_belly_mesh_instance.layers = _character_mesh.layers
	_belly_mesh_instance.transparency = 0.0
	_belly_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_belly_attachment.add_child(_belly_mesh_instance)

	var skin_color : Color = Color(0.68, 0.68, 0.68, 1.0)
	if _body_material != null:
		var shader_color : Variant = _body_material.get_shader_parameter("skin_albedo")
		if shader_color is Color:
			skin_color = shader_color as Color
	skin_color.a = 1.0
	_belly_material = ShaderMaterial.new()
	_belly_material.shader = BELLY_SHADER
	_belly_material.set_shader_parameter("skin_albedo", skin_color)
	_belly_mesh_instance.set_surface_override_material(0, _belly_material)
	_update_procedural_belly()


func _build_belly_dome_mesh() -> ArrayMesh:
	var surface_tool : SurfaceTool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	for latitude : int in BELLY_LATITUDE_SEGMENTS:
		var phi_top : float = PI * float(latitude) / float(BELLY_LATITUDE_SEGMENTS)
		var phi_bottom : float = PI * float(latitude + 1) / float(BELLY_LATITUDE_SEGMENTS)
		for arc : int in BELLY_ARC_SEGMENTS:
			var theta_left : float = TAU * float(arc) / float(BELLY_ARC_SEGMENTS)
			var theta_right : float = TAU * float(arc + 1) / float(BELLY_ARC_SEGMENTS)
			var top_left : Vector3 = _belly_dome_point(phi_top, theta_left)
			var top_right : Vector3 = _belly_dome_point(phi_top, theta_right)
			var bottom_left : Vector3 = _belly_dome_point(phi_bottom, theta_left)
			var bottom_right : Vector3 = _belly_dome_point(phi_bottom, theta_right)

			_add_belly_triangle(
				surface_tool,
				top_left,
				bottom_right,
				bottom_left
			)
			_add_belly_triangle(
				surface_tool,
				top_left,
				top_right,
				bottom_right
			)

	return surface_tool.commit()


func _belly_dome_point(phi : float, theta : float) -> Vector3:
	var sine_phi : float = sin(phi)
	var point : Vector3 = Vector3(
		sine_phi * cos(theta),
		cos(phi),
		sine_phi * sin(theta)
	)
	# The rear half closes the dome but remains shallow enough to stay embedded
	# inside the animated torso instead of creating a second back silhouette.
	if point.z < 0.0:
		point.z *= BELLY_BACK_DEPTH
	# More mass below the center gives a hanging alien belly, while the top
	# stays tucked under the chest instead of becoming another sphere.
	if point.y < 0.0:
		var lower_weight : float = -point.y
		point.x *= 1.0 + lower_weight * 0.08
		point.z *= 1.0 + lower_weight * 0.28
		point.y *= 1.08
	else:
		point.z *= 1.0 - point.y * 0.12
	return point


func _add_belly_triangle(surface_tool : SurfaceTool, first : Vector3,
	second : Vector3, third : Vector3) -> void:
	var normal_cross : Vector3 = (second - first).cross(third - first)
	if normal_cross.length_squared() < 0.000001:
		return
	for vertex : Vector3 in [first, second, third]:
		surface_tool.set_normal(_belly_smooth_normal(vertex))
		surface_tool.set_uv(Vector2(vertex.x * 0.5 + 0.5, vertex.y * -0.5 + 0.5))
		surface_tool.add_vertex(vertex)


func _belly_smooth_normal(vertex : Vector3) -> Vector3:
	var normal_source : Vector3 = vertex
	if normal_source.z < 0.0:
		normal_source.z /= BELLY_BACK_DEPTH * BELLY_BACK_DEPTH
	if normal_source.y < 0.0:
		normal_source.x /= 1.08 * 1.08
		normal_source.z /= 1.28 * 1.28
		normal_source.y /= 1.08 * 1.08
	elif normal_source.y > 0.0:
		normal_source.z /= 0.88 * 0.88
	return normal_source.normalized()


func _update_procedural_belly() -> void:
	if _belly_mesh_instance == null:
		return
	var fat_amount : float = _fat_exaggeration()
	_belly_mesh_instance.visible = fat_amount > 0.008
	if not _belly_mesh_instance.visible:
		return

	var extreme_depth : float = pow(fat_amount, 1.12)
	_belly_mesh_instance.scale = Vector3(
		lerpf(0.066, 0.145, fat_amount),
		lerpf(0.080, 0.190, fat_amount),
		lerpf(0.024, 0.235, extreme_depth)
	)
	_belly_attachment.position.y = -0.025 - fat_amount * 0.040
	_belly_attachment.position.z = 0.012
	if _belly_material != null:
		_belly_material.set_shader_parameter("fat_amount", fat_amount)


func _apply_static_visuals() -> void:
	var height_factor : float = _feature_factor("overall_height", 0.82, 1.18)
	var leg_factor : float = _feature_factor("leg_length", 0.75, 1.25)
	if _visual_root != null:
		_visual_root.scale = _base_visual_scale * Vector3(1.0, height_factor, 1.0)
		_visual_root.position = _base_visual_position
		if keep_feet_grounded:
			_visual_root.position.y += LEG_GROUND_OFFSET * height_factor * (leg_factor - 1.0)
	if _eye_material != null:
		_eye_material.set_shader_parameter(
			"eye_scale",
			_feature_factor("eye_size", 0.62, 1.38)
		)
	if _body_material != null:
		_body_material.set_shader_parameter("fat_amount", _fat_exaggeration())
	_update_procedural_belly()


func _apply_bone_scale(role : String, scale_multiplier : Vector3) -> void:
	var skeleton : Skeleton3D = get_skeleton()
	var bone_index : int = int(_bone_ids.get(role, -1))
	if skeleton == null or bone_index < 0:
		return
	skeleton.set_bone_pose_scale(
		bone_index,
		skeleton.get_bone_pose_scale(bone_index) * scale_multiplier
	)


## Adds a skeleton-space rotation to the animation pose already evaluated for
## this frame. Converting the axis through parent global pose and bone rest
## keeps "outward" and "forward" stable even while an animation turns a limb.
func _apply_skeleton_axis_rotation(role : String, skeleton_axis : Vector3,
	angle_radians : float) -> void:
	if is_zero_approx(angle_radians):
		return
	var skeleton : Skeleton3D = get_skeleton()
	var bone_index : int = int(_bone_ids.get(role, -1))
	if skeleton == null or bone_index < 0:
		return

	var parent_basis : Basis = Basis.IDENTITY
	var parent_bone : int = skeleton.get_bone_parent(bone_index)
	if parent_bone >= 0:
		parent_basis = skeleton.get_bone_global_pose(parent_bone).basis
	var pose_base_basis : Basis = parent_basis * skeleton.get_bone_rest(bone_index).basis
	var local_axis : Vector3 = pose_base_basis.inverse() * skeleton_axis.normalized()
	if local_axis.is_zero_approx():
		return

	var offset : Quaternion = Quaternion(local_axis.normalized(), angle_radians)
	var animated_rotation : Quaternion = skeleton.get_bone_pose_rotation(bone_index)
	skeleton.set_bone_pose_rotation(
		bone_index,
		(offset * animated_rotation).normalized()
	)


func _apply_fat_arm_posture(posture_amount : float) -> void:
	if posture_amount <= 0.0:
		return

	# Front is +Z on both ET rigs. Positive Z rotation opens the left arm;
	# the right side mirrors the sign. X rotation moves both hands slightly
	# forward so they rest beside, rather than inside, the abdominal dome.
	var shoulder_open : float = deg_to_rad(4.0) * posture_amount
	var arm_open : float = deg_to_rad(18.0) * posture_amount
	var arm_forward : float = deg_to_rad(-7.0) * posture_amount
	var elbow_open : float = deg_to_rad(9.0) * posture_amount
	var elbow_forward : float = deg_to_rad(-4.0) * posture_amount
	var hand_relax : float = deg_to_rad(7.0) * posture_amount
	var torso_lean : float = deg_to_rad(-4.0) * pow(posture_amount, 1.7)

	_apply_skeleton_axis_rotation("upper_chest", Vector3.RIGHT, torso_lean)
	_apply_skeleton_axis_rotation("left_shoulder", Vector3.BACK, shoulder_open)
	_apply_skeleton_axis_rotation("right_shoulder", Vector3.BACK, -shoulder_open)
	_apply_skeleton_axis_rotation("left_arm", Vector3.BACK, arm_open)
	_apply_skeleton_axis_rotation("right_arm", Vector3.BACK, -arm_open)
	_apply_skeleton_axis_rotation("left_arm", Vector3.RIGHT, arm_forward)
	_apply_skeleton_axis_rotation("right_arm", Vector3.RIGHT, arm_forward)
	_apply_skeleton_axis_rotation("left_forearm", Vector3.BACK, elbow_open)
	_apply_skeleton_axis_rotation("right_forearm", Vector3.BACK, -elbow_open)
	_apply_skeleton_axis_rotation("left_forearm", Vector3.RIGHT, elbow_forward)
	_apply_skeleton_axis_rotation("right_forearm", Vector3.RIGHT, elbow_forward)
	_apply_skeleton_axis_rotation("left_hand", Vector3.BACK, -hand_relax)
	_apply_skeleton_axis_rotation("right_hand", Vector3.BACK, hand_relax)


func _bone_is_direct_child(child_role : String, parent_role : String) -> bool:
	var skeleton : Skeleton3D = get_skeleton()
	var child_bone : int = int(_bone_ids.get(child_role, -1))
	var parent_bone : int = int(_bone_ids.get(parent_role, -1))
	return (
		skeleton != null
		and child_bone >= 0
		and parent_bone >= 0
		and skeleton.get_bone_parent(child_bone) == parent_bone
	)


func _process_modification_with_delta(_delta : float) -> void:
	var head_factor : float = _feature_factor("head_size", 0.70, 1.30)
	var leg_factor : float = _feature_factor("leg_length", 0.75, 1.25)
	var arm_factor : float = _feature_factor("arm_length", 0.74, 1.26)
	var shoulder_factor : float = _feature_factor("shoulder_width", 0.78, 1.22)
	var belly_value : float = float(_profile.get("belly_size", FEATURE_DEFAULT))
	var fat_amount : float = _fat_exaggeration()
	var posture_amount : float = _fat_posture_amount()

	var abdomen_side : float = 1.0 + fat_amount * 0.34
	var abdomen_depth : float = 1.0 + fat_amount * 0.38
	if belly_value < 0.5:
		var slim_factor : float = _feature_factor("belly_size", 0.72, 1.0)
		abdomen_side = slim_factor
		abdomen_depth = slim_factor

	var chest_side : float = 1.0 + fat_amount * 0.18
	var chest_depth : float = 1.0 + fat_amount * 0.24
	var hip_side : float = 1.0 + fat_amount * 0.28
	var hip_depth : float = 1.0 + fat_amount * 0.30
	var neck_thickness : float = 1.0 + fat_amount * 0.30
	var arm_thickness : float = 1.0 + fat_amount * 0.36
	var thigh_thickness : float = 1.0 + fat_amount * 0.48
	var extremity_scale : float = 1.0 - fat_amount * 0.16

	# Each torso section grows independently. Inverse scale on the next bone
	# stops the deformation from propagating into the whole upper body.
	_apply_bone_scale("hips", Vector3(hip_side, 1.0, hip_depth))
	_apply_bone_scale(
		"belly",
		Vector3(abdomen_side / hip_side, 1.0, abdomen_depth / hip_depth)
	)
	_apply_bone_scale(
		"chest",
		Vector3(chest_side / abdomen_side, 1.0, chest_depth / abdomen_depth)
	)
	_apply_bone_scale(
		"upper_chest",
		Vector3(1.0 / chest_side, 1.0, 1.0 / chest_depth)
	)
	_apply_bone_scale("neck", Vector3(neck_thickness, 1.0, neck_thickness))
	_apply_bone_scale(
		"head",
		Vector3(
			head_factor / neck_thickness,
			head_factor,
			head_factor / neck_thickness
		)
	)

	var fat_shoulder_width : float = 1.0 + posture_amount * 0.14
	_apply_bone_scale(
		"left_shoulder",
		Vector3(1.0, shoulder_factor * fat_shoulder_width, 1.0)
	)
	_apply_bone_scale(
		"right_shoulder",
		Vector3(1.0, shoulder_factor * fat_shoulder_width, 1.0)
	)
	_apply_bone_scale(
		"left_arm",
		Vector3(arm_thickness, arm_factor, arm_thickness)
	)
	_apply_bone_scale(
		"right_arm",
		Vector3(arm_thickness, arm_factor, arm_thickness)
	)
	_apply_bone_scale(
		"left_hand",
		Vector3(
			extremity_scale / arm_thickness,
			extremity_scale / arm_factor,
			extremity_scale / arm_thickness
		)
	)
	_apply_bone_scale(
		"right_hand",
		Vector3(
			extremity_scale / arm_thickness,
			extremity_scale / arm_factor,
			extremity_scale / arm_thickness
		)
	)

	var left_hip_compensation : Vector2 = Vector2.ONE
	var right_hip_compensation : Vector2 = Vector2.ONE
	if _bone_is_direct_child("left_leg", "hips"):
		left_hip_compensation = Vector2(hip_side, hip_depth)
	if _bone_is_direct_child("right_leg", "hips"):
		right_hip_compensation = Vector2(hip_side, hip_depth)
	_apply_bone_scale(
		"left_leg",
		Vector3(
			thigh_thickness / left_hip_compensation.x,
			leg_factor,
			thigh_thickness / left_hip_compensation.y
		)
	)
	_apply_bone_scale(
		"right_leg",
		Vector3(
			thigh_thickness / right_hip_compensation.x,
			leg_factor,
			thigh_thickness / right_hip_compensation.y
		)
	)
	_apply_bone_scale(
		"left_lower_leg",
		Vector3(1.0 / thigh_thickness, 1.0, 1.0 / thigh_thickness)
	)
	_apply_bone_scale(
		"right_lower_leg",
		Vector3(1.0 / thigh_thickness, 1.0, 1.0 / thigh_thickness)
	)
	_apply_bone_scale(
		"left_foot",
		Vector3(extremity_scale, extremity_scale / leg_factor, extremity_scale)
	)
	_apply_bone_scale(
		"right_foot",
		Vector3(extremity_scale, extremity_scale / leg_factor, extremity_scale)
	)

	# Rotation offsets deliberately run last: scales establish the silhouette,
	# then the animated arms are opened around it without replacing their pose.
	_apply_fat_arm_posture(posture_amount)
