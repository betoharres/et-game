extends Node3D

const PLAYER_SCENE: PackedScene = preload("res://scenes/Multiplayer/NetworkPlayer.tscn")
const MAX_PLAYERS: int = 4
const DEFAULT_PORT: int = 7000
const SNAPSHOT_INTERVAL: float = 1.0 / 20.0
const EQUIPMENT_COSTS: Dictionary[StringName, int] = {&"xray_goggles": 500, &"energy_shield": 180, &"predator_watch": 650}
const UPGRADE_IDS: Array[StringName] = [&"movement", &"stamina", &"recovery"]
const UPGRADE_COSTS: Array[int] = [60, 100, 150]
const LEVEL_PATHS: Array[String] = ["res://scenes/Multiplayer/PortalCoop.tscn", "res://scenes/Multiplayer/FarmCoop.tscn"]
const CAMPAIGN_SCRIPT: Script = preload("res://scripts/multiplayer/coop_campaign.gd")
const CAMPAIGN_SCENE: String = "res://scenes/Multiplayer/CampaignCoop.tscn"
@export var full_campaign: bool = false
var campaign: Node
var _campaign_loaded: Dictionary[int, bool] = {}
var portable_assets: Dictionary[StringName, Dictionary] = {}
const SHIP_SHOP = preload("res://scripts/space/ship_shop.gd")
const SHARED_SCRAP_SCRIPT: Script = preload("res://scripts/multiplayer/shared_scrap.gd")
const FARM_SCRAPS: Array[String] = ["Bucket", "Radio", "Telephone", "Glasses", "BaseballBat", "Bottle", "Hoe", "WateringCan", "Toothpaste", "StuffedMonkey", "SoccerBall", "RemoteControl"]
const RECOVERY_SCRIPT: Script = preload("res://scripts/multiplayer/coop_recovery.gd")
const VEHICLE_SCRIPT: Script = preload("res://scripts/multiplayer/coop_vehicle.gd")
const BANANA_SCRIPT: Script = preload("res://scripts/multiplayer/coop_banana_trade.gd")
const MIGRATION_SCRIPT: Script = preload("res://scripts/multiplayer/host_migration.gd")
var host_migration: Node
var _migration_address: LineEdit
var _migration_port: SpinBox
var _migration_hint: Label
var recovery: Node3D
var player_names: Dictionary[int, String] = {}
var ready_players: Dictionary[int, bool] = {}
var _name_entry: LineEdit
var _ready_button: Button
var _start_button: Button
var _roster_label: Label
var _reconnect_token: String = Crypto.new().generate_random_bytes(16).hex_encode()
var _peer_tokens: Dictionary[int, String] = {}
var _departed: Dictionary[String, Dictionary] = {}
var _disconnecting: bool = false
var _noise_received: Dictionary[int, Vector3] = {}
var _noise_requests: Array[Dictionary] = []


func request_player_noise(decibels: float, sequence: int, generation: int) -> void:
	if multiplayer.is_server():
		_accept_player_noise(multiplayer.get_unique_id(), decibels, sequence, generation)
	else:
		_request_player_noise.rpc_id(1, decibels, sequence, generation)


@rpc("any_peer", "call_remote", "unreliable_ordered", 6)
func _request_player_noise(decibels: float, sequence: int, generation: int) -> void:
	if multiplayer.is_server():
		_accept_player_noise(multiplayer.get_remote_sender_id(), decibels, sequence, generation)


func _accept_player_noise(peer_id: int, decibels: float, sequence: int, generation: int) -> void:
	if host_migration.active or mission_phase != &"collecting" or not players.has(peer_id):
		return
	var player: CharacterBody3D = players[peer_id]
	var noise: PlayerNoise = player.get_node("PlayerNoise") as PlayerNoise
	if generation != player.life_generation or not player.can_emit_player_noise() or decibels not in [noise.crouch_decibels, noise.walk_decibels, noise.run_decibels, noise.jump_decibels, noise.theft_decibels]:
		return
	var previous: Vector3 = _noise_received.get(peer_id, Vector3(-1, -1, -1))
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	if int(previous.x) == generation and (sequence <= int(previous.y) or now - previous.z < 0.1):
		return
	_noise_received[peer_id] = Vector3(generation, sequence, now)
	if _noise_requests.size() < 64:
		_noise_requests.append({"peer": peer_id, "decibels": decibels, "generation": generation})


func _process_noise_requests() -> void:
	for request: Dictionary in _noise_requests:
		_receive_player_noise(request.peer, request.decibels, request.generation)
		_receive_player_noise.rpc(request.peer, request.decibels, request.generation)
	_noise_requests.clear()


@rpc("authority", "call_remote", "unreliable_ordered", 6)
func _receive_player_noise(peer_id: int, decibels: float, generation: int) -> void:
	if not players.has(peer_id) or players[peer_id].life_generation != generation or not players[peer_id].is_alive():
		return
	var player: CharacterBody3D = players[peer_id]
	var noise: PlayerNoise = player.get_node("PlayerNoise") as PlayerNoise
	if multiplayer.is_server():
		noise.emit_noise(decibels, true)
	if not player.is_local_player():
		player.call("queue_network_noise", decibels)


func set_ready() -> void:
	if multiplayer.is_server():
		_set_ready_peer(multiplayer.get_unique_id())
	else:
		_request_ready.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_ready() -> void:
	if multiplayer.is_server():
		_set_ready_peer(multiplayer.get_remote_sender_id())


func _set_ready_peer(peer_id: int) -> void:
	if not host_migration.active and mission_phase == &"lobby" and players.has(peer_id):
		ready_players[peer_id] = not ready_players.get(peer_id, false)
		_publish_lobby()


func start_expedition() -> void:
	if host_migration.active or not multiplayer.is_server() or mission_phase != &"lobby" or players.is_empty():
		return
	for peer_id: int in players:
		if not ready_players.get(peer_id, false):
			return
	mission_phase = &"collecting"
	_begin_expedition()
	_begin_expedition.rpc()
	_publish_mission()


@rpc("authority", "call_remote", "reliable")
func _begin_expedition() -> void:
	mission_phase = &"collecting"
	_set_menu_open(false)
	for npc: Node3D in npcs.values():
		npc.call("set_host_simulation", multiplayer.is_server())


func _publish_lobby() -> void:
	_receive_lobby(player_names, ready_players)
	_receive_lobby.rpc(player_names, ready_players)


@rpc("authority", "call_remote", "reliable")
func _receive_lobby(names: Dictionary, readiness: Dictionary) -> void:
	player_names.assign(names.duplicate())
	ready_players.assign(readiness.duplicate())
	if _roster_label != null:
		var lines: PackedStringArray = []
		for peer_id: int in player_names:
			lines.append("%s · %s" % [player_names[peer_id], "Ready" if ready_players.get(peer_id, false) else "Not ready"])
		_roster_label.text = "\n".join(lines)
	for peer_id: int in players:
		var label: Label3D = players[peer_id].get_node_or_null("PlayerName") as Label3D
		if label == null:
			label = Label3D.new()
			label.name = "PlayerName"
			label.position.y = 1.8
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			players[peer_id].add_child(label)
		label.text = player_names.get(peer_id, "ET")
		label.visible = peer_id != multiplayer.get_unique_id() and players[peer_id].is_alive()
	_refresh_ui()
