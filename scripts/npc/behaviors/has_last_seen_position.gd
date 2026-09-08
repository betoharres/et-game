extends ConditionLeaf

## Sucede quando o NPC perdeu o jogador de vista mas ainda guarda uma última
## posição vista para investigar. `SearchLastSeenPosition` é quem decide
## quando desistir (limpando `vision.has_last_seen_position`).


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var npc: NPCActor = actor as NPCActor
	if npc == null or npc.vision == null:
		return FAILURE
	var vision: NPCVision = npc.vision
	if vision.has_detected_player or vision.is_currently_visible:
		return FAILURE
	return SUCCESS if vision.has_last_seen_position else FAILURE
