extends SceneTree

var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	var world: Node3D = Node3D.new()
	root.add_child(world)
	var region: NavigationRegion3D = NavigationRegion3D.new()
	region.navigation_mesh = load("res://tools/fixtures/enemy_navigation.tres") as NavigationMesh
	world.add_child(region)
	var actors: Array[NPCActor] = []
	var paths: Array[String] = ["res://scenes/NPCs/SmellyFarmer.tscn", "res://scenes/NPCs/Photographer.tscn", "res://scenes/Multiplayer/CoopGuard.tscn", "res://scenes/NPCs/Pursuit/PursuitAgent.tscn"]
	for index: int in range(paths.size()):
		var actor: NPCActor = (load(paths[index]) as PackedScene).instantiate() as NPCActor
		actor.position = Vector3(index * 4, 0, -10)
		world.add_child(actor)
		actors.append(actor)
	for frame: int in range(30):
		await physics_frame
	for actor: NPCActor in actors:
		_check(actor._navigation_configured, "%s finds saved navigation" % actor.name)
		_check(actor.navigation_agent.get_navigation_map() == region.get_navigation_map(), "%s uses level navigation" % actor.name)
		_check(actor.get_node("NPCBehaviorTree").scene_file_path == "res://scenes/NPCs/Behaviors/NPCBehaviorTree.tscn", "%s shares behavior tree" % actor.name)
		if actor.has_method("set_host_simulation"):
			_check(actor.get("_session") == null and actor.get("_host_simulation") == true, "%s runs standalone" % actor.name)
	var guard: NPCActor = actors[2]
	var route: Array[Vector3] = guard.get_patrol_positions().duplicate()
	_check(route.size() == 2 and route[1].distance_to(route[0]) > 7.9, "Guard resolves local patrol markers")
	guard.position.x += 3.0
	_check(guard.get_patrol_positions() == route, "Patrol markers stay anchored when NPC moves")
	var viewport: SubViewport = SubViewport.new()
	viewport.own_world_3d = true
	root.add_child(viewport)
	var missing: NPCActor = (load(paths[2]) as PackedScene).instantiate() as NPCActor
	viewport.add_child(missing)
	for frame: int in range(30):
		await physics_frame
	_check(not missing._navigation_configured, "Enemy cannot borrow another viewport's navigation")
	var before: Vector3 = missing.global_position
	missing.move_toward_point(before + Vector3.RIGHT * 10, 2.0)
	_check(missing.navigation_failed, "Missing navigation fails movement without direct fallback")
	for frame: int in range(30):
		await physics_frame
	_check(is_zero_approx(missing.global_position.x - before.x), "Missing navigation does not move toward target")
	world.queue_free()
	viewport.queue_free()
	await process_frame
	print("Enemy placement: %d failures" % failures)
	quit(1 if failures > 0 else 0)
