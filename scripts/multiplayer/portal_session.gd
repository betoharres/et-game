extends Node3D

const PLAYER_SCENE: PackedScene = preload("res://scenes/Multiplayer/NetworkPlayer.tscn")
const MAX_PLAYERS: int = 4
const DEFAULT_PORT: int = 7000
const SNAPSHOT_INTERVAL: float = 1.0 / 20.0

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
var _item_owner: int = 0
var _item_revision: int = 0
var _item_spawn_pose: Transform3D
var _item_requests: Array[Dictionary] = []

@onready var player_container: Node3D = $Players
@onready var shared_item: RigidBody3D = $PickupItemsContainer/SharedScrap


func _ready() -> void:
	_item_spawn_pose = shared_item.global_transform
	shared_item.pickup_requested.connect(_on_item_pickup_requested)
	shared_item.drop_requested.connect(_on_item_drop_requested)
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
	_publish_item_state(0, _item_spawn_pose, Vector3.ZERO)
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
	shared_item.call("apply_network_state", null, _item_spawn_pose, Vector3.ZERO, false)
	_item_owner = 0
	_item_revision = 0
	_item_requests.clear()
	_close_peer()
	_connecting = false
	for player: CharacterBody3D in players.values():
		player_container.remove_child(player)
		player.queue_free()
	players.clear()
	_profiles.clear()
	_slots.clear()
	$LobbyCamera.make_current()
	_set_menu_open(true)
	_refresh_ui()
	_set_status(message)


func _close_peer() -> void:
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func _on_connected() -> void:
	_register_player.rpc_id(1, _local_appearance())


func _on_connection_failed() -> void:
	disconnect_game("Could not connect. Check the address, port, or whether the session is full.")


func _on_server_disconnected() -> void:
	disconnect_game("The host disconnected.")


