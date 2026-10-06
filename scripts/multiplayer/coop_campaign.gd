extends Node

const ORBIT: String = "res://scenes/Space/Orbit.tscn"
const FARM: String = "res://scenes/world.tscn"
const COUNTRY: String = "res://scenes/CountryTown/CountryTown.tscn"
const ACTOR_SYNC: Script = preload("res://scripts/multiplayer/coop_actor_sync.gd")
const DOOR_SCRIPT: Script = preload("res://scripts/multiplayer/coop_door.gd")
const ENEMY_SCRIPT: Script = preload("res://scripts/multiplayer/network_farm_enemy.gd")
const LIGHT_SCRIPT: Script = preload("res://scripts/multiplayer/network_living_light.gd")
const GUARD: PackedScene = preload("res://scenes/Multiplayer/CoopGuard.tscn")
const RECOVERY_SHIP: Script = preload("res://scripts/multiplayer/coop_recovery_ship.gd")
const DELIVERY: Script = preload("res://scripts/multiplayer/coop_delivery_area.gd")
const PURSUIT: Script = preload("res://scripts/multiplayer/coop_pursuit.gd")
const DYNAMIC_SYNC: Script = preload("res://scripts/multiplayer/coop_dynamic_sync.gd")

var delivery: Node3D
var pursuit: Node3D
var loading_ready: bool = true
var session: Node3D
var world: Node3D
var spawn_position: Vector3 = Vector3.ZERO
var pending_destination: String = ""
var unlocked: PackedStringArray = PackedStringArray([FARM])
var rescue_accepted: bool = false
var discovered: bool = false
var objective: String = "Choose a mission at the ship console."
var title: String = "Orbital expedition"
var _doors: Array[Node3D] = []
var _clock: float = 0.0
var _ui: MissionSelectUI
var _dialogue: MissionDialogueUI
var _console: ConsoleButton
var _guide: MissionGiverNPC
var _crash_site: Node3D
var _ship: Node3D
var _ground_spawn: Vector3
var _arrival_remaining: float = 0.0
var _arrival_beam: ArrivalBeam
var _transport: Node3D
var _collected: Dictionary[StringName, bool] = {}


