extends Node

@export var plane: bool = false
var occupants: Array[int] = []
var controls: Vector2 = Vector2.ZERO
var aim: Vector3 = Vector3.FORWARD
var _session: Node3D
var _body: RigidBody3D
var _elapsed: float = 0.0
var _control_age: float = 0.0
var _target: Transform3D
var _has_pose: bool = false
var _collision: Dictionary[int, Vector2i] = {}
var _spawn: Transform3D


func _ready() -> void:
	_body = get_parent() as RigidBody3D
	_spawn = _body.global_transform
	_session = _body.get_parent().get_parent() as Node3D
	occupants.resize(1 if plane else 4)
	occupants.fill(0)
	add_to_group(&"house_doors")
	_configure.call_deferred()


func _configure() -> void:
	_body.set_process_input(false)
	_body.set_process_unhandled_input(false)
	_body.set_physics_process(false)
	_body.freeze = not multiplayer.is_server() or occupants[0] == 0
	if plane:
		_body.set("standalone_control_if_no_player", false)
	else:
		_body.get_node("ET2").hide()
	for node: Node in _body.find_children("*", "Camera3D", true, false):
		(node as Camera3D).current = false
	for node: Node in _body.find_children("*", "Node3D", true, false):
		node.set_process_input(false)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact") or event.is_echo():
		return
	var peer_id: int = multiplayer.get_unique_id()
	if not _session.players.has(peer_id):
		return
	var player: CharacterBody3D = _session.players[peer_id]
	if reserves_interaction_for(player):
		request_seat()
		get_viewport().set_input_as_handled()


func reserves_interaction_for(player: Node3D) -> bool:
	if not player.has_method("is_local_player") or not player.is_local_player() or player.get_world_3d() != _body.get_world_3d():
		return false
	return occupants.has(player.get_multiplayer_authority()) or player.is_alive() and not _session._menu_open and _session.mission_phase == &"collecting" and player.carried_item == null and player.global_position.distance_to(_body.global_position) < 4.0


func request_seat() -> void:
	if multiplayer.is_server():
		_change_seat(multiplayer.get_unique_id())
	else:
		_request_seat.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_seat() -> void:
	if multiplayer.is_server():
		_change_seat(multiplayer.get_remote_sender_id())


func _change_seat(peer_id: int) -> void:
	if not _session.players.has(peer_id) or _session.mission_phase != &"collecting":
		return
	var player: CharacterBody3D = _session.players[peer_id]
	var seat: int = occupants.find(peer_id)
	if seat >= 0:
		occupants[seat] = 0
	elif player.is_alive() and not player.has_meta("coop_seated") and player.carried_item == null and player.global_position.distance_to(_body.global_position) < 4.0:
		seat = occupants.find(0)
		if seat < 0:
			return
		occupants[seat] = peer_id
	else:
		return
	_receive_seats(occupants)
	_receive_seats.rpc(occupants)


@rpc("authority", "call_remote", "reliable")
func _receive_seats(seats: Array) -> void:
	for peer_id: int in _collision.keys():
		if not seats.has(peer_id):
			_restore_player(peer_id)
	occupants.assign(seats.duplicate())
	for peer_id: int in occupants:
		if peer_id == 0 or not _session.players.has(peer_id) or _collision.has(peer_id):
			continue
		var player: CharacterBody3D = _session.players[peer_id]
		_collision[peer_id] = Vector2i(player.collision_layer, player.collision_mask)
		player.collision_layer = 0
		player.collision_mask = 0
		player.set_meta("coop_seated", true)
		player.call("set_movement_locked", true)
	_body.freeze = not multiplayer.is_server() or occupants[0] == 0
	controls = Vector2.ZERO


func _restore_player(peer_id: int) -> void:
	if _session.players.has(peer_id):
		var player: CharacterBody3D = _session.players[peer_id]
		player.collision_layer = _collision[peer_id].x
		player.collision_mask = _collision[peer_id].y
		player.remove_meta("coop_seated")
		player.call("set_movement_locked", false)
		player.global_position = _body.global_position + _body.global_basis.x * 3.0 + Vector3.UP
	_collision.erase(peer_id)


