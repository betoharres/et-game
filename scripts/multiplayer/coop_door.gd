extends "res://scripts/house_door.gd"

var _session: Node3D
var _elapsed: float = 0.0


func _ready() -> void:
	_session = get_parent().get_parent() as Node3D
	super._ready()


func interact(body: Node3D) -> bool:
	if not body.has_method("is_local_player") or not bool(body.call("is_local_player")):
		return false
	if multiplayer.is_server():
		return super.interact(body)
	_request_open.rpc_id(1)
	return true


func _manual_body() -> Node3D:
	var player: Node3D = _session.players.get(multiplayer.get_unique_id()) as Node3D
	return player if player != null and player.is_alive() and super.reserves_interaction_for(player) else null


@rpc("any_peer", "call_remote", "reliable")
func _request_open() -> void:
	if not multiplayer.is_server():
		return
	var body: CharacterBody3D = _session.players.get(multiplayer.get_remote_sender_id()) as CharacterBody3D
	if body != null and body.is_alive() and trigger.global_position.distance_to(body.global_position + Vector3.UP) <= trigger_radius:
		super.interact(body)


func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		super._physics_process(delta)
		_elapsed += delta
		if _elapsed >= 0.05 and not _session.players.is_empty():
			_elapsed = 0.0
			_receive_state.rpc(leaf.rotation.y, locked)


@rpc("authority", "call_remote", "unreliable_ordered", 5)
func _receive_state(angle: float, is_locked: bool) -> void:
	leaf.rotation.y = angle
	locked = is_locked
	leaf_shape.set_deferred("disabled", is_open())
	_refresh_prompt()


func open_for(body: Node3D) -> bool:
	return super.open_for(body) if multiplayer.is_server() else false


func close() -> void:
	if multiplayer.is_server():
		super.close()


func set_locked(value: bool) -> void:
	if multiplayer.is_server():
		super.set_locked(value)
		if _session != null and not _session.players.is_empty():
			_receive_lock.rpc(value)


@rpc("authority", "call_remote", "reliable")
func _receive_lock(value: bool) -> void:
	locked = value
	_refresh_prompt()


func send_snapshot(peer_id: int) -> void:
	_receive_lock.rpc_id(peer_id, locked)
	_receive_state.rpc_id(peer_id, leaf.rotation.y, locked)