func load_world(path: String) -> void:
	delivery = null
	pursuit = null
	_transport = null
	_arrival_remaining = 0.0
	_arrival_beam = null
	_doors.clear()
	_collected.clear()
	_crash_site = null
	_console = null
	_guide = null
	_ui = null
	_dialogue = null
	_ship = null
	discovered = false
	world = (load(path) as PackedScene).instantiate() as Node3D
	world.set_script(null)
	world.name = "CampaignWorld"
	_prepare(world)
	session.add_child(world)
	var dungeon: Node3D = world.get_node_or_null("Dungeon") as Node3D
	var dungeon_door: Node3D = world.get_node_or_null("DungeonDoor") as Node3D
	if dungeon != null and dungeon_door != null:
		dungeon.set("generation_seed", 1337)
		dungeon.call("ensure_generated", dungeon_door.global_position)
		for candidate: Node in dungeon.find_children("*", "RigidBody3D", true, false):
			if candidate.has_method("is_available_for_abduction"):
				_convert_runtime_item(candidate as RigidBody3D)
	for item: Node in world.find_children("*", "RigidBody3D", true, false):
		if item.get_script() == session.SHARED_SCRAP_SCRIPT:
			session.register_shared_item(item as RigidBody3D)
	for body: Node in world.find_children("*", "RigidBody3D", true, false):
		if body.has_node("CoopSeats"):
			body.reparent(session.get_node("VehiclesContainer"))
	for node: Node in world.find_children("*", "Node3D", true, false):
		if node.get_script() in [ACTOR_SYNC, DYNAMIC_SYNC]:
			session.npcs[StringName(str(world.get_path_to(node)))] = node as Node3D
		elif node.has_method("make_network_state") and node.has_method("set_host_simulation"):
			session.npcs[StringName(str(world.get_path_to(node)))] = node as Node3D
	if path == ORBIT:
		_ship = world.get_node("AlienShip") as Node3D
		_ship.set("spin_speed", 0.0)
		spawn_position = _ship.get_node("SpawnPoint").global_position
		_console = _ship.get_node("ConsoleButton") as ConsoleButton
		_ui = world.get_node("MissionSelectUI") as MissionSelectUI
		_dialogue = world.get_node("MissionDialogue") as MissionDialogueUI
		_guide = _ship.get_node_or_null("MissionGiver") as MissionGiverNPC
		_console.activated.connect(_open_console)
		_ui.level_chosen.connect(_choose_level)
		_ui.closed.connect(_close_ui)
		_dialogue.accepted.connect(_accept_rescue)
		_dialogue.declined.connect(_close_ui)
		_dialogue.closed.connect(_close_ui)
		if _guide != null:
			_guide.activated.connect(_open_rescue)
		title = "Orbital expedition"
		objective = "Choose a mission at the ship console."
		_setup_services()
	else:
		_ground_spawn = spawn_position
		if path == COUNTRY:
			title = "Rescue mission"
			objective = "Locate the crash site."
			for marker: Node in world.find_children("AlienCrashSite", "Node3D", true, false):
				_crash_site = marker as Node3D
				break
			for ship: Node in world.find_children("*", "Node3D", true, false):
				if ship.get_script() == RECOVERY_SHIP:
					_ship = ship as Node3D
					break
			if _ship == null:
				var recovery_ship: Node3D = (load("res://scenes/Space/RecoveryShip.tscn") as PackedScene).instantiate() as Node3D
				recovery_ship.set_script(RECOVERY_SHIP)
				recovery_ship.set("session", session)
				recovery_ship.set("zone_path", NodePath("../RecoveryPoint/CollectionArea"))
				recovery_ship.position = (world.get_node("RecoveryPoint") as Node3D).position + Vector3.UP * 45.0
				world.add_child(recovery_ship)
				_ship = recovery_ship
		else:
			title = "Farm expedition"
			objective = "Collect scrap, repair the ship and return to orbit."
			_ship = world.get_node_or_null("SpaceShip") as Node3D
		_setup_services()
		if path == COUNTRY:
			_set_discovered(false)
			_guide = world.find_child("CrashSiteGuide", true, false) as MissionGiverNPC
			_dialogue = world.get_node_or_null("MissionDialogue") as MissionDialogueUI
			if _guide != null and _dialogue != null:
				_guide.activated.connect(_open_country_guide)
				_dialogue.closed.connect(_close_ui)
		_arrival_remaining = 5.0
		session.mission_phase = &"arriving"
		_arrival_beam = (load("res://scenes/FX/ArrivalBeam.tscn") as PackedScene).instantiate() as ArrivalBeam
		world.add_child(_arrival_beam)
		_arrival_beam.configure(_ground_spawn, 48.0)
	if _ship != null:
		_ship.set_process_unhandled_input(false)
		_ship.set_process_input(false)
		var interior: Node = _ship.get_node_or_null("Interior")
		if interior != null:
			interior.set_process(false)
			interior.set_process_input(false)
			interior.set_process_unhandled_input(false)
			if interior.has_signal("descend_requested"):
				interior.connect("descend_requested", request_return)


