extends Node

const CHECKPOINT_INTERVAL: float = 0.5
const RECONNECT_TIMEOUT: float = 12.0

var enabled: bool = true
var active: bool = false
var is_restoring: bool = false
var checkpoint: Dictionary = {}
var endpoints: Dictionary[int, Dictionary] = {}
var _session: Node3D
var _elapsed: float = 0.0
var _waiting: Dictionary[int, String] = {}
var _survivors: Array[String] = []
var _successor: String = ""
var _listen_port: int = 0
var _paused_modes: Dictionary[Node, int] = {}
var _revision: int = 0
var _acknowledged: Dictionary[int, int] = {}
var _attempt: int = 0


func _ready() -> void:
	_session = get_parent() as Node3D


func record_endpoint(peer_id: int, address: String, port: int) -> void:
	var peer: ENetMultiplayerPeer = multiplayer.multiplayer_peer as ENetMultiplayerPeer
	var observed: String = peer.get_peer(peer_id).get_remote_address()
	endpoints[peer_id] = {"address": address if address.is_valid_ip_address() else observed,
		"port": port if port >= 1024 and port <= 65535 else mini(65535, int(_session._port.value) + _session._slots[peer_id] + 1)}


func _process(delta: float) -> void:
	if active or _session._disconnecting:
		return
	if not enabled or _session.players.size() < 2 or not multiplayer.is_server():
		return
	_elapsed += delta
	if _elapsed >= CHECKPOINT_INTERVAL:
		_elapsed = 0.0
		publish_checkpoint()


func publish_checkpoint() -> void:
	if not enabled or not multiplayer.is_server() or _session.players.size() < 2:
		return
	checkpoint = capture()
	_revision += 1
	checkpoint["revision"] = _revision
	_receive_checkpoint.rpc(checkpoint)


@rpc("authority", "call_remote", "reliable")
func _receive_checkpoint(state: Dictionary) -> void:
	if not active:
		checkpoint = state
		_ack_checkpoint.rpc_id(1, int(state.revision))
		_session._refresh_ui()


@rpc("any_peer", "call_remote", "reliable")
func _ack_checkpoint(revision: int) -> void:
	if multiplayer.is_server() and revision == _revision and _session.players.has(multiplayer.get_remote_sender_id()):
		_acknowledged[multiplayer.get_remote_sender_id()] = revision


func acknowledged() -> bool:
	for id: int in checkpoint.get("roster", {}):
		if id != 1 and _acknowledged.get(id, -1) < _revision:
			return false
	return true


func capture() -> Dictionary:
	var roster: Dictionary = {}
	for id: int in _session.players:
		if id != 1 and not multiplayer.get_peers().has(id):
			continue
		var player: CharacterBody3D = _session.players[id]
		roster[id] = {"token": _session._peer_tokens.get(id, ""), "slot": _session._slots[id],
			"name": _session.player_names.get(id, "ET"), "ready": _session.ready_players.get(id, false),
			"profile": _session._profiles[id], "motion": player.make_snapshot(),
			"combat": _session._combat_state(id, Vector3.ZERO)}
	var item_states: Dictionary = {}
	for id: StringName in _session.items:
		var item: RigidBody3D = _session.items[id]
		item_states[id] = {"owner": _session._item_owners[id], "pose": item.global_transform,
			"motion": item.linear_velocity, "revision": _session._item_revisions[id], "spawn": _session._item_spawns[id]}
	var npc_states: Dictionary = {}
	for id: StringName in _session.npcs:
		npc_states[id] = _session.npcs[id].make_migration_state()
	var vehicles: Dictionary = {}
	var container: Node = _session.get_node_or_null("VehiclesContainer")
	if container != null:
		for body: RigidBody3D in container.get_children():
			var seats: Node = body.get_node("CoopSeats")
			vehicles[body.name] = {"pose": body.global_transform, "velocity": body.linear_velocity,
				"angular": body.angular_velocity, "seats": seats.occupants.duplicate()}
	var quest_state: Dictionary = {}
	var quest: Node = _session.get_node_or_null("NPCsContainer/Gorilla/BananaTrade")
	if quest != null:
		quest_state = {"accepted": quest.accepted, "completed": quest.completed, "reward": quest._reward_path, "item": quest._consumed_id}
	var door_state: Dictionary = {}
	var door: Node = _session.get_node_or_null("BuildingContainers/BarnDoor")
	if door != null:
		door_state = {"angle": door.leaf.rotation.y, "locked": door.locked, "target": door._target}
	return {"level": _session.scene_file_path, "roster": roster, "endpoints": endpoints.duplicate(true),
		"mission": _session._mission_snapshot(), "money": _session.team_money, "score": _session.team_score,
		"deliveries": _session.deliveries, "purchases": _session.purchases.duplicate(true),
		"sales": _session._round_sales_money, "start_deliveries": _session._round_start_deliveries,
		"mission_elapsed": _session._mission_elapsed, "items": item_states, "npcs": npc_states,
		"vehicles": vehicles, "quest": quest_state, "door": door_state,
		"departed": _session._departed.duplicate(true)}


