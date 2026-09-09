extends ActionLeaf

## Foge do jogador: mira um ponto a `flee_distance` metros na direção oposta
## a ele, recalculado a cada tick para continuar afastando enquanto o alerta
## durar. Usado por moradores (`reaction_mode = FLEE`).


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var npc: NPCActor = actor as NPCActor
	if npc == null or npc.vision == null:
		return FAILURE

	npc.set_state(&"flee")

	var threat_position: Vector3 = (
		npc.vision.get_player_position()
		if npc.vision.is_currently_visible
		else npc.vision.last_seen_position
	)

	var away: Vector3 = npc.global_position - threat_position
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = -npc.global_transform.basis.z
	away = away.normalized()

	var flee_target: Vector3 = npc.global_position + away * npc.flee_distance
	if npc.routine != null:
		flee_target = npc.routine.refuge(threat_position)
	npc.move_toward_point(flee_target, npc.alert_speed)
	return RUNNING