func _prepare(node: Node) -> void:
	for child: Node in node.get_children():
		if child.get_script() in [preload("res://scripts/multiplayer/coop_ship_shop.gd"), preload("res://scripts/multiplayer/revival_tank.gd")]:
			continue
		if child.get_script() == preload("res://scripts/player.gd") or child.name == &"PauseMenu" or child.name == &"PhotoAlertHUD":
			if child is Node3D and child.get_script() == preload("res://scripts/player.gd"):
				spawn_position = (child as Node3D).position
			node.remove_child(child)
			child.free()
			continue
		if child is Terrain3D and int(child.get("collision_mode")) == 4:
			# Full terrain coverage supports teammates splitting up, without editor collider nodes.
			child.set("collision_mode", 3)
		var script: Script = child.get_script() as Script
		var script_path: String = script.resource_path if script != null else ""
		if child is PursuitDirector or script_path.ends_with("delivery_area.gd"):
			var exports: Dictionary = {}
			for property: Dictionary in child.get_property_list():
				if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE and int(property.usage) & PROPERTY_USAGE_STORAGE:
					exports[property.name] = child.get(property.name)
			child.set_script(PURSUIT if child is PursuitDirector else DELIVERY)
			for key: String in exports:
				child.set(key, exports[key])
			child.set("session", session)
			if child.get_script() == PURSUIT:
				pursuit = child as Node3D
			else:
				delivery = child as Node3D
		elif child is RigidBody3D and child.has_method("is_available_for_abduction"):
			var item: RigidBody3D = child as RigidBody3D
			var properties: Dictionary = {}
			for key: StringName in [&"item_id", &"cash_value", &"score_value", &"display_name", &"two_handed", &"slot_cost", &"rejected_by_delivery"]:
				properties[key] = item.get(key)
			var definition: Resource = item.get("definition") as Resource if item is AlienTechnologyItem else null
			var id: StringName = StringName("sp/" + str(world.get_path_to(item)))
			item.set_script(session.SHARED_SCRAP_SCRIPT)
			for key: StringName in properties:
				item.set(key, properties[key])
			item.set("definition", definition)
			item.set("network_id", id)
		elif child is NPCActor:
			var sync: Node3D = Node3D.new()
			sync.name = "CoopSync"
			sync.set_script(ACTOR_SYNC)
			sync.set("session", session)
			child.add_child(sync)
		elif child is ShipCrewAlien:
			_add_dynamic_sync(child as Node3D)
		elif child is RigidBody3D:
			if child.has_method("_apply_driving_input") or child.has_method("_apply_aim_assist"):
				var seats: Node = Node.new()
				seats.name = "CoopSeats"
				seats.set_script(session.VEHICLE_SCRIPT)
				seats.set("plane", child.has_method("_apply_aim_assist"))
				child.add_child(seats)
			else:
				_add_dynamic_sync(child as Node3D)
		elif script_path.ends_with("smelly_farmer.gd") or script_path.ends_with("photographer.gd"):
			_prepare_enemy(child as CharacterBody3D, script_path.ends_with("photographer.gd"))
		elif script_path.ends_with("living_light.gd"):
			child.set_script(LIGHT_SCRIPT)
		elif script_path.ends_with("banana_trade.gd"):
			var rewards: Array[PackedScene] = child.get("rewards")
			child.set_script(session.BANANA_SCRIPT)
			child.set("rewards", rewards)
		elif child is HouseDoor:
			var values: Dictionary = {}
			for property: Dictionary in child.get_property_list():
				if int(property.usage) & PROPERTY_USAGE_STORAGE and str(property.name) not in ["script"]:
					values[property.name] = child.get(property.name)
			child.set_script(DOOR_SCRIPT)
			for key: StringName in values:
				child.set(key, values[key])
			_doors.append(child as Node3D)
		elif script_path.ends_with("ship_shop.gd"):
			# The session's shared terminal is installed after the world enters the tree.
			child.set_script(null)
		elif child is CharacterBody3D:
			_add_dynamic_sync(child as Node3D)
		elif script_path.ends_with("recovery_ship.gd"):
			child.set_script(RECOVERY_SHIP)
			child.set("session", session)
		elif script_path.ends_with("farm_scavenging.gd") or "/spider_bot/" in script_path:
			child.set_process(false)
			child.set_physics_process(false)
			child.set_process_input(false)
			child.set_process_unhandled_input(false)
		_prepare(child)


func _convert_runtime_item(item: RigidBody3D) -> void:
	var id: StringName = StringName("sp/" + str(world.get_path_to(item)))
	var parent: Node = item.get_parent()
	var pose: Transform3D = item.transform
	var properties: Dictionary = {}
	for key: StringName in [&"item_id", &"cash_value", &"score_value", &"display_name", &"two_handed", &"slot_cost", &"rejected_by_delivery"]:
		properties[key] = item.get(key)
	parent.remove_child(item)
	item.set_script(session.SHARED_SCRAP_SCRIPT)
	for key: StringName in properties:
		item.set(key, properties[key])
	item.set("network_id", id)
	item.request_ready()
	parent.add_child(item)
	item.transform = pose


func _add_dynamic_sync(body: Node3D) -> void:
	var sync: Node3D = Node3D.new()
	sync.name = "CoopSync"
	sync.set_script(DYNAMIC_SYNC)
	sync.set("session", session)
	body.add_child(sync)


