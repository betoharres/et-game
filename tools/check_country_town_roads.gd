extends SceneTree

## Checks the saved meshes/collisions, not just the layout recipe.
const Layout: GDScript = preload("res://tools/build_country_town_layout.gd")
var _started: bool = false
var _failures: Array[String] = []
var _samples: int = 0
var _space: PhysicsDirectSpaceState3D
var _terrain: Terrain3D


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _run() -> void:
	var world: Node3D = Node3D.new()
	root.add_child(world)
	for label: String in ["RoadNetwork", "SecondaryPaths", "RiverDistrict"]:
		world.add_child((load("res://scenes/CountryTown/Districts/%s.tscn" % label) as PackedScene).instantiate())
	_terrain = Terrain3D.new()
	world.add_child(_terrain)
	_terrain.data_directory = "res://scenes/CountryTown/Terrain"
	var camera: Camera3D = Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(300, 50, 220)
	_terrain.set_camera(camera)
	for frame: int in 3:
		await physics_frame
	_space = world.get_world_3d().direct_space_state
	for tile: Dictionary in Layout.road_tiles():
		var cell: Vector2i = tile["cell"]
		var center: Vector2 = Layout.grid_position(cell.x, cell.y)
		for direction: Vector2 in Layout.ROAD_CONNECTORS[Layout.shape_of(tile["kind"])]:
			var axis: Vector2 = Layout.rotate_local(direction, tile["angle"])
			_sample_segment(center, center + axis * Layout.TILE * 0.5, 4.0 if tile["kind"].begins_with("asphalt") else 3.5, true)
	for path: Dictionary in Layout.SECONDARY_PATHS:
		var points: Array = path["points"]
		for index: int in points.size() - 1:
			_sample_segment(points[index], points[index + 1], float(path["width"]) * 0.44, path["urban"])
	for bridge: Vector2 in [Vector2(312.1, 167.46), Vector2(204.9, 298.48)]:
		_sample_segment(bridge - Vector2(25, 0), bridge + Vector2(25, 0), 2.0, true)
	var roads: Node = world.get_node("RoadNetwork")
	var asphalt: MeshInstance3D = roads.get_node("AsphaltRoadBed") as MeshInstance3D
	var material: StandardMaterial3D = asphalt.material_override as StandardMaterial3D
	if material == null or material.albedo_texture == null or material.albedo_color.v > 0.25:
		_failures.append("Asphalt must have a dark, textured local material")
	_check_surface_vertices(asphalt)
	_check_surface_vertices(roads.get_node("DirtRoadBed") as MeshInstance3D)
	if _failures.is_empty():
		print("Country Town roads OK: %d floor samples, textured asphalt, terrain below pavement, both bridge ramps." % _samples)
	else:
		for failure: String in _failures:
			printerr(failure)
	world.free()
	quit(0 if _failures.is_empty() else 1)


func _sample_segment(start: Vector2, end: Vector2, half_width: float, flat: bool) -> void:
	var steps: int = maxi(1, ceili(start.distance_to(end)))
	var side: Vector2 = (end - start).normalized().orthogonal()
	for step: int in steps + 1:
		var center: Vector2 = start.lerp(end, float(step) / steps)
		for offset: float in [-half_width, 0.0, half_width]:
			var point: Vector2 = center + side * offset
			var expected: float = Layout.road_height(point) if flat else _terrain.data.get_height(Vector3(point.x, 0, point.y)) + Layout.ROAD_PIECE_LIFT
			var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(Vector3(point.x, expected + 1, point.y), Vector3(point.x, expected - 1, point.y))
			var hit: Dictionary = _space.intersect_ray(query)
			_samples += 1
			if hit.is_empty():
				_failures.append("Missing floor at %s" % point)
			elif absf((hit["position"] as Vector3).y - expected) > 0.045:
				_failures.append("Uneven floor at %s: expected %.3f, found %.3f" % [point, expected, (hit["position"] as Vector3).y])


func _check_surface_vertices(node: MeshInstance3D) -> void:
	var vertices: PackedVector3Array = node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for vertex: Vector3 in vertices:
		var ground: float = _terrain.data.get_height(vertex)
		if is_nan(ground) or ground > vertex.y - 0.01:
			_failures.append("Terrain penetrates %s at %s: ground %.3f" % [node.name, vertex, ground])
