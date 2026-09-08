extends ActionLeaf

## Reação de "notar" o ET antes da detecção se confirmar: o NPC para, encara
## o jogador e aguarda. Representa o estado Alert pedido, distinto de
## Chase/Flee (que só entram após `detection_time` completo).


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var npc: NPCActor = actor as NPCActor
	if npc == null or npc.vision == null:
		return FAILURE

	npc.set_state(&"alert")
	npc.stop_moving()

	var direction: Vector3 = npc.vision.get_player_position() - npc.global_position
	direction.y = 0.0
	npc.face_direction(direction)
	return RUNNING
