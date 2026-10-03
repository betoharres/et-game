extends ActionLeaf


func tick(actor: Node, _blackboard: Blackboard) -> int:
	return RUNNING if bool(actor.call("attack_target")) else FAILURE