signal team_state_changed
var ship_repaired: bool = false
var mission_round: int = 1
var mission_phase: StringName = &"collecting"
var team_radon: float = 1200.0
var _mission_elapsed: float = 0.0
var _departure_remaining: float = 0.0
var _terminal_requests: Array[Dictionary] = []
var _mission_label: Label
var _results_panel: PanelContainer
var _results_label: Label
var _round_sales_money: int = 0
var last_round_money: int = 0
var last_round_deliveries: int = 0
var _round_start_deliveries: int = 0


func _end_run() -> void:
	_reset_run.rpc()
	_reset_run()
	_publish_lobby()
	_publish_mission()
	_publish_economy()


@rpc("authority", "call_remote", "reliable")
func _reset_run() -> void:
	purchases.clear()
	team_money = 0
	team_score = 0
	deliveries = 0
	team_radon = 1200.0
	_departed.clear()
	if campaign != null:
		campaign.reset_progress()
		portable_assets.clear()
	_commit_round(campaign.ORBIT if campaign != null else scene_file_path, mission_round + 1)
	mission_round = 1
	mission_phase = &"lobby"
	for peer_id: int in players:
		ready_players[peer_id] = false
	for npc: Node3D in npcs.values():
		npc.set_host_simulation(false)
	_set_menu_open(true)
	_set_status("Everyone died. Run reset - ready up for a new expedition.")


func request_terminal_action(action: StringName) -> void:
	var peer_id: int = multiplayer.get_unique_id()
	if multiplayer.is_server():
		_terminal_requests.append({"peer": peer_id, "action": action})
	else:
		_request_terminal_action.rpc_id(1, action)


@rpc("any_peer", "call_remote", "reliable")
func _request_terminal_action(action: StringName) -> void:
	if multiplayer.is_server() and players.has(multiplayer.get_remote_sender_id()) and _terminal_requests.size() < 32:
		_terminal_requests.append({"peer": multiplayer.get_remote_sender_id(), "action": action})


func _process_terminal_requests() -> void:
	var terminal: Node3D = get_node_or_null("PropsContainer/ShopTerminal")
	for request: Dictionary in _terminal_requests:
		var peer_id: int = request["peer"]
		if terminal == null or not players.has(peer_id) or not players[peer_id].is_alive() or mission_phase != &"collecting":
			continue
		if players[peer_id].global_position.distance_to(terminal.global_position) > float(terminal.get("interaction_radius")):
			continue
		var action: StringName = request["action"]
		if action == &"repair":
			if not ship_repaired and team_money >= SHIP_SHOP.REPAIR_COST:
				team_money -= SHIP_SHOP.REPAIR_COST
				ship_repaired = true
				if campaign != null and not campaign.unlocked.has(campaign.COUNTRY):
					campaign.unlocked.append(campaign.COUNTRY)
				_publish_economy()
				_publish_mission()
		elif action == &"radon":
			if team_money >= SHIP_SHOP.RADON_COST and team_radon < SHIP_SHOP.GAME_PROGRESS.radon_capacity_seconds:
				team_money -= SHIP_SHOP.RADON_COST
				team_radon = minf(team_radon + SHIP_SHOP.RADON_PURCHASE_SECONDS, SHIP_SHOP.GAME_PROGRESS.radon_capacity_seconds)
				_publish_economy()
				_publish_mission()
		elif action == &"launch":
			var ready: bool = ship_repaired
			for player: CharacterBody3D in players.values():
				ready = ready and player.is_alive() and player.global_position.distance_to(terminal.global_position) <= 6.0
			if ready:
				mission_phase = &"departing"
				_departure_remaining = 3.0
				last_round_deliveries = deliveries - _round_start_deliveries
				last_round_money = _round_sales_money
				_publish_mission()
			else:
				if peer_id == 1:
					_purchase_result("Repair the ship and gather every living player at the terminal before departure.")
				else:
					_purchase_result.rpc_id(peer_id, "Repair the ship and gather every living player at the terminal before departure.")
		else:
			_queue_purchase(peer_id, action)
	_terminal_requests.clear()


func _mission_snapshot() -> Dictionary:
	var state: Dictionary = {"round": mission_round, "phase": mission_phase, "repaired": ship_repaired, "radon": team_radon, "remaining": _departure_remaining, "last_deliveries": last_round_deliveries, "last_money": last_round_money}
	if campaign != null:
		state["campaign"] = campaign.capture()
	return state


func _publish_mission() -> void:
	var state: Dictionary = _mission_snapshot()
	_receive_mission(state)
	for peer_id: int in players:
		if peer_id != 1:
			_receive_mission.rpc_id(peer_id, state)


@rpc("authority", "call_remote", "reliable")
func _receive_mission(state: Dictionary) -> void:
	var previous_phase: StringName = mission_phase
	mission_round = state["round"]
	mission_phase = state["phase"]
	ship_repaired = state["repaired"]
	team_radon = state["radon"]
	_departure_remaining = state["remaining"]
	last_round_deliveries = state["last_deliveries"]
	last_round_money = state["last_money"]
	if campaign != null and state.has("campaign"):
		campaign.restore(state.campaign)
		_set_campaign_load_timeout(not campaign.loading_ready or mission_phase in [&"departing", &"arriving"])
		if mission_phase == &"collecting" and previous_phase != &"collecting":
			for npc: Node3D in npcs.values():
				npc.call("set_host_simulation", multiplayer.is_server())
	for player: CharacterBody3D in players.values():
		player.call("_update_oxygen_display")
	if mission_phase != &"collecting":
		var terminal: Node = get_node_or_null("PropsContainer/ShopTerminal")
		if terminal != null:
			terminal.call("close")
		for player: CharacterBody3D in players.values():
			player.call("set_movement_locked", true)
		for npc: Node3D in npcs.values():
			npc.call("set_host_simulation", false)
	_refresh_ui()
	team_state_changed.emit()


func _advance_mission() -> void:
	if campaign != null:
		campaign.advance()
		return
	var next_path: String = LEVEL_PATHS[(LEVEL_PATHS.find(scene_file_path) + 1) % LEVEL_PATHS.size()]
	_commit_round.rpc(next_path, mission_round + 1)
	_commit_round(next_path, mission_round + 1)
	_publish_mission()
	_publish_economy()