func _prepare_enemy(enemy: CharacterBody3D, photographer: bool) -> void:
	var awareness: Node = enemy.get_node_or_null("EnemyAwareness")
	if awareness != null:
		enemy.remove_child(awareness)
		awareness.free()
	var brain: Node = GUARD.instantiate()
	for component_name: String in ["NPCVision", "NPCBehaviorTree"]:
		var component: Node = brain.get_node(component_name)
		brain.remove_child(component)
		enemy.add_child(component)
	brain.free()
	enemy.set_script(ENEMY_SCRIPT)
	enemy.set("photographer", photographer)
	enemy.set("activity_distance", 0.0)
	enemy.set("grounded", true)
	enemy.set("attack_range", 9.0 if photographer else 12.0)
	enemy.set("attack_interval", 6.0 if photographer else 2.0)


func _setup_services() -> void:
	var zone: Area3D = Area3D.new()
	zone.name = "DeliveryZone"
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.name = "Collision"
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(8, 4, 8)
	shape.shape = box
	zone.add_child(shape)
	zone.position = spawn_position + Vector3(0, 1, -6)
	if delivery != null:
		zone.position = delivery.global_position
	if session.scene_file_path == COUNTRY:
		var recovery_zone: Node3D = world.get_node_or_null("RecoveryPoint/CollectionArea") as Node3D
		if recovery_zone != null:
			zone.position = recovery_zone.global_position + Vector3.UP * 2.0
	session.add_child(zone)


func _local_player() -> CharacterBody3D:
	return session.players.get(multiplayer.get_unique_id()) as CharacterBody3D


func _open_console() -> void:
	var player: CharacterBody3D = _local_player()
	if player == null or not player.is_alive() or session.mission_phase != &"collecting":
		return
	player.set_movement_locked(true)
	_ui.session_unlocked_paths = unlocked
	_ui.open()


func _close_ui() -> void:
	var player: CharacterBody3D = _local_player()
	if player != null:
		player.set_movement_locked(session._menu_open or session.mission_phase != &"collecting")
	if _console != null:
		_console.set_armed(true)
	if _guide != null:
		_guide.set_armed(true)
		_guide.set_talking(false)


func _choose_level(level: LevelDefinition) -> void:
	_ui.close()
	if level.scene_path == COUNTRY:
		_open_rescue()
	else:
		choose_destination(level.scene_path)


func _open_rescue() -> void:
	var player: CharacterBody3D = _local_player()
	if player == null or not player.is_alive() or session.mission_phase != &"collecting":
		return
	player.set_movement_locked(true)
	if _guide != null:
		_guide.set_armed(false)
		_guide.set_talking(true)
	_dialogue.open("Crewmate", ["Recover the alien technology before the humans find it.", "Travel to Earth with the team now?"], "Travel", "Later")


func _accept_rescue() -> void:
	_dialogue.close()
	choose_destination(COUNTRY)


func _open_country_guide() -> void:
	var player: CharacterBody3D = _local_player()
	if player == null or not player.is_alive():
		return
	player.set_movement_locked(true)
	_guide.set_armed(false)
	_dialogue.open_information("Crewmate", [objective])


func choose_destination(path: String) -> void:
	if multiplayer.is_server():
		_choose_destination(multiplayer.get_unique_id(), path)
	else:
		_request_destination.rpc_id(1, path)


@rpc("any_peer", "call_remote", "reliable")
func _request_destination(path: String) -> void:
	if multiplayer.is_server():
		_choose_destination(multiplayer.get_remote_sender_id(), path)


func _choose_destination(peer_id: int, path: String) -> void:
	if session.host_migration.active or session.mission_phase != &"collecting" or session.scene_file_path != ORBIT or not unlocked.has(path) or not session.players.has(peer_id):
		return
	var player: CharacterBody3D = session.players[peer_id]
	if not player.is_alive() or player.global_position.distance_to(spawn_position) > 20.0:
		return
	for teammate: CharacterBody3D in session.players.values():
		if not teammate.is_alive() or teammate.global_position.distance_to(spawn_position) > 25.0:
			session._set_status("Gather the whole team aboard the ship before travel.")
			return
	rescue_accepted = rescue_accepted or path == COUNTRY
	pending_destination = path
	session.mission_phase = &"departing"
	session._departure_remaining = 4.0
	session._publish_mission()


func request_return() -> void:
	session.request_terminal_action(&"launch")


