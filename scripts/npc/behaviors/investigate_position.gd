extends ActionLeaf

## Vai até a posição do ruído ouvido, espera `investigate_wait_time`
## observando o local e consome o ruído do sensor de audição ao terminar.

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

	if not _has_target:
		_target = npc.hearing.consume_noise()
		_has_target = true

	if not _arrived:
		if npc.move_toward_point(_target, npc.walk_speed):
			_arrived = true
		return RUNNING

	_elapsed += get_physics_process_delta_time()
	npc.stop_moving()

	return SUCCESS if _elapsed >= npc.investigate_wait_time else RUNNING
