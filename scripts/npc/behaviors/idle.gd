extends ActionLeaf

## Só sucede (aceita rodar) quando o NPC tem no máximo um ponto de patrulha —
## o caso do "fica parado trabalhando/observando". Anda até esse único ponto,
## se houver, e então aguarda um tempo aleatório olhando ao redor antes de
## repetir, dando espaço para `TalkToNeighbor` competir de novo a cada ciclo.

var _elapsed: float = 0.0
var _wait_duration: float = 0.0


func before_run(_actor: Node, _blackboard: Blackboard) -> void:
	_elapsed = 0.0
	_wait_duration = 0.0


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var npc: NPCActor = actor as NPCActor
	if npc == null:
		return FAILURE

	var points: Array[Vector3] = npc.get_patrol_positions()
	if points.size() > 1:
		return FAILURE

	npc.set_state(&"idle")

	if points.size() == 1 and not npc.move_toward_point(points[0], npc.walk_speed):
		return RUNNING

	npc.stop_moving()

	if _wait_duration <= 0.0:
		_wait_duration = randf_range(npc.idle_wait_time_min, npc.idle_wait_time_max)

	var look_angle: float = _elapsed * 0.5
	npc.face_direction(Vector3(sin(look_angle), 0.0, cos(look_angle)))
	_elapsed += get_physics_process_delta_time()

	return SUCCESS if _elapsed >= _wait_duration else RUNNING
