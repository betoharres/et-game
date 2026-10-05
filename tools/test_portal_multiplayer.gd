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
		session.set_script(load("res://tools/network_fault_session.gd"))
		viewport.add_child(session)
		session.host_migration.enabled = false
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
		_sessions[index].set_ready()
	_check(await _wait_for(func() -> bool: return _sessions[0].ready_players.values().count(true) == 4), "All four players ready")
	_sessions[0].start_expedition()
	_check(await _wait_for(func() -> bool: return _sessions[1].mission_phase == &"collecting"), "Host starts ready lobby")
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
	_sessions[0].simulate_faults = true
	moving_player.global_position += Vector3(1, 0, 0)
	_check(await _wait_for(func() -> bool: return _sessions[2].players[moving_id].global_position.distance_to(moving_player.global_position) < 0.05), "Movement converges with 33% snapshot loss and 40?120 ms reordered delay")
	_sessions[0].simulate_faults = false
	await create_timer(0.15).timeout
	var stale: Dictionary = moving_player.make_snapshot()
	var invalid: Dictionary = stale.duplicate()
	invalid["velocity"] = Vector3(1000, 0, 0)
	_check(not _sessions[0]._valid_snapshot(invalid), "Excessive movement velocity is rejected")
	invalid = stale.duplicate()
	invalid["transform"] = Transform3D(Basis.IDENTITY.scaled(Vector3(2, 2, 2)), Vector3.ZERO)
	_check(not _sessions[0]._valid_snapshot(invalid), "Scaled player transforms are rejected")
	_check(_sessions[4].join_game("127.0.0.1", PORT) == OK, "Fifth peer attempts connection")
	await create_timer(0.8).timeout
	_check(_sessions[4].players.is_empty() and _sessions[0].players.size() == 4, "Fifth player is refused")
	_sessions[4].disconnect_game()
	await _claim_item(_sessions[3])
	var departing_id: int = _sessions[3].multiplayer.get_unique_id()
	_check(_sessions[0]._item_owner == departing_id, "Departing guest carries the item")
	_sessions[0].damage_player(departing_id, _sessions[0].players[departing_id].energy_shield + 25.0)
	var returning_health: float = _sessions[0].players[departing_id].health
	var returning_purchases: Dictionary = _sessions[0].purchases.get(departing_id, {}).duplicate(true)
	_sessions[3].disconnect_game()
	_check(await _wait_for(func() -> bool: return _sessions[0].players.size() == 3 and _sessions[1].players.size() == 3), "Disconnect removes player from peers")
	_check(await _wait_for(func() -> bool: return _sessions[0]._item_owner == 0 and not _sessions[1].shared_item.carried), "Disconnect drops the item instead of deleting it")
	_check(_sessions[3].join_game("127.0.0.1", PORT) == OK, "Disconnected player reconnects")
	_check(await _wait_for(func() -> bool: return _sessions[3].players.size() == 4), "Reconnect roster completes")
	var returning_id: int = _sessions[3].multiplayer.get_unique_id()
	_check(await _wait_for(func() -> bool: return is_equal_approx(_sessions[3].players[returning_id].health, returning_health) and _sessions[0].purchases.get(returning_id, {}) == returning_purchases), "Reconnect retains health and purchases without free healing")
	_sessions[3].disconnect_game()
	_check(await _wait_for(func() -> bool: return _sessions[0].players.size() == 3), "Reconnect releases its slot again")
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
		_check(_sessions[index].items.keys() == host.items.keys() and host.items.size() == 16, "All peers register test and SP scrap IDs")
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
		farm.host_migration.enabled = false
		_sessions[index] = farm
	await process_frame
	var host: Node3D = _sessions[0]
	var guest: Node3D = _sessions[1]
	_check(host.host_game(PORT + 1) == OK, "Farm host starts")
	_check(guest.join_game("127.0.0.1", PORT + 1) == OK, "Farm guest connects")
	_check(await _wait_for(func() -> bool: return guest.players.size() == 2), "Farm roster completes")
	host.set_ready()
	guest.set_ready()
	_check(await _wait_for(func() -> bool: return host.ready_players.values().count(true) == 2), "Farm lobby ready")
	host.start_expedition()
	_check(await _wait_for(func() -> bool: return guest.mission_phase == &"collecting"), "Farm expedition starts")
	_check(host.items.size() == 17 and host.get_node("BuildingContainers/Barn") != null, "Farm has SP and test scraps and its barn")
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
		farm.host_migration.enabled = false
		_sessions[index] = farm
		_check(farm.join_game("127.0.0.1", PORT + 1) == OK, "Late farm guest connects")
		_check(await _wait_for(func() -> bool: return farm.players.size() == index + 1 and not farm.players[peer_id].is_alive()), "Late farm join receives the dead guest")
		_check(await _wait_for(func() -> bool: return farm.npcs[&"Guard"]._has_network_state), "Late farm join receives current NPC state")
	_check(host.players.size() == 4, "Farm supports four players with one authoritative guard")
	await _test_farm_features()
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
	await _test_mission_loop()


