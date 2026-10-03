extends SceneTree

const PORT: int = 17070
var _sessions: Array[Node3D] = []
var _viewports: Array[SubViewport] = []
var _failed: bool = false
var _original_appearance: Dictionary


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var appearance: Node = root.get_node("CharacterAppearance")
	_original_appearance = appearance.call("get_profile")
	var session_scene: PackedScene = load("res://scenes/Multiplayer/PortalCoop.tscn") as PackedScene
	for index: int in 5:
		var viewport: SubViewport = SubViewport.new()
		viewport.name = "Peer%d" % index
		viewport.own_world_3d = true
		root.add_child(viewport)
		var api: MultiplayerAPI = MultiplayerAPI.create_default_interface()
		set_multiplayer(api, viewport.get_path())
		var session: Node3D = session_scene.instantiate() as Node3D
		viewport.add_child(session)
		_sessions.append(session)
		_viewports.append(viewport)
	await process_frame
	_check(_sessions[0].host_game(PORT) == OK, "Host starts")
	for index: int in range(1, 4):
		var profile: Dictionary = _original_appearance.duplicate(true)
		profile["head_size"] = float(index) * 0.25
		appearance.call("set_profile", profile, false)
		_check(_sessions[index].join_game("127.0.0.1", PORT) == OK, "Client connects")
		_check(await _wait_for(func() -> bool: return _sessions[index].players.size() == index + 1), "Join handshake completes")
	_check(await _wait_for(func() -> bool:
		for index: int in 4:
			if _sessions[index].players.size() != 4:
				return false
		return true), "All four peers receive the same roster")
	if _failed:
		_finish()
		return
	for index: int in 4:
		var session: Node3D = _sessions[index]
		var local_id: int = session.multiplayer.get_unique_id()
		var local: CharacterBody3D = session.players[local_id]
		local.set_physics_process(false)
		_check(_viewports[index].get_camera_3d() == local.camera_pivot.get_camera(), "Each viewport uses its own local camera")
		for peer_id: int in session.players:
			var player: CharacterBody3D = session.players[peer_id]
			_check(player.is_local_player() == (peer_id == local_id), "Player ownership")
			_check(player.get_node("PlayerHUD").visible == (peer_id == local_id), "Only local HUD is visible")
			var source: CharacterBody3D = _sessions[0].players[peer_id]
			_check(player.get_appearance_profile() == source.get_appearance_profile(), "Each player's appearance reaches late joiners")
		var pair: Node3D = session.get_node("PortalPair")
		pair._process(0.0)
		_check(pair.player_camera == local.camera_pivot.get_camera(), "Portal follows the local camera")
	await _test_collectible()
	var moving_session: Node3D = _sessions[1]
	var moving_id: int = moving_session.multiplayer.get_unique_id()
	var moving_player: CharacterBody3D = moving_session.players[moving_id]
	moving_player.global_position = Vector3(4, 1, 8)
	moving_player.velocity = Vector3(0.4, 0, 0)
	_check(await _wait_for(func() -> bool:
		return _sessions[0].players[moving_id].global_position.distance_to(Vector3(4, 1, 8)) < 0.05
		), "Guest movement reaches host")
	_check(await _wait_for(func() -> bool:
		return _sessions[2].players[moving_id].global_position.distance_to(Vector3(4, 1, 8)) < 0.05
		), "Host relays guest movement to other guests")
	var pair: Node3D = moving_session.get_node("PortalPair")
	var expected: Transform3D = pair._portal_mapping(pair.portal_1, pair.portal_2) * moving_player.global_transform
	moving_player.apply_portal_transform(pair._portal_mapping(pair.portal_1, pair.portal_2))
	_check(await _wait_for(func() -> bool:
		return _sessions[0].players[moving_id].global_position.distance_to(expected.origin) < 0.001
		), "Portal crossing replicates without interpolation across the map")
	var remote: CharacterBody3D = _sessions[0].players[moving_id]
	var before: Transform3D = remote.global_transform
	remote.apply_portal_transform(Transform3D(Basis.IDENTITY, Vector3(20, 0, 0)))
	_check(remote.global_transform == before, "Remote bodies cannot teleport independently")
	_check(not _sessions[0]._valid_snapshot({"transform": Transform3D.IDENTITY}), "Malformed snapshots are rejected")
	_check(_sessions[4].join_game("127.0.0.1", PORT) == OK, "Fifth peer attempts connection")
	await create_timer(0.8).timeout
	_check(_sessions[4].players.is_empty() and _sessions[0].players.size() == 4, "Fifth player is refused")
	_sessions[4].disconnect_game()
	await _claim_item(_sessions[3])
	var departing_id: int = _sessions[3].multiplayer.get_unique_id()
	_check(_sessions[0]._item_owner == departing_id, "Departing guest carries the item")
	_sessions[3].disconnect_game()
	_check(await _wait_for(func() -> bool: return _sessions[0].players.size() == 3 and _sessions[1].players.size() == 3), "Disconnect removes player from peers")
	_check(await _wait_for(func() -> bool: return _sessions[0]._item_owner == 0 and not _sessions[1].shared_item.carried), "Disconnect drops the item instead of deleting it")
	await _claim_item(_sessions[1])
	_check(_sessions[4].join_game("127.0.0.1", PORT) == OK, "Replacement player joins")
	_check(await _wait_for(func() -> bool: return _sessions[4].players.size() == 4), "Freed slot is reusable")
	_check(await _wait_for(func() -> bool: return _sessions[4]._item_owner == moving_id and _sessions[4].shared_item.carrier == _sessions[4].players[moving_id]), "Late join receives the held item and its carrier")
	_sessions[0].disconnect_game()
	_check(await _wait_for(func() -> bool: return _sessions[1].players.is_empty() and _sessions[2].players.is_empty() and _sessions[4].players.is_empty()), "Host shutdown returns guests to connection UI")
	_finish()


