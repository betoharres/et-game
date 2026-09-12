extends ActionLeaf


func tick(actor: Node, _blackboard: Blackboard) -> int:
	if not actor.is_in_group(&"town_pedestrians"):
		return FAILURE
	var npc: NPCActor = actor as NPCActor
	var path: PackedVector3Array = npc.navigation_agent.get_current_navigation_path()
	if path.is_empty():
		return FAILURE
	var next: Vector3 = path[mini(npc.navigation_agent.get_current_navigation_path_index(), path.size() - 1)]
	for node: Node in actor.get_tree().get_nodes_in_group(&"town_crosswalks"):
		var crossing: Node3D = node as Node3D
		var local: Vector3 = crossing.to_local(npc.global_position)
		if absf(local.z) > 2.8 or absf(local.x) < 4.6 or absf(local.x) > 7.5:
			continue
		var destination: Vector3 = crossing.to_local(next)
		if (destination.x - local.x) * local.x >= -0.1:
			continue
		for candidate: Node in actor.get_tree().get_nodes_in_group(&"vehicles"):
			var car: RigidBody3D = candidate as RigidBody3D
			if car == null:
				continue
			var car_position: Vector3 = crossing.to_local(car.global_position)
			var car_velocity: Vector3 = crossing.global_basis.inverse() * car.linear_velocity
			var approaching: bool = car_position.z * car_velocity.z < 0.0
			var horizon: float = 7.0 + absf(car_velocity.z) * 3.0
			if absf(car_position.x) < 5.5 and (absf(car_position.z) < 5.0 or (approaching and absf(car_position.z) < horizon)):
				npc.set_state(&"wait")
				npc.stop_moving()
				return RUNNING
	return FAILURE
