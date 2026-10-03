extends Node3D

const PLAYER_SCENE: PackedScene = preload("res://scenes/Multiplayer/NetworkPlayer.tscn")
const MAX_PLAYERS: int = 4
const DEFAULT_PORT: int = 7000
const SNAPSHOT_INTERVAL: float = 1.0 / 20.0
const EQUIPMENT_COSTS: Dictionary[StringName, int] = {&"xray_goggles": 500, &"energy_shield": 180, &"predator_watch": 650}
const UPGRADE_IDS: Array[StringName] = [&"movement", &"stamina", &"recovery"]
const UPGRADE_COSTS: Array[int] = [60, 100, 150]
const LEVEL_PATHS: Array[String] = ["res://scenes/Multiplayer/PortalCoop.tscn", "res://scenes/Multiplayer/FarmCoop.tscn"]
@export var session_title: String = "PORTAL CO-OP · UP TO 4 PLAYERS"
var _map_choice: OptionButton
var _respawn_button: Button
var _life_generations: Dictionary[int, int] = {}
var _combat_revisions: Dictionary[int, int] = {}
var npcs: Dictionary[StringName, NPCActor] = {}


func damage_player(peer_id: int, amount: float, direction: Vector3 = Vector3.ZERO, push: float = 0.0) -> void:
	if not multiplayer.is_server() or not players.has(peer_id) or not is_finite(amount) or amount <= 0.0 or not direction.is_finite():
		return
	var player: CharacterBody3D = players[peer_id]
	if not player.is_alive():
		return
	player.call("apply_host_damage", amount, direction, push)
	_publish_combat(peer_id, direction)


func on_player_death(peer_id: int) -> void:
	if multiplayer.is_server():
		for item_id: StringName in items:
			if _item_owners[item_id] == peer_id:
				_release_item(peer_id, item_id)
	if peer_id == multiplayer.get_unique_id():
		_set_menu_open(true)
		_set_status("You died. Respawn to rejoin your team.")
	_refresh_ui()


func _combat_state(peer_id: int, direction: Vector3) -> Dictionary:
	return {"generation": _life_generations[peer_id], "revision": _combat_revisions.get(peer_id, 0),
		"health": players[peer_id].health, "shield": players[peer_id].energy_shield, "direction": direction}


func _publish_combat(peer_id: int, direction: Vector3 = Vector3.ZERO) -> void:
	_combat_revisions[peer_id] = _combat_revisions.get(peer_id, 0) + 1
	var state: Dictionary = _combat_state(peer_id, direction)
	for target_id: int in players:
		if target_id != 1:
			_receive_combat.rpc_id(target_id, peer_id, state)


@rpc("authority", "call_remote", "reliable")
func _receive_combat(peer_id: int, state: Dictionary) -> void:
	if players.has(peer_id):
		players[peer_id].call("receive_combat_state", state)


func request_respawn() -> void:
	if multiplayer.is_server():
		_respawn_player(1)
	else:
		_request_respawn.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_respawn() -> void:
	if multiplayer.is_server():
		_respawn_player(multiplayer.get_remote_sender_id())


func _respawn_player(peer_id: int) -> void:
	if not players.has(peer_id) or players[peer_id].is_alive():
		return
	var generation: int = _life_generations[peer_id] + 1
	_replace_player(peer_id, generation)
	_replace_player.rpc(peer_id, generation)
	_publish_combat(peer_id)


@rpc("authority", "call_remote", "reliable")
func _replace_player(peer_id: int, generation: int) -> void:
	if not players.has(peer_id) or generation <= _life_generations.get(peer_id, -1):
		return
	var old: CharacterBody3D = players[peer_id]
	player_container.remove_child(old)
	old.queue_free()
	players.erase(peer_id)
	_life_generations[peer_id] = generation
	_combat_revisions[peer_id] = 0
	_spawn_player(peer_id, _slots[peer_id], _profiles[peer_id], Transform3D(Basis.IDENTITY, _spawn_position(_slots[peer_id])), generation)
	players[peer_id].call("apply_team_purchases")


@rpc("authority", "call_remote", "unreliable_ordered", 3)
func _receive_npc_states(states: Dictionary) -> void:
	for npc_id: StringName in states:
		if npcs.has(npc_id):
			npcs[npc_id].call("receive_network_state", states[npc_id])