func advance() -> void:
	var path: String = pending_destination if session.scene_file_path == ORBIT else ORBIT
	if path.is_empty():
		return
	session._commit_round.rpc(path, session.mission_round + 1)
	session._commit_round(path, session.mission_round + 1)
	session._publish_mission()
	session._publish_economy()


func _physics_process(delta: float) -> void:
	if world == null or session.host_migration.active:
		return
	if _guide != null:
		_guide.set("_player", _local_player())
	if session.scene_file_path == ORBIT:
		var player: CharacterBody3D = _local_player()
		if player != null:
			_ship.call("set_player_inside", player, true)
		if session.mission_phase == &"departing":
			var earth: Node3D = world.get_node_or_null("SkyRotation/Earth") as Node3D
			if earth != null:
				earth.position.z = lerpf(earth.position.z, -260.0, delta * 0.8)
	else:
		if session.mission_phase == &"arriving" and loading_ready:
			_arrival_remaining = maxf(0.0, _arrival_remaining - delta)
			var height: float = 45.0 * smoothstep(0.0, 1.0, _arrival_remaining / 5.0)
			for id: int in session.players:
				var player: CharacterBody3D = session.players[id]
				player.set_meta("coop_arrival", true)
				player.global_position = session._spawn_position(session._slots[id]) + Vector3.UP * height
				player.velocity = Vector3.ZERO
				player.call("_update_camera_target")
			if _arrival_remaining <= 0.0 and multiplayer.is_server():
				session.mission_phase = &"collecting"
				for npc: Node3D in session.npcs.values():
					npc.set_host_simulation(true)
				session._publish_mission()
		if multiplayer.is_server() and session.scene_file_path == COUNTRY and not discovered and _crash_site != null:
			for player: CharacterBody3D in session.players.values():
				if player.is_alive() and player.global_position.distance_to(_crash_site.global_position) <= 14.0:
					_set_discovered(true)
					objective = "Recover the debris and deliver it at the recovery point."
					session._publish_mission()
					break
	if multiplayer.is_server():
		_clock += delta
		if _clock >= 0.1 and not session.players.is_empty():
			_clock = 0.0
			_receive_doors.rpc(_door_states())
			if _ship != null and _ship.get_script() == RECOVERY_SHIP:
				_receive_recovery_visual.rpc(_ship.global_transform, is_instance_valid(_ship._cargo))


@rpc("authority", "call_remote", "unreliable_ordered", 7)
func _receive_recovery_visual(pose: Transform3D, beam_visible: bool) -> void:
	if _ship != null and _ship.get_script() == RECOVERY_SHIP:
		_ship.global_transform = pose
		_ship.call("_set_tractor_beam", beam_visible)


func _set_discovered(value: bool) -> void:
	discovered = value
	for item: RigidBody3D in session.items.values():
		if item.is_in_group("alien_debris") and not item.carried and not item.network_consumed and (item.definition == null or not item.definition.is_locator):
			item.call("set_discovered", value)


func _door_states() -> Dictionary:
	var result: Dictionary = {}
	for door: Node3D in _doors:
		result[str(world.get_path_to(door))] = [door.leaf.rotation.y, door.locked, door._target]
	return result


@rpc("authority", "call_remote", "unreliable_ordered", 5)
func _receive_doors(states: Dictionary) -> void:
	for path: String in states:
		var door: Node = world.get_node_or_null(NodePath(path))
		if door != null:
			door.call("_receive_state", states[path][0], states[path][1])
			door.set("_target", states[path][2])


func capture() -> Dictionary:
	var quests: Dictionary = {}
	for trade: Node in world.find_children("*", "Node", true, false):
		if trade.get_script() == session.BANANA_SCRIPT:
			quests[str(world.get_path_to(trade))] = {"accepted": trade.accepted, "completed": trade.completed, "reward": trade._reward_path, "item": trade._consumed_id}
	var recovery_state: Dictionary = {}
	if _ship != null and _ship.get_script() == RECOVERY_SHIP:
		recovery_state = {"pose": _ship.global_transform, "cargo": _ship._cargo.network_id if is_instance_valid(_ship._cargo) else &""}
	return {"destination": pending_destination, "unlocked": unlocked, "rescue": rescue_accepted,
		"discovered": discovered, "title": title, "objective": objective,
		"doors": _door_states(), "collected": _collected.duplicate(), "assets": session.portable_assets.duplicate(true), "recovery": recovery_state, "quests": quests, "arrival": _arrival_remaining, "ready": loading_ready, "pursuit": pursuit.make_migration_state() if pursuit != null else {}, "delivery": delivery.make_migration_state() if delivery != null else {}}


