extends ConditionLeaf

## Sucede quando a visão do NPC já confirmou o jogador (após `detection_time`
## de contato contínuo, incluindo a memória de curto prazo até `lose_sight_after`).


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var npc: NPCActor = actor as NPCActor
	if npc == null or npc.vision == null:
		return FAILURE
	return SUCCESS if npc.vision.has_detected_player else FAILURE