@rpc("authority", "call_remote", "reliable")
func _commit_round(level_path: String, round_number: int) -> void:
	if (not LEVEL_PATHS.has(level_path) and not (campaign != null and level_path in [campaign.ORBIT, campaign.FARM, campaign.COUNTRY])) or round_number <= mission_round:
		return
	if campaign != null:
		campaign.loading_ready = false
		_campaign_loaded.clear()
		_set_campaign_load_timeout(true)
	var travelling_items: Array[Dictionary] = []
	if campaign != null and not host_migration.is_restoring:
		for id: StringName in items:
			if _item_owners[id] != 0 and not recovery.victims.has(id):
				var path: String = items[id].scene_file_path
				if not path.is_empty():
					travelling_items.append({"id": id, "owner": _item_owners[id], "path": path})
	var source: Node3D = (load(level_path) as PackedScene).instantiate() as Node3D if campaign == null else null
	recovery.call("reset")
	for item_id: StringName in items:
		items[item_id].call("apply_network_state", null, _item_spawns[item_id], Vector3.ZERO, false)
	for child: Node in get_children():
		if child is Node3D and child != player_container and child != recovery or child is WorldEnvironment:
			if child.name == &"VehiclesContainer":
				for vehicle: Node in child.get_children():
					vehicle.get_node("CoopSeats").call("reset")
			remove_child(child)
			child.queue_free()
	items.clear()
	npcs.clear()
	_item_owners.clear()
	_item_revisions.clear()
	_item_spawns.clear()
	_item_requests.clear()
	_purchase_requests.clear()
	_terminal_requests.clear()
	mission_round = round_number
	scene_file_path = level_path
	mission_phase = &"collecting"
	ship_repaired = false
	_round_start_deliveries = deliveries
	_round_sales_money = 0
	if campaign != null:
		_make_campaign_containers()
		portable_assets.clear()
		campaign.load_world(level_path)
		if level_path == campaign.ORBIT:
			mission_phase = &"loading"
	else:
		for child: Node in source.get_children():
			if child.name == &"Players":
				continue
			source.remove_child(child)
			add_child(child)
		source.free()
	_register_world_items()
	for peer_id: int in players.keys():
		_replace_player(peer_id, _life_generations[peer_id] + 1)
	for npc: Node3D in npcs.values():
		npc.call("set_host_simulation", multiplayer.is_server() and mission_phase == &"collecting")
	for item_id: StringName in items:
		items[item_id].call("apply_network_state", null, _item_spawns[item_id], Vector3.ZERO, multiplayer.is_server())
	for record: Dictionary in travelling_items:
		var id: StringName = StringName("travel/" + str(record.owner) + "/" + str(travelling_items.find(record)))
		portable_assets[id] = {"path": record.path}
		spawn_shared_asset(id, record.path, _spawn_position(_slots[record.owner]))
		_receive_item_state(record.owner, items[id].global_transform, Vector3.ZERO, _item_revisions[id] + 1, id)
	if campaign != null:
		if not host_migration.is_restoring:
			if multiplayer.is_server():
				_campaign_player_loaded(1, round_number)
			else:
				_campaign_world_loaded.rpc_id(1, round_number)
		_map_choice.select(2)
	else:
		_map_choice.select(LEVEL_PATHS.find(level_path))
	_refresh_ui()


func _register_world_items() -> void:
	if campaign != null:
		return
	var container: Node = $PickupItemsContainer
	for index: int in FARM_SCRAPS.size():
		var item: RigidBody3D = (load("res://scenes/Farm/Scraps/%s.tscn" % FARM_SCRAPS[index]) as PackedScene).instantiate() as RigidBody3D
		var properties: Dictionary = {}
		for property: StringName in [&"item_id", &"cash_value", &"score_value", &"display_name", &"two_handed", &"slot_cost", &"rejected_by_delivery"]:
			properties[property] = item.get(property)
		item.set_script(SHARED_SCRAP_SCRIPT)
		for property: StringName in properties:
			item.set(property, properties[property])
		item.set("network_id", StringName("farm_%02d" % index))
		item.name = "FarmScrap%d" % index
		item.position = Vector3(-8 + (index % 6) * 4, 0.5, -5 - (index / 6) * 3)
		container.add_child(item)
		item.add_to_group(&"farm_scraps")
		for mesh: Node in item.find_children("*", "MeshInstance3D", true, false):
			(mesh as MeshInstance3D).layers = 128
	_register_items()
	var npc_container: Node = get_node_or_null("NPCsContainer")
	if npc_container != null:
		for npc: NPCActor in npc_container.get_children():
			npcs[npc.name] = npc
	shared_item = $PickupItemsContainer/SharedScrap
	_setup_vehicles()
	_setup_farm_content()


func _make_campaign_containers() -> void:
	for container_name: String in ["PickupItemsContainer", "NPCsContainer", "BuildingContainers", "PropsContainer", "VehiclesContainer"]:
		var container: Node3D = Node3D.new()
		container.name = container_name
		add_child(container)


func spawn_shared_asset(id: StringName, path: String, position: Vector3) -> void:
	if items.has(id):
		return
	var item: RigidBody3D = (load(path) as PackedScene).instantiate() as RigidBody3D
	var properties: Dictionary = {}
	var item_definition: Resource = item.get("definition") as Resource if item is AlienTechnologyItem else null
	for property: StringName in [&"item_id", &"cash_value", &"score_value", &"display_name", &"two_handed", &"slot_cost", &"rejected_by_delivery"]:
		properties[property] = item.get(property)
	item.set_script(SHARED_SCRAP_SCRIPT)
	item.set("definition", item_definition)
	for property: StringName in properties:
		item.set(property, properties[property])
	item.name = str(id)
	item.set("network_id", id)
	item.position = position
	$PickupItemsContainer.add_child(item)
	items[id] = item
	_item_owners[id] = 0
	_item_revisions[id] = mission_round * 1000000
	_item_spawns[id] = item.global_transform
	item.pickup_requested.connect(_on_item_pickup_requested.bind(id))
	item.drop_requested.connect(_on_item_drop_requested.bind(id))
	item.call("apply_network_state", null, item.global_transform, Vector3.ZERO, multiplayer.is_server() and not players.is_empty())


func _setup_farm_content() -> void:
	if not scene_file_path.ends_with("FarmCoop.tscn"):
		return
	var gorilla: Node3D = (load("res://scenes/NPCs/Gorilla.tscn") as PackedScene).instantiate() as Node3D
	gorilla.name = "Gorilla"
	gorilla.position = Vector3(-6, 0, 16)
	var trade: Node = gorilla.get_node("BananaTrade")
	var rewards: Array[PackedScene] = trade.get("rewards")
	trade.set_script(BANANA_SCRIPT)
	trade.set("rewards", rewards)
	$NPCsContainer.add_child(gorilla)
	gorilla.set_physics_process(false)
	gorilla.get_node("NPCBehaviorTree").set("enabled", false)
	gorilla.get_node("ActivityCheck").call("stop")
	var enemy_scene: PackedScene = load("res://scenes/Multiplayer/CoopGuard.tscn") as PackedScene
	var enemy_paths: Array[String] = ["SmellyFarmer", "Photographer", "Photographer"]
	for index: int in enemy_paths.size():
		var enemy: CharacterBody3D = (load("res://scenes/NPCs/%s.tscn" % enemy_paths[index]) as PackedScene).instantiate() as CharacterBody3D
		var awareness: Node = enemy.get_node_or_null("EnemyAwareness")
		if awareness != null:
			enemy.remove_child(awareness)
			awareness.free()
		enemy.set_script(load("res://scripts/multiplayer/network_farm_enemy.gd"))
		enemy.name = "Farmer" if index == 0 else "Photographer%d" % index
		enemy.position = Vector3(18 + index * 4, 0, 18)
		enemy.set("grounded", true)
		enemy.set("activity_distance", 0.0)
		enemy.set("photographer", index > 0)
		enemy.set("attack_range", 9.0 if index > 0 else 12.0)
		enemy.set("attack_interval", 6.0 if index > 0 else 2.0)
		enemy.set("attack_damage", 30.0)
		var patrol: Array[Vector3] = [enemy.position, enemy.position + Vector3(0, 0, -8)]
		enemy.set("patrol_points", patrol)
		var brain: CharacterBody3D = enemy_scene.instantiate() as CharacterBody3D
		for component_name: String in ["NPCVision", "NPCBehaviorTree"]:
			var component: Node = brain.get_node(component_name)
			brain.remove_child(component)
			enemy.add_child(component)
		brain.free()
		$NPCsContainer.add_child(enemy)
		npcs[enemy.name] = enemy
	var light: CharacterBody3D = (load("res://scenes/NPCs/LivingLight.tscn") as PackedScene).instantiate() as CharacterBody3D
	light.set_script(load("res://scripts/multiplayer/network_living_light.gd"))
	light.name = "LivingLight"
	light.position = Vector3(11, 1, -12)
	$NPCsContainer.add_child(light)
	npcs[light.name] = light
	spawn_shared_asset(&"banana_box", "res://scenes/Items/BananaBox.tscn", Vector3(-1, 0.3, 16))
	var door: Node3D = (load("res://scenes/Multiplayer/CoopBarnDoor.tscn") as PackedScene).instantiate() as Node3D
	door.position = Vector3(-13.4, 0, -3)
	$BuildingContainers.add_child(door)


