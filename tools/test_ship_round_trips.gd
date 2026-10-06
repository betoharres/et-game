extends SceneTree

var _failed: bool = false
var _sessions: Array[Node3D] = []
var _views: Array[SubViewport] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	print("PASS: " + message if condition else "FAIL: " + message)
	_failed = _failed or not condition

func _wait(condition: Callable, seconds: float = 60.0) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await process_frame
	return condition.call()

func _interact(view: SubViewport) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = &"interact"
	event.pressed = true
	view.push_input(event)
	event = InputEventAction.new()
	event.action = &"interact"
	view.push_input(event)

func _run() -> void:
	for index: int in 2:
		var view: SubViewport = SubViewport.new()
		view.name = "TransportPeer%d" % index
		view.own_world_3d = true
		root.add_child(view)
		set_multiplayer(MultiplayerAPI.create_default_interface(), view.get_path())
		var session: Node3D = (load("res://scenes/Multiplayer/CampaignCoop.tscn") as PackedScene).instantiate() as Node3D
		view.add_child(session)
		session.host_migration.enabled = false
		_sessions.append(session)
		_views.append(view)
	var host: Node3D = _sessions[0]
	var guest: Node3D = _sessions[1]
	_check(host.host_game(17109) == OK and guest.join_game("127.0.0.1", 17109) == OK, "Host and joining ET connect")
	if not await _wait(func() -> bool: return guest.players.size() == 2):
		_check(false, "Roster complete")
		_finish()
		return
	host.set_ready()
	guest.set_ready()
	await _wait(func() -> bool: return host.ready_players.values().count(true) == 2)
	host.start_expedition()
	await _wait(func() -> bool: return guest.mission_phase == &"collecting")
	host.campaign.choose_destination(host.campaign.FARM)
	if not await _wait(func() -> bool: return guest.scene_file_path == guest.campaign.FARM and guest.mission_phase == &"collecting"):
		_check(false, "Farm arrival completes")
		_finish()
		return
	for npc: Node3D in host.npcs.values():
		npc.set_host_simulation(false)
	_check(host.get_shop_terminal().get_parent() == host.campaign._ship.get_node("PropsContainer") and host.get_revival_tank().get_parent() == host.campaign._ship.get_node("PropsContainer"), "Authored ship shop and revival tank are discovered")
	for index: int in 2:
		var session: Node3D = _sessions[index]
		var id: int = session.multiplayer.get_unique_id()
		var player: CharacterBody3D = session.players[id]
		var console: Node3D = session.campaign._ship.get_node("PropsContainer/TransportConsole") as Node3D
		var ground: Vector3 = console.ground_position
		var deck: Vector3 = (console.get_node(console.ship_spawn) as Node3D).global_position
		var cargo: StringName = &""
		player.set_physics_process(false)
		for item_id: StringName in host.items:
			var item: RigidBody3D = host.items[item_id]
			if not item.two_handed and item.slot_cost == 1 and host._item_owners[item_id] == 0 and not item.network_consumed and not item.rejected_by_delivery:
				for offset: Vector3 in [Vector3(0, 0.2, 0.6), Vector3(0.6, 0.2, 0), Vector3(0, 0.2, -0.6), Vector3(-0.6, 0.2, 0)]:
					player.global_position = item.get_pickup_target_position() + offset
					await _wait(func() -> bool: return host.players[id].global_position.distance_to(player.global_position) < 0.1)
					session.items[item_id].pickup(player)
					if await _wait(func() -> bool: return host._item_owners[item_id] == id and player.exploration_inventory.items.size() > 0, 2.0):
						cargo = item_id
						break
				if cargo != &"":
					break
		if cargo != &"":
			_check(true, "Peer picks up inventory cargo before transport")
		else:
			_check(false, "Inventory cargo is available")
			_finish()
			return
		player.global_position = ground
		player.velocity = Vector3.ZERO
		player.set_physics_process(true)
		await _wait(func() -> bool: return host.players[id].global_position.distance_to(ground) < 1.0)
		var round_id: int = session.mission_round
		var balance: int = session.team_money
		var cycles: int = 1 if OS.get_cmdline_user_args().has("--sell-only") else 10
		for cycle: int in cycles:
			await create_timer(0.6).timeout
			_interact(_views[index])
			var up: bool = await _wait(func() -> bool: return _both_near(id, deck), 3.0)
			_check(up, "Peer %d cycle %d boards through interact" % [index, cycle + 1])
			await create_timer(0.6).timeout
			_interact(_views[index])
			var down: bool = await _wait(func() -> bool: return _both_near(id, ground), 3.0)
			_check(down, "Peer %d cycle %d descends through interact" % [index, cycle + 1])
			_check(not player._movement_locked and player.velocity.length() < 2.0 and session.mission_round == round_id and session.team_money == balance and session.mission_phase == &"collecting", "No stuck movement, launch or economy change")
			_check(cargo != &"" and host._item_owners[cargo] == id and session._item_owners[cargo] == id and player.exploration_inventory.items.size() > 0, "Cargo stays owned and stored")
			if not up or not down:
				_finish()
				return
		player.global_position = ground + Vector3(8, 0, 0)
		await _wait(func() -> bool: return host.players[id].global_position.distance_to(player.global_position) < 1.0)
		console.request_transport()
		await create_timer(0.6).timeout
		_check(player.global_position.distance_to(ground) > 5.0, "Out-of-range request rejected")
		session.request_terminal_action(&"sell_inventory")
		await create_timer(0.3).timeout
		_check(host._item_owners[cargo] == id and session.team_money == balance, "Remote inventory sale rejected away from vending machine")
		player.global_position = ground
		await _wait(func() -> bool: return host.players[id].global_position.distance_to(ground) < 1.0)
		_interact(_views[index])
		_check(await _wait(func() -> bool: return _both_near(id, deck), 3.0), "ET beams aboard with sale cargo")
		var terminal: Node3D = session.get_shop_terminal()
		player.global_position = terminal.global_position + Vector3(0.8, 0.1, 0)
		await _wait(func() -> bool: return host.players[id].global_position.distance_to(player.global_position) < 0.1)
		_check(terminal.open(player), "ET opens vending machine aboard ship")
		for observer: Node3D in _sessions:
			observer.items[cargo].rejected_by_delivery = true
		session.request_terminal_action(&"sell_inventory")
		await create_timer(0.3).timeout
		_check(host._item_owners[cargo] == id and session.team_money == balance, "Protected inventory items are not sold")
		for observer: Node3D in _sessions:
			observer.items[cargo].rejected_by_delivery = false
		terminal._refresh()
		var value: int = host.items[cargo].cash_value
		var score: int = host.team_score
		var count: int = host.deliveries
		_check(not terminal._sell_button.disabled, "Sell inventory button is available")
		terminal._sell_button.pressed.emit()
		terminal._sell_button.pressed.emit()
		_check(await _wait(func() -> bool:
			for observer: Node3D in _sessions:
				if observer.team_money != balance + value or not observer.items[cargo].network_consumed or observer.players[id].exploration_inventory.items.size() != 0:
					return false
			return true, 5.0), "Sale credits team and removes scrap from inventory on both peers")
		_check(host.deliveries == count + 1 and host.team_score == score + host.items[cargo].score_value and host._round_sales_money > 0, "Sale counts toward score and mission results exactly once")
		_check(terminal._sell_button.disabled, "Empty inventory disables sale button")
		terminal.close()
		session.request_terminal_action(&"sell_inventory")
		await create_timer(0.3).timeout
		_check(session.team_money == balance + value, "Repeated sale cannot pay twice")
		player.global_position = ground + Vector3(8, 0, 0)
	print("RESULT: ", "FAIL" if _failed else "PASS — host and joining ET transport and inventory sales")
	_finish()

func _both_near(peer_id: int, point: Vector3) -> bool:
	for session: Node3D in _sessions:
		if session.players[peer_id].global_position.distance_to(point) > 1.1:
			return false
	return true

func _finish() -> void:
	for session: Node3D in _sessions:
		session.disconnect_game()
	for view: SubViewport in _views:
		view.queue_free()
	await process_frame
	quit(1 if _failed else 0)