func _test_farm_features() -> void:
	var host: Node3D = _sessions[0]
	var guest: Node3D = _sessions[1]
	var guest_id: int = guest.multiplayer.get_unique_id()
	for npc: CharacterBody3D in host.npcs.values():
		npc.set_host_simulation(false)
		_check(not _sessions[1].npcs[npc.name]._host_simulation, "Farm guests do not simulate NPCs")
	host.team_money = 199
	host._publish_economy()
	var corpse_id: StringName = StringName("corpse_%d" % guest_id)
	var tank: Node3D = host.get_node("PropsContainer/RevivalTank")
	host._publish_item_state(0, Transform3D(Basis.IDENTITY, tank.global_position + Vector3(0, 0.4, 0)), Vector3.ZERO, corpse_id)
	await create_timer(0.25).timeout
	_check(not host.players[guest_id].is_alive() and host.team_money == 199, "Insufficient team funds keep deposited teammate dead")
	host.team_money = 200
	host._publish_economy()
	_check(await _wait_for(func() -> bool: return guest.players[guest_id].is_alive(), 25.0), "Earning the remaining dollar allows revival after regeneration")
	_check(host.team_money == 0, "Recovery debits $200 exactly once")
	for index: int in 4:
		_sessions[index].players[_sessions[index].multiplayer.get_unique_id()].set_physics_process(false)
	var truck: Node3D = host.get_node("VehiclesContainer/Truck")
	var seats: Node = truck.get_node("CoopSeats")
	for index: int in 4:
		var session: Node3D = _sessions[index]
		var id: int = session.multiplayer.get_unique_id()
		session.players[id].global_position = truck.global_position + Vector3(2, 0, 0)
		_check(await _wait_for(func() -> bool: return host.players[id].global_position.distance_to(session.players[id].global_position) < 0.1), "Player reaches truck")
		session.get_node("VehiclesContainer/Truck/CoopSeats").request_seat()
		_check(await _wait_for(func() -> bool: return seats.occupants.has(id)), "Truck boards each player")
	_check(seats.occupants.count(0) == 0, "Truck supports all four seats")
	_check(await _wait_for(func() -> bool: return _sessions[3].get_node("VehiclesContainer/Truck/CoopSeats").occupants == seats.occupants), "Truck seats replicate")
	for index: int in 4:
		_sessions[index].get_node("VehiclesContainer/Truck/CoopSeats").request_seat()
	_check(await _wait_for(func() -> bool: return seats.occupants.count(0) == 4), "All players can leave truck")
	var plane: Node3D = host.get_node("VehiclesContainer/Plane")
	guest.players[guest_id].global_position = plane.global_position + Vector3(2, 0, 0)
	await _wait_for(func() -> bool: return host.players[guest_id].global_position.distance_to(guest.players[guest_id].global_position) < 0.1)
	guest.get_node("VehiclesContainer/Plane/CoopSeats").request_seat()
	_check(await _wait_for(func() -> bool: return plane.get_node("CoopSeats").occupants[0] == guest_id), "Guest pilots plane")
	host.players[1].global_position = plane.global_position + Vector3(2, 0, 0)
	plane.get_node("CoopSeats").request_seat()
	_check(plane.get_node("CoopSeats").occupants.size() == 1 and plane.get_node("CoopSeats").occupants[0] == guest_id, "Occupied plane refuses another player")
	var plane_pose: Vector3 = plane.global_position
	_check(await _wait_for(func() -> bool: return plane.global_position.distance_to(plane_pose) > 0.3), "Host simulates guest-controlled plane")
	guest.get_node("VehiclesContainer/Plane/CoopSeats").request_seat()
	await _wait_for(func() -> bool: return plane.get_node("CoopSeats").occupants[0] == 0)
	var trade: Node3D = host.get_node("NPCsContainer/Gorilla/BananaTrade")
	host.players[1].global_position = trade.global_position + Vector3(0, 0, 1)
	trade.interact(host.players[1])
	_check(await _wait_for(func() -> bool: return guest.get_node("NPCsContainer/Gorilla/BananaTrade").accepted), "Host starts team banana quest")
	var banana: RigidBody3D = host.items[&"banana_box"]
	guest.players[guest_id].global_position = banana.global_position + Vector3(0, 0, 1.2)
	await _wait_for(func() -> bool: return host.players[guest_id].global_position.distance_to(guest.players[guest_id].global_position) < 0.1)
	guest.items[&"banana_box"].pickup(guest.players[guest_id])
	_check(await _wait_for(func() -> bool: return host._item_owners[&"banana_box"] == guest_id), "Different teammate collects banana box")
	guest.players[guest_id].global_position = trade.global_position + Vector3(0, 0, 1)
	await _wait_for(func() -> bool: return host.players[guest_id].global_position.distance_to(guest.players[guest_id].global_position) < 0.1)
	guest.get_node("NPCsContainer/Gorilla/BananaTrade").interact(guest.players[guest_id])
	_check(await _wait_for(func() -> bool: return trade.completed and _sessions[3].items.has(&"quest_reward")), "Different teammate completes shared quest and replicates reward")
	_check(host.items[&"banana_box"].network_consumed, "Delivered banana cannot be collected again")
	var door: Node3D = host.get_node("BuildingContainers/BarnDoor")
	guest.players[guest_id].global_position = door.get_node("Trigger").global_position - Vector3.UP + Vector3(0, 0, 0.6)
	await _wait_for(func() -> bool: return host.players[guest_id].global_position.distance_to(guest.players[guest_id].global_position) < 0.1)
	await physics_frame
	guest.get_node("BuildingContainers/BarnDoor").interact(guest.players[guest_id])
	_check(await _wait_for(func() -> bool: return door.is_open() and _sessions[2].get_node("BuildingContainers/BarnDoor").is_open()), "Guest opens host-owned barn door")
	host.team_money = 1000
	host._publish_economy()
	guest.buy_item(&"predator_watch")
	_check(await _wait_for(func() -> bool: return host.purchases.get(guest_id, {}).has(&"predator_watch")), "Guest buys watch from team funds")
	guest.players[guest_id].toggle_predator_cloak()
	_check(await _wait_for(func() -> bool: return host.players[guest_id].predator_cloak_active and _sessions[3].players[guest_id].predator_cloak_active), "Watch activation reaches host and observers")
	var charge: float = host.players[guest_id].predator_cloak_energy
	await create_timer(0.2).timeout
	_check(host.players[guest_id].predator_cloak_energy < charge, "Host drains invisibility energy")
	guest.players[guest_id].toggle_predator_cloak()
	_check(await _wait_for(func() -> bool: return not host.players[guest_id].predator_cloak_active), "Watch deactivates across peers")
	var farmer: NPCActor = host.npcs[&"Farmer"]
	var third: Node3D = _sessions[2]
	var third_id: int = third.multiplayer.get_unique_id()
	third.players[third_id].global_position = farmer.global_position + Vector3(0, 0, 2)
	await _wait_for(func() -> bool: return host.players[third_id].global_position.distance_to(third.players[third_id].global_position) < 0.05)
	farmer.set_host_simulation(true)
	_check(await _wait_for(func() -> bool: return farmer.target_peer_id == third_id and third.players[third_id].health < third.players[third_id].max_health), "Farmer selects and shoots player three")
	farmer.set_host_simulation(false)
	var photographer: NPCActor = host.npcs[&"Photographer2"]
	var fourth: Node3D = _sessions[3]
	var fourth_id: int = fourth.multiplayer.get_unique_id()
	fourth.players[fourth_id].global_position = photographer.global_position + Vector3(0, 0, 2)
	await _wait_for(func() -> bool: return host.players[fourth_id].global_position.distance_to(fourth.players[fourth_id].global_position) < 0.05)
	photographer.set_host_simulation(true)
	_check(await _wait_for(func() -> bool: return photographer.photo_count > 0 and _sessions[2].npcs[&"Photographer2"].photo_count > 0), "Photographer photographs player four and shares the event")
	photographer.set_host_simulation(false)
	var light: CharacterBody3D = host.npcs[&"LivingLight"]
	third.players[third_id].global_position = light.global_position + Vector3(2, 0, 0)
	await _wait_for(func() -> bool: return host.players[third_id].global_position.distance_to(third.players[third_id].global_position) < 0.05)
	light.set_host_simulation(true)
	_check(await _wait_for(func() -> bool: return light._player == host.players[third_id] and guest.npcs[&"LivingLight"]._has_network_state), "Living light reacts to the closest living teammate and replicates")
	light.set_host_simulation(false)
	host.team_money = 0
	host._publish_economy()