func _test_collectible() -> void:
	var host: Node3D = _sessions[0]
	var guest: Node3D = _sessions[1]
	var guest_id: int = guest.multiplayer.get_unique_id()
	var guest_player: CharacterBody3D = guest.players[guest_id]
	_check(await _wait_for(func() -> bool: return host.shared_item.global_position.y < 0.3), "Host simulates the loose item's physics")
	_check(not host.shared_item.freeze and guest.shared_item.freeze, "Only host simulates the loose rigid body")
	guest.shared_item.pickup(guest_player)
	await create_timer(0.15).timeout
	_check(host._item_owner == 0, "Host rejects an out-of-range pickup")
	guest_player.global_position = host.shared_item.global_position + Vector3(0, 0, 1.5)
	_check(await _wait_for(func() -> bool: return host.players[guest_id].global_position.distance_to(guest_player.global_position) < 0.05), "Pickup requester position reaches host")
	var wall: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(1, 2, 0.15)
	collision.shape = shape
	wall.add_child(collision)
	host.add_child(wall)
	wall.global_position = host.shared_item.global_position + Vector3(0, 0.5, 0.75)
	await physics_frame
	await physics_frame
	guest.shared_item.pickup(guest_player)
	await create_timer(0.15).timeout
	_check(host._item_owner == 0, "Host rejects pickup through an obstacle")
	wall.queue_free()
	await physics_frame
	await physics_frame
	_check(guest_player.get_pickup_candidate() == guest.shared_item, "Player pickup candidate stays in its own peer's world")
	host.players[1].global_position = host.shared_item.global_position + Vector3(0.5, 0, 1)
	guest_player.try_pickup()
	host.shared_item.pickup(host.players[1])
	_check(await _wait_for(func() -> bool:
		var owner_id: int = host._item_owner
		if owner_id == 0:
			return false
		for index: int in 4:
			if _sessions[index]._item_owner != owner_id:
				return false
		return true), "Concurrent requests produce exactly one replicated owner")
	var owner_id: int = host._item_owner
	if owner_id == 0:
		return
	var owner_session: Node3D = host if owner_id == 1 else guest
	var owner: CharacterBody3D = owner_session.players[owner_id]
	var losing_session: Node3D = guest if owner_id == 1 else host
	losing_session._send_item_request(losing_session.players[losing_session.multiplayer.get_unique_id()], false)
	await create_timer(0.15).timeout
	_check(host._item_owner == owner_id, "A non-owner cannot drop another player's item")
	for index: int in 4:
		var session: Node3D = _sessions[index]
		_check(session.shared_item.carrier == session.players[owner_id], "All peers attach the scrap to the same carrier")
		_check(session.players[owner_id].carried_item == session.shared_item, "Carry state and HUD reference the shared item")
	var pair: Node3D = owner_session.get_node("PortalPair")
	pair._on_portal_body_entered(owner, pair.portal_1, pair.portal_2)
	var visual: Node3D = pair._travellers[owner.get_instance_id()]["visual"]
	_check(_visual_contains(visual, owner_session.shared_item.get_node("Mesh")), "Held scrap participates in portal slicing and clones")
	var mapping: Transform3D = pair._portal_mapping(pair.portal_1, pair.portal_2)
	var expected_item: Vector3 = mapping * owner_session.shared_item.global_position
	owner.apply_portal_transform(mapping)
	_check(owner_session.shared_item.global_position.distance_to(expected_item) < 0.001, "Held item travels through the portal with its carrier")
	_check(await _wait_for(func() -> bool:
		return _sessions[2].shared_item.global_position.distance_to(owner_session.shared_item.global_position) < 0.05), "Carried portal crossing reaches observers")
	var old_revision: int = host._item_revision
	var drop_event: InputEventAction = InputEventAction.new()
	drop_event.action = &"drop_item"
	drop_event.pressed = true
	owner._input(drop_event)
	_check(await _wait_for(func() -> bool:
		for index: int in 4:
			if _sessions[index]._item_owner != 0 or _sessions[index].shared_item.carried:
				return false
		return true), "Existing drop control releases the scrap for every peer")
	visual = pair._travellers[owner.get_instance_id()]["visual"] if pair._travellers.has(owner.get_instance_id()) else null
	if visual != null:
		_check(not _visual_contains(visual, owner_session.shared_item.get_node("Mesh")), "Dropping removes the scrap from the carrier's portal clone")
		pair._remove_traveller(owner.get_instance_id())
	_check(await _wait_for(func() -> bool:
		return guest.shared_item.global_position.distance_to(host.shared_item.global_position) < 0.12), "Host replicates dropped item motion")
	guest._receive_item_motion(old_revision, Transform3D(Basis.IDENTITY, Vector3(99, 99, 99)), Vector3.ZERO)
	_check(guest.shared_item._target_pose.origin.distance_to(Vector3(99, 99, 99)) > 1.0, "Stale item motion cannot overwrite a newer ownership revision")
	_check(host.shared_item.collision_layer == 8 and host.shared_item.collision_mask == 1, "Drop restores item collisions")


