class_name NPCNavigation
extends RefCounted


static func wait_for_region(origin: Node3D, region_path: NodePath = NodePath()) -> NavigationRegion3D:
	for frame: int in range(20):
		if not is_instance_valid(origin) or not origin.is_inside_tree():
			return null
		var region: NavigationRegion3D = find_region(origin, region_path)
		if region != null and NavigationServer3D.map_get_iteration_id(region.get_navigation_map()) > 0:
			return region
		await origin.get_tree().physics_frame
	return null


static func find_region(origin: Node3D, region_path: NodePath = NodePath()) -> NavigationRegion3D:
	if not region_path.is_empty():
		var explicit_region: NavigationRegion3D = origin.get_node_or_null(region_path) as NavigationRegion3D
		return explicit_region if _usable(explicit_region, origin) else null
	var selected: NavigationRegion3D = null
	var closest: float = INF
	for node: Node in origin.get_tree().root.find_children("*", "NavigationRegion3D", true, false):
		var region: NavigationRegion3D = node as NavigationRegion3D
		if not _usable(region, origin):
			continue
		var nav_map: RID = region.get_navigation_map()
		if NavigationServer3D.map_get_iteration_id(nav_map) == 0:
			continue
		var point: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, origin.global_position)
		var distance: float = origin.global_position.distance_squared_to(point)
		if distance <= 9.0 and distance < closest:
			closest = distance
			selected = region
	return selected


static func _usable(region: NavigationRegion3D, origin: Node3D) -> bool:
	return region != null and region.enabled and region.get_world_3d() == origin.get_world_3d() and region.navigation_mesh != null and region.navigation_mesh.get_polygon_count() > 0
