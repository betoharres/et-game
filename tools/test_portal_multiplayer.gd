extends SceneTree

const PORT: int = 17070
var _sessions: Array[Node3D] = []
var _viewports: Array[SubViewport] = []
var _failed: bool = false
var _original_appearance: Dictionary
var _visual: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_visual = OS.get_cmdline_user_args().has("--visual")
	if _visual:
		root.size = Vector2i(960, 540)
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
		if _visual and index == 0:
			viewport.size = Vector2i(960, 540)
			var screen: TextureRect = TextureRect.new()
			screen.texture = viewport.get_texture()
			screen.size = Vector2(960, 540)
			root.add_child(screen)
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
	await _test_team_economy()
	await _test_multiple_items()
	await _test_combat()
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
	_check(await _wait_for(func() -> bool:
		return _sessions[4].team_money == _sessions[0].team_money and _sessions[4].deliveries == _sessions[0].deliveries and _sessions[4].purchases == _sessions[0].purchases), "Late join receives team money, score and purchases")
	_sessions[0].disconnect_game()
	_check(await _wait_for(func() -> bool: return _sessions[1].players.is_empty() and _sessions[2].players.is_empty() and _sessions[4].players.is_empty()), "Host shutdown returns guests to connection UI")
	await _test_farm()
	_finish()


func _test_multiple_items() -> void:
	var host: Node3D = _sessions[0]
	for index: int in 4:
		_check(_sessions[index].items.keys() == host.items.keys() and host.items.size() == 4, "All peers register four stable item IDs")
	for index: int in 2:
		var session: Node3D = _sessions[index]
		var peer_id: int = session.multiplayer.get_unique_id()
		var item_id: StringName = &"scrap_02" if index == 0 else &"scrap_03"
		var player: CharacterBody3D = session.players[peer_id]
		player.global_position = host.items[item_id].global_position + Vector3(0, 0, 1.2)
		_check(await _wait_for(func() -> bool: return host.players[peer_id].global_position.distance_to(player.global_position) < 0.05), "Carrier reaches its separate scrap")
		session.items[item_id].pickup(player)
		_check(await _wait_for(func() -> bool: return host._item_owners[item_id] == peer_id), "Separate items have independent owners")
	var guest_id: int = _sessions[1].multiplayer.get_unique_id()
	_check(await _wait_for(func() -> bool: return _sessions[2]._item_owners[&"scrap_02"] == 1 and _sessions[2]._item_owners[&"scrap_03"] == guest_id), "Both carried scraps replicate together")
	host._queue_item_request(1, true, &"scrap_04")
	host._queue_item_request(1, true, &"unknown")
	await create_timer(0.15).timeout
	_check(host._item_owners[&"scrap_04"] == 0, "A carrier cannot acquire a second item")
	var money: int = host.team_money
	var deliveries: int = host.deliveries
	var pose: Transform3D = Transform3D(Basis.IDENTITY, host.get_node("DeliveryZone").global_position + Vector3(0, -0.8, 0))
	host._publish_item_state(0, pose, Vector3.ZERO, &"scrap_02")
	host._publish_item_state(0, pose, Vector3.ZERO, &"scrap_03")
	_check(await _wait_for(func() -> bool: return host.deliveries == deliveries + 2 and _sessions[1].team_money == money + 120), "Two independent deliveries credit the same team pool")
	await create_timer(0.15).timeout
	_check(host.deliveries == deliveries + 2, "Multiple deliveries each pay once")


