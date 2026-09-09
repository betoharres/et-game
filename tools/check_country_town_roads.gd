extends SceneTree

## Checks the saved meshes/collisions, not just the layout recipe.
## Urban roads have a paved floor of their own. Rural routes do not: the terrain
## is the floor there, and the wheel tracks only sit on top of it.
const Layout: GDScript = preload("res://tools/build_country_town_layout.gd")
const Rural: GDScript = preload("res://tools/build_rural_roads.gd")
var _rural_profile: Resource
var _main_footprints: Array[PackedVector2Array] = []
var _asphalt_footprints: Array[PackedVector2Array] = []
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
	_rural_profile = load(Rural.PRESET)
	_rural_profile.configure(Rural.BRIDGE_ZONES)
	_main_footprints = Layout.road_polygons(false) + Layout.road_polygons(true)
	_asphalt_footprints = Layout.road_polygons(true)
	var world: Node3D = Node3D.new()
	root.add_child(world)
	for label: String in ["RoadNetwork", "SecondaryPaths", "RiverDistrict"]:
		world.add_child((load("res://scenes/CountryTown/Districts/%s.tscn" % label) as PackedScene).instantiate())
	_terrain = Terrain3D.new()
	world.add_child(_terrain)
	_terrain.data_directory = "res://scenes/CountryTown/Terrain"
	# O terreno agora e o piso das vias rurais, e os raios saem por todo o mapa:
	# sem colisao completa so existiria chao perto da camera.
	_terrain.set("collision_mode", 3) # Full / Game
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
		var paved: bool = tile["kind"].begins_with("asphalt")
		for direction: Vector2 in Layout.ROAD_CONNECTORS[Layout.shape_of(tile["kind"])]:
			var axis: Vector2 = Layout.rotate_local(direction, tile["angle"])
			_sample_segment(Layout.aligned_road_point(center), Layout.aligned_road_point(center + axis * Layout.TILE * 0.5), 4.0 if paved else 3.5, paved)
	for path: Dictionary in Layout.SECONDARY_PATHS:
		var points: Array = path["points"]
		for index: int in points.size() - 1:
			_sample_segment(points[index], points[index + 1], float(path["width"]) * 0.44, path["urban"])
	for bridge: Vector2 in [Vector2(318.18723, 167.46), Vector2(204.9, 298.48)]:
		_sample_segment(bridge - Vector2(25, 0), bridge + Vector2(25, 0), 2.0, true)
	var roads: Node = world.get_node("RoadNetwork")
	var asphalt: MeshInstance3D = roads.get_node("AsphaltRoadBed") as MeshInstance3D
	var material: StandardMaterial3D = asphalt.material_override as StandardMaterial3D
	if material == null or material.albedo_texture == null or material.albedo_color.v > 0.25:
		_failures.append("Asphalt must have a dark, textured local material")
	_check_surface_vertices(asphalt)
	for label: String in ["Sidewalks", "Curbs"]:
		_check_pavement_walls(roads.get_node(label) as MeshInstance3D)
	_check_apron(roads.get_node_or_null("DirtRoadBed") as MeshInstance3D)
	for label: String in Rural.RETIRED:
		if roads.get_node_or_null(label) != null or world.get_node_or_null("SecondaryPaths/%s" % label) != null:
			_failures.append("Rural dirt floor %s is back: the terrain is the floor now" % label)
	var marks: int = _check_tire_tracks(roads.get_node_or_null("TireTracks"))
	marks += _check_tire_tracks(world.get_node_or_null("SecondaryPaths/TireTracks"))
	if marks == 0:
		_failures.append("Missing rural tire tracks: run tools/build_tire_tracks.gd")
	if _failures.is_empty():
		print("Country Town roads OK: %d floor samples, textured asphalt, %d tire tracks on the terrain, both bridge ramps." % [_samples, marks])
	else:
		for failure: String in _failures:
			printerr(failure)
	world.free()
	quit(0 if _failures.is_empty() else 1)


## Paved routes must land on their own floor. Rural ones only need continuous
## ground: the terrain, or the graded apron next to a bridge.
func _sample_segment(start: Vector2, end: Vector2, half_width: float, paved: bool) -> void:
	var steps: int = maxi(1, ceili(start.distance_to(end)))
	var side: Vector2 = (end - start).normalized().orthogonal()
	for step: int in steps + 1:
		var center: Vector2 = start.lerp(end, float(step) / steps)
		for offset: float in [-half_width, 0.0, half_width]:
			var point: Vector2 = center + side * offset
			var ground: float = _ground(point)
			var expected: float = Layout.road_height(point) if paved else ground
			if paved:
				for polygon: PackedVector2Array in _asphalt_footprints:
					if Geometry2D.is_point_in_polygon(point, polygon):
						expected = Layout.asphalt_height(point)
						break
			var ceiling: float = expected + 0.045
			var pit: float = expected - 0.045
			if not paved:
				# Bridge aprons keep a graded floor above the flattened terrain.
				for polygon: PackedVector2Array in _main_footprints:
					if Geometry2D.is_point_in_polygon(point, polygon):
						ceiling = maxf(ceiling, Layout.road_height(point) + 0.05)
						break
				ceiling = maxf(ceiling, ground + 0.09)
				pit = ground - 0.03
			var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(Vector3(point.x, ceiling + 1.5, point.y), Vector3(point.x, pit - 1.5, point.y))
			var hit: Dictionary = _space.intersect_ray(query)
			_samples += 1
			if hit.is_empty():
				_failures.append("Missing floor at %s" % point)
			elif (hit["position"] as Vector3).y > ceiling or (hit["position"] as Vector3).y < pit:
				_failures.append("Floor out of range at %s: expected %.3f..%.3f, found %.3f" % [point, pit, ceiling, (hit["position"] as Vector3).y])


