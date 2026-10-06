extends "res://scripts/pursuit_director.gd"

const ACTOR_SYNC: Script = preload("res://scripts/multiplayer/coop_actor_sync.gd")
const ALERT_SCRIPT: Script = preload("res://scripts/photo_alert_system.gd")
var session: Node3D
var _host: bool = false
var _next_unit: int = 0


func _ready() -> void:
	_alert = Node.new()
	_alert.name = "TeamAlert"
	_alert.set_script(ALERT_SCRIPT)
	add_child(_alert)
	_alert.stars_per_theft = stars_per_theft
	_alert.stars_per_photo = stars_per_photo
	_alert.hidden_seconds_per_star = hidden_seconds_per_star
	_alert.photo_count_changed.connect(_on_level_changed)
	_alert.incident_reported.connect(_on_incident)
	_spawn_shape = CapsuleShape3D.new()
	_spawn_shape.radius = 0.35
	_spawn_shape.height = 1.9
	set_host_simulation(false)


func set_host_simulation(enabled: bool) -> void:
	_host = enabled
	set_physics_process(enabled)
	_alert.set_process(enabled)



func _physics_process(delta: float) -> void:
	var nearest: float = INF
	_player = null
	for candidate: CharacterBody3D in session.players.values():
		if not candidate.is_alive():
			continue
		var distance: float = candidate.global_position.distance_squared_to(_last_reported_position) if _last_reported_position.is_finite() else float(session._slots[candidate.get_multiplayer_authority()])
		if distance < nearest:
			nearest = distance
			_player = candidate
	if _player == null:
		_alert.reset()
		return
	for node: Node3D in session.npcs.values():
		if node.get("photographer") == true and node.get("vision") != null:
			_alert.set_photographer_observing(node.get_instance_id(), node.vision.is_currently_visible)
	super._physics_process(delta)


func report_theft(item: RigidBody3D, player: CharacterBody3D) -> void:
	if _host and player.is_alive():
		_player = player
		_alert.register_theft(item, player.global_position)


func report_photo(source: Node3D, player: CharacterBody3D) -> void:
	if _host and player.is_alive():
		_player = player
		_alert.register_photo(source.get_instance_id(), player.global_position)


func _spawn_wave(profile: PursuitProfile, replacement: bool = false) -> int:
	var previous: Array[PursuitNPC] = active_enemies.duplicate()
	var count: int = super._spawn_wave(profile, replacement)
	for npc: PursuitNPC in active_enemies:
		if not previous.has(npc):
			npc.name = "Pursuer_%d" % _next_unit
			_next_unit += 1
			_attach_sync(npc)
	return count


func _attach_sync(npc: PursuitNPC) -> void:
	var sync: Node3D = Node3D.new()
	sync.name = "CoopSync"
	sync.set_script(ACTOR_SYNC)
	sync.set("session", session)
	npc.add_child(sync)
	session.npcs[StringName("pursuit/" + str(npc.name))] = sync
	sync.call_deferred("set_host_simulation", _host)


func _on_enemy_exiting(npc: PursuitNPC) -> void:
	session.npcs.erase(StringName("pursuit/" + str(npc.name)))
	super._on_enemy_exiting(npc)


func make_network_state() -> Dictionary:
	var units: Dictionary = {}
	for npc: PursuitNPC in active_enemies:
		if is_instance_valid(npc) and not npc.is_queued_for_deletion():
			units[str(npc.name)] = {"profile": npc.profile.resource_path, "pose": npc.global_transform}
	return {"units": units, "stars": _alert.photo_count, "hidden": _alert.hidden_time, "next": _next_unit}


func receive_network_state(state: Dictionary) -> void:
	if not _host:
		_restore_units(state)


func _restore_units(state: Dictionary) -> void:
	_next_unit = int(state.next)
	_alert._set_photo_count(int(state.stars))
	_alert.hidden_time = float(state.hidden)
	for npc: PursuitNPC in active_enemies.duplicate():
		if not state.units.has(str(npc.name)):
			_retire(npc)
	for unit_name: String in state.units:
		if _units.has_node(NodePath(unit_name)):
			continue
		var record: Dictionary = state.units[unit_name]
		var npc: PursuitNPC = agent_scene.instantiate() as PursuitNPC
		npc.name = unit_name
		npc.profile = load(record.profile) as PursuitProfile
		_units.add_child(npc)
		npc.global_transform = record.pose
		active_enemies.append(npc)
		npc.tree_exiting.connect(_on_enemy_exiting.bind(npc), CONNECT_ONE_SHOT)
		_attach_sync(npc)
		if _host:
			npc.navigation_agent.set_navigation_map(navigation.get_navigation_map())


func make_migration_state() -> Dictionary:
	var state: Dictionary = make_network_state()
	var queue: Array[Dictionary] = []
	for request: RespawnRequest in _respawn_queue:
		queue.append({"profile": request.profile.resource_path, "remaining": request.remaining})
	var thefts: Array[StringName] = []
	for id: StringName in session.items:
		if _alert._reported_thefts.has(session.items[id].get_instance_id()):
			thefts.append(id)
	state.merge({"last": _last_reported_position, "reinforce": _reinforcement_timer,
		"respawn": _respawn_timer, "queue": queue, "thefts": thefts})
	return state


func restore_migration_state(state: Dictionary) -> void:
	_restore_units(state)
	_last_reported_position = state.get("last", Vector3.INF)
	_reinforcement_timer = float(state.get("reinforce", initial_response_delay))
	_respawn_timer = float(state.get("respawn", 0.0))
	_respawn_queue.clear()
	for record: Dictionary in state.get("queue", []):
		_respawn_queue.append(RespawnRequest.new(load(record.profile) as PursuitProfile, record.remaining))
	_alert._reported_thefts.clear()
	for id: StringName in state.get("thefts", []):
		if session.items.has(id):
			_alert._reported_thefts[session.items[id].get_instance_id()] = true


func _on_level_changed(level: int, maximum: int) -> void:
	if not _host:
		return
	if level > 0 and _player == null:
		for candidate: CharacterBody3D in session.players.values():
			if candidate.is_alive():
				_player = candidate
				break
		if _player == null:
			return
	super._on_level_changed(level, maximum)
