extends SceneTree

## Gera somente navegação e população; não regrava terreno nem distritos visuais.
const Layout: GDScript = preload("res://tools/build_country_town_layout.gd")
const NAV_PATH: String = "res://scenes/CountryTown/Layout/PedestrianNavigation.res"
const POP_PATH: String = "res://scenes/CountryTown/Districts/NPCs.tscn"
const ACTIVITY_SCRIPT: Script = preload("res://scripts/npc/npc_activity.gd")
const ROUTINE_SCRIPT: Script = preload("res://scripts/npc/npc_routine.gd")
var _world: Node3D
var _terrain: Terrain3D
var _population: Node3D
var _activities: Node3D
var _map: RID
var _region: RID
var _roads: Array[PackedVector2Array] = []
var _failures: Array[String] = []
var _spawn_counts: Dictionary[String, int] = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	_world.process_mode = Node.PROCESS_MODE_DISABLED
	for district: String in ["RoadNetwork", "SecondaryPaths", "RiverDistrict", "FarmDistrict", "TownDistrict", "Detailing", "DeliveryYard", "MinePortalSite", "CrashSiteDistrict"]:
		_world.add_child((load("res://scenes/CountryTown/Districts/%s.tscn" % district) as PackedScene).instantiate())
	_terrain = Terrain3D.new()
	_world.add_child(_terrain)
	_terrain.data_directory = "res://scenes/CountryTown/Terrain"
	await process_frame
	var nav: NavigationMesh = _bake_navigation()
	if nav.get_polygon_count() == 0:
		push_error("Navegacao vazia")
		quit(1)
		return
	_map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_use_async_iterations(_map, false)
	NavigationServer3D.map_set_cell_size(_map, nav.cell_size)
	NavigationServer3D.map_set_cell_height(_map, nav.cell_height)
	NavigationServer3D.map_set_active(_map, true)
	_region = NavigationServer3D.region_create()
	NavigationServer3D.region_set_enabled(_region, true)
	NavigationServer3D.region_set_navigation_layers(_region, 1)
	NavigationServer3D.region_set_transform(_region, Transform3D.IDENTITY)
	NavigationServer3D.region_set_map(_region, _map)
	NavigationServer3D.region_set_navigation_mesh(_region, nav)
	NavigationServer3D.map_force_update(_map)
	for frame: int in 4:
		await physics_frame
	await create_timer(0.2).timeout
	NavigationServer3D.map_force_update(_map)
	print("Navegacao sincronizada: iteracao %d, %d poligonos" % [NavigationServer3D.map_get_iteration_id(_map), nav.get_polygon_count()])
	print("Regioes: ", NavigationServer3D.map_get_regions(_map), " vertices: ", nav.get_vertices().size(), " primeiro: ", nav.get_vertices()[0], " bounds: ", NavigationServer3D.region_get_bounds(_region))
	_population = Node3D.new()
	_population.name = "NPCs"
	# Fora da árvore: PackedScene guarda apenas configuração, sem executar NPCs.
	_activities = Node3D.new()
	_activities.name = "Activities"
	_population.add_child(_activities)
	_activities.owner = _population
	_build_activities()
	_build_people()
	_validate_routes()
	if not _failures.is_empty():
		for failure: String in _failures:
			push_error(failure)
		quit(1)
		return
	var packed: PackedScene = PackedScene.new()
	var result: Error = packed.pack(_population)
	if result == OK:
		result = ResourceSaver.save(packed, POP_PATH)
	if result == OK:
		result = ResourceSaver.save(nav, NAV_PATH)
	print("Country Town: %d NPCs, %d atividades, %d poligonos de navegacao. Resultado: %s" % [_population.get_child_count() - 1, _activities.get_child_count(), nav.get_polygon_count(), error_string(result)])
	_population.free()
	_world.free()
	NavigationServer3D.free_rid(_region)
	NavigationServer3D.free_rid(_map)
	quit(0 if result == OK else 1)


func _bake_navigation() -> NavigationMesh:
	var nav: NavigationMesh = NavigationMesh.new()
	nav.cell_size = 0.3
	nav.cell_height = 0.15
	nav.agent_radius = 0.35
	nav.agent_height = 1.9
	nav.agent_max_climb = 0.3
	nav.agent_max_slope = 35.0
	nav.region_min_size = 3.0
	nav.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav.filter_baking_aabb = AABB(Vector3(15, 3.9, 10), Vector3(555, 17, 400))
	var source: NavigationMeshSourceGeometryData3D = NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nav, source, _world)
	_roads = Layout.road_polygons(false, 3.0) + Layout.road_polygons(true, 4.0)
	var faces: PackedVector3Array = []
	for z: int in range(10, 410):
		for x: int in range(15, 570):
			var center: Vector2 = Vector2(x + 0.5, z + 0.5)
			if not _walkable_ground(center):
				continue
			var a: Vector3 = _ground(x, z)
			var b: Vector3 = _ground(x + 1, z)
			var c: Vector3 = _ground(x + 1, z + 1)
			var d: Vector3 = _ground(x, z + 1)
			if minf(minf(a.y, b.y), minf(c.y, d.y)) < 4.2:
				continue
			faces.append_array(PackedVector3Array([a, b, c, a, c, d]))
	source.add_faces(faces, Transform3D.IDENTITY)
	print("Assando navegacao: %d triangulos de terreno e colisoes dos distritos." % (faces.size() / 3))
	NavigationServer3D.bake_from_source_geometry_data(nav, source)
	return nav