func _check_surface_vertices(node: MeshInstance3D) -> void:
	var vertices: PackedVector3Array = node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for vertex: Vector3 in vertices:
		var ground: float = _terrain.data.get_height(vertex)
		if is_nan(ground) or ground > vertex.y - 0.01:
			_failures.append("Terrain penetrates %s at %s: ground %.3f" % [node.name, vertex, ground])


## Inspect indexed faces and raycast across exposed edges, not just the AABB:
## unused wall vertices can enlarge the bounds without closing a single gap.
func _check_pavement_walls(node: MeshInstance3D) -> void:
	var faces: PackedVector3Array = node.mesh.get_faces()
	var top: float = node.mesh.get_aabb().end.y
	var edges: Dictionary = {}
	var walls: int = 0
	for index: int in range(0, faces.size(), 3):
		var a: Vector3 = faces[index]
		var b: Vector3 = faces[index + 1]
		var c: Vector3 = faces[index + 2]
		if maxf(a.y, maxf(b.y, c.y)) - minf(a.y, minf(b.y, c.y)) > 0.1:
			walls += 1
		if absf(a.y - top) > 0.001 or absf(b.y - top) > 0.001 or absf(c.y - top) > 0.001:
			continue
		for corner: int in 3:
			var key: Array[Vector3] = [
				faces[index + corner].snapped(Vector3.ONE * 0.001),
				faces[index + (corner + 1) % 3].snapped(Vector3.ONE * 0.001)
			]
			key.sort()
			edges[key] = int(edges.get(key, 0)) + 1
	if walls == 0:
		_failures.append("%s has no indexed side faces: pavement is open underneath" % node.name)
		return
	var samples: int = 0
	for key: Array in edges:
		if edges[key] != 1 or (key[1] as Vector3).distance_to(key[0]) < 0.02:
			continue
		var middle: Vector3 = (key[0] + key[1]) * 0.5 - Vector3.UP * 0.1
		var side: Vector3 = (key[1] - key[0]).normalized().cross(Vector3.UP) * 0.01
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			node.to_global(middle + side), node.to_global(middle - side)
		)
		var hit: Dictionary = _space.intersect_ray(query)
		if hit.is_empty():
			# Concave collision faces are one-sided; inspect the opposite side
			# too, since the sorted edge does not retain the surface winding.
			var start: Vector3 = query.from
			query.from = query.to
			query.to = start
			hit = _space.intersect_ray(query)
		if hit.is_empty():
			_failures.append("Open pavement edge on %s at %s" % [node.name, node.to_global(middle)])
		samples += 1
	print("%s: %d indexed wall triangles, %d side collision samples" % [node.name, walls, samples])


## What is left of the dirt floor may only be the bridge aprons.
func _check_apron(node: MeshInstance3D) -> void:
	if node == null:
		_failures.append("Missing bridge aprons: the dirt ramps to both bridges are gone")
		return
	_check_surface_vertices(node)
	for vertex: Vector3 in node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		var reach: float = INF
		for zone: Vector3 in Rural.BRIDGE_ZONES:
			reach = minf(reach, Vector2(vertex.x, vertex.z).distance_to(Vector2(zone.x, zone.y)) - zone.z - 8.0)
		if reach > 2.0:
			_failures.append("Dirt floor %.1f m away from any bridge landing at %s" % [reach, vertex])
			return


## The tracks are a thin decal over the ground: no collision of their own, never
## sunk into the terrain and never floating above it. Returns how many marks the
## group carries, so the caller can tell an empty district from a missing one.
func _check_tire_tracks(group: Node) -> int:
	if group == null:
		return 0
	var marks: int = 0
	for track: Node in group.get_children():
		var surface: MeshInstance3D = track.get_node_or_null("Surface") as MeshInstance3D
		if surface == null or surface.mesh == null:
			_failures.append("Tire track %s has no baked surface" % track.name)
			continue
		marks += 1
		if not surface.material_override is ShaderMaterial:
			_failures.append("Tire track %s needs the tire_track shader material" % track.name)
		if surface.visibility_range_end <= 0.0:
			_failures.append("Tire track %s needs a visibility range" % track.name)
		for child: Node in surface.get_children():
			if child is StaticBody3D:
				_failures.append("Tire tracks must not collide: the terrain carries the floor")
		var placement: Transform3D = (track as Node3D).transform
		for vertex: Vector3 in surface.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			var world_vertex: Vector3 = placement * vertex
			var ground: float = _terrain.data.get_height(world_vertex)
			if is_nan(ground):
				_failures.append("Tire track outside the terrain at %s" % world_vertex)
				break
			var lift: float = world_vertex.y - ground
			if lift < 0.005 or lift > 0.09:
				_failures.append("Tire track %.3f m above the ground at %s" % [lift, world_vertex])
				break
	return marks


func _ground(point: Vector2) -> float:
	var height: float = _terrain.data.get_height(Vector3(point.x, 0.0, point.y))
	return Layout.GROUND_HEIGHT if is_nan(height) else height