var team_money: int = 0
var team_score: int = 0
var deliveries: int = 0
var purchases: Dictionary[int, Dictionary] = {}
var _purchase_requests: Array[Dictionary] = []
var _team_label: Label
var _shop_panel: PanelContainer
var _shop_buttons: Dictionary[StringName, Button] = {}

var players: Dictionary[int, CharacterBody3D] = {}
var _profiles: Dictionary[int, Dictionary] = {}
var _slots: Dictionary[int, int] = {}
var _send_elapsed: float = 0.0
var _connecting_elapsed: float = 0.0
var _connecting: bool = false
var _menu_open: bool = true
var _status: Label
var _panel: PanelContainer
var _address: LineEdit
var _port: SpinBox
var _host_button: Button
var _join_button: Button
var _disconnect_button: Button
var _resume_button: Button
var items: Dictionary[StringName, RigidBody3D] = {}
var _item_owners: Dictionary[StringName, int] = {}
var _item_revisions: Dictionary[StringName, int] = {}
var _item_spawns: Dictionary[StringName, Transform3D] = {}
var _registry_valid: bool = true
var _item_owner: int:
	get: return _item_owners.get(&"scrap_01", 0)
var _item_revision: int:
	get: return _item_revisions.get(&"scrap_01", 0)
var _item_spawn_pose: Transform3D:
	get: return _item_spawns.get(&"scrap_01", Transform3D.IDENTITY)
var _item_requests: Array[Dictionary] = []

@onready var player_container: Node3D = $Players
@onready var shared_item: RigidBody3D = $PickupItemsContainer/SharedScrap


func _ready() -> void:
	var container: Node = get_node_or_null("NPCsContainer")
	if container != null:
		for npc: NPCActor in container.get_children():
			npcs[npc.name] = npc
	for node: Node in $PickupItemsContainer.get_children():
		var item: RigidBody3D = node as RigidBody3D
		if item == null:
			continue
		var item_id: StringName = item.get("network_id")
		if item_id == &"" or items.has(item_id):
			_registry_valid = false
			push_error("Collectibles need unique, nonempty network_id values.")
			continue
		items[item_id] = item
		_item_owners[item_id] = 0
		_item_revisions[item_id] = 0
		_item_spawns[item_id] = item.global_transform
		item.pickup_requested.connect(_on_item_pickup_requested.bind(item_id))
		item.drop_requested.connect(_on_item_drop_requested.bind(item_id))
	_build_ui()
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _exit_tree() -> void:
	_close_peer()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func host_game(port: int = DEFAULT_PORT) -> Error:
	if not _registry_valid or items.is_empty():
		return ERR_INVALID_DATA
	if _connecting or not players.is_empty():
		return ERR_ALREADY_IN_USE
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var error: Error = peer.create_server(port, MAX_PLAYERS - 1)
	if error != OK:
		_set_status("Could not host: %s" % error_string(error))
		return error
	multiplayer.multiplayer_peer = peer
	var profile: Dictionary = _local_appearance()
	_spawn_player(1, 0, profile, Transform3D(Basis.IDENTITY, _spawn_position(0)))
	for npc: NPCActor in npcs.values():
		npc.call("set_host_simulation", true)
	for item_id: StringName in items:
		_publish_item_state(0, _item_spawns[item_id], Vector3.ZERO, item_id)
	_set_menu_open(false)
	_refresh_ui()
	return OK


func join_game(address: String, port: int = DEFAULT_PORT) -> Error:
	if _connecting or not players.is_empty():
		return ERR_ALREADY_IN_USE
	if address.strip_edges().is_empty():
		_set_status("Enter the host's IP address.")
		return ERR_INVALID_PARAMETER
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var error: Error = peer.create_client(address.strip_edges(), port)
	if error != OK:
		_set_status("Could not join: %s" % error_string(error))
		return error
	multiplayer.multiplayer_peer = peer
	_connecting = true
	_connecting_elapsed = 0.0
	_refresh_ui()
	_set_status("Connecting…")
	return OK


