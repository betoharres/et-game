extends SceneTree

const Layout: GDScript = preload("res://tools/build_country_town_layout.gd")
const Cars: GDScript = preload("res://tools/town_civilian_cars.gd")
const OUTPUT: String = "res://scenes/CountryTown/Districts/PedestrianLife.tscn"
const INFILL: String = "res://scenes/CountryTown/Districts/UrbanInfill.tscn"
const CORE_COUNT: int = 24
const OUTSKIRT_COUNT: int = 9
const FARM_COMMUTER_COUNT: int = 6
const TOTAL_COUNT: int = CORE_COUNT + OUTSKIRT_COUNT + FARM_COMMUTER_COUNT
# X, Z e orientação da via; cada faixa une as duas calçadas fora do cruzamento.
const CROSSINGS: Array[Vector3] = [
	Vector3(455.05, 183, 0), Vector3(455.05, 224, 0),
	Vector3(455.05, 260, 0), Vector3(455.05, 288, 0),
	Vector3(480, 167.46, 90), Vector3(480, 211, 90),
	Vector3(480, 238.93, 90), Vector3(480, 278, 90),
	Vector3(516, 183, 0), Vector3(516, 224, 0),
	Vector3(516, 260, 0), Vector3(535, 211, 90),
	Vector3(535, 238.93, 90), Vector3(535, 278, 90),
	Vector3(424, 195, 0), Vector3(440, 238.93, 90),
	Vector3(339, 167.46, 90), Vector3(234, 298.48, 90),
	Vector3(385, 167.46, 90), Vector3(440, 167.46, 90),
	Vector3(535, 167.46, 90), Vector3(367, 285, 0),
	Vector3(553, 305, 0), Vector3(535, 318, 90),
	Vector3(455, 340, 0), Vector3(350, 365, 0),
]
var _farm_links: Array[PackedVector2Array] = [
	PackedVector2Array([Vector2(400, 161.2), Vector2(365, 161.2), Vector2(344, 161.2), Vector2(335, 165.2), Vector2(318, 165.2), Vector2(300, 165.2), Vector2(288, 162.5), Vector2(200, 162.5), Vector2(68, 162.5), Vector2(56.5, 155), Vector2(56.5, 40)]),
	PackedVector2Array([Vector2(372, 304.5), Vector2(350, 304.5), Vector2(235, 304.5), Vector2(228, 300.5), Vector2(205, 300.5), Vector2(181, 303.5), Vector2(151, 303.5), Vector2(151, 289)]),
]
var _map: RID
var _region: RID
var _random: RandomNumberGenerator = RandomNumberGenerator.new()
var _scene: NavigationRegion3D
var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_random.seed = 81723
	_scene = NavigationRegion3D.new()
	_scene.name = "PedestrianLife"
	_scene.set_script(load("res://scripts/town_pedestrian_navigation.gd"))
	var source: NavigationMeshSourceGeometryData3D = NavigationMeshSourceGeometryData3D.new()
	var roads: Node3D = (load("res://scenes/CountryTown/Districts/RoadNetwork.tscn") as PackedScene).instantiate() as Node3D
	for label: String in ["Sidewalks", "Curbs"]:
		var mesh: MeshInstance3D = roads.get_node(label) as MeshInstance3D
		source.add_mesh(mesh.mesh, mesh.transform)
	roads.free()
	_add_farm_links(source)
	_build_crossings(source)
	var nav: NavigationMesh = NavigationMesh.new()
	nav.cell_size = 0.2
	nav.cell_height = 0.1
	nav.agent_radius = 0.4
	nav.agent_height = 1.9
	nav.agent_max_climb = 0.3
	nav.region_min_size = 1.0
	nav.filter_baking_aabb = AABB(Vector3(45, 5.7, 25), Vector3(530, 2, 390))
	NavigationServer3D.bake_from_source_geometry_data(nav, source)
	_scene.navigation_mesh = nav
	_map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_use_async_iterations(_map, false)
	NavigationServer3D.map_set_cell_size(_map, nav.cell_size)
	NavigationServer3D.map_set_cell_height(_map, nav.cell_height)
	NavigationServer3D.map_set_active(_map, true)
	_region = NavigationServer3D.region_create()
	NavigationServer3D.region_set_map(_region, _map)
	NavigationServer3D.region_set_navigation_mesh(_region, nav)
	NavigationServer3D.map_force_update(_map)
	for frame: int in 4:
		await physics_frame
	NavigationServer3D.map_force_update(_map)
	_build_pedestrians()
	if _failures.is_empty():
		_save(_scene, OUTPUT)
		_update_cars()
	for failure: String in _failures:
		push_error(failure)
	print("Street life: %d pedestrians (%d outskirts, %d farm commuters), %d crossings, %d navigation polygons; %d failures" % [TOTAL_COUNT, OUTSKIRT_COUNT, FARM_COMMUTER_COUNT, CROSSINGS.size(), nav.get_polygon_count(), _failures.size()])
	_scene.free()
	NavigationServer3D.free_rid(_region)
	NavigationServer3D.free_rid(_map)
	quit(0 if _failures.is_empty() else 1)


