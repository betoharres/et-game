extends ActionLeaf

## Vai até a última posição vista do jogador e procura ali por
## `NPCActor.search_duration` segundos (olhando ao redor, sem se mover) antes
## de desistir. Ao desistir, limpa `vision.has_last_seen_position` para a
## condição `HasLastSeenPosition` liberar o retorno à rotina.

var _elapsed: float = 0.0
var _arrived: bool = false


func before_run(_actor: Node, _blackboard: Blackboard) -> void:
	_elapsed = 0.0
	_arrived = false


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var npc: NPCActor = actor as NPCActor
	if npc == null or npc.vision == null:
		return FAILURE

	npc.set_state(&"search")

	if not _arrived:
		if npc.move_toward_point(npc.vision.last_seen_position, npc.alert_speed):
			_arrived = true
		return RUNNING

	var delta: float = get_physics_process_delta_time()
	_elapsed += delta
	npc.stop_moving()

	var look_angle: float = _elapsed * 1.3
	npc.face_direction(Vector3(sin(look_angle), 0.0, cos(look_angle)))

	if _elapsed >= npc.search_duration:
		npc.vision.has_last_seen_position = false
		return SUCCESS

	return RUNNING
