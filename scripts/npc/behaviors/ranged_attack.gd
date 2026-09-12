extends ActionLeaf


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var combat: NPCRangedCombat = actor.get_node_or_null("NPCCombat") as NPCRangedCombat
	if combat == null or not combat.can_engage():
		if combat != null:
			combat.interrupt_aim()
		return FAILURE
	var npc: NPCActor = actor as NPCActor
	npc.set_state(&"attack")
	npc.stop_moving()
	combat.aim_and_fire(get_physics_process_delta_time())
	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var combat: NPCRangedCombat = actor.get_node_or_null("NPCCombat") as NPCRangedCombat
	if combat != null:
		combat.interrupt_aim()
	super(actor, blackboard)
