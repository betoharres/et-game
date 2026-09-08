extends ConditionLeaf

## Condição parametrizável: compara `NPCActor.reaction_mode` com um valor
## esperado. Reaproveitada duas vezes na árvore (ramo de perseguição e ramo
## de fuga) para decidir qual ação de resposta ao ET usar.

@export var expected_mode: NPCActor.ReactionMode = NPCActor.ReactionMode.CHASE


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var npc: NPCActor = actor as NPCActor
	if npc == null:
		return FAILURE
	return SUCCESS if npc.reaction_mode == expected_mode else FAILURE