func _claim_item(session: Node3D) -> void:
	var host: Node3D = _sessions[0]
	if host._item_owner != 0:
		var current_id: int = host._item_owner
		host._queue_item_request(current_id, false)
		_check(await _wait_for(func() -> bool: return host._item_owner == 0), "Previous carrier releases item")
	var peer_id: int = session.multiplayer.get_unique_id()
	var player: CharacterBody3D = session.players[peer_id]
	player.set_physics_process(false)
	player.global_position = host.shared_item.global_position + Vector3(0, 0, 1.2)
	_check(await _wait_for(func() -> bool: return host.players[peer_id].global_position.distance_to(player.global_position) < 0.05), "Next carrier reaches the dropped scrap")
	session.shared_item.pickup(player)
	_check(await _wait_for(func() -> bool: return host._item_owner == peer_id and session.shared_item.carrier == player), "Another player can collect the dropped scrap")


func _visual_contains(visual: Node3D, mesh: MeshInstance3D) -> bool:
	for entry: Dictionary in visual._meshes:
		if entry["source"] == mesh:
			return true
	return false


func _wait_for(predicate: Callable) -> bool:
	var deadline: int = Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		if bool(predicate.call()):
			return true
		await process_frame
	return false


func _check(condition: bool, description: String) -> void:
	if not condition:
		push_error("FAIL: " + description)
		_failed = true


func _finish() -> void:
	root.get_node("CharacterAppearance").call("set_profile", _original_appearance, false)
	for session: Node3D in _sessions:
		session.disconnect_game()
	for viewport: SubViewport in _viewports:
		viewport.queue_free()
	await process_frame
	if not _failed:
		print("PASS: four-player networking and shared collectible ownership, pickup/drop, portal carry, late join and disconnects")
	quit(1 if _failed else 0)