func disconnect_game(message: String = "Disconnected. Host or join another session.") -> void:
	for npc: NPCActor in npcs.values():
		npc.call("set_host_simulation", false)
	for item_id: StringName in items:
		items[item_id].call("apply_network_state", null, _item_spawns[item_id], Vector3.ZERO, false)
		_item_owners[item_id] = 0
		_item_revisions[item_id] = 0
	_item_requests.clear()
	_close_peer()
	_connecting = false
	for player: CharacterBody3D in players.values():
		player_container.remove_child(player)
		player.queue_free()
	players.clear()
	_profiles.clear()
	_slots.clear()
	_life_generations.clear()
	_combat_revisions.clear()
	team_money = 0
	team_score = 0
	deliveries = 0
	purchases.clear()
	_purchase_requests.clear()
	$LobbyCamera.make_current()
	_set_menu_open(true)
	_refresh_ui()
	_set_status(message)


func _close_peer() -> void:
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func _on_connected() -> void:
	_register_player.rpc_id(1, _local_appearance(), scene_file_path, items.keys())


@rpc("authority", "call_remote", "reliable")
func _reject_connection(reason: String) -> void:
	disconnect_game(reason)


func _on_connection_failed() -> void:
	disconnect_game("Could not connect. Check the address, port, or whether the session is full.")


func _on_server_disconnected() -> void:
	disconnect_game("The host disconnected.")


