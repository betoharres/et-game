extends "res://scripts/npc/banana_trade.gd"

var _session: Node3D
var _reward_path: String = ""
var _consumed_id: StringName = &"banana_box"


func _ready() -> void:
	_session = get_parent() as Node3D
	while _session != null and not _session.has_method("damage_player"):
		_session = _session.get_parent() as Node3D
	super._ready()


func _nearby_player() -> Node3D:
	var id: int = multiplayer.get_unique_id()
	var character: Node3D = _session.players.get(id) as Node3D
	return character if character != null and reserves_interaction_for(character) else null


func reserves_interaction_for(character: Node3D) -> bool:
	return character != null and character.get_world_3d() == get_world_3d() and character.has_method("is_local_player") and bool(character.call("is_local_player")) and bool(character.call("is_alive")) and super.reserves_interaction_for(character)


func interact(character: Node3D) -> void:
	if not reserves_interaction_for(character):
		return
	if multiplayer.is_server():
		_interact_peer(multiplayer.get_unique_id())
	else:
		_request_interaction.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_interaction() -> void:
	if multiplayer.is_server():
		_interact_peer(multiplayer.get_remote_sender_id())


func _interact_peer(peer_id: int) -> void:
	if completed or not _session.players.has(peer_id) or not _session.players[peer_id].is_alive() or global_position.distance_to(_session.players[peer_id].global_position) > interact_radius:
		return
	if not accepted:
		accepted = true
	else:
		for id: StringName in _session.items:
			if _session._item_owners[id] == peer_id and str(_session.items[id].item_id) == requested_item_id:
				_session.call("_publish_item_state", 0, _session._item_spawns[id], Vector3.ZERO, id)
				_consumed_id = id
				completed = true
				_reward_path = rewards[0].resource_path
				break
	_receive_state(accepted, completed, _reward_path, _consumed_id)
	_receive_state.rpc(accepted, completed, _reward_path, _consumed_id)


@rpc("authority", "call_remote", "reliable")
func _receive_state(started: bool, finished: bool, reward_path: String, consumed_id: StringName = &"banana_box") -> void:
	_consumed_id = consumed_id
	accepted = started
	completed = finished
	_reward_path = reward_path
	_label.text = "Thanks, team! Your scrap is beside me." if completed else "Team quest: bring me a banana box." if accepted else "!\nBigfoot — bananas for scrap"
	if completed:
		var banana: RigidBody3D = _session.items.get(_consumed_id) as RigidBody3D
		if banana != null:
			banana.set("network_consumed", true)
			banana.hide()
			banana.freeze = true
			banana.collision_layer = 0
			banana.collision_mask = 0
		if not _session.items.has(&"quest_reward"):
			_session.call("spawn_shared_asset", &"quest_reward", reward_path, _reward_marker.global_position)


func send_snapshot(peer_id: int) -> void:
	_receive_state.rpc_id(peer_id, accepted, completed, _reward_path, _consumed_id)


func reset() -> void:
	accepted = false
	completed = false
	_reward_path = ""
	_label.text = "!\nBigfoot ? bananas for scrap"
	var banana: RigidBody3D = _session.items.get(_consumed_id) as RigidBody3D
	if banana != null:
		banana.network_consumed = false
		banana.show()
	if _session.items.has(&"quest_reward"):
		_session.items[&"quest_reward"].queue_free()
		_session.items.erase(&"quest_reward")
		_session._item_owners.erase(&"quest_reward")
		_session._item_revisions.erase(&"quest_reward")
		_session._item_spawns.erase(&"quest_reward")
