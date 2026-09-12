class_name PursuitNavigation
extends NavigationRegion3D

@export var baking_bounds: AABB = AABB(Vector3(-150, -32, -150), Vector3(400, 96, 300))
@export_range(0.5, 4.0, 0.5) var terrain_sample_spacing: float = 1.0

var _map: RID
var _building: bool = false
var _map_synced: bool = false


func _ready() -> void:
	# Mapa separado: a plataforma da nave não pode ser confundida com o chão
	# da fazenda, nem esta malha mudar a patrulha dos NPCs legados.
	_map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_cell_size(_map, 0.3)
	NavigationServer3D.map_set_cell_height(_map, 0.15)
	NavigationServer3D.map_set_active(_map, true)
	set_navigation_map(_map)


func _exit_tree() -> void:
	if _map.is_valid():
		NavigationServer3D.free_rid(_map)


func is_ready_for_paths() -> bool:
	if _building or navigation_mesh == null or navigation_mesh.get_polygon_count() == 0:
		return false
	if not _map_synced:
		# O mapa vazio já pode ter uma iteração; o bake e a publicação dos seus
		# polígonos no NavigationServer terminam em momentos diferentes.
		var sample: Vector3 = global_transform * navigation_mesh.get_vertices()[0]
		_map_synced = NavigationServer3D.map_get_closest_point_owner(_map, sample) == get_rid()
	return _map_synced


func build(geometry_root: Node3D, terrain: Terrain3D = null) -> void:
	if _building:
		return
	_building = true
	_map_synced = false
	var mesh: NavigationMesh = NavigationMesh.new()
	mesh.cell_size = 0.3
	mesh.cell_height = 0.15
	mesh.agent_radius = 0.6
	mesh.agent_height = 1.95
	mesh.agent_max_climb = 0.3
	mesh.agent_max_slope = 35.0
	mesh.region_min_size = 2.0
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.filter_baking_aabb = baking_bounds
	var source: NavigationMeshSourceGeometryData3D = NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(mesh, source, geometry_root)
	if terrain != null:
		var faces: PackedVector3Array = []
		var step: float = maxf(terrain_sample_spacing, 0.5)
		var columns: int = ceili(baking_bounds.size.x / step)
		var rows: int = ceili(baking_bounds.size.z / step)
		for row: int in range(rows):
			for column: int in range(columns):
				var a: Vector3 = baking_bounds.position + Vector3(column * step, 0.0, row * step)
				var b: Vector3 = a + Vector3(step, 0.0, 0.0)
				var c: Vector3 = a + Vector3(step, 0.0, step)
				var d: Vector3 = a + Vector3(0.0, 0.0, step)
				a.y = terrain.data.get_height(a)
				b.y = terrain.data.get_height(b)
				c.y = terrain.data.get_height(c)
				d.y = terrain.data.get_height(d)
				if a.is_finite() and b.is_finite() and c.is_finite() and d.is_finite():
					faces.append_array(PackedVector3Array([a, b, c, a, c, d]))
		source.add_faces(faces, Transform3D.IDENTITY)
	NavigationServer3D.bake_from_source_geometry_data_async(mesh, source, _on_baked.bind(mesh))


func _on_baked(mesh: NavigationMesh) -> void:
	if not is_inside_tree():
		return
	navigation_mesh = mesh
	_building = false
	if mesh.get_polygon_count() == 0:
		push_error("Perseguição: nenhuma superfície navegável dentro de %s." % baking_bounds)