@rpc("any_peer", "call_remote", "reliable")
func _register_player(profile: Dictionary, level_path: String, item_ids: Array) -> void:
	if not multiplayer.is_server():
		return
	var peer_id: int = multiplayer.get_remote_sender_id()
	if peer_id <= 1 or players.has(peer_id) or not multiplayer.get_peers().has(peer_id):
		return
	if not _registry_valid or level_path != scene_file_path or item_ids.size() != items.size():
		_reject_connection.rpc_id(peer_id, "Select the same map as the host before joining.")
		return
	var unique_ids: Dictionary = {}
	for item_id: Variant in item_ids:
		if not items.has(item_id) or unique_ids.has(item_id):
			_reject_connection.rpc_id(peer_id, "Collectible layout differs from the host. Use the same game version.")
			return
		unique_ids[item_id] = true
	if players.size() >= MAX_PLAYERS:
		(multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(peer_id)
		return
	var slot: int = 0
	while _slots.values().has(slot):
		slot += 1
	var sanitized: Dictionary = _sanitize_appearance(profile)
	for existing_id: int in players:
		_spawn_player.rpc_id(peer_id, existing_id, _slots[existing_id], _profiles[existing_id], players[existing_id].global_transform, _life_generations[existing_id])
		_receive_combat.rpc_id(peer_id, existing_id, _combat_state(existing_id, Vector3.ZERO))
	var initial_transform: Transform3D = Transform3D(Basis.IDENTITY, _spawn_position(slot))
	_spawn_player(peer_id, slot, sanitized, initial_transform)
	_spawn_player.rpc(peer_id, slot, sanitized, initial_transform)
	for item_id: StringName in items:
		var item: RigidBody3D = items[item_id]
		_receive_item_state.rpc_id(peer_id, _item_owners[item_id], item.global_transform, item.linear_velocity, _item_revisions[item_id], item_id)
	_publish_economy()


@rpc("authority", "call_remote", "reliable")
func _spawn_player(peer_id: int, slot: int, profile: Dictionary, initial_transform: Transform3D, generation: int = 0) -> void:
	if players.has(peer_id) or players.size() >= MAX_PLAYERS:
		return
	var player: CharacterBody3D = PLAYER_SCENE.instantiate() as CharacterBody3D
	player.name = str(peer_id)
	player.set_multiplayer_authority(peer_id)
	player.transform = initial_transform
	player.set("life_generation", generation)
	_life_generations[peer_id] = generation
	player_container.add_child(player)
	player.call("sync_appearance", profile)
	players[peer_id] = player
	_profiles[peer_id] = profile
	_slots[peer_id] = slot
	if peer_id == multiplayer.get_unique_id():
		_connecting = false
		_set_menu_open(false)
	_refresh_ui()


func _on_peer_disconnected(peer_id: int) -> void:
	if multiplayer.is_server():
		for item_id: StringName in items:
			if _item_owners[item_id] == peer_id:
				_release_item(peer_id, item_id)
		_remove_player(peer_id)
		_remove_player.rpc(peer_id)


@rpc("authority", "call_remote", "reliable")
func _remove_player(peer_id: int) -> void:
	if players.has(peer_id):
		var player: CharacterBody3D = players[peer_id]
		player_container.remove_child(player)
		player.queue_free()
		players.erase(peer_id)
	_profiles.erase(peer_id)
	_slots.erase(peer_id)
	purchases.erase(peer_id)
	_life_generations.erase(peer_id)
	_combat_revisions.erase(peer_id)
	_refresh_ui()


func _physics_process(delta: float) -> void:
	if multiplayer.is_server() and not players.is_empty():
		_process_item_requests()
		_check_delivery()
		_process_purchases()
		for peer_id: int in players:
			if players[peer_id].is_alive():
				players[peer_id].call("recover_host_shield", delta)
				if players[peer_id].global_position.y < -10.0:
					damage_player(peer_id, players[peer_id].max_health + players[peer_id].energy_shield)
		for item_id: StringName in items:
			if _item_owners[item_id] == 0 and items[item_id].global_position.y < -10.0:
				_publish_item_state(0, _item_spawns[item_id], Vector3.ZERO, item_id)
	if _connecting:
		_connecting_elapsed += delta
		if _connecting_elapsed >= 10.0:
			disconnect_game("Connection timed out. Check the host address and port.")
	var local_id: int = multiplayer.get_unique_id()
	if not players.has(local_id):
		return
	_send_elapsed += delta
	if _send_elapsed < SNAPSHOT_INTERVAL:
		return
	_send_elapsed = 0.0
	var state: Dictionary = players[local_id].call("make_snapshot")
	if multiplayer.is_server():
		_relay_snapshot(local_id, state)
		var npc_states: Dictionary = {}
		for npc_id: StringName in npcs:
			npc_states[npc_id] = npcs[npc_id].call("make_network_state")
		for peer_id: int in players:
			_publish_combat(peer_id)
			if peer_id != 1:
				_receive_npc_states.rpc_id(peer_id, npc_states)
		var motions: Dictionary = {}
		for item_id: StringName in items:
			if _item_owners[item_id] == 0:
				motions[item_id] = [_item_revisions[item_id], items[item_id].global_transform, items[item_id].linear_velocity]
		for target_id: int in players:
			if target_id != 1:
				_receive_items_motion.rpc_id(target_id, motions)
	else:
		_submit_snapshot.rpc_id(1, state)


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _submit_snapshot(state: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var peer_id: int = multiplayer.get_remote_sender_id()
	if not players.has(peer_id) or not players[peer_id].is_alive() or int(state.get("generation", -1)) != _life_generations[peer_id] or not _valid_snapshot(state):
		return
	players[peer_id].call("receive_snapshot", state)
	_relay_snapshot(peer_id, state)


func _relay_snapshot(peer_id: int, state: Dictionary) -> void:
	for target_id: int in players:
		if target_id != 1 and target_id != peer_id:
			_receive_snapshot.rpc_id(target_id, peer_id, state)


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _receive_snapshot(peer_id: int, state: Dictionary) -> void:
	if players.has(peer_id) and _valid_snapshot(state):
		players[peer_id].call("receive_snapshot", state)


func _on_item_pickup_requested(player: Node3D, item_id: StringName) -> void:
	_send_item_request(player, true, item_id)


func _on_item_drop_requested(player: Node3D, item_id: StringName) -> void:
	_send_item_request(player, false, item_id)


func _send_item_request(player: Node3D, pickup: bool, item_id: StringName = &"scrap_01") -> void:
	var local_id: int = multiplayer.get_unique_id()
	if players.get(local_id) != player:
		return
	if multiplayer.is_server():
		_queue_item_request(local_id, pickup, item_id)
	else:
		_request_item.rpc_id(1, pickup, item_id)


@rpc("any_peer", "call_remote", "reliable")
func _request_item(pickup: bool, item_id: StringName) -> void:
	if multiplayer.is_server():
		_queue_item_request(multiplayer.get_remote_sender_id(), pickup, item_id)


func _queue_item_request(peer_id: int, pickup: bool, item_id: StringName = &"scrap_01") -> void:
	if players.has(peer_id) and items.has(item_id) and _item_requests.size() < 32:
		_item_requests.append({"peer": peer_id, "pickup": pickup, "item": item_id})


func _process_item_requests() -> void:
	# RPCs enqueue requests; reach and obstruction checks run on the physics tick.
	for request: Dictionary in _item_requests:
		var peer_id: int = request["peer"]
		if not players.has(peer_id):
			continue
		var item_id: StringName = request["item"]
		var item: RigidBody3D = items[item_id]
		if request["pickup"]:
			if _item_owners[item_id] == 0 and bool(item.call("can_pickup", players[peer_id])):
				_publish_item_state(peer_id, item.global_transform, Vector3.ZERO, item_id)
		elif _item_owners[item_id] == peer_id:
			_release_item(peer_id, item_id)
	_item_requests.clear()


func _release_item(peer_id: int, item_id: StringName = &"scrap_01") -> void:
	var player: CharacterBody3D = players[peer_id]
	var pose: Transform3D = player.global_transform
	pose.origin += player.global_basis.z * 1.2 + player.global_basis.y * 0.4
	_publish_item_state(0, pose, player.velocity, item_id)


func _publish_item_state(owner_id: int, pose: Transform3D, motion: Vector3, item_id: StringName = &"scrap_01") -> void:
	var revision: int = _item_revisions[item_id] + 1
	_receive_item_state(owner_id, pose, motion, revision, item_id)
	for target_id: int in players:
		if target_id != 1 and multiplayer.get_peers().has(target_id):
			_receive_item_state.rpc_id(target_id, owner_id, pose, motion, revision, item_id)


@rpc("authority", "call_remote", "reliable")
func _receive_item_state(owner_id: int, pose: Transform3D, motion: Vector3, revision: int, item_id: StringName = &"scrap_01") -> void:
	if not items.has(item_id) or revision < _item_revisions[item_id] or (owner_id != 0 and not players.has(owner_id)):
		return
	var previous_owner: CharacterBody3D = players.get(_item_owners[item_id]) as CharacterBody3D
	var new_owner: CharacterBody3D = players.get(owner_id) as CharacterBody3D
	_item_owners[item_id] = owner_id
	_item_revisions[item_id] = revision
	items[item_id].call("apply_network_state", new_owner, pose, motion, multiplayer.is_server() and not players.is_empty())
	var pair: Node3D = $PortalPair
	if is_instance_valid(previous_owner):
		pair.call("refresh_traveller_visual", previous_owner)
	if new_owner != null and new_owner != previous_owner:
		pair.call("refresh_traveller_visual", new_owner)


@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _receive_items_motion(motions: Dictionary) -> void:
	for item_id: StringName in motions:
		var state: Variant = motions[item_id]
		if state is Array and state.size() == 3 and state[0] is int and state[1] is Transform3D and state[2] is Vector3:
			_receive_item_motion(state[0], state[1], state[2], item_id)


func _receive_item_motion(revision: int, pose: Transform3D, motion: Vector3, item_id: StringName = &"scrap_01") -> void:
	if items.has(item_id) and revision == _item_revisions[item_id] and _item_owners[item_id] == 0 and pose.is_finite() and motion.is_finite():
		items[item_id].call("receive_world_pose", pose, motion)


func _check_delivery() -> void:
	var zone: Area3D = $DeliveryZone
	var shape: BoxShape3D = $DeliveryZone/Collision.shape as BoxShape3D
	var credited: bool = false
	for item_id: StringName in items:
		var item: RigidBody3D = items[item_id]
		if _item_owners[item_id] != 0 or not AABB(-shape.size * 0.5, shape.size).has_point(zone.to_local(item.global_position)):
			continue
		team_money += int(item.get("cash_value"))
		team_score += int(item.get("score_value"))
		deliveries += 1
		# Reset each delivered object before the next tick can credit it again.
		_publish_item_state(0, _item_spawns[item_id], Vector3.ZERO, item_id)
		credited = true
	if credited:
		_publish_economy()


func get_purchase_cost(peer_id: int, item_id: StringName) -> int:
	var owned: Dictionary = purchases.get(peer_id, {})
	if EQUIPMENT_COSTS.has(item_id):
		return -1 if owned.has(item_id) else EQUIPMENT_COSTS[item_id]
	if UPGRADE_IDS.has(item_id):
		var level: int = int(owned.get(item_id, 0))
		return UPGRADE_COSTS[level] if level < UPGRADE_COSTS.size() else -1
	return -1


func buy_item(item_id: StringName) -> void:
	var peer_id: int = multiplayer.get_unique_id()
	if not players.has(peer_id):
		return
	if multiplayer.is_server():
		_queue_purchase(peer_id, item_id)
	else:
		_request_purchase.rpc_id(1, item_id)


@rpc("any_peer", "call_remote", "reliable")
func _request_purchase(item_id: StringName) -> void:
	if multiplayer.is_server():
		_queue_purchase(multiplayer.get_remote_sender_id(), item_id)


func _queue_purchase(peer_id: int, item_id: StringName) -> void:
	if players.has(peer_id) and _purchase_requests.size() < 32:
		_purchase_requests.append({"peer": peer_id, "item": item_id})


func _process_purchases() -> void:
	for request: Dictionary in _purchase_requests:
		var peer_id: int = request["peer"]
		var item_id: StringName = request["item"]
		if not players.has(peer_id):
			continue
		var cost: int = get_purchase_cost(peer_id, item_id)
		if cost <= 0 or team_money < cost:
			if peer_id == 1:
				_purchase_result("Purchase refused: insufficient team funds, or item already owned.")
			elif multiplayer.get_peers().has(peer_id):
				_purchase_result.rpc_id(peer_id, "Purchase refused: insufficient team funds, or item already owned.")
			continue
		team_money -= cost
		var owned: Dictionary = purchases.get(peer_id, {}).duplicate()
		owned[item_id] = int(owned.get(item_id, 0)) + 1
		purchases[peer_id] = owned
		_publish_economy()
		if peer_id == 1:
			_purchase_result("Purchased %s for $%d from team funds." % [item_id, cost])
		elif multiplayer.get_peers().has(peer_id):
			_purchase_result.rpc_id(peer_id, "Purchased %s for $%d from team funds." % [item_id, cost])
	_purchase_requests.clear()


@rpc("authority", "call_remote", "reliable")
func _purchase_result(message: String) -> void:
	_set_status(message)


func _publish_economy() -> void:
	_receive_economy(team_money, team_score, deliveries, purchases)
	for peer_id: int in players:
		if peer_id != 1 and multiplayer.get_peers().has(peer_id):
			_receive_economy.rpc_id(peer_id, team_money, team_score, deliveries, purchases)


@rpc("authority", "call_remote", "reliable")
func _receive_economy(balance: int, points: int, count: int, owned: Dictionary) -> void:
	team_money = balance
	team_score = points
	deliveries = count
	purchases.assign(owned.duplicate(true))
	for player: CharacterBody3D in players.values():
		player.call("apply_team_purchases")
	_refresh_ui()


func _valid_snapshot(state: Dictionary) -> bool:
	if state.size() != 11 or not state.get("generation") is int or state["generation"] < 0:
		return false
	if not state.get("transform") is Transform3D or not state.get("velocity") is Vector3:
		return false
	var pose: Transform3D = state["transform"]
	var motion: Vector3 = state["velocity"]
	if not pose.is_finite() or not motion.is_finite() or absf(pose.basis.determinant()) < 0.001:
		return false
	for key: String in ["on_floor", "sprinting", "crouching", "eye_light"]:
		if not state.get(key) is bool:
			return false
	for key: String in ["yaw", "pitch"]:
		if not state.get(key) is float or not is_finite(state[key]):
			return false
	return state.get("jump") is int and state["jump"] in [0, 1] and state.get("epoch") is int and state["epoch"] >= 0


func _spawn_position(slot: int) -> Vector3:
	return Vector3(-2.25 + float(slot) * 1.5, 1.0, 7.0)


func _local_appearance() -> Dictionary:
	return get_node("/root/CharacterAppearance").call("make_replication_payload") as Dictionary


func _sanitize_appearance(payload: Dictionary) -> Dictionary:
	var appearance: Node = get_node("/root/CharacterAppearance")
	var profile: Dictionary = appearance.call("profile_from_replication_payload", payload)
	return appearance.call("make_replication_payload", profile) as Dictionary


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not event.is_echo() and not players.is_empty():
		_set_menu_open(not _menu_open)
		get_viewport().set_input_as_handled()


func _set_menu_open(open: bool) -> void:
	_menu_open = open
	_panel.visible = open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED
	var local_id: int = multiplayer.get_unique_id()
	if players.has(local_id):
		var player: CharacterBody3D = players[local_id]
		player.call("set_movement_locked", open)
		player.set_process_input(not open and player.is_alive())
		player.get_node("CameraHolder").set_process_input(not open and player.is_alive())
	_refresh_ui()


func _refresh_ui() -> void:
	if _status == null:
		return
	var active: bool = not players.is_empty() or _connecting
	_host_button.disabled = active
	_join_button.disabled = active
	_address.editable = not active
	_port.editable = not active
	_map_choice.disabled = active
	_disconnect_button.visible = active
	_resume_button.visible = not players.is_empty()
	var local: CharacterBody3D = players.get(multiplayer.get_unique_id())
	var dead: bool = local != null and not local.is_alive()
	_respawn_button.visible = dead
	_resume_button.disabled = dead
	_team_label.text = "TEAM MONEY $%d · SCORE %d · DELIVERIES %d" % [team_money, team_score, deliveries]
	_shop_panel.visible = _menu_open and not players.is_empty()
	var local_id: int = multiplayer.get_unique_id()
	for item_id: StringName in _shop_buttons:
		var cost: int = get_purchase_cost(local_id, item_id)
		var title: String = str(item_id).replace("_", " ").capitalize()
		_shop_buttons[item_id].text = "%s · $%d" % [title, cost] if cost > 0 else "%s · Owned / max level" % title
		_shop_buttons[item_id].disabled = cost <= 0 or team_money < cost
	if not players.is_empty():
		_set_status("%s · %d/%d players · Port %d · ESC: session menu" % [
			"Hosting" if multiplayer.is_server() else "Connected", players.size(), MAX_PLAYERS, int(_port.value)])


func _set_status(message: String) -> void:
	if _status != null:
		_status.text = message


func _build_ui() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	_status = Label.new()
	_status.position = Vector2(24, 72)
	layer.add_child(_status)
	_team_label = Label.new()
	_team_label.position = Vector2(24, 100)
	layer.add_child(_team_label)
	_panel = PanelContainer.new()
	_panel.position = Vector2(24, 140)
	_panel.custom_minimum_size = Vector2(380, 0)
	layer.add_child(_panel)
	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	_panel.add_child(margin)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var title: Label = Label.new()
	title.text = session_title
	column.add_child(title)
	_map_choice = OptionButton.new()
	_map_choice.add_item("Portal arena")
	_map_choice.add_item("Farm prototype")
	_map_choice.select(maxi(0, LEVEL_PATHS.find(scene_file_path)))
	_map_choice.item_selected.connect(func(index: int) -> void:
		if players.is_empty() and not _connecting:
			get_tree().change_scene_to_file(LEVEL_PATHS[index]))
	column.add_child(_map_choice)
	_address = LineEdit.new()
	_address.text = "127.0.0.1"
	_address.placeholder_text = "Host IP address"
	column.add_child(_address)
	var port_row: HBoxContainer = HBoxContainer.new()
	column.add_child(port_row)
	var port_label: Label = Label.new()
	port_label.text = "UDP port"
	port_row.add_child(port_label)
	_port = SpinBox.new()
	_port.min_value = 1024
	_port.max_value = 65535
	_port.value = DEFAULT_PORT
	port_row.add_child(_port)
	_host_button = _button(column, "Host game", func() -> void: host_game(int(_port.value)))
	_join_button = _button(column, "Join game", func() -> void: join_game(_address.text, int(_port.value)))
	_resume_button = _button(column, "Resume", func() -> void: _set_menu_open(false))
	_respawn_button = _button(column, "Respawn", request_respawn)
	_disconnect_button = _button(column, "Disconnect", func() -> void: disconnect_game())
	_button(column, "Main menu", func() -> void:
		disconnect_game()
		get_tree().change_scene_to_file("res://scenes/Menu/main_menu.tscn"))
	_shop_panel = PanelContainer.new()
	_shop_panel.position = Vector2(430, 140)
	_shop_panel.custom_minimum_size.x = 320
	layer.add_child(_shop_panel)
	var shop: VBoxContainer = VBoxContainer.new()
	_shop_panel.add_child(shop)
	var shop_title: Label = Label.new()
	shop_title.text = "TEAM FUNDS · EQUIPMENT FOR YOU"
	shop.add_child(shop_title)
	for item_id: StringName in [&"movement", &"stamina", &"recovery", &"energy_shield", &"xray_goggles", &"predator_watch"]:
		_shop_buttons[item_id] = _button(shop, str(item_id), buy_item.bind(item_id))
	_refresh_ui()
	_set_status("Host a game, or join using the host's IP. Same computer: 127.0.0.1.")


func _button(parent: VBoxContainer, caption: String, callback: Callable) -> Button:
	var button: Button = Button.new()
	button.text = caption
	button.custom_minimum_size.y = 36
	button.pressed.connect(callback)
	parent.add_child(button)
	return button