func _test_farm() -> void:
	for session: Node3D in _sessions:
		session.disconnect_game()
	var farm_scene: PackedScene = load("res://scenes/Multiplayer/FarmCoop.tscn") as PackedScene
	for index: int in 2:
		var old: Node3D = _sessions[index]
		_viewports[index].remove_child(old)
		old.free()
		var farm: Node3D = farm_scene.instantiate() as Node3D
		_viewports[index].add_child(farm)
		_sessions[index] = farm
	await process_frame
	var host: Node3D = _sessions[0]
	var guest: Node3D = _sessions[1]
	_check(host.host_game(PORT + 1) == OK, "Farm host starts")
	_check(guest.join_game("127.0.0.1", PORT + 1) == OK, "Farm guest connects")
	_check(await _wait_for(func() -> bool: return guest.players.size() == 2), "Farm roster completes")
	_check(host.items.size() == 4 and host.get_node("BuildingContainers/Barn") != null, "Farm has independent scraps and its barn")
	_check(_sessions[2].join_game("127.0.0.1", PORT + 1) == OK, "Different map attempts to join")
	await create_timer(0.5).timeout
	_check(host.players.size() == 2 and _sessions[2].players.is_empty(), "Host rejects mismatched map before spawning a player")
	if guest.players.is_empty():
		return
	var peer_id: int = guest.multiplayer.get_unique_id()
	var player: CharacterBody3D = guest.players[peer_id]
	player.set_physics_process(false)
	player.global_position = host.items[&"scrap_02"].global_position + Vector3(0, 0, 1.2)
	_check(await _wait_for(func() -> bool: return host.players[peer_id].global_position.distance_to(player.global_position) < 0.05), "Guest reaches barn scrap")
	guest.items[&"scrap_02"].pickup(player)
	_check(await _wait_for(func() -> bool: return host._item_owners[&"scrap_02"] == peer_id), "Barn scrap pickup reaches farm host")
	var guard: NPCActor = host.npcs[&"Guard"]
	_check(await _wait_for(func() -> bool: return guard.global_position.distance_to(Vector3(8, 0, 13)) > 0.3), "Host guard patrol moves")
	_check(not guest.npcs[&"Guard"]._host_simulation and guest.npcs[&"Guard"].get_node("NPCBehaviorTree").enabled == false, "Guest guard does not run AI")
	guard.global_transform = Transform3D(Basis.IDENTITY, Vector3(8, 0, 13))
	player.global_position = Vector3(8, 0, 14.5)
	await _wait_for(func() -> bool: return host.players[peer_id].global_position.distance_to(player.global_position) < 0.05)
	guard.global_transform = Transform3D(Basis.IDENTITY, Vector3(8, 0, 13))
	await physics_frame
	_check(await _wait_for(func() -> bool: return player.health < player.max_health), "Host guard detects and damages a guest")
	_check(await _wait_for(func() -> bool: return not player.is_alive()), "Host guard kills the guest")
	_check(await _wait_for(func() -> bool: return host._item_owners[&"scrap_02"] == 0 and not guest.items[&"scrap_02"].carried), "NPC death drops the held scrap on all peers")
	_check(await _wait_for(func() -> bool: return guest.npcs[&"Guard"].global_position.distance_to(guard.global_position) < 0.4), "Guard pose reaches guest")
	for index: int in range(2, 4):
		var old: Node3D = _sessions[index]
		_viewports[index].remove_child(old)
		old.free()
		var farm: Node3D = farm_scene.instantiate() as Node3D
		_viewports[index].add_child(farm)
		_sessions[index] = farm
		_check(farm.join_game("127.0.0.1", PORT + 1) == OK, "Late farm guest connects")
		_check(await _wait_for(func() -> bool: return farm.players.size() == index + 1 and not farm.players[peer_id].is_alive()), "Late farm join receives the dead guest")
		_check(await _wait_for(func() -> bool: return farm.npcs[&"Guard"]._has_network_state), "Late farm join receives current NPC state")
	_check(host.players.size() == 4, "Farm supports four players with one authoritative guard")
	if _visual:
		await RenderingServer.frame_post_draw
		var capture_path: String = OS.get_environment("TEMP").path_join("et_coop_farm_test.png")
		_check(root.get_texture().get_image().save_png(capture_path) == OK, "Rendered farm capture saves")
		print("Farm capture: ", capture_path)
	guest.disconnect_game()
	_check(await _wait_for(func() -> bool: return host.players.size() == 3 and host._item_owners[&"scrap_02"] == 0), "Dead guest disconnect cleans up without deleting its scrap")
	var pose: Transform3D = Transform3D(Basis.IDENTITY, host.get_node("DeliveryZone").global_position + Vector3(0, -0.8, 0))
	host._publish_item_state(0, pose, Vector3.ZERO, &"scrap_02")
	_check(await _wait_for(func() -> bool: return host.deliveries == 1 and host.team_money == 60), "Farm delivery credits the shared pool")


