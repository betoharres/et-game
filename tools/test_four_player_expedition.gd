extends SceneTree

var sessions: Array[Node3D] = []
var views: Array[SubViewport] = []
var failed: bool = false

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> bool:
	print(("PASS: " if ok else "FAIL: ") + label)
	failed = failed or not ok
	return ok

func until(condition: Callable, seconds: float = 20.0) -> bool:
	var end: int = Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < end:
		if condition.call():
			return true
		await process_frame
	return condition.call()

func all_at(path: String) -> bool:
	for session: Node3D in sessions:
		if session.players.size() != 4 or session.scene_file_path != path or session.mission_phase != &"collecting":
			return false
	return true

func local(session: Node3D) -> CharacterBody3D:
	return session.players[session.multiplayer.get_unique_id()]

func position(session: Node3D, point: Vector3) -> bool:
	var player: CharacterBody3D = local(session)
	player.set_physics_process(false)
	player.global_position = point
	player.velocity = Vector3.ZERO
	return await until(func() -> bool: return sessions[0].players[player.get_multiplayer_authority()].global_position.distance_to(point) < 0.1)

func freeze_locals() -> void:
	for session: Node3D in sessions:
		local(session).set_physics_process(false)
		session._set_menu_open(false)

func pickup(session: Node3D, id: StringName) -> bool:
	for offset: Vector3 in [Vector3(0, 0.2, 0.6), Vector3(0.6, 0.2, 0), Vector3(0, 0.2, -0.6), Vector3(-0.6, 0.2, 0)]:
		if not await position(session, sessions[0].items[id].global_position + offset): continue
		session.items[id].pickup(local(session))
		if await until(func() -> bool: return sessions[0]._item_owners[id] == session.multiplayer.get_unique_id(), 3): return true
	return false

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/four-player-expedition/%s.png" % label)

