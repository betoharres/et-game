extends ActionLeaf

## Vai até a posição do ruído ouvido, espera `investigate_wait_time`
## observando o local; novos ruídos atualizam o destino.

var _target: Vector3 = Vector3.ZERO
var _has_target: bool = false
var _elapsed: float = 0.0
var _arrived: bool = false


func before_run(_actor: Node, _blackboard: Blackboard) -> void:
	_has_target = false
	_elapsed = 0.0
	_arrived = false


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var npc: NPCActor = actor as NPCActor
	if npc == null or npc.hearing == null:
		return FAILURE

	npc.set_state(&"investigate")

	if not _has_target or npc.hearing.has_pending_noise():
		_target = npc.hearing.begin_investigation()
		_elapsed = 0.0
		_arrived = false
		_has_target = true
		if npc.reaction_mode == NPCActor.ReactionMode.FLEE and npc.routine != null:
			_target = npc.routine.refuge(_target)

	if not _arrived:
		if npc.move_toward_point(_target, npc.alert_speed) or npc.navigation_failed:
			_arrived = true
		return RUNNING

	_elapsed += get_physics_process_delta_time()
	npc.stop_moving()

	if _elapsed >= npc.investigate_wait_time:
		npc.hearing.finish_investigation()
		if npc.vision != null:
			npc.vision.has_last_seen_position = false
		return SUCCESS
	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var npc: NPCActor = actor as NPCActor
	if npc != null and npc.hearing != null:
		npc.hearing.finish_investigation()
	super(actor, blackboard)