func _test_combat() -> void:
	var host: Node3D = _sessions[0]
	var guest: Node3D = _sessions[1]
	var peer_id: int = guest.multiplayer.get_unique_id()
	var target: CharacterBody3D = guest.players[peer_id]
	var previous: float = target.health
	var solo_money: int = int(root.get_node("GlobalScore").get("money"))
	var initial_money: int = host.team_money
	host.players[1].debug_add_team_money()
	target.debug_add_team_money()
	_check(await _wait_for(func() -> bool:
		for index: int in 4:
			if _sessions[index].team_money != initial_money + 20000:
				return false
		return true), "Host and guest money cheats credit the shared team pool")
	_check(int(root.get_node("GlobalScore").get("money")) == solo_money, "Co-op money cheat leaves single-player wallet unchanged")
	target.take_damage(1000.0)
	await create_timer(0.1).timeout
	_check(target.health == previous and host.players[peer_id].health == previous, "Guest cannot author damage")
	var shield: float = host.players[peer_id].energy_shield
	host.damage_player(peer_id, 10.0)
	_check(await _wait_for(func() -> bool: return is_equal_approx(target.energy_shield, shield - 10.0)), "Host shield absorption replicates")
	_check(target.health == previous, "Shield protects health")
	var observer: CharacterBody3D = _sessions[2].players[peer_id]
	_check(await _wait_for(func() -> bool: return observer.energy_shield_mesh.visible), "Shield hit is visible on remote replica")
	_check(await _wait_for(func() -> bool: return not observer.energy_shield_mesh.visible), "Remote shield hit effect expires")
	host.players[peer_id]._energy_shield_recovery_timer = 0.05
	_check(await _wait_for(func() -> bool: return target.energy_shield > shield - 10.0), "Host shield recovery reaches its owner")
	await _claim_item(guest)
	host.damage_player(peer_id, host.players[peer_id].energy_shield)
	_check(await _wait_for(func() -> bool: return target.energy_shield == 0.0 and observer.energy_shield == 0.0), "Shield can be depleted without killing its owner")
	_check(target.is_alive() and not target.energy_shield_mesh.visible and not observer.energy_shield_mesh.visible, "Depleted shield is hidden on owner and observer")
	var money: int = host.team_money
	var owned: Dictionary = host.purchases[peer_id].duplicate(true)
	var stale_motion: Dictionary = target.make_snapshot()
	host.damage_player(peer_id, 1000.0)
	_check(await _wait_for(func() -> bool:
		for index: int in 4:
			if _sessions[index].players[peer_id].is_alive():
				return false
		return true), "Fatal damage and death reach all four peers")
	_check(host._item_owner == 0 and guest.shared_item.carrier == null, "Death releases carried item")
	for index: int in 4:
		_check(not _sessions[index].players[peer_id].energy_shield_mesh.visible, "Dead player's shield is hidden on every peer")
	_check(guest._respawn_button.visible and not target.get_node("PlayerHUD").defeat_menu.visible, "Death offers multiplayer respawn instead of scene reload")
	guest.request_respawn()
	guest.request_respawn()
	_check(await _wait_for(func() -> bool: return guest.players[peer_id].is_alive() and guest.players[peer_id].life_generation == 1), "Guest respawns through host")
	_check(await _wait_for(func() -> bool: return _sessions[2].players[peer_id].life_generation == 1), "Respawn replaces remote replicas")
	_check(host.team_money == money and host.purchases[peer_id] == owned, "Respawn preserves shared money and personal purchases")
	var replacement: CharacterBody3D = _sessions[2].players[peer_id]
	var pose: Transform3D = replacement.global_transform
	replacement.receive_snapshot(stale_motion)
	_check(replacement.global_transform == pose, "Previous life's delayed movement is ignored")
	for index: int in 4:
		var session: Node3D = _sessions[index]
		session.players[session.multiplayer.get_unique_id()].set_physics_process(false)
	host.damage_player(1, 1000.0)
	_check(await _wait_for(func() -> bool: return not guest.players[1].is_alive()), "Host death replicates without closing the session")
	host.request_respawn()
	_check(await _wait_for(func() -> bool: return guest.players[1].is_alive() and guest.players[1].life_generation == 1), "Host respawn replicates")
	host.players[1].set_physics_process(false)


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