func _setup_vehicles() -> void:
	if not scene_file_path.ends_with("FarmCoop.tscn"):
		return
	var container: Node3D = Node3D.new()
	container.name = "VehiclesContainer"
	add_child(container)
	var paths: Array[String] = ["res://scenes/Vehicles/DriveableTruck.tscn", "res://scenes/Vehicles/FlyablePlane.tscn"]
	for index: int in paths.size():
		var body: RigidBody3D = (load(paths[index]) as PackedScene).instantiate() as RigidBody3D
		body.name = "Plane" if index == 1 else "Truck"
		body.position = Vector3(-20, 2, 12 + index * 10)
		var seats: Node = Node.new()
		seats.name = "CoopSeats"
		seats.set_script(VEHICLE_SCRIPT)
		seats.set("plane", index == 1)
		body.add_child(seats)
		container.add_child(body)


func _register_items() -> void:
	for node: Node in $PickupItemsContainer.get_children():
		var item: RigidBody3D = node as RigidBody3D
		if item == null:
			continue
		register_shared_item(item)


func register_shared_item(item: RigidBody3D) -> void:
		var item_id: StringName = item.get("network_id")
		if item_id == &"" or items.has(item_id):
			_registry_valid = false
			push_error("Collectibles need unique, nonempty network_id values.")
			return
		items[item_id] = item
		_item_owners[item_id] = 0
		_item_revisions[item_id] = mission_round * 1000000
		_item_spawns[item_id] = item.global_transform
		item.pickup_requested.connect(_on_item_pickup_requested.bind(item_id))
		item.drop_requested.connect(_on_item_drop_requested.bind(item_id))
@export var session_title: String = "PORTAL CO-OP · UP TO 4 PLAYERS"
var _map_choice: OptionButton
var _respawn_button: Button
var _life_generations: Dictionary[int, int] = {}
var _combat_revisions: Dictionary[int, int] = {}
var npcs: Dictionary[StringName, Node3D] = {}


func debug_add_team_money() -> void:
	if not players.has(multiplayer.get_unique_id()):
		return
	if multiplayer.is_server():
		team_money += 10000
		_publish_economy()
	else:
		_request_debug_money.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_debug_money() -> void:
	if multiplayer.is_server() and players.has(multiplayer.get_remote_sender_id()):
		team_money += 10000
		_publish_economy()


func damage_player(peer_id: int, amount: float, direction: Vector3 = Vector3.ZERO, push: float = 0.0) -> void:
	if not multiplayer.is_server() or not players.has(peer_id) or not is_finite(amount) or amount <= 0.0 or not direction.is_finite():
		return
	var player: CharacterBody3D = players[peer_id]
	if not player.is_alive():
		return
	player.call("apply_host_damage", amount, direction, push)
	_publish_combat(peer_id, direction)


func request_cloak_toggle() -> void:
	if multiplayer.is_server():
		_toggle_cloak(multiplayer.get_unique_id())
	else:
		_request_cloak_toggle.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_cloak_toggle() -> void:
	if multiplayer.is_server():
		_toggle_cloak(multiplayer.get_remote_sender_id())


func _toggle_cloak(peer_id: int) -> void:
	if players.has(peer_id) and players[peer_id].is_alive() and players[peer_id].can_use_predator_watch():
		players[peer_id].call("apply_host_cloak_toggle")
		_publish_combat(peer_id)


func on_player_death(peer_id: int) -> void:
	if host_migration.is_restoring:
		return
	if multiplayer.is_server():
		for item_id: StringName in items:
			if _item_owners[item_id] == peer_id:
				_release_item(peer_id, item_id)
		recovery.call("create_corpse", peer_id)
	if peer_id == multiplayer.get_unique_id():
		var terminal: Node = get_node_or_null("PropsContainer/ShopTerminal")
		if terminal != null:
			terminal.call("close")
		_set_menu_open(true)
		_set_status("Your teammates must return your body to the ship tank. Revival costs $200.")
	_refresh_ui()


func _combat_state(peer_id: int, direction: Vector3) -> Dictionary:
	return {"generation": _life_generations[peer_id], "revision": _combat_revisions.get(peer_id, 0),
		"health": players[peer_id].health, "shield": players[peer_id].energy_shield, "direction": direction,
		"cloak": players[peer_id].predator_cloak_active, "cloak_energy": players[peer_id].predator_cloak_energy, "stealth": players[peer_id].get_stealth_alert()}


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
	_set_status("Revival requires your body in the ship tank and $200 in team funds.")


@rpc("any_peer", "call_remote", "reliable")
func _request_respawn() -> void:
	return


func _respawn_player(peer_id: int) -> void:
	if mission_phase != &"collecting" or not players.has(peer_id) or players[peer_id].is_alive():
		return
	var generation: int = _life_generations[peer_id] + 1
	var revival_position: Vector3 = $PropsContainer/RevivalTank.global_position + Vector3(0, 1, 2)
	_replace_player(peer_id, generation, revival_position)
	_replace_player.rpc(peer_id, generation, revival_position)
	_publish_combat(peer_id)


@rpc("authority", "call_remote", "reliable")
func _replace_player(peer_id: int, generation: int, spawn: Vector3 = Vector3.INF) -> void:
	_noise_received.erase(peer_id)
	if not players.has(peer_id) or generation <= _life_generations.get(peer_id, -1):
		return
	var old: CharacterBody3D = players[peer_id]
	player_container.remove_child(old)
	old.queue_free()
	players.erase(peer_id)
	_life_generations[peer_id] = generation
	_combat_revisions[peer_id] = 0
	_spawn_player(peer_id, _slots[peer_id], _profiles[peer_id], Transform3D(Basis.IDENTITY, spawn if spawn.is_finite() else _spawn_position(_slots[peer_id])), generation)
	players[peer_id].call("apply_team_purchases")


