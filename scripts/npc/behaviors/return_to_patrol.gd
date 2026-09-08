extends ActionLeaf

## Volta ao ponto de patrulha mais próximo depois de investigar um ruído ou
## procurar o jogador, antes de a árvore devolver o controle à rotina normal.


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var npc: NPCActor = actor as NPCActor
	if npc == null:
		return FAILURE

	var points: Array[Vector3] = npc.get_patrol_positions()
	if points.is_empty():
		return SUCCESS

	npc.set_state(&"patrol")

	var closest: Vector3 = points[0]
	var closest_distance: float = npc.global_position.distance_to(closest)
	for point in points:
		var distance: float = npc.global_position.distance_to(point)
		if distance < closest_distance:
			closest = point
			closest_distance = distance

	return SUCCESS if npc.move_toward_point(closest, npc.walk_speed) else RUNNING
