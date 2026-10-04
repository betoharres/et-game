extends Node3D

@export_range(1, 3, 1) var recursion_limit: int = 3

const RECURSIVE_VIEWS: GDScript = preload("res://scripts/portal/portal_recursive_views.gd")
const TRAVELLER_VISUAL: GDScript = preload("res://scripts/portal/portal_traveller_visual.gd")
const PORTAL_LAYER: int = 1 << 5
const CLIP_PLANE_OFFSET: float = 0.01

var player_camera: Camera3D

@onready var portal_1: MeshInstance3D = $Mesh1
@onready var portal_2: MeshInstance3D = $Mesh2
@onready var viewport_1: SubViewport = $Mesh1/SubViewport
@onready var viewport_2: SubViewport = $Mesh2/SubViewport2
@onready var portal_1_camera: Camera3D = $Mesh1/SubViewport/Camera3D
@onready var portal_2_camera: Camera3D = $Mesh2/SubViewport2/Camera3D2
@onready var portal_1_area: Area3D = $Mesh1/TeleportArea
@onready var portal_2_area: Area3D = $Mesh2/TeleportArea

var _recursive_views: Node3D

var _travellers: Dictionary[int, Dictionary] = {}


func _ready() -> void:
	viewport_1.world_3d = get_world_3d()
	viewport_2.world_3d = get_world_3d()
	# Os materiais usam estas texturas apenas quando a superfície é desenhada.
	viewport_1.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	viewport_2.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	portal_1.material_override = _create_portal_material(viewport_1)
	portal_2.material_override = _create_portal_material(viewport_2)
	_configure_viewport_aspect(viewport_1, portal_1)
	_configure_viewport_aspect(viewport_2, portal_2)

	portal_1.layers = PORTAL_LAYER
	portal_2.layers = PORTAL_LAYER
	portal_1.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	portal_2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	portal_1_camera.cull_mask &= ~PORTAL_LAYER
	portal_2_camera.cull_mask &= ~PORTAL_LAYER
	_recursive_views = RECURSIVE_VIEWS.new()
	add_child(_recursive_views)
	_recursive_views.setup(self)
	process_priority = 100
	process_physics_priority = 100
	portal_1_area.body_entered.connect(_on_portal_body_entered.bind(portal_1, portal_2))
	portal_2_area.body_entered.connect(_on_portal_body_entered.bind(portal_2, portal_1))
	portal_1_area.body_exited.connect(_on_portal_body_exited.bind(portal_1))
	portal_2_area.body_exited.connect(_on_portal_body_exited.bind(portal_2))


func _process(_delta: float) -> void:
	_update_traveller_visuals()
	player_camera = get_viewport().get_camera_3d()
	if not is_instance_valid(player_camera):
		return

	_update_camera_for_portal(portal_1_camera, portal_1, portal_2)
	_update_camera_for_portal(portal_2_camera, portal_2, portal_1)
	_recursive_views.update_views()


func _physics_process(_delta: float) -> void:
	for body_id: int in _travellers.keys():
		var traveller: Dictionary = _travellers[body_id]
		var body: Node3D = instance_from_id(body_id) as Node3D
		if not is_instance_valid(body):
			_remove_traveller(body_id)
			continue
		var entrance: MeshInstance3D = traveller["entrance"]
		var exit: MeshInstance3D = traveller["exit"]
		var side: float = _side_of_portal(entrance, body.global_position)
		if absf(side) < 0.0001:
			continue
		if side * float(traveller["side"]) < 0.0:
			if body.has_method("is_local_player") and not bool(body.call("is_local_player")):
				traveller["side"] = side
				continue
			_teleport_body(body, entrance, exit)
			traveller["entrance"] = exit
			traveller["exit"] = entrance
			traveller["side"] = _side_of_portal(exit, body.global_position)
		else:
			traveller["side"] = side


func _create_portal_material(source_viewport: SubViewport) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = preload("res://shaders/portal_surface.gdshader")
	material.set_shader_parameter("portal_texture", source_viewport.get_texture())
	return material


func _portal_transform(portal: MeshInstance3D) -> Transform3D:
	var frame: Dictionary = _get_portal_frame(portal)
	return Transform3D(frame["basis"], frame["center"])