@rpc("authority", "call_remote", "unreliable_ordered", 3)
func _receive_npc_states(states: Dictionary, round_number: int = 1) -> void:
	if round_number != mission_round:
		return
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
@onready var shared_item: RigidBody3D = get_node_or_null("PickupItemsContainer/SharedScrap") as RigidBody3D


func _ready() -> void:
	host_migration = Node.new()
	host_migration.name = "HostMigration"
	host_migration.set_script(MIGRATION_SCRIPT)
	add_child(host_migration)
	recovery = Node3D.new()
	recovery.name = "Recovery"
	recovery.set_script(RECOVERY_SCRIPT)
	add_child(recovery)
	if full_campaign:
		campaign = Node.new()
		campaign.name = "Campaign"
		campaign.set_script(CAMPAIGN_SCRIPT)
		campaign.set("session", self)
		add_child(campaign)
		scene_file_path = campaign.ORBIT
		campaign.load_world(scene_file_path)
	_register_world_items()
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
	if not _registry_valid or (items.is_empty() and campaign == null):
		return ERR_INVALID_DATA
	if _connecting or not players.is_empty():
		return ERR_ALREADY_IN_USE
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var error: Error = peer.create_server(port, MAX_PLAYERS - 1)
	if error != OK:
		_set_status("Could not host: %s" % error_string(error))
		return error
	multiplayer.multiplayer_peer = peer
	_port.value = port
	_peer_tokens[1] = _reconnect_token
	var profile: Dictionary = _local_appearance()
	mission_phase = &"lobby"
	player_names[1] = _name_entry.text.strip_edges().left(24) if not _name_entry.text.strip_edges().is_empty() else "ET Host"
	ready_players[1] = false
	_spawn_player(1, 0, profile, Transform3D(Basis.IDENTITY, _spawn_position(0)))
	for npc: Node3D in npcs.values():
		npc.call("set_host_simulation", false)
	for item_id: StringName in items:
		_publish_item_state(0, _item_spawns[item_id], Vector3.ZERO, item_id)
	_set_menu_open(true)
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
	_port.value = port
	_connecting = true
	_connecting_elapsed = 0.0
	_refresh_ui()
	_set_status("Connecting…")
	return OK


func disconnect_game(message: String = "Disconnected. Host or join another session.") -> void:
	if not _disconnecting and not host_migration.active and host_migration.enabled and multiplayer.is_server() and multiplayer.multiplayer_peer is ENetMultiplayerPeer and players.size() > 1:
		host_migration.publish_checkpoint()
		_disconnecting = true
		host_migration.pause_world()
		_set_status("Passing the expedition to the next host...")
		_disconnect_after_handoff(message)
		return
	host_migration.reset()
	_disconnecting = true
	var quest: Node = get_node_or_null("NPCsContainer/Gorilla/BananaTrade")
	if quest != null:
		quest.call("reset")
	recovery.call("reset")
	var vehicles: Node = get_node_or_null("VehiclesContainer")
	if vehicles != null:
		for vehicle: Node in vehicles.get_children():
			vehicle.get_node("CoopSeats").call("reset")
	var terminal: Node = get_node_or_null("PropsContainer/ShopTerminal")
	if terminal != null:
		terminal.call("close")
	ship_repaired = false
	mission_phase = &"collecting"
	team_radon = 1200.0
	_terminal_requests.clear()
	mission_round = 1
	_round_sales_money = 0
	_round_start_deliveries = 0
	last_round_deliveries = 0
	last_round_money = 0
	for npc: Node3D in npcs.values():
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
	_noise_received.clear()
	_noise_requests.clear()
	_profiles.clear()
	_slots.clear()
	_life_generations.clear()
	_combat_revisions.clear()
	team_money = 0
	team_score = 0
	deliveries = 0
	purchases.clear()
	player_names.clear()
	ready_players.clear()
	_peer_tokens.clear()
	_departed.clear()
	_purchase_requests.clear()
	var lobby_camera: Camera3D = get_node_or_null("LobbyCamera") as Camera3D
	if lobby_camera != null:
		lobby_camera.make_current()
	_set_menu_open(true)
	_refresh_ui()
	_set_status(message)
	_disconnecting = false


func _disconnect_after_handoff(message: String) -> void:
	var leaving_peer: MultiplayerPeer = multiplayer.multiplayer_peer
	var deadline: int = Time.get_ticks_msec() + 1500
	while not host_migration.acknowledged() and Time.get_ticks_msec() < deadline:
		if multiplayer.multiplayer_peer != leaving_peer:
			return
		await get_tree().process_frame
	if multiplayer.multiplayer_peer == leaving_peer:
		disconnect_game(message)


func _close_peer() -> void:
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func _on_connected() -> void:
	if campaign != null:
		_set_campaign_load_timeout(true)
	if host_migration.active:
		host_migration.connected()
		return
	_register_player.rpc_id(1, _local_appearance(), scene_file_path, _static_item_ids(), _name_entry.text.strip_edges().left(24), _reconnect_token, _migration_address.text.strip_edges(), int(_migration_port.value))


func _static_item_ids() -> Array:
	var ids: Array = []
	for id: StringName in items:
		if not str(id).begins_with("corpse_") and not str(id).begins_with("travel/") and id != &"quest_reward":
			ids.append(id)
	return ids


@rpc("authority", "call_remote", "reliable")
func _reject_connection(reason: String) -> void:
	disconnect_game(reason)


func _on_connection_failed() -> void:
	if host_migration.active:
		host_migration.fail("Could not reach the replacement host. Check its advertised IP and UDP forwarding.")
		return
	disconnect_game("Could not connect. Check host IP, matching UDP port and map, Windows firewall, and router UDP forwarding for internet play.")


func _on_server_disconnected() -> void:
	if host_migration.active:
		host_migration.fail("The replacement host disconnected during migration.")
	elif not host_migration.begin():
		disconnect_game("The host disconnected. No migration checkpoint is available.")


