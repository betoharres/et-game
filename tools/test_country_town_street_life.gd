extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _run() -> void:
	var world: Node3D = Node3D.new()
	root.add_child(world)
	_add_terrain_floor(world)
	for label: String in ["RoadNetwork", "TownDistrict"]:
		var district: Node = (load("res://scenes/CountryTown/Districts/%s.tscn" % label) as PackedScene).instantiate()
		world.add_child(district)
		for node: Node in district.find_children("*", "", true, false):
			node.set_process(false)
			node.set_physics_process(false)
	var life: NavigationRegion3D = (load("res://scenes/CountryTown/Districts/PedestrianLife.tscn") as PackedScene).instantiate() as NavigationRegion3D
	world.add_child(life)
	for frame: int in 12:
		await physics_frame
	var actors: Array[Node] = life.get_node("Pedestrians").get_children()
	_check(actors.size() == 78, "Expected 78 pedestrians")
	_check(get_nodes_in_group(&"town_outskirts_pedestrians").size() == 18, "Expected 18 outskirts pedestrians")
	_check(get_nodes_in_group(&"farm_commuters").size() == 12, "Expected 12 farm commuters")
	_check(get_nodes_in_group(&"town_crosswalks").size() == 26, "Expected 26 crosswalks")
	var map: RID = life.get_navigation_map()
	_check(map != world.get_world_3d().navigation_map, "Pedestrians must use a separate map")
	var starts: Array[Vector3] = []
	for node: Node in actors:
		var actor: NPCActor = node as NPCActor
		starts.append(actor.global_position)
		_check(actor.navigation_agent.get_navigation_map() == map, "Incorrect navigation map: %s" % actor.name)
		var player: AnimationPlayer = actor.get_node("AnimationPlayer") as AnimationPlayer
		_check(player.has_animation(&"Walk") and player.has_animation(&"Idle"), "Missing animation: %s" % actor.name)
		for index: int in actor.patrol_points.size():
			var from: Vector3 = actor.patrol_points[index]
			var to: Vector3 = actor.patrol_points[(index + 1) % actor.patrol_points.size()]
			var path: PackedVector3Array = NavigationServer3D.map_get_path(map, from, to, true)
			_check(not path.is_empty() and path[-1].distance_to(to) < 0.8, "Disconnected route: %s %s -> %s" % [actor.name, from, to])
	for frame: int in 480:
		await physics_frame
	var moved: int = 0
	for index: int in actors.size():
		var actor: NPCActor = actors[index] as NPCActor
		if Vector2(actor.global_position.x, actor.global_position.z).distance_to(Vector2(starts[index].x, starts[index].z)) > 2.0:
			moved += 1
		_check(actor.global_position.y > 5.5, "Pedestrian fell through ground: %s at %s" % [actor.name, actor.global_position])
	_check(moved >= 70, "Only %d/78 pedestrians moved more than 2 m" % moved)
	await _test_crossing(life, world)
	print("Street life check: %d/78 moving, 18 outskirts walkers, 12 farm commuters, 26 crossings, animations, routes and crossing priority; %d failures" % [moved, _failures.size()])
	for failure: String in _failures:
		push_error(failure)
	world.queue_free()
	for frame: int in 3:
		await process_frame
	quit(0 if _failures.is_empty() else 1)


func _add_terrain_floor(world: Node3D) -> void:
	# As vias ligadas são niveladas na cota do vale; um piso amplo isola a locomoção.
	var body: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(550, 0.2, 410)
	collision.shape = shape
	collision.position = Vector3(310, 5.9, 220)
	body.add_child(collision)
	world.add_child(body)


func _test_crossing(life: NavigationRegion3D, world: Node3D) -> void:
	var actor: NPCActor = life.get_node("Pedestrians/Pedestrian01") as NPCActor
	for node: Node in life.get_node("Pedestrians").get_children():
		(node.get_node("NPCBehaviorTree") as BeehaveTree).enabled = false
	var crossing: Node3D = life.get_node("Crosswalk02") as Node3D
	actor.global_position = crossing.to_global(Vector3(-5.8, 0.25, 0))
	actor.velocity = Vector3.ZERO
	actor.stop_moving()
	actor.navigation_agent.target_position = crossing.to_global(Vector3(5.8, 0.25, 0))
	for frame: int in 3:
		await physics_frame
		actor.navigation_agent.get_next_path_position()
	var leaf: ActionLeaf = actor.get_node("NPCBehaviorTree/Root/WaitForTraffic") as ActionLeaf
	var blackboard: Blackboard = Blackboard.new()
	var car: RigidBody3D = RigidBody3D.new()
	car.gravity_scale = 0.0
	car.add_to_group(&"vehicles")
	world.add_child(car)
	car.global_position = crossing.to_global(Vector3(2.25, 0.5, -15.0))
	car.linear_velocity = crossing.global_basis * Vector3(0, 0, 6)
	_check(leaf.tick(actor, blackboard) == ActionLeaf.RUNNING, "Pedestrian must yield to approaching vehicle")
	car.global_position = crossing.to_global(Vector3(2.25, 0.5, 20.0))
	_check(leaf.tick(actor, blackboard) == ActionLeaf.FAILURE, "Pedestrian must resume after vehicle passes")
	actor.global_position = crossing.to_global(Vector3(0, 0.25, 0))
	car.global_position = crossing.to_global(Vector3(2.25, 0.5, -4.0))
	_check(leaf.tick(actor, blackboard) == ActionLeaf.FAILURE, "Pedestrian already crossing must clear the road")
	car.queue_free()
	blackboard.free()