func _portal_mapping(entrance: MeshInstance3D, exit: MeshInstance3D) -> Transform3D:
	return _portal_transform(exit) * Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO) \
		* _portal_transform(entrance).affine_inverse()


func _side_of_portal(portal: MeshInstance3D, position: Vector3) -> float:
	return (_portal_transform(portal).affine_inverse() * position).z


func _update_camera_for_portal(
	portal_camera: Camera3D,
	entrance: MeshInstance3D,
	exit: MeshInstance3D
) -> void:
	portal_camera.cull_mask = player_camera.cull_mask & ~PORTAL_LAYER
	var virtual_position: Vector3 = _portal_mapping(entrance, exit) * player_camera.global_position
	_configure_portal_frustum(portal_camera, exit, virtual_position)
	_update_surface_material(entrance.material_override as ShaderMaterial, entrance, player_camera.global_position)


func _update_surface_material(material: ShaderMaterial, entrance: MeshInstance3D, view_position: Vector3) -> void:
	var frame: Dictionary = _get_portal_frame(entrance)
	var basis: Basis = frame["basis"]
	material.set_shader_parameter("frame_center", frame["center"])
	material.set_shader_parameter("frame_right", basis.x)
	material.set_shader_parameter("frame_up", basis.y)
	material.set_shader_parameter("frame_size", frame["size"])
	material.set_shader_parameter("flip_x", _side_of_portal(entrance, view_position) < 0.0)


func _configure_portal_frustum(
	portal_camera: Camera3D,
	exit: MeshInstance3D,
	camera_position: Vector3
) -> void:
	var portal_frame: Dictionary = _get_portal_frame(exit)
	var exit_basis: Basis = portal_frame["basis"] as Basis
	var mesh_center: Vector3 = portal_frame["center"] as Vector3
	var mesh_size: Vector2 = portal_frame["size"] as Vector2
	var camera_side: float = signf(exit_basis.z.dot(camera_position - mesh_center))
	if is_zero_approx(camera_side):
		camera_side = 1.0

	# Aligning the camera with the surface allows clipping with a native frustum.
	var camera_basis : Basis = exit_basis
	if camera_side < 0.0:
		camera_basis = exit_basis * Basis(Vector3.UP, PI)
	portal_camera.global_transform = Transform3D(camera_basis, camera_position)

	var portal_center_in_camera : Vector3 = portal_camera.to_local(mesh_center)
	var plane_distance : float = maxf(-portal_center_in_camera.z, 0.001)
	var clip_distance : float = maxf(plane_distance + CLIP_PLANE_OFFSET, 0.01)
	var near_scale : float = clip_distance / plane_distance
	var frustum_size: float = maxf(mesh_size.y * near_scale, 0.01)
	var frustum_offset : Vector2 = Vector2(
		portal_center_in_camera.x,
		portal_center_in_camera.y
	) * near_scale

	portal_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	portal_camera.set_frustum(
		frustum_size,
		frustum_offset,
		clip_distance,
		maxf(player_camera.far, clip_distance + 0.01)
	)


func _get_portal_frame(portal: MeshInstance3D) -> Dictionary:
	var mesh_aabb: AABB = portal.mesh.get_aabb()
	var mesh_size: Vector3 = mesh_aabb.size
	var normal_axis: int = 0
	if mesh_size.y < mesh_size.x and mesh_size.y <= mesh_size.z:
		normal_axis = 1
	elif mesh_size.z < mesh_size.x and mesh_size.z < mesh_size.y:
		normal_axis = 2

	var source_basis: Basis = portal.global_basis.orthonormalized()
	var tangent_axes: Array[int] = []
	for axis: int in range(3):
		if axis != normal_axis:
			tangent_axes.append(axis)
	var first_tangent: Vector3 = _get_basis_axis(source_basis, tangent_axes[0])
	var second_tangent: Vector3 = _get_basis_axis(source_basis, tangent_axes[1])
	var tangent_y_axis: int = tangent_axes[0]
	if absf(second_tangent.dot(Vector3.UP)) > absf(first_tangent.dot(Vector3.UP)):
		tangent_y_axis = tangent_axes[1]
	var tangent_x_axis: int = tangent_axes[0] if tangent_y_axis == tangent_axes[1] else tangent_axes[1]
	var tangent_x: Vector3 = _get_basis_axis(source_basis, tangent_x_axis)
	var tangent_y: Vector3 = _get_basis_axis(source_basis, tangent_y_axis)
	if tangent_y.dot(Vector3.UP) < 0.0:
		tangent_y = -tangent_y
	var normal: Vector3 = tangent_x.cross(tangent_y).normalized()
	var frame: Basis = Basis(tangent_x, tangent_y, normal).orthonormalized()
	var mesh_center: Vector3 = portal.global_transform * mesh_aabb.get_center()
	var tangent_x_scale: float = _get_basis_axis(portal.global_basis, tangent_x_axis).length()
	var tangent_y_scale: float = _get_basis_axis(portal.global_basis, tangent_y_axis).length()
	var frame_size: Vector2 = Vector2(
		mesh_size[tangent_x_axis] * tangent_x_scale,
		mesh_size[tangent_y_axis] * tangent_y_scale
	)
	return {"basis": frame, "center": mesh_center, "size": frame_size}