@rpc("any_peer", "call_remote", "reliable")
func _register_player(profile: Dictionary, level_path: String, item_ids: Array, display_name: String = "ET", token: String = "", hosting_address: String = "", hosting_port: int = 0) -> void:
	if not multiplayer.is_server() or host_migration.active:
		return
	var peer_id: int = multiplayer.get_remote_sender_id()
	if campaign != null:
		_set_campaign_load_timeout(true, peer_id)
	if peer_id <= 1 or players.has(peer_id) or not multiplayer.get_peers().has(peer_id):
		return
	if _disconnecting:
		_reject_connection.rpc_id(peer_id, "The host is leaving. Join the replacement host after migration completes.")
		return
	if token.length() != 32 or _peer_tokens.values().has(token):
		_reject_connection.rpc_id(peer_id, "Invalid or already connected player identity.")
		return
	if not hosting_address.is_empty() and not hosting_address.is_valid_ip_address():
		_reject_connection.rpc_id(peer_id, "Your hosting address must be an IP address, or left empty for auto-detection.")
		return
	if hosting_port != 0 and (hosting_port < 1024 or hosting_port > 65535):
		_reject_connection.rpc_id(peer_id, "Your hosting UDP port must be 1024-65535, or 0 for automatic selection.")
		return
	if mission_phase not in [&"collecting", &"lobby"]:
		_reject_connection.rpc_id(peer_id, "The team is departing. Join after the next round starts.")
		return
	if not _registry_valid or level_path != scene_file_path or item_ids.size() != _static_item_ids().size():
		if campaign != null and level_path == campaign.ORBIT and scene_file_path != campaign.ORBIT:
			_prepare_campaign_join.rpc_id(peer_id, scene_file_path, mission_round)
			return
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
	_peer_tokens[peer_id] = token
	var returning: Dictionary = _departed.get(token, {})
	player_names[peer_id] = display_name.strip_edges().left(24) if not display_name.strip_edges().is_empty() else "ET Guest"
	ready_players[peer_id] = mission_phase == &"collecting"
	for existing_id: int in players:
		_spawn_player.rpc_id(peer_id, existing_id, _slots[existing_id], _profiles[existing_id], players[existing_id].global_transform, _life_generations[existing_id])
		_receive_combat.rpc_id(peer_id, existing_id, _combat_state(existing_id, Vector3.ZERO))
	var initial_transform: Transform3D = Transform3D(Basis.IDENTITY, _spawn_position(slot))
	_spawn_player(peer_id, slot, sanitized, initial_transform)
	_spawn_player.rpc(peer_id, slot, sanitized, initial_transform)
	if not returning.is_empty():
		purchases[peer_id] = returning["purchases"]
		players[peer_id].energy_shield = returning["shield"]
		players[peer_id].predator_cloak_energy = returning["cloak_energy"]
		players[peer_id].call("apply_team_purchases")
		if float(returning["health"]) <= 0.0:
			players[peer_id].energy_shield = 0.0
			players[peer_id].call("apply_host_damage", players[peer_id].max_health, Vector3.ZERO, 0.0)
		else:
			players[peer_id].health = returning["health"]
		_departed.erase(token)
		_publish_combat(peer_id)
	recovery.call("send_snapshot", peer_id)
	var door: Node = get_node_or_null("BuildingContainers/BarnDoor")
	if door != null:
		door.call("send_snapshot", peer_id)
	var quest: Node = get_node_or_null("NPCsContainer/Gorilla/BananaTrade")
	if quest != null:
		quest.call("send_snapshot", peer_id)
	var vehicles: Node = get_node_or_null("VehiclesContainer")
	if vehicles != null:
		for vehicle: Node in vehicles.get_children():
			vehicle.get_node("CoopSeats").call("send_snapshot", peer_id)
	_receive_economy.rpc_id(peer_id, team_money, team_score, deliveries, purchases)
	if campaign != null:
		_receive_mission.rpc_id(peer_id, _mission_snapshot())
	for item_id: StringName in items:
		var item: RigidBody3D = items[item_id]
		_receive_item_state.rpc_id(peer_id, _item_owners[item_id], item.global_transform, item.linear_velocity, _item_revisions[item_id], item_id)
	_publish_economy()
	_receive_mission.rpc_id(peer_id, _mission_snapshot())
	host_migration.record_endpoint(peer_id, hosting_address, hosting_port)
	_publish_lobby()
	host_migration.publish_checkpoint()


@rpc("authority", "call_remote", "reliable")
func _spawn_player(peer_id: int, slot: int, profile: Dictionary, initial_transform: Transform3D, generation: int = 0) -> void:
	if players.has(peer_id) or players.size() >= MAX_PLAYERS:
		return
	var player: CharacterBody3D = PLAYER_SCENE.instantiate() as CharacterBody3D
	player.name = str(peer_id)
	player.set_multiplayer_authority(peer_id)
	player.transform = initial_transform
	player.set("life_generation", generation)
	if campaign != null and mission_phase == &"arriving":
		player.set_meta("coop_arrival", true)
	_life_generations[peer_id] = generation
	player_container.add_child(player)
	player.call("sync_appearance", profile)
	players[peer_id] = player
	_profiles[peer_id] = profile
	_slots[peer_id] = slot
	if peer_id == multiplayer.get_unique_id():
		_connecting = false
		_set_menu_open(mission_phase == &"lobby")
	_refresh_ui()


func _on_peer_disconnected(peer_id: int) -> void:
	if host_migration.active:
		host_migration.peer_disconnected(peer_id)
		return
	if _disconnecting or not players.has(peer_id):
		return
	if multiplayer.is_server():
		if players.has(peer_id) and _peer_tokens.has(peer_id):
			var player: CharacterBody3D = players[peer_id]
			_departed[_peer_tokens[peer_id]] = {"purchases": purchases.get(peer_id, {}).duplicate(true), "health": player.health, "shield": player.energy_shield, "cloak_energy": player.predator_cloak_energy}
		_peer_tokens.erase(peer_id)
		host_migration.endpoints.erase(peer_id)
		recovery.call("remove_peer", peer_id)
		for item_id: StringName in items:
			if _item_owners[item_id] == peer_id:
				_release_item(peer_id, item_id)
		_remove_player(peer_id)
		_remove_player.rpc(peer_id)
		if campaign != null and not campaign.loading_ready:
			_campaign_player_loaded(1, mission_round)
		_publish_lobby()


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
	player_names.erase(peer_id)
	ready_players.erase(peer_id)
	_life_generations.erase(peer_id)
	_combat_revisions.erase(peer_id)
	_refresh_ui()


func _physics_process(delta: float) -> void:
	if host_migration.active or _disconnecting:
		return
	if multiplayer.is_server() and not players.is_empty():
		if mission_phase == &"collecting":
			_process_noise_requests()
			_process_terminal_requests()
			_process_item_requests()
			_check_delivery()
			_process_purchases()
			_mission_elapsed += delta
			if _mission_elapsed >= 1.0:
				team_radon = maxf(0.0, team_radon - _mission_elapsed)
				_mission_elapsed = 0.0
				_publish_mission()
			var living: bool = false
			for peer_id: int in players:
				if team_radon <= 0.0 and players[peer_id].is_alive():
					damage_player(peer_id, players[peer_id].max_health + players[peer_id].energy_shield)
				living = living or players[peer_id].is_alive()
			if not living:
				mission_phase = &"failed"
				_end_run.call_deferred()
		elif mission_phase == &"departing":
			_departure_remaining -= delta
			if _departure_remaining <= 0.0:
				mission_phase = &"loading"
				_advance_mission.call_deferred()
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
				_receive_npc_states.rpc_id(peer_id, npc_states, mission_round)
		var motions: Dictionary = {}
		for item_id: StringName in items:
			if _item_owners[item_id] == 0:
				motions[item_id] = [_item_revisions[item_id], items[item_id].global_transform, items[item_id].linear_velocity]
		var batch: Dictionary = {}
		for id: StringName in motions:
			batch[id] = motions[id]
			if batch.size() >= 6:
				_send_item_motions(batch)
				batch = {}
		if not batch.is_empty():
			_send_item_motions(batch)
	else:
		_submit_snapshot.rpc_id(1, state)


