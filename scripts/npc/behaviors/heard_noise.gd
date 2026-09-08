extends ConditionLeaf

## Sucede quando o componente de audição do NPC tem um ruído pendente dentro
## da janela de memória (`NPCHearing.noise_memory_seconds`).


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var npc: NPCActor = actor as NPCActor
	if npc == null or npc.hearing == null:
		return FAILURE
	return SUCCESS if npc.hearing.has_pending_noise() else FAILURE
