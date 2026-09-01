extends SceneTree

const SHIP_SCENE: PackedScene = preload("res://scenes/Space/AlienShip.tscn")
const SETTLE_FRAMES: int = 10
const TEST_FRAMES: int = 180
const MINIMUM_MOVEMENT: float = 0.25


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var ship: AlienShip = SHIP_SCENE.instantiate() as AlienShip
	ship.spin_speed = 0.18
	root.add_child(ship)
	for frame: int in range(SETTLE_FRAMES):
		await physics_frame

	var npc: GenericNPC = ship.get_node("GenericNPC") as GenericNPC
	var region: NavigationRegion3D = ship.get_node("NavigationRegion3D") as NavigationRegion3D
	var agent: NavigationAgent3D = npc.get_node("NavigationAgent3D") as NavigationAgent3D
	var agent_map: RID = agent.get_navigation_map()
	var region_map: RID = NavigationServer3D.region_get_map(region.get_rid())

	print("NPC behavior: ", npc.behavior)
	print("NPC region path: ", npc.navigation_region_path)
	print("Agent map valid: ", agent_map.is_valid())
	print("Region map valid: ", region_map.is_valid())
	print("Maps match: ", agent_map == region_map)
	print("Map iteration: ", NavigationServer3D.map_get_iteration_id(agent_map))
	print("Region enabled: ", region.enabled)
	print(
		"Region sample: ",
		NavigationServer3D.region_get_random_point(
			region.get_rid(),
			agent.navigation_layers,
			true
		)
	)

	var start_position: Vector3 = npc.position
	for frame: int in range(TEST_FRAMES):
		await physics_frame
	var end_position: Vector3 = npc.position
	var displacement: float = start_position.distance_to(end_position)
	print("NPC start: ", start_position)
	print("NPC end: ", end_position)
	print("NPC displacement: ", displacement)
	print("NPC has target: ", npc.get("_has_patrol_target"))
	print("NPC stored target: ", npc.get("_patrol_target_local"))
	print("Agent target: ", agent.target_position)
	print("Agent next point: ", agent.get_next_path_position())
	print("Agent reachable: ", agent.is_target_reachable())
	print("Agent finished: ", agent.is_navigation_finished())
	print("Agent path: ", agent.get_current_navigation_path())

	if displacement < MINIMUM_MOVEMENT:
		push_error("GenericNPC did not move on the baked navigation region.")
		quit(1)
		return
	quit(0)