@rpc("any_peer", "call_remote", "reliable")
func _register_player(profile: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var peer_id: int = multiplayer.get_remote_sender_id()
	if peer_id <= 1 or players.has(peer_id) or not multiplayer.get_peers().has(peer_id):
		return
	if players.size() >= MAX_PLAYERS:
		(multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(peer_id)
		return
	var slot: int = 0
	while _slots.values().has(slot):
		slot += 1
	var sanitized: Dictionary = _sanitize_appearance(profile)
	for existing_id: int in players:
		_spawn_player.rpc_id(peer_id, existing_id, _slots[existing_id], _profiles[existing_id], players[existing_id].global_transform)
	var initial_transform: Transform3D = Transform3D(Basis.IDENTITY, _spawn_position(slot))
	_spawn_player(peer_id, slot, sanitized, initial_transform)
	_spawn_player.rpc(peer_id, slot, sanitized, initial_transform)
	_receive_item_state.rpc_id(peer_id, _item_owner, shared_item.global_transform, shared_item.linear_velocity, _item_revision)


@rpc("authority", "call_remote", "reliable")
func _spawn_player(peer_id: int, slot: int, profile: Dictionary, initial_transform: Transform3D) -> void:
	if players.has(peer_id) or players.size() >= MAX_PLAYERS:
		return
	var player: CharacterBody3D = PLAYER_SCENE.instantiate() as CharacterBody3D
	player.name = str(peer_id)
	player.set_multiplayer_authority(peer_id)
	player.transform = initial_transform
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
		if _item_owner == peer_id:
			_release_item(peer_id)
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
	_refresh_ui()


func _physics_process(delta: float) -> void:
	if multiplayer.is_server() and not players.is_empty():
		_process_item_requests()
		if _item_owner == 0 and shared_item.global_position.y < -10.0:
			_publish_item_state(0, _item_spawn_pose, Vector3.ZERO)
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
		if _item_owner == 0:
			for target_id: int in players:
				if target_id != 1:
					_receive_item_motion.rpc_id(target_id, _item_revision, shared_item.global_transform, shared_item.linear_velocity)
	else:
		_submit_snapshot.rpc_id(1, state)


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _submit_snapshot(state: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var peer_id: int = multiplayer.get_remote_sender_id()
	if not players.has(peer_id) or not _valid_snapshot(state):
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


func _on_item_pickup_requested(player: Node3D) -> void:
	_send_item_request(player, true)


func _on_item_drop_requested(player: Node3D) -> void:
	_send_item_request(player, false)


func _send_item_request(player: Node3D, pickup: bool) -> void:
	var local_id: int = multiplayer.get_unique_id()
	if players.get(local_id) != player:
		return
	if multiplayer.is_server():
		_queue_item_request(local_id, pickup)
	else:
		_request_item.rpc_id(1, pickup)


@rpc("any_peer", "call_remote", "reliable")
func _request_item(pickup: bool) -> void:
	if multiplayer.is_server():
		_queue_item_request(multiplayer.get_remote_sender_id(), pickup)


func _queue_item_request(peer_id: int, pickup: bool) -> void:
	if players.has(peer_id) and _item_requests.size() < 32:
		_item_requests.append({"peer": peer_id, "pickup": pickup})


func _process_item_requests() -> void:
	# RPCs enqueue requests; reach and obstruction checks run on the physics tick.
	for request: Dictionary in _item_requests:
		var peer_id: int = request["peer"]
		if not players.has(peer_id):
			continue
		if request["pickup"]:
			if _item_owner == 0 and bool(shared_item.call("can_pickup", players[peer_id])):
				_publish_item_state(peer_id, shared_item.global_transform, Vector3.ZERO)
		elif _item_owner == peer_id:
			_release_item(peer_id)
	_item_requests.clear()


func _release_item(peer_id: int) -> void:
	var player: CharacterBody3D = players[peer_id]
	var pose: Transform3D = player.global_transform
	pose.origin += player.global_basis.z * 1.2 + player.global_basis.y * 0.4
	_publish_item_state(0, pose, player.velocity)


func _publish_item_state(owner_id: int, pose: Transform3D, motion: Vector3) -> void:
	var revision: int = _item_revision + 1
	_receive_item_state(owner_id, pose, motion, revision)
	for target_id: int in players:
		if target_id != 1 and multiplayer.get_peers().has(target_id):
			_receive_item_state.rpc_id(target_id, owner_id, pose, motion, revision)


@rpc("authority", "call_remote", "reliable")
func _receive_item_state(owner_id: int, pose: Transform3D, motion: Vector3, revision: int) -> void:
	if revision < _item_revision or (owner_id != 0 and not players.has(owner_id)):
		return
	var previous_owner: CharacterBody3D = players.get(_item_owner) as CharacterBody3D
	var new_owner: CharacterBody3D = players.get(owner_id) as CharacterBody3D
	_item_owner = owner_id
	_item_revision = revision
	shared_item.call("apply_network_state", new_owner, pose, motion, multiplayer.is_server() and not players.is_empty())
	var pair: Node3D = $PortalPair
	if is_instance_valid(previous_owner):
		pair.call("refresh_traveller_visual", previous_owner)
	if new_owner != null and new_owner != previous_owner:
		pair.call("refresh_traveller_visual", new_owner)


@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _receive_item_motion(revision: int, pose: Transform3D, motion: Vector3) -> void:
	if revision == _item_revision and _item_owner == 0 and pose.is_finite() and motion.is_finite():
		shared_item.call("receive_world_pose", pose, motion)


func _valid_snapshot(state: Dictionary) -> bool:
	if state.size() != 10:
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
		player.set_process_input(not open)
		player.get_node("CameraHolder").set_process_input(not open)


func _refresh_ui() -> void:
	if _status == null:
		return
	var active: bool = not players.is_empty() or _connecting
	_host_button.disabled = active
	_join_button.disabled = active
	_address.editable = not active
	_port.editable = not active
	_disconnect_button.visible = active
	_resume_button.visible = not players.is_empty()
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
	_panel = PanelContainer.new()
	_panel.position = Vector2(24, 112)
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
	title.text = "PORTAL CO-OP · UP TO 4 PLAYERS"
	column.add_child(title)
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
	_disconnect_button = _button(column, "Disconnect", func() -> void: disconnect_game())
	_button(column, "Main menu", func() -> void:
		disconnect_game()
		get_tree().change_scene_to_file("res://scenes/Menu/main_menu.tscn"))
	_refresh_ui()
	_set_status("Host a game, or join using the host's IP. Same computer: 127.0.0.1.")


func _button(parent: VBoxContainer, caption: String, callback: Callable) -> Button:
	var button: Button = Button.new()
	button.text = caption
	button.custom_minimum_size.y = 36
	button.pressed.connect(callback)
	parent.add_child(button)
	return button
