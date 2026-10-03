extends "res://tools/test_portal_multiplayer.gd"


func _run() -> void:
	_visual = OS.get_cmdline_user_args().has("--visual")
	_original_appearance = root.get_node("CharacterAppearance").get_profile()
	var scene: PackedScene = load("res://scenes/Multiplayer/FarmCoop.tscn") as PackedScene
	for index: int in 4:
		var viewport: SubViewport = SubViewport.new()
		if _visual and index == 1:
			viewport.size = Vector2i(960, 540)
		viewport.name = "MigrationPeer%d" % index
		viewport.own_world_3d = true
		root.add_child(viewport)
		set_multiplayer(MultiplayerAPI.create_default_interface(), viewport.get_path())
		var session: Node3D = scene.instantiate() as Node3D
		viewport.add_child(session)
		_sessions.append(session)
		_viewports.append(viewport)
		if _visual and index == 1:
			var screen: TextureRect = TextureRect.new()
			screen.texture = viewport.get_texture()
			screen.size = Vector2(960, 540)
			root.add_child(screen)
	await process_frame
	var host: Node3D = _sessions[0]
	_check(host.host_game(PORT + 20) == OK, "Migration host starts")
	for index: int in range(1, 4):
		_check(_sessions[index].join_game("127.0.0.1", PORT + 20) == OK, "Migration guest connects")
		_check(await _wait_for(func() -> bool: return _sessions[index].players.size() == index + 1), "Migration roster completes")
	for session: Node3D in _sessions:
		session.set_ready()
	_check(await _wait_for(func() -> bool: return host.ready_players.values().count(true) == 4), "Migration lobby ready")
	host.start_expedition()
	await create_timer(0.2).timeout
	for session: Node3D in _sessions:
		session.players[session.multiplayer.get_unique_id()].set_physics_process(false)
	for npc: CharacterBody3D in host.npcs.values():
		npc.set_host_simulation(false)
	var successor: Node3D = _sessions[1]
	var driver: Node3D = _sessions[2]
	var dead: Node3D = _sessions[3]
	var successor_id: int = successor.multiplayer.get_unique_id()
	var driver_id: int = driver.multiplayer.get_unique_id()
	var dead_id: int = dead.multiplayer.get_unique_id()
	host.team_money = 1200
	host.ship_repaired = true
	host.team_score = 50
	host.deliveries = 3
	host._round_sales_money = 180
	host.team_radon = 1900
	host.purchases[successor_id] = {&"predator_watch": 1, &"movement": 1}
	host._publish_economy()
	host._publish_mission()
	host.damage_player(successor_id, 25.0)
	await _claim_item(successor)
	var truck: Node3D = host.get_node("VehiclesContainer/Truck")
	driver.players[driver_id].global_position = truck.global_position + Vector3(2, 0, 0)
	await _wait_for(func() -> bool: return host.players[driver_id].global_position.distance_to(driver.players[driver_id].global_position) < 0.1)
	driver.get_node("VehiclesContainer/Truck/CoopSeats").request_seat()
	_check(await _wait_for(func() -> bool: return truck.get_node("CoopSeats").occupants[0] == driver_id), "Guest drives before migration")
	host.damage_player(dead_id, 1000.0)
	var quest: Node = host.get_node("NPCsContainer/Gorilla/BananaTrade")
	quest._receive_state(true, true, quest.rewards[0].resource_path)
	quest._receive_state.rpc(true, true, quest.rewards[0].resource_path)
	var door: Node = host.get_node("BuildingContainers/BarnDoor")
	door.leaf.rotation.y = 0.9
	door._target = 0.9
	host.host_migration.publish_checkpoint()
	_check(await _wait_for(func() -> bool: return successor.host_migration.checkpoint.money == 1200), "Guests cache complete checkpoint")
	host.disconnect_game()
	_check(await _migration_finished(successor, 3), "Graceful exit migrates to next slot")
	if _failed:
		await _cleanup()
		return
	_check(successor.multiplayer.is_server() and successor.multiplayer.get_unique_id() == 1, "Successor becomes ENet authority")
	for session: Node3D in [successor, driver, dead]:
		_check(session.players.size() == 3 and session.team_money == 1200 and session.team_score == 50 and session.deliveries == 3, "Roster and economy survive migration")
		_check(session.ship_repaired and session.team_radon > 1850 and session.mission_phase == &"collecting", "Mission and reserve survive migration")
		_check(is_equal_approx(session.players[1].health, 75.0) and session.purchases[1].has(&"predator_watch"), "Successor retains health and purchases")
		_check(session._item_owner == 1 and session.shared_item.carrier == session.players[1], "Held item remaps to new host")
		_check(session.get_node("NPCsContainer/Gorilla/BananaTrade").completed and session.items.has(&"quest_reward"), "Shared quest and reward survive")
	var new_driver: int = driver.multiplayer.get_unique_id()
	var new_dead: int = dead.multiplayer.get_unique_id()
	_check(_viewports[1].get_camera_3d() == successor.players[1].camera_pivot.get_camera(), "Migrated host owns its camera")
	_check(successor.players[1].get_node("PlayerHUD").visible and not driver.players[1].get_node("PlayerHUD").visible, "HUD ownership survives migration")
	_check(successor.get_node("VehiclesContainer/Truck/CoopSeats").occupants[0] == new_driver, "Vehicle seat remaps to new guest")
	_check(not successor.players[new_dead].is_alive() and successor.items.has(StringName("corpse_%d" % new_dead)), "Dead player and recoverable body survive")
	_check(await _wait_for(func() -> bool: return driver.get_node("BuildingContainers/BarnDoor").leaf.rotation.y > 0.3), "Door state survives")
	for session: Node3D in [successor, driver, dead]:
		session.players[session.multiplayer.get_unique_id()].set_physics_process(false)
	driver.get_node("VehiclesContainer/Truck/CoopSeats").request_seat()
	_check(await _wait_for(func() -> bool: return successor.get_node("VehiclesContainer/Truck/CoopSeats").occupants[0] == 0), "New host processes vehicle exit")
	driver.players[new_driver].global_position = Vector3(4, 1, 8)
	_check(await _wait_for(func() -> bool: return successor.players[new_driver].global_position.distance_to(driver.players[new_driver].global_position) < 0.05), "Movement works on migrated connection")
	for npc: CharacterBody3D in successor.npcs.values():
		npc.set_host_simulation(false)
	successor.host_migration.publish_checkpoint()
	_check(await _wait_for(func() -> bool: return driver.host_migration.checkpoint.roster.size() == 3), "New host distributes future migration checkpoint")
	# Closing the transport directly models host loss without the graceful handoff.
	successor.host_migration.enabled = false
	successor._close_peer()
	successor.disconnect_game()
	_check(await _migration_finished(driver, 2), "Abrupt host loss migrates again")
	_check(driver.multiplayer.is_server() and driver.team_money == 1200 and dead.players.size() == 2, "Second host continues the same expedition")
	await _test_lobby_handoff(driver, dead)
	await _test_unreachable_host(driver, dead)
	await _cleanup()