func _build_crossings(source: NavigationMeshSourceGeometryData3D) -> void:
	var paint: StandardMaterial3D = StandardMaterial3D.new()
	paint.albedo_color = Color(0.88, 0.86, 0.77)
	paint.roughness = 0.96
	var stripe: PlaneMesh = PlaneMesh.new()
	stripe.size = Vector2(0.48, 3.2)
	var deck: PlaneMesh = PlaneMesh.new()
	deck.size = Vector2(13.0, 3.2)
	for index: int in CROSSINGS.size():
		var recipe: Vector3 = CROSSINGS[index]
		var crossing: Node3D = Node3D.new()
		crossing.name = "Crosswalk%02d" % (index + 1)
		crossing.position = Vector3(recipe.x, Layout.asphalt_marking_height(Vector2(recipe.x, recipe.y)), recipe.y)
		crossing.rotation_degrees.y = recipe.z
		crossing.add_to_group(&"town_crosswalks", true)
		_scene.add_child(crossing)
		for bar: int in 11:
			var visual: MeshInstance3D = MeshInstance3D.new()
			visual.name = "Stripe%02d" % bar
			visual.mesh = stripe
			visual.material_override = paint
			visual.position.x = (bar - 5) * 0.78
			# Sobrepõe a linha central existente sem duas pinturas coplanares piscando.
			visual.position.y = 0.008
			visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			visual.visibility_range_end = 180.0
			visual.visibility_range_end_margin = 15.0
			crossing.add_child(visual)
		var nav_transform: Transform3D = crossing.transform
		nav_transform.origin.y = 6.08
		source.add_mesh(deck, nav_transform)


func _add_farm_links(source: NavigationMeshSourceGeometryData3D) -> void:
	var faces: PackedVector3Array = []
	for path: PackedVector2Array in _farm_links:
		for index: int in path.size() - 1:
			var start: Vector2 = path[index]
			var end: Vector2 = path[index + 1]
			var side: Vector2 = (end - start).normalized().orthogonal() * 1.25
			var a: Vector2 = start + side
			var b: Vector2 = end + side
			var c: Vector2 = end - side
			var d: Vector2 = start - side
			faces.append_array(PackedVector3Array([_road_point(a), _road_point(b), _road_point(c), _road_point(a), _road_point(c), _road_point(d)]))
	source.add_faces(faces, Transform3D.IDENTITY)


func _road_point(point: Vector2) -> Vector3:
	return Vector3(point.x, Layout.road_height(point) + 0.08, point.y)


func _build_pedestrians() -> void:
	var people: Node3D = Node3D.new()
	people.name = "Pedestrians"
	_scene.add_child(people)
	var core_candidates: Array[Vector3] = _sidewalk_candidates(Rect2i(407, 176, 150, 136), false)
	var outskirts_candidates: Array[Vector3] = _sidewalk_candidates(Rect2i(348, 145, 214, 215), true)
	var used: Array[Vector3] = []
	_spawn_people(people, core_candidates, used, CORE_COUNT, "Pedestrian", 0)
	_spawn_people(people, outskirts_candidates, used, OUTSKIRT_COUNT, "OutskirtsPedestrian", CORE_COUNT)
	_spawn_farm_commuters(people, CORE_COUNT + OUTSKIRT_COUNT)


