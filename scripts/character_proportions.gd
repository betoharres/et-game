extends SkeletonModifier3D

const EYE_SHADER : Shader = preload("res://shaders/character_eyes.gdshader")
const BODY_SHADER : Shader = preload("res://shaders/character_body.gdshader")
const FEATURE_DEFAULT : float = 0.5
const LEG_GROUND_OFFSET : float = 0.42
const BLEND_SHAPES : Dictionary = {
	"belly_size": &"Belly",
	"head_size": &"Head",
	"eye_size": &"Eyes",
}

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


func _ready() -> void:
	_visual_root = get_node_or_null(visual_root_path) as Node3D
	_character_mesh = get_node_or_null(character_mesh_path) as MeshInstance3D
	if _visual_root != null:
		_base_visual_scale = _visual_root.scale
		_base_visual_position = _visual_root.position
	_cache_bones()
	_setup_body_material()
	_setup_eye_material()

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


func _apply_static_visuals() -> void:
	var height_factor : float = _feature_factor("overall_height", 0.82, 1.18)
	var leg_factor : float = _feature_factor("leg_length", 0.75, 1.25)
	if _visual_root != null:
		_visual_root.scale = _base_visual_scale * Vector3(1.0, height_factor, 1.0)
		_visual_root.position = _base_visual_position
		if keep_feet_grounded:
			_visual_root.position.y += LEG_GROUND_OFFSET * height_factor * (leg_factor - 1.0)
	_apply_blend_shapes()


func _apply_blend_shapes() -> void:
	if _character_mesh == null or _character_mesh.mesh == null:
		return
	for feature : String in BLEND_SHAPES:
		var blend_shape : StringName = StringName(BLEND_SHAPES[feature])
		var blend_shape_index : int = _find_blend_shape(blend_shape)
		if blend_shape_index >= 0:
			_character_mesh.set_blend_shape_value(blend_shape_index, float(_profile[feature]))


func _find_blend_shape(blend_shape : StringName) -> int:
	if _character_mesh == null or _character_mesh.mesh == null:
		return -1
	for index : int in _character_mesh.mesh.get_blend_shape_count():
		if _character_mesh.mesh.get_blend_shape_name(index) == blend_shape:
			return index
	return -1


func _apply_bone_scale(role : String, scale_multiplier : Vector3) -> void:
	var skeleton : Skeleton3D = get_skeleton()
	var bone_index : int = int(_bone_ids.get(role, -1))
	if skeleton == null or bone_index < 0:
		return
	skeleton.set_bone_pose_scale(
		bone_index,
		skeleton.get_bone_pose_scale(bone_index) * scale_multiplier
	)


func _process_modification_with_delta(_delta : float) -> void:
	var leg_factor : float = _feature_factor("leg_length", 0.75, 1.25)
	var arm_factor : float = _feature_factor("arm_length", 0.74, 1.26)
	var shoulder_factor : float = _feature_factor("shoulder_width", 0.78, 1.22)
	_apply_bone_scale(
		"left_shoulder",
		Vector3(1.0, shoulder_factor, 1.0)
	)
	_apply_bone_scale(
		"right_shoulder",
		Vector3(1.0, shoulder_factor, 1.0)
	)
	_apply_bone_scale(
		"left_arm",
		Vector3(1.0, arm_factor, 1.0)
	)
	_apply_bone_scale(
		"right_arm",
		Vector3(1.0, arm_factor, 1.0)
	)
	_apply_bone_scale(
		"left_hand",
		Vector3(1.0, 1.0 / arm_factor, 1.0)
	)
	_apply_bone_scale(
		"right_hand",
		Vector3(1.0, 1.0 / arm_factor, 1.0)
	)

	_apply_bone_scale(
		"left_leg",
		Vector3(
			1.0,
			leg_factor,
			1.0
		)
	)
	_apply_bone_scale(
		"right_leg",
		Vector3(
			1.0,
			leg_factor,
			1.0
		)
	)
	_apply_bone_scale(
		"left_lower_leg",
		Vector3.ONE
	)
	_apply_bone_scale(
		"right_lower_leg",
		Vector3.ONE
	)
	_apply_bone_scale(
		"left_foot",
		Vector3(1.0, 1.0 / leg_factor, 1.0)
	)
	_apply_bone_scale(
		"right_foot",
		Vector3(1.0, 1.0 / leg_factor, 1.0)
	)