func _test_lobby_handoff(host: Node3D, guest: Node3D) -> void:
	for npc: CharacterBody3D in host.npcs.values():
		npc.set_host_simulation(false)
	for peer_id: int in host.players.keys():
		host.damage_player(peer_id, 1000.0)
	_check(await _wait_for(func() -> bool: return host.mission_phase == &"lobby" and guest.mission_phase == &"lobby"), "Team reset reaches lobby before handoff")
	host.host_migration.publish_checkpoint()
	_check(await _wait_for(func() -> bool: return guest.host_migration.checkpoint.mission.phase == &"lobby"), "Lobby state cached")
	host.disconnect_game()
	_check(await _migration_finished(guest, 1), "Lobby host can migrate to last guest")
	_check(guest.multiplayer.is_server() and guest.team_money == 0 and guest.mission_phase == &"lobby" and not guest.ready_players[1], "Lobby remains reset and not ready")
	guest.set_ready()
	guest.start_expedition()
	_check(guest.mission_phase == &"collecting", "Last survivor can start a new expedition as host")


func _test_unreachable_host(spare: Node3D, host: Node3D) -> void:
	spare.host_migration.enabled = true
	spare.disconnect_game()
	var port: int = int(host._port.value)
	_check(spare.join_game("127.0.0.1", port) == OK, "Guest joins migrated host")
	_check(await _wait_for(func() -> bool: return spare.players.size() == 2), "Migrated host accepts normal join")
	for npc: CharacterBody3D in host.npcs.values():
		npc.set_host_simulation(false)
	spare.players[spare.multiplayer.get_unique_id()].set_physics_process(false)
	host.ship_repaired = true
	host.mission_phase = &"departing"
	host._departure_remaining = 3.0
	host.last_round_money = 180
	host.last_round_deliveries = 3
	host._publish_mission()
	host.host_migration.publish_checkpoint()
	_check(await _wait_for(func() -> bool: return spare.host_migration.checkpoint.mission.phase == &"departing"), "Departure checkpoint cached")
	host.disconnect_game()
	_check(await _migration_finished(spare, 1), "Host migrates during departure")
	_check(await _wait_for(func() -> bool: return spare.mission_round == 2 and spare.scene_file_path.ends_with("PortalCoop.tscn")), "Migrated departure completes exactly once")
	_check(spare.last_round_money == 180 and spare.last_round_deliveries == 3, "Departure results survive migration")
	host.host_migration.enabled = false
	host._commit_round(spare.scene_file_path, 2)
	_check(host.join_game("127.0.0.1", int(spare._port.value)) == OK, "Guest joins after migrated map transition")
	_check(await _wait_for(func() -> bool: return host.players.size() == 2), "Post-transition roster completes")
	var old_host: Node3D = host
	host = spare
	spare = old_host
	spare.host_migration.enabled = true
	var peer_id: int = spare.multiplayer.get_unique_id()
	var endpoint: Dictionary = host.host_migration.endpoints[peer_id]
	var occupied: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	_check(occupied.create_server(int(endpoint.port), 1) == OK, "Test reserves successor UDP port")
	host.host_migration.publish_checkpoint()
	_check(await _wait_for(func() -> bool: return spare.host_migration.checkpoint.roster.size() == 2), "Failure scenario checkpoint cached")
	host.disconnect_game()
	_check(await _wait_for(func() -> bool: return spare.players.is_empty() and not spare.host_migration.active), "Unavailable successor port returns to connection UI")
	_check(spare._status.text.contains("migrate host") and not spare._host_button.disabled, "Migration failure explains bind error and permits hosting again")
	occupied.close()


func _migration_finished(session: Node3D, count: int) -> bool:
	var deadline: int = Time.get_ticks_msec() + 18000
	while Time.get_ticks_msec() < deadline:
		if not session.host_migration.active and session.players.size() == count and session.multiplayer.multiplayer_peer is ENetMultiplayerPeer:
			return true
		await process_frame
	return false


func _cleanup() -> void:
	for session: Node3D in _sessions:
		session.host_migration.enabled = false
		session.disconnect_game()
	root.get_node("CharacterAppearance").set_profile(_original_appearance, false)
	for viewport: SubViewport in _viewports:
		viewport.queue_free()
	await process_frame
	if not _failed:
		print("PASS: graceful/abrupt/lobby host migration, ID remapping, gameplay state, cameras, continued play, normal join and unavailable-port recovery")
	quit(1 if _failed else 0)
