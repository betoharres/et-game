extends ActionLeaf

## Aproximação simples e sem handshake: se houver outro NPC do mesmo
## `social_group_name` por perto e o cooldown tiver passado, anda até ele,
## encara e pausa por um tempo — o suficiente para ler como "parou para
## conversar com o vizinho", mesmo que o outro não reaja ativamente.

var _partner: Node3D = null
var _elapsed: float = 0.0
var _arrived: bool = false
var _chat_duration: float = 0.0


func before_run(_actor: Node, _blackboard: Blackboard) -> void:
	_partner = null
	_elapsed = 0.0
	_arrived = false


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var npc: NPCActor = actor as NPCActor
	if npc == null or not npc.can_socialize or npc.social_group_name == &"":
		return FAILURE

	var now: float = Time.get_ticks_msec() / 1000.0
	if now - npc.last_chat_time < npc.chat_cooldown:
		return FAILURE

	if _partner == null:
		_partner = _find_nearby_partner(npc)
		if _partner == null:
			return FAILURE
		_chat_duration = randf_range(npc.chat_duration_min, npc.chat_duration_max)

	var to_partner: Vector3 = _partner.global_position - npc.global_position
	to_partner.y = 0.0

	if not _arrived:
		if to_partner.length() <= npc.chat_stop_distance:
			_arrived = true
		else:
			npc.move_toward_point(_partner.global_position, npc.walk_speed)
			return RUNNING

	npc.stop_moving()
	npc.face_direction(to_partner)
	_elapsed += get_physics_process_delta_time()

	if _elapsed >= _chat_duration:
		npc.last_chat_time = now
		return SUCCESS

	return RUNNING


func _find_nearby_partner(npc: NPCActor) -> Node3D:
	for candidate in npc.get_tree().get_nodes_in_group(npc.social_group_name):
		if candidate == npc or not (candidate is NPCActor):
			continue
		var other: NPCActor = candidate as NPCActor
		if other.state != &"patrol" and other.state != &"idle":
			continue
		if npc.global_position.distance_to(other.global_position) <= npc.chat_radius:
			return other
	return null