func _send_item_motions(motions: Dictionary) -> void:
	for target_id: int in players:
		if target_id != 1:
			_receive_items_motion.rpc_id(target_id, motions)


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _submit_snapshot(state: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var peer_id: int = multiplayer.get_remote_sender_id()
	if not players.has(peer_id) or players[peer_id].has_meta("coop_seated") or not players[peer_id].is_alive() or int(state.get("generation", -1)) != _life_generations[peer_id] or not _valid_snapshot(state):
		return
	if int(state["sequence"]) <= int(players[peer_id].get("_remote_sequence")) or int(state["epoch"]) < int(players[peer_id].get("_remote_epoch")):
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
				if campaign != null and campaign.pursuit != null:
					campaign.pursuit.report_theft(item, players[peer_id])
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
	var pair: Node3D = get_node_or_null("PortalPair") as Node3D
	if pair == null and campaign != null:
		pair = campaign.world.get_node_or_null("PortalPair") as Node3D
	if pair != null and is_instance_valid(previous_owner):
		pair.call("refresh_traveller_visual", previous_owner)
	if pair != null and new_owner != null and new_owner != previous_owner:
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
	if campaign != null and (scene_file_path == campaign.COUNTRY or campaign.delivery != null):
		return
	var zone: Area3D = get_node_or_null("DeliveryZone") as Area3D
	if zone == null:
		return
	var shape: BoxShape3D = $DeliveryZone/Collision.shape as BoxShape3D
	var credited: bool = false
	for item_id: StringName in items:
		var item: RigidBody3D = items[item_id]
		if _item_owners[item_id] != 0 or not AABB(-shape.size * 0.5, shape.size).has_point(zone.to_local(item.global_position)):
			continue
		if bool(item.get("rejected_by_delivery")):
			continue
		if campaign != null and not campaign.deliver(item_id):
			continue
		team_money += int(item.get("cash_value"))
		_round_sales_money += int(item.get("cash_value"))
		team_score += int(item.get("score_value"))
		deliveries += 1
		# Reset each delivered object before the next tick can credit it again.
		if campaign == null:
			_publish_item_state(0, _item_spawns[item_id], Vector3.ZERO, item_id)
		credited = true
	if credited:
		_publish_economy()
		if campaign != null:
			_publish_mission()


func credit_shared_delivery(item: RigidBody3D) -> void:
	if not multiplayer.is_server() or campaign == null or not campaign.deliver(item.network_id):
		return
	team_money += item.cash_value
	team_score += item.score_value
	_round_sales_money += item.cash_value
	deliveries += 1
	_publish_economy()
	_publish_mission()


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
		var inventory: Node = players[peer_id].exploration_inventory
		var needs_slot: bool = item_id in [&"energy_shield", &"predator_watch"] and int(purchases.get(peer_id, {}).get(item_id, 0)) == 0
		if cost <= 0 or team_money < cost or (needs_slot and inventory.used_slots() >= inventory.capacity):
			if peer_id == 1:
				_purchase_result("Purchase refused: insufficient funds, equipment already owned, or inventory full.")
			elif multiplayer.get_peers().has(peer_id):
				_purchase_result.rpc_id(peer_id, "Purchase refused: insufficient funds, equipment already owned, or inventory full.")
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
	var terminal: Node = get_node_or_null("PropsContainer/ShopTerminal")
	if terminal != null and bool(terminal.call("is_open")):
		terminal.call("show_result", message)


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
	team_state_changed.emit()


func _valid_snapshot(state: Dictionary) -> bool:
	if state.size() != 13 or not state.get("generation") is int or state["generation"] < 0:
		return false
	var visual: Variant = state.get("visual")
	if not visual is Dictionary or not visual.get("fall") is int or visual.fall not in [0, 1, 2] or not visual.get("face_up") is bool or not visual.get("binos") is bool:
		return false
	if not visual.get("recovery") is float or not is_finite(visual.recovery) or visual.recovery < 0.0 or visual.recovery > 1.0:
		return false
	for key: String in ["fall_time", "stand_time"]:
		if not visual.get(key) is float or not is_finite(visual[key]) or visual[key] < 0.0 or visual[key] > 60.0:
			return false
	if not visual.get("pose") is PackedFloat32Array or visual.pose.size() > 512:
		return false
	for value: float in visual.pose:
		if not is_finite(value) or absf(value) > 100.0:
			return false
	if not visual.get("reaction_sequence") is int or visual.reaction_sequence < 0 or not visual.get("reaction") is Array or visual.reaction.size() != 3:
		return false
	if not visual.reaction[0] is int or visual.reaction[0] not in [0, 1, 2] or not visual.reaction[1] is Vector3 or not visual.reaction[1].is_finite() or not visual.reaction[2] is float or not is_finite(visual.reaction[2]):
		return false
	if not state.get("transform") is Transform3D or not state.get("velocity") is Vector3:
		return false
	var pose: Transform3D = state["transform"]
	var motion: Vector3 = state["velocity"]
	if not pose.is_finite() or not motion.is_finite() or absf(pose.basis.determinant()) < 0.001:
		return false
	if motion.length() > 150.0 or pose.origin.length() > 10000.0:
		return false
	var scale: Vector3 = pose.basis.get_scale()
	if scale.distance_to(Vector3.ONE) > 0.05:
		return false
	for key: String in ["on_floor", "sprinting", "crouching", "eye_light"]:
		if not state.get(key) is bool:
			return false
	for key: String in ["yaw", "pitch"]:
		if not state.get(key) is float or not is_finite(state[key]):
			return false
	return state.get("sequence") is int and state["sequence"] >= 0 and state.get("jump") is int and state["jump"] in [0, 1] and state.get("epoch") is int and state["epoch"] >= 0


func _spawn_position(slot: int) -> Vector3:
	if campaign != null:
		return campaign.spawn_position + Vector3(float(slot % 2) * 0.7, 0.1, float(slot / 2) * 0.7)
	return Vector3(-2.25 + float(slot) * 1.5, 1.0, 7.0)


func _local_appearance() -> Dictionary:
	return get_node("/root/CharacterAppearance").call("make_replication_payload") as Dictionary


func _sanitize_appearance(payload: Dictionary) -> Dictionary:
	var appearance: Node = get_node("/root/CharacterAppearance")
	var profile: Dictionary = appearance.call("profile_from_replication_payload", payload)
	return appearance.call("make_replication_payload", profile) as Dictionary


func _input(event: InputEvent) -> void:
	var terminal: Node = get_node_or_null("PropsContainer/ShopTerminal")
	if terminal != null and bool(terminal.call("is_open")):
		return
	if event.is_action_pressed("ui_cancel") and not event.is_echo() and not players.is_empty():
		_set_menu_open(not _menu_open)
		get_viewport().set_input_as_handled()


func _set_menu_open(open: bool) -> void:
	if host_migration.active:
		open = true
	_menu_open = open
	_panel.visible = open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED
	var local_id: int = multiplayer.get_unique_id()
	if players.has(local_id):
		var player: CharacterBody3D = players[local_id]
		player.call("set_movement_locked", open or mission_phase != &"collecting")
		player.set_process_input(not open and player.is_alive())
		player.get_node("CameraHolder").set_process_input(not open and player.is_alive())
	_refresh_ui()


func _refresh_ui() -> void:
	if _status == null:
		return
	var active: bool = not players.is_empty() or _connecting
	if _migration_hint != null:
		var local_id: int = multiplayer.get_unique_id()
		if players.has(local_id) and not host_migration.active:
			var endpoint: Dictionary = host_migration.checkpoint.get("endpoints", {}).get(local_id, {})
			var hosting_port: int = int(_migration_port.value) if _migration_port.value > 0 else mini(65535, int(_port.value) + _slots[local_id] + 1)
			hosting_port = int(endpoint.get("port", hosting_port))
			_migration_hint.text = "Hosting UDP: %d" % int(_port.value) if multiplayer.is_server() else "Your hosting UDP: %d. Forward this port for internet migration." % hosting_port
		else:
			_migration_hint.text = "A replacement host needs a reachable IP and forwarded UDP port. Automatic port is shown after joining."
	_host_button.disabled = active
	_join_button.disabled = active
	_address.editable = not active
	_migration_address.editable = not active
	_migration_port.editable = not active
	_port.editable = not active
	_map_choice.disabled = active
	if _ready_button != null:
		_ready_button.visible = active and mission_phase == &"lobby"
		_start_button.visible = active and mission_phase == &"lobby" and multiplayer.is_server()
		_start_button.disabled = ready_players.is_empty() or ready_players.values().has(false)
		_name_entry.editable = not active
	_disconnect_button.visible = active
	_resume_button.visible = not players.is_empty()
	var local: CharacterBody3D = players.get(multiplayer.get_unique_id())
	var dead: bool = local != null and not local.is_alive()
	_respawn_button.visible = false
	_respawn_button.disabled = mission_phase != &"collecting"
	_resume_button.disabled = dead or mission_phase != &"collecting" or host_migration.active
	_team_label.text = "TEAM MONEY $%d · SCORE %d · DELIVERIES %d" % [team_money, team_score, deliveries]
	if _mission_label != null:
		_mission_label.text = "ROUND %d · %s · %s" % [mission_round, str(mission_phase).to_upper(), "SHIP REPAIRED — GATHER AT TERMINAL" if ship_repaired else "SELL SCRAP → REPAIR SHIP ($1000)"]
		if mission_round > 1:
			_mission_label.text += " · LAST ROUND: %d SALES" % last_round_deliveries
	if _results_panel != null:
		_results_panel.visible = mission_phase == &"departing" or mission_phase == &"failed"
		_results_label.text = "MISSION COMPLETE\n%d sales · $%d earned\nShip repaired. Departing together…" % [last_round_deliveries, last_round_money] if mission_phase == &"departing" else "TEAM LOST\n%d sales · $%d earned\nReturning to lobby. Run reset." % [last_round_deliveries, last_round_money]

	_shop_panel.visible = _menu_open and not players.is_empty() and mission_phase == &"collecting" and not host_migration.active
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
	_mission_label = Label.new()
	_mission_label.position = Vector2(24, 120)
	layer.add_child(_mission_label)
	_results_panel = PanelContainer.new()
	_results_panel.position = Vector2(430, 140)
	_results_panel.custom_minimum_size = Vector2(450, 180)
	layer.add_child(_results_panel)
	var results: VBoxContainer = VBoxContainer.new()
	_results_panel.add_child(results)
	_results_label = Label.new()
	_results_label.add_theme_font_size_override("font_size", 24)
	results.add_child(_results_label)
	_panel = PanelContainer.new()
	_panel.theme = SHIP_SHOP.HUD_THEME
	_panel.position = Vector2(24, 140)
	_panel.custom_minimum_size = Vector2(380, 0)
	layer.add_child(_panel)
	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	_panel.add_child(margin)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(340, clampf(get_viewport().get_visible_rect().size.y - 200.0, 280.0, 600.0))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var column: VBoxContainer = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 12)
	scroll.add_child(column)
	var title: Label = Label.new()
	title.text = session_title
	column.add_child(title)
	_name_entry = LineEdit.new()
	_name_entry.text = "ET"
	_name_entry.placeholder_text = "Your name"
	_name_entry.max_length = 24
	column.add_child(_name_entry)
	_roster_label = Label.new()
	column.add_child(_roster_label)
	_map_choice = OptionButton.new()
	_map_choice.add_item("Portal arena")
	_map_choice.add_item("Farm prototype")
	_map_choice.add_item("SP campaign - Orbit")
	_map_choice.select(2 if campaign != null else maxi(0, LEVEL_PATHS.find(scene_file_path)))
	_map_choice.item_selected.connect(func(index: int) -> void:
		if players.is_empty() and not _connecting:
			get_tree().change_scene_to_file(CAMPAIGN_SCENE if index == 2 else LEVEL_PATHS[index]))
	column.add_child(_map_choice)
	_address = LineEdit.new()
	_address.text = "127.0.0.1"
	_address.placeholder_text = "Host IP address"
	column.add_child(_address)
	_migration_address = LineEdit.new()
	_migration_address.placeholder_text = "Your hosting IP (optional; auto-detected)"
	column.add_child(_migration_address)
	_migration_port = SpinBox.new()
	_migration_port.max_value = 65535
	_migration_port.prefix = "Hosting UDP (0 = automatic): "
	column.add_child(_migration_port)
	_migration_hint = Label.new()
	_migration_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_migration_hint)
	var guidance: Label = Label.new()
	guidance.text = "Internet: host forwards the UDP port and allows Godot through the firewall. Guests use the host's public IP; on the same network, use its LAN IP."
	guidance.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(guidance)
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
	_ready_button = _button(column, "Toggle ready", set_ready)
	_start_button = _button(column, "Start expedition", start_expedition)
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