func _physics_process(delta: float) -> void:
	if _session.players.is_empty():
		_body.freeze = true
		return
	for peer_id: int in occupants.duplicate():
		if peer_id != 0 and (not _session.players.has(peer_id) or not _session.players[peer_id].is_alive()):
			if multiplayer.is_server():
				occupants[occupants.find(peer_id)] = 0
				_receive_seats(occupants)
				_receive_seats.rpc(occupants)
	if not multiplayer.is_server() and _has_pose:
		_body.global_transform = _body.global_transform.interpolate_with(_target, 1.0 - exp(-15.0 * delta))
	if occupants[0] == multiplayer.get_unique_id() and _session.players.has(occupants[0]):
		var player: CharacterBody3D = _session.players[occupants[0]]
		var motion: Vector2 = Vector2.ZERO if _session._menu_open or _session.mission_phase != &"collecting" else Vector2(Input.get_axis("ui_down", "ui_up"), Input.get_axis("ui_right", "ui_left"))
		var direction: Vector3 = -player.camera_pivot.get_camera().global_basis.z
		if multiplayer.is_server():
			controls = motion
			aim = direction
		else:
			_control.rpc_id(1, motion, direction)
	_control_age += delta
	if multiplayer.is_server() and occupants[0] != 0:
		if _control_age > 0.5 and occupants[0] != 1:
			controls = Vector2.ZERO
		if plane:
			_body.set("plane_controlled", true)
			_body.set("current_engine_force", _body.get("engine_force"))
			_body.target.global_position = _body.global_position + aim * 30.0
			_body.call("_apply_engine_and_drag")
			_body.call("_apply_lift")
			_body.call("_apply_aim_assist")
		else:
			_body.brake = 0.0
			_body.call("_apply_driving_input", controls.x, controls.y, delta)
	for seat: int in occupants.size():
		var peer_id: int = occupants[seat]
		if peer_id == 0 or not _session.players.has(peer_id):
			continue
		var player: CharacterBody3D = _session.players[peer_id]
		var offset: Vector3 = Vector3.ZERO if plane else [Vector3(-0.45, 0.6, 0.3), Vector3(0.45, 0.6, 0.3), Vector3(-0.45, 0.6, 2), Vector3(0.45, 0.6, 2)][seat]
		player.global_transform = _body.global_transform * Transform3D(Basis.IDENTITY, offset)
		player.velocity = _body.linear_velocity
		player.call("_update_camera_target")
	_elapsed += delta
	if multiplayer.is_server() and _elapsed >= 0.05:
		_elapsed = 0.0
		_receive_pose.rpc(_body.global_transform)


@rpc("any_peer", "call_remote", "unreliable_ordered", 4)
func _control(motion: Vector2, direction: Vector3) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != occupants[0] or not motion.is_finite() or not direction.is_finite():
		return
	controls = motion.clamp(Vector2(-1, -1), Vector2(1, 1))
	aim = direction.normalized()
	_control_age = 0.0


@rpc("authority", "call_remote", "unreliable_ordered", 4)
func _receive_pose(pose: Transform3D) -> void:
	_target = pose
	_has_pose = true


func send_snapshot(peer_id: int) -> void:
	_receive_seats.rpc_id(peer_id, occupants)
	_receive_pose.rpc_id(peer_id, _body.global_transform)


func reset() -> void:
	for peer_id: int in _collision.keys():
		_restore_player(peer_id)
	occupants.fill(0)
	controls = Vector2.ZERO
	_body.freeze = true
	_body.global_transform = _spawn
	_body.linear_velocity = Vector3.ZERO
	_body.angular_velocity = Vector3.ZERO
	_has_pose = false


func _exit_tree() -> void:
	if is_instance_valid(_session):
		reset()