func _ground(x: float, z: float) -> Vector3:
	var point: Vector3 = Vector3(x, 0, z)
	point.y = _terrain.data.get_height(point)
	return point


func _walkable_ground(point: Vector2) -> bool:
	# Bairro e pátios; as colisões recortam casas, cercas, cargas e carros.
	if Rect2(373, 135, 185, 225).has_point(point):
		return true
	for area: Rect2 in Layout.SETTLEMENT_CLEARINGS:
		if area.grow(5.0).has_point(point):
			return true
	for area: Rect2 in [Rect2(35, 34, 50, 84), Rect2(153, 151, 100, 45), Rect2(134, 279, 35, 51), Rect2(310, 360, 50, 32), Rect2(36, 345, 31, 25)]:
		if area.has_point(point):
			return true
	for polygon: PackedVector2Array in _roads:
		if Geometry2D.is_point_in_polygon(point, polygon):
			return true
	for path: Dictionary in Layout.SECONDARY_PATHS:
		var points: Array = path["points"]
		for index: int in points.size() - 1:
			if Geometry2D.get_closest_point_to_segment(point, points[index], points[index + 1]).distance_to(point) < float(path["width"]) * 0.5 + 1.0:
				return true
	return false


func _activity(label: String, point: Vector3, kind: StringName, capacity: int = 1, wait_min: float = 15.0, wait_max: float = 35.0) -> void:
	var activity: NPCActivity = ACTIVITY_SCRIPT.new() as NPCActivity
	activity.name = label
	activity.activity = kind
	activity.duration_min = wait_min
	activity.duration_max = wait_max
	var center: Vector3 = NavigationServer3D.map_get_closest_point(_map, point)
	if center.distance_to(point) > 12.0 or absf(center.y - point.y) > 1.5:
		_failures.append("Atividade %s longe de passagem: %s -> %s" % [label, point, center])
	activity.position = center
	activity.slots = PackedVector3Array()
	for index: int in capacity:
		var offset: Vector3 = Vector3((index - (capacity - 1) * 0.5) * 1.6, 0, 0)
		var slot: Vector3 = NavigationServer3D.map_get_closest_point(_map, center + offset)
		activity.slots.append(slot - center)
	_activities.add_child(activity)
	activity.owner = _population


func _build_activities() -> void:
	_activity("Square", Vector3(466, 6, 218), &"observe", 3, 18, 45)
	_activity("Store", Vector3(400, 6, 214), &"wait", 2, 10, 24)
	_activity("Bakery", Vector3(450, 6, 220), &"wait", 2, 10, 22)
	_activity("Cafe", Vector3(536, 6, 213), &"observe", 3, 22, 50)
	_activity("Church", Vector3(532, 6, 285), &"observe", 3, 20, 45)
	_activity("NorthCorner", Vector3(450, 6, 173), &"observe", 2, 5, 12)
	_activity("SouthCorner", Vector3(508, 6, 353), &"observe", 2, 6, 14)
	_activity("Farmhouse", Vector3(60, 6, 47), &"observe", 2, 20, 40)
	_activity("Barn", Vector3(82, 6, 101), &"work", 2, 25, 55)
	_activity("Tractor", Vector3(133, 6, 146), &"work", 2, 25, 50)
	_activity("Pen", Vector3(186, 6, 169), &"work", 2, 25, 50)
	_activity("EastFarm", Vector3(240, 6, 178), &"work", 2, 25, 55)
	_activity("Mill", Vector3(151, 6, 289), &"work", 2, 25, 55)
	_activity("MillYard", Vector3(152, 6, 315), &"work", 2, 20, 45)
	_activity("Dock", Vector3(50, 6, 357), &"observe", 2, 35, 70)
	_activity("Shed", Vector3(47, 6, 225), &"work", 1, 25, 55)
	_activity("Delivery", Vector3(349, 6, 369), &"work", 2, 20, 50)
	_activity("SouthFarm", Vector3(321, 6, 374), &"work", 2, 25, 55)
	var town: Node = _world.get_node("TownDistrict/UrbanInfill")
	for lot: Node in town.get_children():
		if not String(lot.name).begins_with("Casa"):
			continue
		var entry: Node3D = lot.get_node("Entrance") as Node3D
		_activity(String(lot.name), entry.global_position, &"home", 1, 35, 85)


