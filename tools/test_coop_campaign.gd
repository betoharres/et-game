extends SceneTree

var _sessions: Array[Node3D] = []
var _views: Array[SubViewport] = []
var _failed: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error("FAIL: " + message)
	else:
		print("PASS: " + message)


func _wait(condition: Callable, seconds: float = 12.0) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await process_frame
	return condition.call()


func _run() -> void:
	var scene: PackedScene = load("res://scenes/Multiplayer/CampaignCoop.tscn") as PackedScene
	for index: int in 2:
		var viewport: SubViewport = SubViewport.new()
		viewport.name = "CampaignPeer%d" % index
		viewport.own_world_3d = true
		root.add_child(viewport)
		set_multiplayer(MultiplayerAPI.create_default_interface(), viewport.get_path())
		var session: Node3D = scene.instantiate() as Node3D
		viewport.add_child(session)
		session.host_migration.enabled = false
		_sessions.append(session)
		_views.append(viewport)
	var host: Node3D = _sessions[0]
	var guest: Node3D = _sessions[1]
	_check(host.host_game(17085) == OK, "Campaign host starts in Orbit without test scraps")
	_check(guest.join_game("127.0.0.1", 17085) == OK, "Campaign guest connects")
	if not await _wait(func() -> bool: return guest.players.size() == 2):
		_check(false, "Orbital roster completes")
		_finish()
		return
	host.set_ready()
	guest.set_ready()
	await _wait(func() -> bool: return host.ready_players.values().count(true) == 2)
	host.start_expedition()
	await _wait(func() -> bool: return guest.mission_phase == &"collecting")
	_check(host.scene_file_path == host.campaign.ORBIT, "Expedition begins inside the SP orbital ship")
	var guest_id: int = guest.multiplayer.get_unique_id()
	guest.players[guest_id].set_physics_process(false)
	host.players[1].set_physics_process(false)
	guest.campaign.choose_destination(guest.campaign.FARM)
	if not await _wait(func() -> bool: return host.scene_file_path == host.campaign.FARM and guest.scene_file_path == guest.campaign.FARM, 30.0):
		_check(false, "Team travels together to the authored SP farm")
		_finish()
		return
	_check(host.items.size() > 0 and guest.items.size() == host.items.size(), "Authored farm collectibles have matching network IDs")
	await _wait(func() -> bool: return guest.mission_phase == &"collecting")
	host.players[1].set_physics_process(false)
	guest.players[guest_id].set_physics_process(false)
	var selected: StringName = &""
	for id: StringName in host.items:
		if not host.items[id].two_handed and host.items[id].slot_cost == 1:
			selected = id
			break
	_check(selected != &"", "Farm supplies small inventory items")
	if selected != &"":
		var player: CharacterBody3D = guest.players[guest_id]
		player.global_position = host.items[selected].global_position + Vector3(0, 0.2, 0.6)
		await _wait(func() -> bool: return host.players[guest_id].global_position.distance_to(player.global_position) < 0.05)
		guest.items[selected].pickup(player)
		_check(await _wait(func() -> bool: return host._item_owners[selected] == guest_id), "Host accepts guest inventory pickup")
		_check(await _wait(func() -> bool: return host.players[guest_id].exploration_inventory.items.size() == 1 and player.exploration_inventory.items.size() == 1), "Inventory contents replicate and leave hands free")
		_check(player.carried_item == null and not guest.items[selected].visible, "Stored item is hidden and does not occupy hands")
		var solo_money: int = int(root.get_node("GlobalScore").get("money"))
		var balance: int = host.team_money
		var pose: Transform3D = Transform3D(Basis.IDENTITY, host.get_node("DeliveryZone").global_position)
		host._publish_item_state(0, pose, Vector3.ZERO, selected)
		guest.players[guest_id].global_position = host.campaign.delivery.global_position + Vector3(0, 0.2, 0.8)
		await _wait(func() -> bool: return host.campaign.delivery._nearby_characters.has(host.players[guest_id]))
		Input.action_press("request_abduction")
		var delivered: bool = await _wait(func() -> bool: return host.team_money > balance, 30.0)
		Input.action_release("request_abduction")
		_check(delivered, "A guest's held signal delivers through the SP tractor beam")
		_check(int(root.get_node("GlobalScore").get("money")) == solo_money, "Co-op delivery preserves single-player money")
		_check(await _wait(func() -> bool: return guest.items[selected].network_consumed), "Sold campaign item is consumed on both peers")
	var trade: Node3D = host.campaign.world.find_child("BananaTrade", true, false) as Node3D
	if trade != null:
		var banana_id: StringName = &""
		for id: StringName in host.items:
			if host.items[id].item_id == trade.requested_item_id:
				banana_id = id
				break
		_check(banana_id != &"", "Native farm quest finds its networked banana box")
		if banana_id != &"":
			host.players[1].global_position = trade.global_position
			trade._interact_peer(1)
			host._publish_item_state(guest_id, host.items[banana_id].global_transform, Vector3.ZERO, banana_id)
			guest.players[guest_id].global_position = trade.global_position
			await _wait(func() -> bool: return host.players[guest_id].global_position.distance_to(trade.global_position) < 2.0)
			trade._interact_peer(guest_id)
			_check(await _wait(func() -> bool: return guest.items[banana_id].network_consumed and guest.items.has(&"quest_reward")), "Native farm quest consumes the correct box and shares its reward")
	var checkpoint: Dictionary = host.host_migration.capture()
	_check(checkpoint.mission.has("campaign"), "Migration checkpoints include campaign progression")
	var held_id: StringName = &""
	for id: StringName in host.items:
		if id != selected and not host.items[id].two_handed and host.items[id].slot_cost == 1 and not host.items[id].scene_file_path.is_empty():
			held_id = id
			break
	if held_id != &"":
		host._publish_item_state(guest_id, host.items[held_id].global_transform, Vector3.ZERO, held_id)
		_check(await _wait(func() -> bool: return guest.players[guest_id].exploration_inventory.items.size() == 1), "Guest stores an item before return travel")
	host.debug_add_team_money()
	var terminal: Node3D = host.get_shop_terminal() as Node3D
	host.players[1].global_position = terminal.global_position + Vector3(0, 0, 1.2)
	guest.players[guest_id].global_position = terminal.global_position + Vector3(0.6, 0, 1.2)
	await _wait(func() -> bool: return host.players[guest_id].global_position.distance_to(terminal.global_position) < 3.0)
	guest.request_terminal_action(&"repair")
	_check(await _wait(func() -> bool: return host.ship_repaired and guest.campaign.unlocked.has(guest.campaign.COUNTRY)), "Repair unlocks the rescue mission for the team")
	guest.request_terminal_action(&"launch")
	_check(await _wait(func() -> bool: return host.scene_file_path == host.campaign.ORBIT and guest.scene_file_path == guest.campaign.ORBIT, 30.0), "Shared departure returns the team to Orbit")
	if held_id != &"":
		_check(await _wait(func() -> bool: return guest.players[guest_id].exploration_inventory.items.size() == 1), "Inventory survives shared travel back to Orbit")
	var late_view: SubViewport = SubViewport.new()
	late_view.name = "CampaignLatePeer"
	late_view.own_world_3d = true
	root.add_child(late_view)
	set_multiplayer(MultiplayerAPI.create_default_interface(), late_view.get_path())
	var late: Node3D = scene.instantiate() as Node3D
	late_view.add_child(late)
	late.host_migration.enabled = false
	_views.append(late_view)
	_sessions.append(late)
	_check(late.join_game("127.0.0.1", 17085) == OK, "A late guest joins the current Orbit expedition")
	_check(await _wait(func() -> bool: return late.players.size() == 3 and late.campaign.unlocked.has(late.campaign.COUNTRY) and late.players[guest_id].exploration_inventory.items.size() == 1), "Late join restores unlocked destinations and travelling inventory")
	for session: Node3D in _sessions:
		session.host_migration.enabled = true
	host.host_migration.publish_checkpoint()
	_check(await _wait(func() -> bool: return late.host_migration.checkpoint.get("roster", {}).size() == 3), "Campaign checkpoint reaches every guest")
	host.disconnect_game()
	_check(await _wait(func() -> bool: return not guest.host_migration.active and guest.multiplayer.is_server() and guest.players.size() == 2, 30.0), "The campaign migrates to the next host")
	host = guest
	guest = late
	guest_id = guest.multiplayer.get_unique_id()
	_check(host.campaign.unlocked.has(host.campaign.COUNTRY) and host.players[1].exploration_inventory.items.size() == 1, "Campaign progression and inventory survive peer ID remapping")
	for session: Node3D in _sessions:
		session.host_migration.enabled = false
	guest.players[guest_id].set_physics_process(false)
	host.players[1].set_physics_process(false)
	guest.campaign.choose_destination(guest.campaign.COUNTRY)
	_check(await _wait(func() -> bool: return host.scene_file_path == host.campaign.COUNTRY and guest.scene_file_path == guest.campaign.COUNTRY, 60.0), "The team boards the rescue saucer and reaches Country Town")
	_check(await _wait(func() -> bool: return host.mission_phase == &"collecting" and guest.mission_phase == &"collecting", 90.0), "Shared arrival beam releases the team on the ground: phase=%s ready=%s peers=%s remaining=%s" % [host.mission_phase, host.campaign.loading_ready, host._campaign_loaded, host.campaign._arrival_remaining])
	_check(not host.campaign.discovered and not guest.campaign.discovered, "Crash-site debris stays hidden until discovery")
	var crash_site: Node3D = host.campaign._crash_site as Node3D
	_check(crash_site != null, "The authored crash-site marker is found")
	if crash_site != null:
		guest.players[guest_id].set_physics_process(false)
		guest.players[guest_id].global_position = crash_site.global_position
		_check(await _wait(func() -> bool: return host.campaign.discovered and guest.campaign.discovered, 30.0), "A guest discovers the crash site for every peer: alive=%s snapshot=%s fall=%s host_position=%s" % [host.players[guest_id].is_alive(), host._valid_snapshot(guest.players[guest_id].make_snapshot()), guest.players[guest_id]._fall_state, host.players[guest_id].global_position])
	var debris_id: StringName = &""
	for id: StringName in host.items:
		var item: RigidBody3D = host.items[id]
		if item.definition != null and item.definition.transportable and not item.definition.is_locator:
			debris_id = id
			break
	_check(debris_id != &"", "Country Town preserves transportable technology definitions")
	if debris_id != &"":
		var zone: Node3D = host.campaign.world.get_node("RecoveryPoint/CollectionArea") as Node3D
		var pose: Transform3D = Transform3D(Basis.IDENTITY, zone.global_position + Vector3.UP)
		var old_deliveries: int = host.deliveries
		host._publish_item_state(0, pose, Vector3.ZERO, debris_id)
		_check(await _wait(func() -> bool: return host.deliveries == old_deliveries + 1 and guest.items[debris_id].network_consumed, 90.0), "The recovery ship collects debris and credits the team once")
	_finish()


func _finish() -> void:
	for session: Node3D in _sessions:
		session.host_migration.enabled = false
		session.disconnect_game()
	for viewport: SubViewport in _views:
		viewport.queue_free()
	await process_frame
	quit(1 if _failed else 0)
