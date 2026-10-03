extends Node3D

var _meshes: Array[Dictionary] = []
var _skeletons: Dictionary[int, Dictionary] = {}


func setup(body: Node3D) -> void:
	name = "PortalTravellerVisual"
	for node: Node in body.find_children("*", "MeshInstance3D", true, false):
		var source: MeshInstance3D = node as MeshInstance3D
		if source.mesh == null:
			continue
		var clone: MeshInstance3D = MeshInstance3D.new()
		clone.mesh = source.mesh
		clone.skin = source.skin
		add_child(clone)
		var skeleton: Skeleton3D = source.get_node_or_null(source.skeleton) as Skeleton3D
		if skeleton != null:
			var mirror: Skeleton3D = _get_mirror_skeleton(skeleton)
			clone.skeleton = clone.get_path_to(mirror)
		var entry: Dictionary = {
			"source": source, "clone": clone, "override": source.material_override,
			"surfaces": [], "materials": []
		}
		for surface: int in source.mesh.get_surface_count():
			entry["surfaces"].append(source.get_surface_override_material(surface))
			var original: Material = source.get_active_material(surface)
			var sliced: ShaderMaterial = _slice_material(original)
			entry["materials"].append({"original": original, "sliced": sliced})
			source.set_surface_override_material(surface, sliced)
			clone.set_surface_override_material(surface, sliced)
		source.material_override = null
		_meshes.append(entry)


func update_visual(mapping: Transform3D, entrance: Transform3D, exit: Transform3D, side: float) -> void:
	var keep_side: float = 1.0 if side >= 0.0 else -1.0
	for entry: Dictionary in _skeletons.values():
		var source: Skeleton3D = entry["source"]
		var clone: Skeleton3D = entry["clone"]
		if is_instance_valid(source):
			clone.global_transform = mapping * source.global_transform
	for entry: Dictionary in _meshes:
		var source: MeshInstance3D = entry["source"]
		var clone: MeshInstance3D = entry["clone"]
		if not is_instance_valid(source):
			clone.hide()
			continue
		clone.global_transform = mapping * source.global_transform
		clone.visible = source.is_visible_in_tree()
		clone.layers = source.layers
		clone.cast_shadow = source.cast_shadow
		clone.transparency = source.transparency
		if source.mesh is ArrayMesh:
			for blend: int in source.mesh.get_blend_shape_count():
				clone.set_blend_shape_value(blend, source.get_blend_shape_value(blend))
		_set_plane(source, entrance.origin, entrance.basis.z * keep_side)
		_set_plane(clone, exit.origin, exit.basis.z * keep_side)
		for material: Dictionary in entry["materials"]:
			_sync_material(material["original"], material["sliced"])


func _set_plane(mesh: MeshInstance3D, center: Vector3, normal: Vector3) -> void:
	mesh.set_instance_shader_parameter("portal_slice_center", center)
	mesh.set_instance_shader_parameter("portal_slice_normal", normal)


func _get_mirror_skeleton(source: Skeleton3D) -> Skeleton3D:
	var id: int = source.get_instance_id()
	if _skeletons.has(id):
		return _skeletons[id]["clone"]
	var clone: Skeleton3D = Skeleton3D.new()
	add_child(clone)
	for bone: int in source.get_bone_count():
		clone.add_bone(source.get_bone_name(bone))
		clone.set_bone_parent(bone, source.get_bone_parent(bone))
		clone.set_bone_rest(bone, source.get_bone_rest(bone))
	var callback: Callable = _copy_pose.bind(source, clone)
	# Read the final pose after IK and proportions, rather than replaying animation.
	source.skeleton_updated.connect(callback)
	_skeletons[id] = {"source": source, "clone": clone, "callback": callback}
	_copy_pose(source, clone)
	return clone


func _copy_pose(source: Skeleton3D, clone: Skeleton3D) -> void:
	for bone: int in source.get_bone_count():
		var pose: Transform3D = source.get_bone_global_pose(bone)
		var parent: int = source.get_bone_parent(bone)
		if parent >= 0:
			pose = source.get_bone_global_pose(parent).affine_inverse() * pose
		clone.set_bone_pose(bone, pose)