func _get_basis_axis(source_basis: Basis, axis: int) -> Vector3:
	match axis:
		0:
			return source_basis.x
		1:
			return source_basis.y
		_:
			return source_basis.z


func _configure_viewport_aspect(viewport: SubViewport, portal: MeshInstance3D) -> void:
	var frame_size: Vector2 = (_get_portal_frame(portal)["size"] as Vector2).abs()
	if frame_size.x <= 0.001 or frame_size.y <= 0.001:
		return
	var viewport_height: int = 1024
	var viewport_width: int = maxi(1, roundi(float(viewport_height) * frame_size.x / frame_size.y))
	viewport.size = Vector2i(viewport_width, viewport_height)


func _on_portal_body_entered(body: Node3D, entrance: MeshInstance3D, exit: MeshInstance3D) -> void:
	if not body.is_in_group(&"players") or _travellers.has(body.get_instance_id()):
		return
	var visual: Node3D = TRAVELLER_VISUAL.new()
	add_child(visual)
	visual.setup(body)
	_travellers[body.get_instance_id()] = {
		"visual": visual,
		"entrance": entrance, "exit": exit,
		"side": _side_of_portal(entrance, body.global_position)
	}
	var exit_callback: Callable = _on_traveller_tree_exiting.bind(body.get_instance_id())
	if not body.tree_exiting.is_connected(exit_callback):
		body.tree_exiting.connect(exit_callback, CONNECT_ONE_SHOT)


func _on_traveller_tree_exiting(body_id: int) -> void:
	if _travellers.has(body_id):
		_remove_traveller(body_id)


func refresh_traveller_visual(body: Node3D) -> void:
	var body_id: int = body.get_instance_id()
	if not _travellers.has(body_id):
		return
	var old_visual: Node3D = _travellers[body_id]["visual"]
	remove_child(old_visual)
	old_visual.queue_free()
	var visual: Node3D = TRAVELLER_VISUAL.new()
	add_child(visual)
	visual.setup(body)
	_travellers[body_id]["visual"] = visual


func _on_portal_body_exited(body: Node3D, entrance: MeshInstance3D) -> void:
	var body_id: int = body.get_instance_id()
	if _travellers.has(body_id) and _travellers[body_id]["entrance"] == entrance:
		_remove_traveller(body_id)


func _remove_traveller(body_id: int) -> void:
	var visual: Node3D = _travellers[body_id]["visual"]
	remove_child(visual)
	visual.queue_free()
	_travellers.erase(body_id)


func _update_traveller_visuals() -> void:
	for traveller: Dictionary in _travellers.values():
		var entrance: MeshInstance3D = traveller["entrance"]
		var exit: MeshInstance3D = traveller["exit"]
		traveller["visual"].update_visual(_portal_mapping(entrance, exit),
			_portal_transform(entrance), _portal_transform(exit), float(traveller["side"]))


func _teleport_body(body: Node3D, entrance: MeshInstance3D, exit: MeshInstance3D) -> void:
	var mapping: Transform3D = _portal_mapping(entrance, exit)
	if body.has_method("apply_portal_transform"):
		body.call("apply_portal_transform", mapping)
	else:
		body.global_transform = (mapping * body.global_transform).orthonormalized()
		if body is CharacterBody3D:
			body.velocity = mapping.basis * body.velocity
