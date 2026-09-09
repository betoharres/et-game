extends ActionLeaf


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var npc: NPCActor = actor as NPCActor
	if npc == null or npc.routine == null:
		return FAILURE
	npc.routine.tick(get_physics_process_delta_time())
	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var npc: NPCActor = actor as NPCActor
	if npc != null and npc.routine != null:
		npc.routine.interrupt()
	super(actor, blackboard)
