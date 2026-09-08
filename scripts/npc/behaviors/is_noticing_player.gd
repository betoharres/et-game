extends ConditionLeaf

## Sucede enquanto o NPC está no meio da progressão de detecção (já viu algo,
## ainda não confirmou) — o momento de "notar" o ET antes do alerta virar
## perseguição/fuga.


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var npc: NPCActor = actor as NPCActor
	if npc == null or npc.vision == null:
		return FAILURE
	var vision: NPCVision = npc.vision
	if vision.has_detected_player:
		return FAILURE
	return SUCCESS if vision.detection_progress > 0.0 else FAILURE
