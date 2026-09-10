extends ActionLeaf

## Persegue o jogador: enquanto há contato visual, mira a posição atual dele;
## sem contato (ainda dentro da memória de `lose_sight_after`), continua até a
## última posição vista. Nunca retorna SUCCESS sozinho — quem tira o NPC deste
## ramo é a árvore, ao `CanSeePlayer` falhar (memória expirada).


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var npc: NPCActor = actor as NPCActor
	if npc == null or npc.vision == null:
		return FAILURE

	npc.set_state(&"chase")

	var target: Vector3 = (
		npc.vision.get_player_position()
		if npc.vision.is_currently_visible
		else npc.vision.last_seen_position
	)
	npc.move_toward_point(target, npc.alert_speed)
	return FAILURE if npc.navigation_failed else RUNNING
