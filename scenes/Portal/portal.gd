extends Node3D

@export var player_camera: Camera3D

@onready var portal_1: MeshInstance3D = $Mesh1
@onready var portal_2: MeshInstance3D = $Mesh2
@onready var viewport_1: SubViewport = $Mesh1/SubViewport
@onready var viewport_2: SubViewport = $Mesh2/SubViewport2
@onready var portal_1_camera: Camera3D = $Mesh1/SubViewport/Camera3D
@onready var portal_2_camera: Camera3D = $Mesh2/SubViewport2/Camera3D2


func _ready() -> void:
	viewport_1.world_3d = get_world_3d()
	viewport_2.world_3d = get_world_3d()
	portal_1.material_override = _create_portal_material(viewport_1)
	portal_2.material_override = _create_portal_material(viewport_2)

	# Portal surfaces never appear in either render target, avoiding feedback.
	var portal_layers: int = portal_1.layers | portal_2.layers
	portal_1_camera.cull_mask &= ~portal_layers
	portal_2_camera.cull_mask &= ~portal_layers


func _process(_delta: float) -> void:
	if not is_instance_valid(player_camera):
		player_camera = get_viewport().get_camera_3d()
	if not is_instance_valid(player_camera):
		return

	_update_camera_for_portal(portal_1_camera, portal_1, portal_2)
	_update_camera_for_portal(portal_2_camera, portal_2, portal_1)


func _create_portal_material(source_viewport: SubViewport) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
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
	var camera_from_entrance := entrance.global_transform.affine_inverse() \
		* player_camera.global_transform
	var half_turn := Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	portal_camera.global_transform = exit.global_transform * half_turn * camera_from_entrance

	portal_camera.projection = player_camera.projection
	portal_camera.fov = player_camera.fov
	portal_camera.size = player_camera.size
	portal_camera.near = player_camera.near
	portal_camera.far = player_camera.far
	portal_camera.keep_aspect = player_camera.keep_aspect
