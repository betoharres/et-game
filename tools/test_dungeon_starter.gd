extends SceneTree

const DUNGEON_SCENE: PackedScene = preload("res://scenes/Dungeon/Dungeon.tscn")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for seed_value: int in range(1, 13):
		var dungeon: Node3D = DUNGEON_SCENE.instantiate() as Node3D
		root.add_child(dungeon)
		dungeon.set("generation_seed", seed_value)
		dungeon.set("grid_width", 2 if seed_value < 7 else 12)
		dungeon.set("grid_depth", 2 if seed_value < 7 else 12)
		dungeon.call("ensure_generated", Vector3.ZERO)
		assert(bool(dungeon.get("_generated")), "Generation failed")
		var connections: Dictionary = dungeon.call("get_connection_masks")
		assert(bool(dungeon.call("_validate_connection_masks", connections)))
		var entry: Vector2i = dungeon.get("_entry_cell")
		assert(int(connections[entry]) == DungeonModule.Direction.SOUTH)
		var starter: Node3D = dungeon.get("_start_module") as Node3D
		var doorway: Node3D = starter.get_node("Doorway") as Node3D
		var neighbor: Vector2i = entry + Vector2i.UP
		var neighbor_position: Vector3 = dungeon.call("_cell_to_local", neighbor)
		assert(doorway.global_position.is_equal_approx(dungeon.to_global(neighbor_position + Vector3(0, 0, 2))))
		assert(bool(int(connections[neighbor]) & DungeonModule.Direction.NORTH))
		assert(dungeon.get_node("ExitDoor").global_transform.is_equal_approx(starter.get_node("PortalSpawn").global_transform))
		assert(starter.get_node("DungeonStartModule").get_child_count() == 1, "Room collision missing")
		var module_count: int = dungeon.get_node("Modules").get_child_count()
		dungeon.call("ensure_generated", Vector3.ONE)
		assert(dungeon.get_node("Modules").get_child_count() == module_count, "Starter duplicated on reentry")
		for scrap: Node3D in dungeon.get_node("Pickups").get_children():
			assert(scrap.global_position.distance_to(starter.global_position) > 5.0)
		dungeon.free()
	print("PASS: 12 dungeon seeds, minimum/default grids, connectivity, doorway alignment, portal placement, collision and reentry")
	quit()