func begin() -> bool:
	if not enabled or active or checkpoint.is_empty():
		return false
	var candidates: Array = checkpoint.roster.keys()
	candidates.erase(1)
	candidates.sort_custom(func(a: int, b: int) -> bool: return checkpoint.roster[a].slot < checkpoint.roster[b].slot)
	if candidates.is_empty() or not checkpoint.endpoints.has(candidates[0]):
		return false
	_survivors.clear()
	for id: int in candidates:
		_survivors.append(str(checkpoint.roster[id].token))
	if not _survivors.has(_session._reconnect_token):
		return false
	_successor = _survivors[0]
	active = true
	_attempt += 1
	_waiting.clear()
	_session._connecting = false
	_session._set_menu_open(true)
	# OfflineMultiplayerPeer reports server authority; suspend the old world before replacing ENet.
	pause_world()
	_session._close_peer()
	_session._set_status("Host left. Paused while reconnecting to the next host...")
	for npc: CharacterBody3D in _session.npcs.values():
		npc.set_physics_process(false)
	for item: RigidBody3D in _session.items.values():
		item.freeze = true
	var vehicles: Node = _session.get_node_or_null("VehiclesContainer")
	if vehicles != null:
		for body: RigidBody3D in vehicles.get_children():
			body.freeze = true
			body.get_node("CoopSeats").set_physics_process(false)
	_connect.call_deferred(checkpoint.endpoints[candidates[0]])
	return true


func _connect(endpoint: Dictionary) -> void:
	var attempt: int = _attempt
	# Give peers time to observe the old connection closing before opening the replacement.
	await get_tree().create_timer(0.35).timeout
	if not active or attempt != _attempt:
		return
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	_listen_port = int(endpoint.port)
	var error: Error
	if _session._reconnect_token == _successor:
		error = peer.create_server(int(endpoint.port), _session.MAX_PLAYERS - 1)
		if error == OK:
			multiplayer.multiplayer_peer = peer
			_waiting[1] = _successor
			if _survivors.size() == 1:
				finish.call_deferred()
	else:
		error = peer.create_client(str(endpoint.address), int(endpoint.port))
		if error == OK:
			multiplayer.multiplayer_peer = peer
	if error != OK:
		fail("Could not migrate host: %s" % error_string(error))
		return
	await get_tree().create_timer(RECONNECT_TIMEOUT).timeout
	if not active or attempt != _attempt:
		return
	if _session._reconnect_token == _successor:
		finish()
	else:
		fail("Host migration timed out. The replacement host must allow and forward its advertised UDP port.")


func connected() -> void:
	_register_survivor.rpc_id(1, _session._reconnect_token)


