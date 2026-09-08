extends SceneTree

## Updates only the paved floor and its subsoil, retaining authored districts,
## vegetation, rural wear, sidewalks and bridge aprons. Safe to repeat.
const Layout: GDScript = preload("res://tools/build_country_town_layout.gd")
const Surface: GDScript = preload("res://tools/country_town_road_surface.gd")
const TERRAIN_DIR: String = "res://scenes/CountryTown/Terrain"


func _process(_delta: float) -> bool:
	var pavement_only: bool = OS.get_cmdline_user_args().has("--pavement-only")
	var terrain: Terrain3D
	if not pavement_only:
		terrain = Terrain3D.new()
		root.add_child(terrain)
		terrain.data_directory = TERRAIN_DIR
		if terrain.data.get_region_count() == 0:
			push_error("Missing Country Town terrain")
			quit(1)
			return true
		recess_terrain(terrain.data)
		terrain.data.save_directory(TERRAIN_DIR)
	var network: Node3D = (load(Layout.ROAD_SCENE_PATH) as PackedScene).instantiate()
	var road_labels: Array[String] = []
	if not pavement_only:
		road_labels.assign(["AsphaltRoadBed", "MainRoadCenterLines"])
	for label: String in road_labels:
		var old: MeshInstance3D = network.get_node(label) as MeshInstance3D
		var mat: Material = old.material_override
		var polygons: Array[PackedVector2Array] = []
		if label == "AsphaltRoadBed":
			polygons = Layout.road_polygons(true)
		else:
			# Keep the authored marking footprints, changing only their elevation.
			var faces: PackedVector3Array = old.mesh.get_faces()
			for index: int in range(0, faces.size(), 3):
				var polygon: PackedVector2Array = PackedVector2Array()
				for corner: int in 3:
					var point: Vector3 = faces[index + corner]
					polygon.append(Vector2(point.x, point.z))
				if Geometry2D.is_polygon_clockwise(polygon):
					polygon.reverse()
				polygons.append(polygon)
		network.remove_child(old)
		old.free()
		var empty: Array[PackedVector2Array] = []
		var height_at: Callable = Layout.asphalt_height if label == "AsphaltRoadBed" else Layout.asphalt_marking_height
		Surface.build(network, label, polygons, empty, 0.0, mat, label == "AsphaltRoadBed", height_at)
	_close_pavement(network)
	var packed: PackedScene = PackedScene.new()
	var result: Error = packed.pack(network)
	if result == OK:
		result = ResourceSaver.save(packed, Layout.ROAD_SCENE_PATH)
	network.free()
	if terrain != null:
		terrain.free()
	quit(0 if result == OK else 1)
	return true


## Reuse the saved walking faces verbatim; replace only the buried enclosure.
func _close_pavement(network: Node3D) -> void:
	for label: String in ["Sidewalks", "Curbs"]:
		var node: MeshInstance3D = network.get_node(label) as MeshInstance3D
		var arrays: Array = node.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var top: SurfaceTool = SurfaceTool.new()
		top.begin(Mesh.PRIMITIVE_TRIANGLES)
		for triangle: int in range(0, indices.size(), 3):
			if normals[indices[triangle]].dot(Vector3.UP) < 0.99:
				continue
			for corner: int in 3:
				var index: int = indices[triangle + corner]
				top.set_normal(normals[index])
				top.set_uv(uvs[index])
				top.add_vertex(vertices[index])
		top.index()
		node.mesh = Surface.thicken_pavement(top.commit(), Surface.PAVEMENT_DEPTH)
		var collider: CollisionShape3D = node.get_child(0).get_child(0) as CollisionShape3D
		collider.shape = node.mesh.create_trimesh_shape()
		print("%s: closed sides extend %.2f m below the unchanged walking surface" % [label, Surface.PAVEMENT_DEPTH])


static func recess_terrain(data: Terrain3DData) -> void:
	# One heightmap cell diagonal ensures interpolation cannot protrude through
	# the asphalt edge. In town this transition is hidden under the 2.1 m walk.
	# Uncurbed approaches retain a short earthen bank at their existing edge.
	var polygons: Array[PackedVector2Array] = Layout.road_polygons(true, sqrt(2.0) + 0.01)
	var changed: Dictionary[Vector2i, bool] = {}
	var bed: float = Layout.GROUND_HEIGHT - Layout.ASPHALT_DROP
	for polygon: PackedVector2Array in polygons:
		var bounds: Rect2 = Surface.bounds(polygon)
		for z: int in range(floori(bounds.position.y), ceili(bounds.end.y) + 1):
			for x: int in range(floori(bounds.position.x), ceili(bounds.end.x) + 1):
				var key: Vector2i = Vector2i(x, z)
				if changed.has(key) or not Geometry2D.is_point_in_polygon(Vector2(x, z), polygon):
					continue
				var point: Vector3 = Vector3(x, 0.0, z)
				var current: float = data.get_height(point)
				if not is_nan(current) and current > bed:
					data.set_height(point, bed)
					changed[key] = true
	data.update_maps(Terrain3DRegion.TYPE_HEIGHT)
	print("Asphalt subsoil: %d samples; sidewalks and outer terrain retained." % changed.size())