func _sidewalk_candidates(bounds: Rect2i, outskirts_only: bool) -> Array[Vector3]:
	var candidates: Array[Vector3] = []
	for z: int in range(bounds.position.y, bounds.end.y, 4):
		for x: int in range(bounds.position.x, bounds.end.x, 4):
			var target: Vector3 = Vector3(x, 6.1, z)
			var point: Vector3 = NavigationServer3D.map_get_closest_point(_map, target)
			if point.distance_to(target) < 0.65 and _on_sidewalk(point) and (not outskirts_only or _is_outskirts(point)):
				candidates.append(point)
	return candidates


func _is_outskirts(point: Vector3) -> bool:
	return point.x < 410.0 or point.x > 545.0 or point.z < 178.0 or point.z > 310.0


func _spawn_people(people: Node3D, candidates: Array[Vector3], used: Array[Vector3], count: int, prefix: String, ordinal_start: int) -> void:
	var packed: PackedScene = load("res://scenes/NPCs/Townsperson.tscn") as PackedScene
	for local_index: int in count:
		var ordinal: int = ordinal_start + local_index
		var spawn: Vector3 = Vector3.INF
		for attempt: int in 600:
			if candidates.is_empty():
				break
			var candidate: Vector3 = candidates[_random.randi_range(0, candidates.size() - 1)]
			var clear: bool = true
			for previous: Vector3 in used:
				if previous.distance_to(candidate) < (4.0 if prefix == "OutskirtsPedestrian" else 3.0):
					clear = false
			if clear:
				spawn = candidate
				break
		if not spawn.is_finite():
			_failures.append("No separated sidewalk spawn for %s %d" % [prefix, local_index])
			return
		used.append(spawn)
		var route: Array[Vector3] = []
		var current: Vector3 = spawn
		for stop: int in 4:
			for attempt: int in 300:
				var target: Vector3 = candidates[_random.randi_range(0, candidates.size() - 1)]
				if current.distance_to(target) < 18.0 or current.distance_to(target) > 65.0:
					continue
				var path: PackedVector3Array = NavigationServer3D.map_get_path(_map, current, target, true)
				if path.is_empty() or path[-1].distance_to(target) > 0.8:
					continue
				var length: float = 0.0
				for step: int in path.size() - 1:
					length += path[step].distance_to(path[step + 1])
				if length > 110.0:
					continue
				route.append(target)
				current = target
				break
		if route.size() != 4:
			_failures.append("Incomplete pedestrian route at %s" % spawn)
			continue
		route.append(spawn)
		var actor: NPCActor = packed.instantiate() as NPCActor
		_configure_person(actor, people, route, "%s%02d" % [prefix, local_index + 1], ordinal, prefix == "OutskirtsPedestrian")


func _spawn_farm_commuters(people: Node3D, ordinal_start: int) -> void:
	var north: Array[Vector3] = []
	for point: Vector2 in _farm_links[0]:
		north.append(_road_point(point))
	var south: Array[Vector3] = []
	for point: Vector2 in _farm_links[1]:
		south.append(_road_point(point))
	var packed: PackedScene = load("res://scenes/NPCs/Townsperson.tscn") as PackedScene
	for index: int in FARM_COMMUTER_COUNT:
		var route: Array[Vector3] = north.duplicate() if index < 8 else south.duplicate()
		if index % 2 == 1:
			route.reverse()
		var shift: int = floori(float(index) / 2.0) % route.size()
		for step: int in shift:
			route.append(route.pop_front())
		var actor: NPCActor = packed.instantiate() as NPCActor
		_configure_person(actor, people, route, "FarmCommuter%02d" % (index + 1), ordinal_start + index, false)
		actor.add_to_group(&"farm_commuters", true)
		actor.walk_speed = _random.randf_range(1.25, 1.7)


