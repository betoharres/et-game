extends ActionLeaf


func tick(actor: Node, _blackboard: Blackboard) -> int:
	if not actor.has_method("attack_target"):
		return FAILURE
	return RUNNING if bool(actor.call("attack_target")) else FAILURE