@rpc("any_peer", "call_remote", "reliable")
func _register_survivor(token: String) -> void:
	if not active or not multiplayer.is_server() or not _survivors.has(token) or _waiting.values().has(token):
		return
	_waiting[multiplayer.get_remote_sender_id()] = token
	if _waiting.size() == _survivors.size():
		finish.call_deferred()


func finish() -> void:
	if not active or not multiplayer.is_server():
		return
	for id: int in _waiting.keys():
		if id != 1 and not multiplayer.get_peers().has(id):
			_waiting.erase(id)
	var roster: Dictionary = _waiting.duplicate()
	_restore.rpc(checkpoint, roster)
	_restore(checkpoint, roster)


@rpc("authority", "call_remote", "reliable")
func _restore(state: Dictionary, connected_roster: Dictionary) -> void:
	if not active:
		return
	is_restoring = true
	var mapping: Dictionary[int, int] = {}
	for old_id: int in state.roster:
		var token: String = state.roster[old_id].token
		for new_id: int in connected_roster:
			if connected_roster[new_id] == token:
				mapping[old_id] = new_id
	_session.recovery.reset()
	var old_vehicles: Node = _session.get_node_or_null("VehiclesContainer")
	if old_vehicles != null:
		for body: Node in old_vehicles.get_children():
			body.get_node("CoopSeats").reset()
	for id: StringName in _session.items:
		_session.items[id].apply_network_state(null, _session._item_spawns[id], Vector3.ZERO, false)
	for id: int in _session.players.keys():
		_session._remove_player(id)
	_session._commit_round(str(state.level), maxi(_session.mission_round, int(state.mission.round)) + 1)
	_session.player_container.process_mode = Node.PROCESS_MODE_INHERIT
	_session.recovery.process_mode = Node.PROCESS_MODE_INHERIT
	_session.mission_round = state.mission.round
	_session.team_money = state.money
	_session.team_score = state.score
	_session.deliveries = state.deliveries
	_session._round_sales_money = state.sales
	_session._round_start_deliveries = state.start_deliveries
	_session._mission_elapsed = state.mission_elapsed
	_session._departed.assign(state.departed)
	_session._peer_tokens.clear()
	endpoints.clear()
	for old_id: int in mapping:
		var id: int = mapping[old_id]
		var record: Dictionary = state.roster[old_id]
		_session._peer_tokens[id] = record.token
		_session.player_names[id] = record.name
		_session.ready_players[id] = record.ready
		_session.purchases[id] = state.purchases.get(old_id, {}).duplicate(true)
		_session._spawn_player(id, record.slot, record.profile, record.motion.transform, record.combat.generation)
		var player: CharacterBody3D = _session.players[id]
		player.apply_team_purchases()
		player.velocity = record.motion.velocity
		player.camera_yaw = record.motion.yaw
		player.camera_pitch = record.motion.pitch
		player._portal_epoch = record.motion.epoch
		player._snapshot_sequence = record.motion.sequence
		player.call("restore_motion_visual", record.motion.visual)
		player.receive_combat_state(record.combat)
		_session._combat_revisions[id] = record.combat.revision
		if id != 1 and state.endpoints.has(old_id):
			endpoints[id] = state.endpoints[old_id].duplicate()
	for old_id: int in state.roster:
		if mapping.has(old_id):
			continue
		var record: Dictionary = state.roster[old_id]
		_session._departed[record.token] = {"purchases": state.purchases.get(old_id, {}).duplicate(true),
			"health": record.combat.health, "shield": record.combat.shield, "cloak_energy": record.combat.cloak_energy}
	var quest: Node = _session.get_node_or_null("NPCsContainer/Gorilla/BananaTrade")
	if quest != null and not state.quest.is_empty():
		quest._receive_state(state.quest.accepted, state.quest.completed, state.quest.reward, state.quest.get("item", &"banana_box"))
	if _session.campaign != null and state.mission.has("campaign"):
		if not state.mission.campaign.get("delivery", {}).is_empty():
			state.mission.campaign.delivery.target = mapping.get(state.mission.campaign.delivery.target, 0)
		_session.mission_phase = state.mission.phase
		_session.campaign.restore(state.mission.campaign)
	for old_id: StringName in state.items:
		var id: StringName = old_id
		if str(old_id).begins_with("corpse_"):
			var victim: int = int(str(old_id).trim_prefix("corpse_"))
			if not mapping.has(victim):
				continue
			id = StringName("corpse_%d" % mapping[victim])
			_session.recovery._spawn_corpse(mapping[victim], state.items[old_id].pose)
		if not _session.items.has(id):
			continue
		var item: Dictionary = state.items[old_id]
		_session._item_spawns[id] = item.spawn
		_session._item_revisions[id] = item.revision - 1
		_session._receive_item_state(mapping.get(item.owner, 0), item.pose, item.motion, item.revision, id)
	_session._receive_mission(state.mission)
	for id: StringName in state.npcs:
		if not _session.npcs.has(id):
			continue
		var npc: Node3D = _session.npcs[id]
		npc.set_host_simulation(false)
		var snapshot: Dictionary = state.npcs[id].duplicate(true)
		if snapshot.has("target"):
			snapshot.target = mapping.get(snapshot.target, 0)
		npc.receive_network_state(snapshot)
		if multiplayer.is_server() and _session.mission_phase == &"collecting":
			npc.set_host_simulation(true)
			npc.restore_migration_state(snapshot)
	for id: StringName in state.vehicles:
		var body: RigidBody3D = _session.get_node("VehiclesContainer").get_node(NodePath(str(id))) as RigidBody3D
		var vehicle: Dictionary = state.vehicles[id]
		var occupants: Array[int] = []
		for occupant_id: int in vehicle.seats:
			occupants.append(mapping.get(occupant_id, 0))
		body.get_node("CoopSeats")._receive_seats(occupants)
		body.global_transform = vehicle.pose
		body.linear_velocity = vehicle.velocity
		body.angular_velocity = vehicle.angular
	var door: Node = _session.get_node_or_null("BuildingContainers/BarnDoor")
	if door != null and not state.door.is_empty():
		door._receive_state(state.door.angle, state.door.locked)
		door._target = state.door.target
	if _session.campaign != null and not _session.campaign.loading_ready:
		_session.campaign.loading_ready = true
		if _session.mission_phase == &"loading":
			_session.mission_phase = &"collecting"
	active = false
	is_restoring = false
	_paused_modes.clear()
	_session._connecting = false
	_session._port.value = _listen_port
	_session._receive_lobby(_session.player_names, _session.ready_players)
	_session._set_menu_open(_session.mission_phase != &"collecting" or not _session.players[multiplayer.get_unique_id()].is_alive())
	_session._set_status("Host migrated. Expedition continues.")
	_session.team_state_changed.emit()
	checkpoint = {}
	if multiplayer.is_server():
		if _session.campaign != null:
			_session._publish_mission()
		publish_checkpoint()
		if _session.mission_phase == &"loading":
			_session._advance_mission.call_deferred()
		elif _session.mission_phase == &"failed":
			_session._end_run.call_deferred()


func fail(message: String) -> void:
	active = false
	checkpoint.clear()
	_session.disconnect_game(message)


func reset() -> void:
	_attempt += 1
	for node: Node in _paused_modes:
		if is_instance_valid(node):
			node.process_mode = _paused_modes[node] as Node.ProcessMode
	_paused_modes.clear()
	active = false
	checkpoint.clear()
	endpoints.clear()
	_waiting.clear()
	_acknowledged.clear()


func pause_world() -> void:
	for child: Node in _session.get_children():
		if child is Node3D and not _paused_modes.has(child):
			_paused_modes[child] = child.process_mode
			child.process_mode = Node.PROCESS_MODE_DISABLED


func peer_disconnected(peer_id: int) -> void:
	_waiting.erase(peer_id)