func restore(state: Dictionary) -> void:
	loading_ready = bool(state.get("ready", true))
	_arrival_remaining = float(state.get("arrival", 0.0))
	pending_destination = state.destination
	unlocked = state.unlocked
	rescue_accepted = state.rescue
	title = state.title
	objective = state.objective
	if session.scene_file_path == ORBIT and session.mission_phase == &"departing" and pending_destination == COUNTRY:
		_board_rescue_transport()
	if session.mission_phase == &"collecting":
		for player: CharacterBody3D in session.players.values():
			if player.has_meta("coop_arrival"):
				player.remove_meta("coop_arrival")
				player.set_movement_locked(session._menu_open if player.is_local_player() else false)
		if is_instance_valid(_arrival_beam):
			_arrival_beam.fade_out(0.35)
			_arrival_beam = null
	for path: String in state.get("quests", {}):
		var trade: Node = world.get_node_or_null(NodePath(path))
		if trade != null:
			var quest: Dictionary = state.quests[path]
			trade.call("_receive_state", quest.accepted, quest.completed, quest.reward, quest.get("item", &"banana_box"))
	session.portable_assets.assign(state.get("assets", {}))
	for id: StringName in session.portable_assets:
		if not session.items.has(id):
			var asset: Dictionary = session.portable_assets[id]
			session.spawn_shared_asset(id, asset.path, spawn_position)
	if delivery != null and not state.get("delivery", {}).is_empty():
		if multiplayer.is_server():
			if session.host_migration.is_restoring:
				delivery.restore_migration_state(state.delivery)
		else:
			delivery.receive_network_state(state.delivery)
	if pursuit != null and not state.get("pursuit", {}).is_empty():
		if multiplayer.is_server():
			if session.host_migration.is_restoring:
				pursuit.restore_migration_state(state.pursuit)
		else:
			pursuit.receive_network_state(state.pursuit)
	_set_discovered(state.discovered)
	_collected.assign(state.get("collected", {}))
	for id: StringName in _collected:
		if session.items.has(id):
			var item: RigidBody3D = session.items[id]
			item.network_consumed = true
			item.hide()
			item.freeze = true
			item.collision_layer = 0
			item.collision_mask = 0
	_receive_doors(state.doors)
	if _ship != null and _ship.get_script() == RECOVERY_SHIP and not state.get("recovery", {}).is_empty():
		_ship.global_transform = state.recovery.pose
		_ship._cargo = session.items.get(state.recovery.cargo)
		if _ship._cargo != null:
			_ship._cargo.being_abducted = true


func _board_rescue_transport() -> void:
	if _transport != null:
		return
	_transport = (load("res://scenes/Space/MissionSaucer.tscn") as PackedScene).instantiate() as Node3D
	_transport.position = Vector3(110, 25, -10)
	world.add_child(_transport)
	_transport.set_physics_process(false)
	var spawn: Node3D = _transport.get_node("SpawnPoint") as Node3D
	for id: int in session.players:
		var player: CharacterBody3D = session.players[id]
		player.set_meta("coop_arrival", true)
		player.global_position = spawn.global_position + Vector3(float(session._slots[id]) * 0.5, 0, 0)
		player.velocity = Vector3.ZERO
		player.camera_yaw = _transport.rotation.y - player.camera_pivot.spring_arm.rotation.y
		player.camera_pitch = 0.0
		if player.is_local_player():
			player.set_first_person(true)
		player.camera_pivot.set_interior_camera_mode(true)
		player.call("_update_camera_target")
	_transport.call("begin_approach_audio", session._departure_remaining)


func deliver(id: StringName) -> bool:
	var item: RigidBody3D = session.items[id]
	if item.network_consumed or (item.definition != null and item.definition.is_locator):
		return false
	_collected[id] = true
	item.network_consumed = true
	item.hide()
	item.freeze = true
	item.collision_layer = 0
	item.collision_mask = 0
	return true


func reset_progress() -> void:
	unlocked = PackedStringArray([FARM])
	rescue_accepted = false
	pending_destination = ""