func _person(label: String, role: String, route: Array[String], ordinal: int) -> void:
	var packed: PackedScene = load("res://scenes/NPCs/%s.tscn" % role) as PackedScene
	var actor: NPCActor = packed.instantiate() as NPCActor
	actor.name = label
	actor.require_navigation = true
	actor.grounded = true
	actor.walk_speed = 1.35 + (ordinal % 7) * 0.1
	actor.alert_speed = 3.3 + (ordinal % 3) * 0.15
	actor.scale = Vector3.ONE * (0.96 + (ordinal % 6) * 0.014)
	actor.rotation.y = ordinal * 2.39996
	actor.search_duration = 8.0 + ordinal % 5
	actor.chat_cooldown = 25.0 + ordinal % 12
	actor.patrol_points = []
	for label_point: String in route:
		actor.patrol_points.append((_activities.get_node(label_point) as Node3D).position)
	var origin: NPCActivity = _activities.get_node(route[0]) as NPCActivity
	var spawn_slot: int = _spawn_counts.get(route[0], 0)
	_spawn_counts[route[0]] = spawn_slot + 1
	if spawn_slot >= origin.slots.size():
		_failures.append("Spawn sem vaga: %s em %s" % [label, route[0]])
	actor.position = origin.position + origin.slots[spawn_slot % origin.slots.size()] + Vector3.UP * 0.1
	_population.add_child(actor)
	actor.owner = _population
	var routine: NPCRoutine = ROUTINE_SCRIPT.new() as NPCRoutine
	routine.name = "NPCRoutine"
	for label_point: String in route:
		routine.activity_paths.append(NodePath("../../Activities/" + label_point))
	routine.refuge_path = routine.activity_paths[0]
	actor.add_child(routine)
	routine.owner = _population
	# Mesma malha/rig, variação discreta local sem alterar materiais importados.
	var visual: MeshInstance3D = actor.get_node("Character/Skeleton3D/PolygonSyntyCharacterMesh") as MeshInstance3D
	var material: StandardMaterial3D = visual.get_active_material(0).duplicate() as StandardMaterial3D
	material.albedo_color = Color.from_hsv(0.06 + (ordinal % 5) * 0.04, 0.05 + (ordinal % 4) * 0.06, 0.78 + (ordinal % 3) * 0.1)
	visual.set_surface_override_material(0, material)
	visual.layers = 16
	# Overrides de descendentes precisam ser editáveis no PackedScene herdado.
	actor.set_editable_instance(actor.get_node("Character"), true)
	_population.set_editable_instance(actor, true)


func _build_people() -> void:
	_person("FarmerPatrolling", "Farmer", ["Farmhouse", "Barn", "Tractor"], 0)
	_person("FarmerWorking", "Farmer", ["Tractor", "Barn"], 1)
	_person("FarmerPatrolling2", "Farmer", ["Pen", "EastFarm"], 2)
	_person("FarmerWorking2", "Farmer", ["EastFarm", "Pen"], 3)
	_person("FarmerPatrolling3", "Farmer", ["Mill", "MillYard"], 4)
	_person("FarmerPatrolling4", "Farmer", ["SouthFarm", "Delivery"], 5)
	_person("DockWorker", "Farmer", ["Dock", "MillYard"], 6)
	_person("ShedWorker", "Farmer", ["Shed", "Barn"], 7)
	_person("DeliveryWorker", "Farmer", ["Delivery", "SouthFarm"], 8)
	_person("MillWorker", "Farmer", ["MillYard", "Mill"], 9)
	var homes: Array[String] = []
	for activity: Node in _activities.get_children():
		if String(activity.name).begins_with("Casa"):
			homes.append(String(activity.name))
	var destinations: Array[String] = ["Store", "Bakery", "Square", "Cafe", "Church"]
	for index: int in homes.size():
		var label: String = "Townsperson" + (str(index + 1) if index > 0 else "")
		_person(label, "Townsperson", [homes[index], destinations[index % 5], homes[index], destinations[(index + 2) % 5]], index + 10)
	_person("PoliceOfficer", "PoliceOfficer", ["NorthCorner", "Store", "Square"], 32)
	_person("PoliceOfficer2", "PoliceOfficer", ["Church", "Cafe", "Square"], 33)
	_person("PoliceOfficer3", "PoliceOfficer", ["SouthCorner", "Church", "Delivery"], 34)
	_person("RiversideWalker", "Townsperson", ["Dock", "Shed", "Mill"], 35)


func _validate_routes() -> void:
	for child: Node in _population.get_children():
		var actor: NPCActor = child as NPCActor
		if actor == null:
			continue
		var points: Array[Vector3] = actor.patrol_points
		for index: int in points.size():
			var from: Vector3 = points[index]
			var to: Vector3 = points[(index + 1) % points.size()]
			var path: PackedVector3Array = NavigationServer3D.map_get_path(_map, from, to, true)
			if path.is_empty() or path[-1].distance_to(to) > 1.0:
				_failures.append("Rota desconectada %s: %s -> %s" % [actor.name, from, to])