func run() -> void:
	if DisplayServer.get_name() != "headless":
		root.scaling_3d_scale = 0.5
	change_scene_to_file("res://scenes/Menu/main_menu.tscn")
	await process_frame
	await process_frame
	current_scene.get_node("ColorRect/MenuBar/VSeparator/CoopButton").pressed.emit()
	if not check(await until(func() -> bool: return current_scene != null and current_scene.get_script() == load("res://scripts/multiplayer/portal_session.gd")), "Main menu opens co-op campaign"):
		quit(1)
		return
	var host: Node3D = current_scene
	sessions.append(host)
	host.host_migration.enabled = false
	host._port.value = 17104
	host._host_button.pressed.emit()
	var scene: PackedScene = load("res://scenes/Multiplayer/CampaignCoop.tscn")
	for index: int in range(1, 4):
		var view: SubViewport = SubViewport.new()
		view.name = "ExpeditionGuest%d" % index
		view.own_world_3d = true
		view.render_target_update_mode = SubViewport.UPDATE_DISABLED
		root.add_child(view)
		set_multiplayer(MultiplayerAPI.create_default_interface(), view.get_path())
		var guest: Node3D = scene.instantiate()
		view.add_child(guest)
		guest.host_migration.enabled = false
		guest._address.text = "127.0.0.1"
		guest._port.value = 17104
		guest._join_button.pressed.emit()
		sessions.append(guest)
		views.append(view)
	if not check(await until(func() -> bool:
		for session: Node3D in sessions:
			if session.players.size() != 4: return false
		return true), "Host and three joining players share complete roster"):
		await finish()
		return
	for session: Node3D in sessions:
		session._ready_button.pressed.emit()
	await until(func() -> bool: return host.ready_players.values().count(true) == 4)
	host._start_button.pressed.emit()
	check(await until(func() -> bool: return all_at(host.campaign.ORBIT)), "Four ready players start expedition through lobby buttons")
	freeze_locals()
	if OS.get_cmdline_user_args().has("--town-only"):
		print("INFO: Isolated arrival fixture; progression and economy are skipped")
		host.campaign.unlocked.append(host.campaign.COUNTRY)
		host._publish_mission()
		await until(func() -> bool: return sessions[2].campaign.unlocked.has(host.campaign.COUNTRY))
		await enter_country(host)
		await finish()
		return
	sessions[1].campaign.choose_destination(host.campaign.COUNTRY)
	await create_timer(0.3).timeout
	check(host.scene_file_path == host.campaign.ORBIT, "Locked next level refuses travel")
	sessions[1].campaign._open_console()
	sessions[1].campaign._ui._level_buttons[0].pressed.emit()
	sessions[1].campaign._ui.go_button.pressed.emit()
	if not check(await until(func() -> bool: return all_at(host.campaign.FARM), 90), "All four arrive at farm"):
		await finish()
		return
	freeze_locals()
	print("INFO: Farm registered %d items; terminal=%s tank=%s" % [host.items.size(), host.get_shop_terminal().global_position, host.get_revival_tank().global_position])
	await capture("farm-arrival")
	for npc: Node3D in host.npcs.values():
		if npc != host.campaign.delivery:
			npc.set_host_simulation(false)
	var ids: Array[StringName] = []
	for id: StringName in host.items:
		if host.items[id].cash_value > 0 and not host.items[id].network_consumed and not host.items[id].rejected_by_delivery:
			ids.append(id)
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return host.items[a].cash_value > host.items[b].cash_value)
	var total: int = 0
	for id: StringName in ids: total += host.items[id].cash_value
	print("INFO: Available scrap value=%d repair=%d" % [total, host.SHIP_SHOP.REPAIR_COST])
	await position(sessions[1], host.campaign.delivery.global_position + Vector3(10, 1, 0))
	sessions[1].items[ids[0]].pickup(local(sessions[1]))
	await create_timer(0.3).timeout
	check(host._item_owners[ids[0]] == 0, "Remote out-of-range pickup is rejected")
	var collected: int = 0
	var pending: Array[StringName] = []
	var pending_value: int = 0
	for id: StringName in ids:
		var session: Node3D = sessions[collected % 4]
		var item: RigidBody3D = host.items[id]
		if not await pickup(session, id):
			print("SKIP: Four automatic approaches could not pick up %s at %s" % [id, item.global_position])
			continue
		check(true, "Player %d picks up %s ($%d)" % [collected % 4 + 1, id, item.cash_value])
		var zone: Node3D = host.get_node("DeliveryZone")
		var corner: Vector3 = Vector3(-0.8 if collected % 2 == 0 else 0.8, 0.3, -0.8 if collected % 4 < 2 else 0.8)
		await position(session, zone.global_position + corner - local(session).global_basis.z * 1.2)
		session.items[id].drop()
		check(await until(func() -> bool: return host._item_owners[id] == 0, 3), "Drop request releases carried scrap")
		print("INFO: Drop %s at %s velocity=%s player=%s" % [id, item.global_position, item.linear_velocity, host.players[session.multiplayer.get_unique_id()].global_position])
		await position(session, zone.global_position + Vector3(6 + collected, 0.2, 6))
		collected += 1
		pending.append(id)
		pending_value += item.cash_value
		if pending.size() < 4 and host.team_money + pending_value < host.SHIP_SHOP.REPAIR_COST + 200 and id != ids.back():
			continue
		await position(session, host.campaign.delivery.global_position + Vector3(1.9, 0.2, 0))
		var sale_balance: int = host.team_money
		Input.action_press("request_abduction")
		var sold: bool = await until(func() -> bool:
			for cargo: StringName in pending:
				if not host.items[cargo].network_consumed: return false
			return true, 90)
		Input.action_release("request_abduction")
		if not check(sold, "Held abduction signal sells dropped scrap once"):
			print("INFO: Unsold position=%s zone=%s" % [item.global_position, zone.global_position])
			for cargo: StringName in pending:
				print("INFO: Cargo %s consumed=%s abducted=%s position=%s" % [cargo, host.items[cargo].network_consumed, host.items[cargo].being_abducted, host.items[cargo].global_position])
			print("INFO: Delivery state=%s elapsed=%s" % [host.campaign.delivery._state, host.campaign.delivery._state_elapsed])
			break
		check(host.team_money == sale_balance + pending_value, "Batch sale credits each scrap exactly once")
		check(await until(func() -> bool:
			for observer: Node3D in sessions:
				if observer.team_money != host.team_money: return false
				for cargo: StringName in pending:
					if not observer.items[cargo].network_consumed: return false
			return true), "Sale and shared balance reach every peer")
		pending.clear()
		pending_value = 0
		if collected >= 4 and host.team_money >= host.SHIP_SHOP.REPAIR_COST + 200: break
	if host.team_money < host.SHIP_SHOP.REPAIR_COST + 200:
		check(false, "Collection earns enough money for repair and revival")
		await finish()
		return
	check(collected >= 4, "Every player collects and delivers scrap")
	for session: Node3D in sessions:
		var peer: int = session.multiplayer.get_unique_id()
		var before: float = host.players[peer].health
		host.damage_player(peer, 10.0)
		check(await until(func() -> bool:
			for observer: Node3D in sessions:
				if observer.players[peer].health >= before: return false
			return true), "Damage replicates for player %d" % peer)
	var victim: int = sessions[3].multiplayer.get_unique_id()
	var victim_generation: int = host.players[victim].life_generation
	var revival_balance: int = host.team_money
	await position(sessions[3], host.campaign.delivery.global_position + Vector3(5, 1, 0))
	host.damage_player(victim, 1000.0)
	var corpse: StringName = StringName("corpse_%d" % victim)
	if check(await until(func() -> bool: return host.items.has(corpse)), "Joining player dies and leaves recoverable body"):
		sessions[3].request_respawn()
		await create_timer(0.3).timeout
		check(not local(sessions[3]).is_alive(), "Dead player cannot bypass recovery with instant respawn")
		var rescuer: Node3D = sessions[2]
		await position(rescuer, host.items[corpse].global_position + Vector3(1.2, 0, 0))
		rescuer.items[corpse].pickup(local(rescuer))
		check(await until(func() -> bool: return host._item_owners[corpse] == rescuer.multiplayer.get_unique_id()), "Another joining player carries corpse")
		await capture("corpse-carried")
		await position(rescuer, host.get_revival_tank().global_position - local(rescuer).global_basis.z * 1.2)
		rescuer.items[corpse].drop()
		check(await until(func() -> bool: return host.recovery.revivals.has(victim)), "Body deposited at authored ship tank starts paid revival")
		check(await until(func() -> bool:
			for session: Node3D in sessions:
				if not session.players[victim].is_alive() or session.players[victim].life_generation != victim_generation + 1: return false
			return true, 90), "Twenty-second revival completes on all four peers")
		check(host.team_money == revival_balance - 200, "Revival charges exactly $200")
		await capture("revived")
	freeze_locals()
	for session: Node3D in sessions:
		await position(session, host.get_shop_terminal().global_position + Vector3(0, 0, 1))
	var balance: int = host.team_money
	var shop: Node3D = sessions[1].get_shop_terminal()
	check(shop.open(local(sessions[1])), "Joining player opens authored shop interface")
	shop._repair_button.pressed.emit()
	if check(await until(func() -> bool:
		for session: Node3D in sessions:
			if not session.ship_repaired or not session.campaign.unlocked.has(host.campaign.COUNTRY): return false
		return true), "Earned scrap money repairs ship and unlocks next level for everyone"):
		check(host.team_money == balance - host.SHIP_SHOP.REPAIR_COST, "Repair charges once")
		await position(sessions[3], host.get_shop_terminal().global_position + Vector3(10, 0, 0))
		shop._next_level_button.pressed.emit()
		await create_timer(0.5).timeout
		check(host.mission_phase == &"collecting", "Departure refuses to leave a teammate behind")
		await position(sessions[3], host.get_shop_terminal().global_position + Vector3(0, 0, 1))
		shop._next_level_button.pressed.emit()
		shop.close()
		check(await until(func() -> bool: return all_at(host.campaign.ORBIT), 90), "Whole team returns to orbital ship")
		freeze_locals()
		await enter_country(host)
	await finish()