func _test_mission_loop() -> void:
	var host: Node3D = _sessions[0]
	var guest: Node3D = _sessions[2]
	var guest_id: int = guest.multiplayer.get_unique_id()
	var solo_money: int = int(root.get_node("GlobalScore").get("money"))
	var solo_progress: int = int(load("res://scripts/levels/game_progress.gd").highest_repaired_level)
	var terminal: Node3D = host.get_node("PropsContainer/ShopTerminal")
	var buyer: CharacterBody3D = guest.players[guest_id]
	for index: int in [0, 2, 3]:
		var session: Node3D = _sessions[index]
		session.players[session.multiplayer.get_unique_id()].set_physics_process(false)
	var native_scrap: RigidBody3D = host.items[&"farm_00"]
	_check(native_scrap.cash_value == 15 and native_scrap.display_name == "Balde de metal" and not native_scrap.two_handed, "SP bucket preserves its value, name and hand mode")
	buyer.global_position = native_scrap.global_position + Vector3(0, 0, 1)
	_check(await _wait_for(func() -> bool: return host.players[guest_id].global_position.distance_to(buyer.global_position) < 0.05), "Guest reaches SP scrap")
	guest.items[&"farm_00"].pickup(buyer)
	_check(await _wait_for(func() -> bool: return host._item_owners[&"farm_00"] == guest_id), "Guest picks up SP scrap through shared ownership")
	var before: int = host.team_money
	var sale_pose: Transform3D = Transform3D(Basis.IDENTITY, host.get_node("DeliveryZone").global_position + Vector3(0, -0.8, 0))
	host._publish_item_state(0, sale_pose, Vector3.ZERO, &"farm_00")
	_check(await _wait_for(func() -> bool: return guest.team_money == before + 15), "SP scrap sells for its authored price into team funds")
	buyer.global_position = terminal.global_position + Vector3(1.3, 0, 1.3)
	_check(await _wait_for(func() -> bool: return host.players[guest_id].global_position.distance_to(buyer.global_position) < 0.05), "Buyer reaches machine")
	var guest_terminal: Node3D = guest.get_node("PropsContainer/ShopTerminal")
	_check(guest_terminal.open(buyer) and not paused, "SP machine interface opens without pausing co-op")
	guest_terminal._repair_ship()
	await create_timer(0.15).timeout
	_check(not host.ship_repaired, "Repair requires sufficient shared funds")
	host.debug_add_team_money()
	var funded: int = host.team_money
	_sessions[3].request_terminal_action(&"repair")
	await create_timer(0.15).timeout
	_check(not host.ship_repaired and host.team_money == funded, "Host rejects out-of-range machine requests")
	host.players[1].global_position = terminal.global_position + Vector3(-1.3, 0, 1.3)
	host.request_terminal_action(&"repair")
	guest_terminal._repair_ship()
	_check(await _wait_for(func() -> bool: return guest.ship_repaired and host.team_money == funded - 1000), "Concurrent repairs debit shared funds only once")
	guest_terminal._buy_upgrade(0)
	_check(await _wait_for(func() -> bool: return int(host.purchases.get(guest_id, {}).get(&"movement", 0)) == 1), "Machine upgrade belongs to its buyer")
	guest_terminal._buy_radon()
	_check(await _wait_for(func() -> bool: return host.team_radon > 1750.0 and absf(host.team_radon - guest.team_radon) < 2.0), "Machine Radon reserve is shared")
	guest_terminal._go_to_next_level()
	await create_timer(0.2).timeout
	_check(host.mission_phase == &"collecting", "Departure waits for the whole team")
	var third: Node3D = _sessions[3]
	var third_player: CharacterBody3D = third.players[third.multiplayer.get_unique_id()]
	third_player.global_position = terminal.global_position + Vector3(0, 0, 2.5)
	_check(await _wait_for(func() -> bool: return host.players[third.multiplayer.get_unique_id()].global_position.distance_to(third_player.global_position) < 0.05), "Team gathers for departure")
	var money: int = host.team_money
	var owned: Dictionary = host.purchases.duplicate(true)
	guest_terminal._go_to_next_level()
	_check(await _wait_for(func() -> bool: return guest.mission_phase == &"departing"), "Guest starts shared departure after repair")
	_check(guest._results_panel.visible and not guest._shop_panel.visible, "Departure results are visible above session UI")
	_check(await _wait_for(func() -> bool: return host.mission_round == 2 and guest.mission_round == 2 and third.mission_round == 2), "All peers advance to the next co-op map")
	_check(host.scene_file_path.ends_with("PortalCoop.tscn") and guest.scene_file_path == host.scene_file_path, "Actual map content changes together")
	_check(host.players.size() == 3 and guest.players.size() == 3 and host.team_money == money and host.purchases == owned, "Map transition keeps connections, funds and equipment")
	_check(not host.ship_repaired and host.team_radon > 1750.0 and host.last_round_deliveries == 2, "Next round resets repair and retains reserve and prior results")
	for peer_id: int in host.players.keys():
		host.damage_player(peer_id, 1000.0)
	_check(await _wait_for(func() -> bool: return host.mission_phase == &"lobby" and guest.mission_phase == &"lobby" and third.mission_phase == &"lobby"), "Team wipe returns everyone to connected lobby")
	_check(host.team_money == 0 and host.purchases.is_empty() and host.mission_round == 1, "Team wipe resets the run")
	_check(int(root.get_node("GlobalScore").get("money")) == solo_money and int(load("res://scripts/levels/game_progress.gd").highest_repaired_level) == solo_progress, "Mission loop does not mutate SP money or unlocks")


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
		var replica: CharacterBody3D = _sessions[index].players[peer_id]
		_check(replica.get_node("DeathEffect").visible == replica.is_local_player(), "Death grayscale appears only on the victim's peer")
		if not replica.is_local_player():
			_check(not replica.get_node("DeathEffect/DeathAudio").playing, "Remote death does not play death music")
	_check(not guest._respawn_button.visible and not target.get_node("PlayerHUD").defeat_menu.visible, "Death requires team recovery")
	guest.request_respawn()
	await create_timer(0.1).timeout
	_check(not guest.players[peer_id].is_alive(), "Instant respawn is refused")
	await _recover_body(host, peer_id)
	_check(await _wait_for(func() -> bool: return _sessions[2].players[peer_id].life_generation == 1), "Revival replaces remote replicas")
	_check(host.team_money == money - 200 and host.purchases[peer_id] == owned, "Revival costs team $200 and preserves purchases")
	var replacement: CharacterBody3D = _sessions[2].players[peer_id]
	var pose: Transform3D = replacement.global_transform
	replacement.receive_snapshot(stale_motion)
	_check(replacement.global_transform == pose, "Previous life's delayed movement is ignored")
	for index: int in 4:
		var session: Node3D = _sessions[index]
		session.players[session.multiplayer.get_unique_id()].set_physics_process(false)
	host.damage_player(1, 1000.0)
	_check(await _wait_for(func() -> bool: return not guest.players[1].is_alive()), "Host death replicates without closing the session")
	await _recover_body(host, 1)
	_check(await _wait_for(func() -> bool: return guest.players[1].is_alive() and guest.players[1].life_generation == 1), "Host respawn replicates")
	host.players[1].set_physics_process(false)