func _test_team_economy() -> void:
	var host: Node3D = _sessions[0]
	var guest: Node3D = _sessions[1]
	var guest_id: int = guest.multiplayer.get_unique_id()
	var solo_money: int = int(root.get_node("GlobalScore").get("money"))
	var solo_shield: bool = bool(root.get_node("GlobalScore").get("energy_shield_owned"))
	_check(host.team_money == 0, "New team starts with an empty shared pool")
	await _deliver_scrap(guest)
	_check(await _wait_for(func() -> bool:
		for index: int in 4:
			if _sessions[index].team_money != 60 or _sessions[index].team_score != 10 or _sessions[index].deliveries != 1:
				return false
		return true), "Delivery credits the same money and score on all four peers")
	guest.buy_item(&"movement")
	host.buy_item(&"movement")
	_check(await _wait_for(func() -> bool: return host.team_money == 0), "Concurrent purchases spend from one pool")
	await create_timer(0.2).timeout
	var levels: int = 0
	for owned: Dictionary in host.purchases.values():
		levels += int(owned.get(&"movement", 0))
	_check(levels == 1 and host.team_money == 0, "Only one $60 purchase succeeds with $60 available")
	_check(await _wait_for(func() -> bool: return guest.purchases == host.purchases and guest.team_money == 0), "Purchase results and remaining balance replicate")
	for peer_id: int in host.players:
		var player: CharacterBody3D = host.players[peer_id]
		var expected: float = player._base_upgrade_stats[&"speed"] * (1.0 + 0.1 * int(host.purchases.get(peer_id, {}).get(&"movement", 0)))
		_check(is_equal_approx(player.speed, expected), "Paid upgrade applies to its buyer")
	guest.buy_item(&"unknown_item")
	await create_timer(0.15).timeout
	_check(host.team_money == 0 and levels == 1, "Invalid product cannot change the balance")
	for index: int in 3:
		await _deliver_scrap(guest)
	_check(await _wait_for(func() -> bool: return guest.team_money == 180), "Further deliveries replenish the same team pool")
	guest.buy_item(&"energy_shield")
	guest.buy_item(&"energy_shield")
	_check(await _wait_for(func() -> bool: return host.team_money == 0 and host.purchases.get(guest_id, {}).has(&"energy_shield")), "Guest buys equipment using team funds")
	await create_timer(0.15).timeout
	_check(int(host.purchases[guest_id].get(&"energy_shield", 0)) == 1, "Duplicate equipment purchase is refused")
	_check(await _wait_for(func() -> bool: return guest.players[guest_id].can_use_energy_shield()), "Purchased shield is usable by the buyer")
	_check(not host.players[1].can_use_energy_shield(), "Personal equipment does not grant itself to other players")
	_check(int(root.get_node("GlobalScore").get("money")) == solo_money and bool(root.get_node("GlobalScore").get("energy_shield_owned")) == solo_shield, "Multiplayer economy does not alter single-player money or equipment")


func _deliver_scrap(session: Node3D) -> void:
	var host: Node3D = _sessions[0]
	await _claim_item(session)
	var peer_id: int = session.multiplayer.get_unique_id()
	var player: CharacterBody3D = session.players[peer_id]
	var count: int = host.deliveries
	player.global_position = session.get_node("DeliveryZone").global_position + Vector3(0, -0.8, 0)
	_check(await _wait_for(func() -> bool: return host.players[peer_id].global_position.distance_to(player.global_position) < 0.05), "Carrier reaches delivery pad")
	await create_timer(0.15).timeout
	_check(host.deliveries == count, "Held scrap cannot be delivered")
	var event: InputEventAction = InputEventAction.new()
	event.action = &"drop_item"
	event.pressed = true
	player._input(event)
	_check(await _wait_for(func() -> bool: return host.deliveries == count + 1), "Dropping on the pad delivers the scrap")
	await create_timer(0.15).timeout
	_check(host.deliveries == count + 1 and host.shared_item.global_position.distance_to(host._item_spawn_pose.origin) < 0.6, "Delivery pays exactly once and respawns the scrap")


func _wait_for(predicate: Callable) -> bool:
	var deadline: int = Time.get_ticks_msec() + (30000 if _visual else 5000)
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
		print("PASS: four players, collectibles, host damage/shield/death/respawn, farm guard AI, economy, late join and disconnects")
	quit(1 if _failed else 0)