func _configure_person(actor: NPCActor, people: Node3D, route: Array[Vector3], label: String, ordinal: int, outskirts: bool) -> void:
	actor.name = label
	actor.add_to_group(&"town_pedestrians", true)
	if outskirts:
		actor.add_to_group(&"town_outskirts_pedestrians", true)
	actor.position = route[-1] + Vector3.UP * 0.05
	actor.rotation.y = atan2(route[0].x - actor.position.x, route[0].z - actor.position.z)
	actor.require_navigation = true
	actor.grounded = true
	actor.walk_speed = _random.randf_range(1.15, 1.85)
	actor.rotation_speed = 5.0
	actor.patrol_points = route
	actor.patrol_wait_time_min = 0.5
	actor.patrol_wait_time_max = 3.5
	actor.scale = Vector3.ONE * _random.randf_range(0.94, 1.05)
	(actor.get_node("NavigationAgent3D") as NavigationAgent3D).path_height_offset = 0.0
	var visual: MeshInstance3D = actor.get_node("Character/Skeleton3D/PolygonSyntyCharacterMesh") as MeshInstance3D
	var material: StandardMaterial3D = visual.get_active_material(0).duplicate() as StandardMaterial3D
	material.albedo_color = Color.from_hsv(float(ordinal % 8) / 8.0, 0.10 + (ordinal % 3) * 0.08, 0.72 + (ordinal % 4) * 0.09)
	visual.set_surface_override_material(0, material)
	visual.layers = 16
	visual.visibility_range_end = 190.0
	visual.visibility_range_end_margin = 20.0
	var animation: NPCAnimation = actor.get_node("NPCAnimation") as NPCAnimation
	if ordinal % 2 == 0:
		animation.idle_clip = load("res://Temporarios/Animations/Polygon/Masculine/Idle/A_Idle_Standing_Masc.fbx") as PackedScene
		animation.walk_clip = load("res://Temporarios/Animations/Polygon/Masculine/Locomotion/Walk/A_Walk_F_Masc.fbx") as PackedScene
	(actor.get_node("AnimationPlayer") as AnimationPlayer).speed_scale = actor.walk_speed / 1.5
	people.add_child(actor)
	_scene.set_editable_instance(actor, true)
	actor.set_editable_instance(actor.get_node("Character"), true)


func _on_sidewalk(point: Vector3) -> bool:
	for recipe: Vector3 in CROSSINGS:
		var local: Vector3 = Basis(Vector3.UP, deg_to_rad(recipe.z)).inverse() * (point - Vector3(recipe.x, 6.08, recipe.y))
		if absf(local.x) < 4.8 and absf(local.z) < 2.0:
			return false
	return true


func _update_cars() -> void:
	var town: Node3D = (load(INFILL) as PackedScene).instantiate() as Node3D
	var count: int = 0
	for lot: Node in town.get_children():
		var old: Node3D = lot.get_node_or_null("ParkedCar") as Node3D
		var space: Node3D = lot.get_node_or_null("ParkingSpace") as Node3D
		if space == null:
			continue
		var number: int = String(lot.name).trim_prefix("Casa").to_int()
		var car: Node3D = Cars.build(number)
		if old != null:
			car.transform = old.transform
			lot.remove_child(old)
			old.free()
		else:
			car.position = space.position - Vector3.UP * 0.02
			car.rotation_degrees.y = 180 if number % 2 == 0 else 0
			var stop: Node = lot.get_node_or_null("WheelStop")
			if stop != null:
				stop.free()
		lot.add_child(car)
		count += 1
	_save(town, INFILL)
	print("Updated %d parked cars in existing private spaces" % count)
	town.free()


func _own(node: Node, owner_root: Node) -> void:
	for child: Node in node.get_children():
		child.owner = owner_root
		if child.scene_file_path.is_empty():
			_own(child, owner_root)


func _save(node: Node, path: String) -> void:
	_own(node, node)
	var packed: PackedScene = PackedScene.new()
	if packed.pack(node) != OK or ResourceSaver.save(packed, path) != OK:
		_failures.append("Cannot save %s" % path)
