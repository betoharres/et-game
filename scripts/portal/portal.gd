extends Node3D

@export var player_camera: Camera3D
@export_range(0.0, 2.0, 0.05) var teleport_cooldown: float = 0.35
@export_range(0.0, 0.1, 0.001) var clip_plane_offset: float = 0.01

@onready var portal_1: MeshInstance3D = $Mesh1
@onready var portal_2: MeshInstance3D = $Mesh2
@onready var viewport_1: SubViewport = $Mesh1/SubViewport
@onready var viewport_2: SubViewport = $Mesh2/SubViewport2
@onready var portal_1_camera: Camera3D = $Mesh1/SubViewport/Camera3D
@onready var portal_2_camera: Camera3D = $Mesh2/SubViewport2/Camera3D2
@onready var portal_1_area: Area3D = $Mesh1/TeleportArea
@onready var portal_2_area: Area3D = $Mesh2/TeleportArea

var _teleport_cooldowns: Dictionary[int, float] = {}


func _ready() -> void:
	viewport_1.world_3d = get_world_3d()
	viewport_2.world_3d = get_world_3d()
	portal_1.material_override = _create_portal_material(viewport_1)
	portal_2.material_override = _create_portal_material(viewport_2)

	# Portal surfaces never appear in either render target, avoiding feedback.
	var portal_layers: int = portal_1.layers | portal_2.layers
	portal_1_camera.cull_mask &= ~portal_layers
	portal_2_camera.cull_mask &= ~portal_layers
	portal_1_area.body_entered.connect(_on_portal_body_entered.bind(portal_1, portal_2))
	portal_2_area.body_entered.connect(_on_portal_body_entered.bind(portal_2, portal_1))


func _process(_delta: float) -> void:
	if not is_instance_valid(player_camera):
		player_camera = get_viewport().get_camera_3d()
	if not is_instance_valid(player_camera):
		return

	_update_camera_for_portal(portal_1_camera, portal_1, portal_2)
	_update_camera_for_portal(portal_2_camera, portal_2, portal_1)


func _physics_process(delta: float) -> void:
	for body_id: int in _teleport_cooldowns.keys():
		var remaining: float = _teleport_cooldowns[body_id] - delta
		if remaining <= 0.0:
			_teleport_cooldowns.erase(body_id)
		else:
			_teleport_cooldowns[body_id] = remaining


func _create_portal_material(source_viewport: SubViewport) -> StandardMaterial3D:
	var material : StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = source_viewport.get_texture()
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	return material


func _update_camera_for_portal(
	portal_camera: Camera3D,
	entrance: MeshInstance3D,
	exit: MeshInstance3D
) -> void:
	var camera_from_entrance : Transform3D = entrance.global_transform.affine_inverse() \
		* player_camera.global_transform
	var half_turn : Transform3D = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	var virtual_transform : Transform3D = exit.global_transform * half_turn * camera_from_entrance
	_configure_portal_frustum(portal_camera, exit, virtual_transform.origin)


func _configure_portal_frustum(
	portal_camera: Camera3D,
	exit: MeshInstance3D,
	camera_position: Vector3
) -> void:
	var exit_basis : Basis = exit.global_basis.orthonormalized()
	var camera_side : float = signf(exit.to_local(camera_position).z)
	if is_zero_approx(camera_side):
		camera_side = 1.0

	# A regular Camera3D cannot receive an arbitrary projection matrix in
	# Godot 4.7. Keeping its near plane parallel to the exit and shifting an
	# asymmetric frustum is the equivalent construction for a planar portal.
	var camera_basis : Basis = exit_basis
	if camera_side < 0.0:
		camera_basis = exit_basis * Basis(Vector3.UP, PI)
	portal_camera.global_transform = Transform3D(camera_basis, camera_position)

	var portal_center_in_camera : Vector3 = portal_camera.to_local(exit.global_position)
	var plane_distance : float = maxf(-portal_center_in_camera.z, 0.001)
	var clip_distance : float = maxf(plane_distance + clip_plane_offset, 0.01)
	var near_scale : float = clip_distance / plane_distance
	var portal_aabb : AABB = exit.mesh.get_aabb()
	var portal_height : float = portal_aabb.size.y * exit.global_basis.y.length()
	var frustum_size : float = maxf(portal_height * near_scale, 0.01)
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


func _on_portal_body_entered(
	body: Node3D,
	entrance: MeshInstance3D,
	exit: MeshInstance3D
) -> void:
	if not body.is_in_group(&"players"):
		return

	var body_id : int = body.get_instance_id()
	if _teleport_cooldowns.has(body_id):
		return
	_teleport_cooldowns[body_id] = teleport_cooldown

	var half_turn : Basis = Basis(Vector3.UP, PI)
	var entrance_basis : Basis = entrance.global_basis.orthonormalized()
	var exit_basis : Basis = exit.global_basis.orthonormalized()
	var direction_mapping : Basis = exit_basis * half_turn * entrance_basis.inverse()
	var local_position : Vector3 = entrance.to_local(body.global_position)
	var destination_position : Vector3 = exit.to_global(half_turn * local_position)

	var destination_transform : Transform3D = body.global_transform
	destination_transform.origin = destination_position
	destination_transform.basis = (direction_mapping * body.global_basis).orthonormalized()
	body.global_transform = destination_transform

	if body is CharacterBody3D:
		body.velocity = direction_mapping * body.velocity