func _recover_body(host: Node3D, peer_id: int) -> void:
	var id: StringName = StringName("corpse_%d" % peer_id)
	_check(await _wait_for(func() -> bool: return host.items.has(id) or host.recovery.revivals.has(peer_id)), "Recoverable body or active tank revival exists")
	if host.recovery.revivals.has(peer_id):
		_check(await _wait_for(func() -> bool: return host.players[peer_id].is_alive(), 25.0), "Body already at tank completes regeneration")
		return
	if not host.items.has(id):
		return
	var carrier_session: Node3D = _sessions[0] if peer_id != 1 else _sessions[1]
	var carrier_id: int = carrier_session.multiplayer.get_unique_id()
	var carrier: CharacterBody3D = carrier_session.players[carrier_id]
	carrier.set_physics_process(false)
	carrier.global_position = host.items[id].global_position + Vector3(1.2, 0, 0)
	_check(await _wait_for(func() -> bool: return host.players[carrier_id].global_position.distance_to(carrier.global_position) < 0.05), "Rescuer reaches corpse")
	carrier_session.items[id].pickup(carrier)
	_check(await _wait_for(func() -> bool: return host._item_owners[id] == carrier_id), "Teammate picks up shared corpse")
	carrier.global_position = host.get_node("PropsContainer/RevivalTank").global_position - carrier.global_basis.z * 1.2
	_check(await _wait_for(func() -> bool: return host.players[carrier_id].global_position.distance_to(carrier.global_position) < 0.05), "Rescuer carries body to ship")
	carrier_session.items[id].drop()
	_check(await _wait_for(func() -> bool: return host.recovery.revivals.has(peer_id)), "Deposited body starts timed regeneration")
	_check(not host.players[peer_id].is_alive(), "Regenerating teammate remains dead")
	_check(await _wait_for(func() -> bool: return _sessions[1].recovery.revivals.has(peer_id)), "Regeneration state reaches guests")
	var slot: int = int(host.recovery.revivals[peer_id].slot) if host.recovery.revivals.has(peer_id) else 0
	var tank_visual: Node3D = host.get_node("PropsContainer/RevivalTank/Tank%d/ET%d" % [slot + 3, slot + 1])
	_check(tank_visual.visible and tank_visual.scale.length() < 0.5, "Tank ET starts visible and small")
	await create_timer(0.5).timeout
	_check(not host.players[peer_id].is_alive(), "Revival does not complete immediately")
	_check(await _wait_for(func() -> bool: return host.players[peer_id].is_alive(), 25.0), "Deposited body revives after 20 seconds")
	_check(not tank_visual.visible and not host.recovery.revivals.has(peer_id), "Completed revival frees and hides tank")


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
	for offset: Vector3 in [Vector3(1.2, 0, 0), Vector3(-1.2, 0, 0), Vector3(0, 0, 1.2), Vector3(0, 0, -1.2)]:
		player.global_position = host.shared_item.global_position + offset
		if not await _wait_for(func() -> bool: return host.players[peer_id].global_position.distance_to(player.global_position) < 0.05):
			continue
		session.shared_item.pickup(player)
		if await _wait_for(func() -> bool: return host._item_owner == peer_id and session.shared_item.carrier == player):
			return
	_check(false, "Another player can collect the dropped scrap from a clear approach")


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


func _wait_for(predicate: Callable, timeout_seconds: float = 5.0) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(maxf(30.0 if _visual else 5.0, timeout_seconds) * 1000.0)
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
		print("PASS: four players, SP scraps/shop, repair races, shared departure/maps/results/recovery, combat, NPC AI, economy, late join and disconnects")
	quit(1 if _failed else 0)