func enter_country(host: Node3D) -> void:
	sessions[2].campaign._open_console()
	sessions[2].campaign._ui._level_buttons[3].pressed.emit()
	sessions[2].campaign._ui.go_button.pressed.emit()
	sessions[2].campaign._dialogue.accepted.emit()
	check(await until(func() -> bool:
		for session: Node3D in sessions:
			if session.scene_file_path != host.campaign.COUNTRY: return false
		return true, 240), "All four load newly unlocked Country Town")
	print("INFO: Mission payload bytes=%d NPCs=%d" % [var_to_bytes(host._mission_snapshot()).size(), host.npcs.size()])
	var npc_states: Dictionary = {}
	for id: StringName in host.npcs: npc_states[id] = host.npcs[id].make_network_state()
	print("INFO: NPC snapshot bytes=%d" % var_to_bytes(npc_states).size())
	var arrived: bool = await until(func() -> bool: return all_at(host.campaign.COUNTRY), 20 if OS.get_cmdline_user_args().has("--town-only") else 90)
	check(arrived, "Country Town arrival releases all four players")
	if arrived:
		check(await until(func() -> bool:
			for id: StringName in host.npcs:
				if host.npcs[id].get_script() != host.campaign.ACTOR_SYNC: continue
				var meshes: PackedByteArray = host.npcs[id].make_network_state().meshes
				for session: Node3D in sessions.slice(1):
					if session.npcs[id].make_network_state().meshes != meshes: return false
			return true), "Compact NPC appearance states match on all four peers")
	if not arrived:
		for session: Node3D in sessions:
			print("INFO: Arrival peer=%d roster=%d path=%s phase=%s ready=%s remaining=%s loaded=%s connection=%s" % [session.multiplayer.get_unique_id(), session.players.size(), session.scene_file_path, session.mission_phase, session.campaign.loading_ready, session.campaign._arrival_remaining, session._campaign_loaded, session.multiplayer.multiplayer_peer.get_connection_status()])
	await capture("country-town")

func finish() -> void:
	Input.action_release("request_abduction")
	for session: Node3D in sessions:
		session.disconnect_game()
	print("RESULT: " + ("FAIL" if failed else "PASS"))
	quit(1 if failed else 0)