@rpc("authority", "call_remote", "reliable")
func _prepare_campaign_join(path: String, round_number: int) -> void:
	if campaign == null or not _connecting or path not in [campaign.FARM, campaign.COUNTRY]:
		return
	_commit_round(path, maxi(round_number, mission_round + 1))
	mission_round = round_number
	_on_connected()


func _set_campaign_load_timeout(loading: bool, target: int = 0) -> void:
	var peer: ENetMultiplayerPeer = multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	var connected: Array[int] = []
	if multiplayer.is_server():
		connected.assign(multiplayer.get_peers())
	else:
		connected.append(1)
	for id: int in connected:
		if target == 0 or target == id:
			var packet_peer: ENetPacketPeer = peer.get_peer(id)
			if packet_peer != null:
				packet_peer.set_timeout(32, 300000 if loading else 5000, 300000 if loading else 30000)


@rpc("any_peer", "call_remote", "reliable")
func _campaign_world_loaded(round_number: int) -> void:
	if multiplayer.is_server():
		_campaign_player_loaded(multiplayer.get_remote_sender_id(), round_number)


func _campaign_player_loaded(peer_id: int, round_number: int) -> void:
	if campaign == null or round_number != mission_round or not players.has(peer_id):
		return
	_campaign_loaded[peer_id] = true
	for id: int in players:
		if not _campaign_loaded.get(id, false):
			return
	campaign.loading_ready = true
	if mission_phase == &"loading":
		mission_phase = &"collecting"
		_begin_expedition()
	_publish_mission()
