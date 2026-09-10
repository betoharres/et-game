extends ActionLeaf

## Percorre `patrol_points` em sequência, parando/observando em cada um por
## um tempo aleatório. Só roda com 2+ pontos (com 0 ou 1, `Idle` assume). Sucede
## a cada parada concluída — não no fim da volta inteira — para que o `Selector`
## de rotina reavalie `TalkToNeighbor` a cada ciclo, em vez de prender o NPC
## na patrulha até o fim da volta.

var _index: int = 0
var _wait_duration: float = 0.0
var _elapsed: float = 0.0
var _arrived: bool = false


func before_run(_actor: Node, _blackboard: Blackboard) -> void:
	_wait_duration = 0.0
	_elapsed = 0.0
	_arrived = false


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var npc: NPCActor = actor as NPCActor
	if npc == null:
		return FAILURE

	var points: Array[Vector3] = npc.get_patrol_positions()
	if points.size() <= 1:
		return FAILURE

	npc.set_state(&"patrol")
	_index = _index % points.size()

	if not _arrived:
		var arrived: bool = npc.move_toward_point(points[_index], npc.walk_speed)
		if npc.navigation_failed:
			# Abandona este ponto; o Selector poderá escolher Idle ou outra rotina.
			_index = (_index + 1) % points.size()
			return FAILURE
		if arrived:
			_arrived = true
		return RUNNING

	npc.stop_moving()

	if _wait_duration <= 0.0:
		_wait_duration = randf_range(npc.patrol_wait_time_min, npc.patrol_wait_time_max)

	_elapsed += get_physics_process_delta_time()
	if _elapsed >= _wait_duration:
		_index = (_index + 1) % points.size()
		return SUCCESS

	return RUNNING