func _slice_material(original: Material) -> ShaderMaterial:
	var sliced: ShaderMaterial = ShaderMaterial.new()
	var code: String
	if original is ShaderMaterial:
		code = original.shader.code
	else:
		code = """shader_type spatial;
render_mode cull_disabled;
uniform vec4 portal_albedo : source_color = vec4(1.0);
uniform sampler2D portal_albedo_texture : source_color, hint_default_white;
uniform vec3 portal_emission;
uniform float portal_roughness = 1.0;
uniform float portal_metallic = 0.0;
void fragment() {
    vec4 color = portal_albedo * texture(portal_albedo_texture, UV);
    if (color.a < 0.1) { discard; }
    ALBEDO = color.rgb;
    ROUGHNESS = portal_roughness;
    METALLIC = portal_metallic;
    EMISSION = portal_emission;
}
"""
	var declarations: String = """
instance uniform vec3 portal_slice_center;
instance uniform vec3 portal_slice_normal;
"""
	var fragment: RegEx = RegEx.new()
	fragment.compile("void\\s+fragment\\s*\\(\\s*\\)\\s*[{]")
	var found: RegExMatch = fragment.search(code)
	var clipping: String = """
    vec3 portal_world_position = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
    if (dot(portal_world_position - portal_slice_center, portal_slice_normal) < 0.0) { discard; }
"""
	if found != null:
		code = code.insert(found.get_end(), clipping)
	else:
		code += "\nvoid fragment() {" + clipping + "}\n"
	# Append after the material's shading so eye emission cannot overwrite the rim.
	var fragment_start: RegExMatch = fragment.search(code)
	var closing: int = fragment_start.get_end()
	var brace_depth: int = 1
	while brace_depth > 0 and closing < code.length():
		if code[closing] == "{":
			brace_depth += 1
		elif code[closing] == "}":
			brace_depth -= 1
		closing += 1
	var border: String = """
    if (length(portal_slice_normal) > 0.5) {
        float portal_edge_distance = dot(portal_world_position - portal_slice_center, portal_slice_normal);
        float portal_edge = 1.0 - smoothstep(0.0, 0.025, portal_edge_distance);
        float portal_pulse = 0.9 + 0.1 * sin(TIME * 10.0 + portal_world_position.y * 18.0);
        vec3 portal_edge_color = vec3(0.08, 0.85, 1.0);
        ALBEDO = mix(ALBEDO, portal_edge_color, portal_edge * portal_pulse);
        EMISSION += portal_edge_color * portal_edge * portal_pulse * 2.0;
    }
"""
	code = code.insert(closing - 1, border)
	code = code.insert(code.find(";") + 1, declarations)
	sliced.shader = Shader.new()
	sliced.shader.code = code
	_sync_material(original, sliced)
	return sliced


func _sync_material(original: Material, sliced: ShaderMaterial) -> void:
	if original is ShaderMaterial:
		for uniform: Dictionary in original.shader.get_shader_uniform_list():
			var value: Variant = original.get_shader_parameter(uniform["name"])
			if value != null:
				sliced.set_shader_parameter(uniform["name"], value)
	elif original is BaseMaterial3D:
		sliced.set_shader_parameter("portal_albedo", original.albedo_color)
		sliced.set_shader_parameter("portal_albedo_texture", original.albedo_texture)
		sliced.set_shader_parameter("portal_roughness", original.roughness)
		sliced.set_shader_parameter("portal_metallic", original.metallic)
		sliced.set_shader_parameter("portal_emission", original.emission * original.emission_energy_multiplier if original.emission_enabled else Color.BLACK)


func _exit_tree() -> void:
	for entry: Dictionary in _meshes:
		var source: MeshInstance3D = entry["source"]
		if not is_instance_valid(source):
			continue
		for surface: int in source.mesh.get_surface_count():
			if source.get_surface_override_material(surface) == entry["materials"][surface]["sliced"]:
				source.set_surface_override_material(surface, entry["surfaces"][surface])
		source.material_override = entry["override"]
		_set_plane(source, Vector3.ZERO, Vector3.ZERO)
	for entry: Dictionary in _skeletons.values():
		var source: Skeleton3D = entry["source"]
		if is_instance_valid(source):
			source.skeleton_updated.disconnect(entry["callback"])
