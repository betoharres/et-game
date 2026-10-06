extends Node3D

var session: Node3D
var _actor: NPCActor
var _target: Transform3D
var _has_pose: bool = false
var _host: bool = false
var _simulating: bool = false
# Identical scene assets give every peer the same mesh order without repeating paths.
var _appearance_meshes: Array[MeshInstance3D] = []


func _ready() -> void:
	if session == null:
		var ancestor: Node = get_parent()
		while ancestor != null and not ancestor.has_method("damage_player"):
			ancestor = ancestor.get_parent()
		session = ancestor as Node3D
	_actor = get_parent() as NPCActor
	if _actor.is_node_ready():
		_initialize_actor()
	else:
		_actor.ready.connect(_initialize_actor, CONNECT_ONE_SHOT)


func _initialize_actor() -> void:
	for mesh: Node in _actor.find_children("*", "MeshInstance3D", true, false):
		_appearance_meshes.append(mesh as MeshInstance3D)
	if session == null:
		_apply_simulation(false)
		return
	process_physics_priority = -1
	if _actor._activity_timer != null:
		_actor._activity_timer.stop()
	var alerts: Node = get_node_or_null("/root/PhotoAlertSystem")
	if alerts != null and alerts.photo_count_changed.is_connected(_actor._on_photo_count_changed):
		alerts.photo_count_changed.disconnect(_actor._on_photo_count_changed)
	if session.campaign != null and session.campaign.pursuit != null:
		session.campaign.pursuit._alert.photo_count_changed.connect(_actor._on_photo_count_changed)
	var combat: Node = _actor.get_node_or_null("NPCCombat")
	if combat != null and combat.has_signal("shot_fired"):
		combat.connect("shot_fired", _on_shot_fired)
	set_host_simulation(false)


func set_host_simulation(enabled: bool) -> void:
	_host = enabled
	_apply_simulation(enabled)
	_actor.player = null
	if _actor.vision != null:
		_actor.vision.player = null


func _apply_simulation(enabled: bool) -> void:
	_simulating = enabled
	_actor.set_physics_process(enabled)
	for node: Node in _actor.find_children("*", "BeehaveTree", true, false):
		node.set("enabled", enabled)
	for child: Node in [_actor.vision, _actor.hearing, _actor.routine]:
		if child != null:
			child.process_mode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED
	_actor.navigation_agent.avoidance_enabled = enabled and _actor.require_navigation
	var combat: Node = _actor.get_node_or_null("NPCCombat")
	if combat != null:
		combat.set_physics_process(enabled)


func _physics_process(_delta: float) -> void:
	if not _host:
		if _has_pose:
			_actor.global_transform = _actor.global_transform.interpolate_with(_target, 0.3)
		return
	var near_team: bool = _actor.activity_distance <= 0.0
	var nearest: float = INF
	var selected: CharacterBody3D = null
	for candidate: CharacterBody3D in session.players.values():
		if not candidate.is_alive():
			continue
		var distance: float = _actor.global_position.distance_squared_to(candidate.global_position)
		if distance <= _actor.activity_distance * _actor.activity_distance:
			near_team = true
		if _actor.activity_distance > 0.0 and distance > _actor.activity_distance * _actor.activity_distance:
			continue
		if _actor.vision != null:
			_actor.vision.player = candidate
		if distance < nearest and (_actor.vision == null or _actor.vision._can_see_player()):
			selected = candidate
			nearest = distance
	if near_team != _simulating:
		_apply_simulation(near_team)
		if not near_team and _actor.vision != null:
			_actor.vision.suspend_contact()
	if selected == null and is_instance_valid(_actor.player) and _actor.player.is_alive():
		selected = _actor.player
	if selected != _actor.player and _actor.vision != null:
		_actor.vision.suspend_contact()
	_actor.player = selected
	if _actor.vision != null:
		_actor.vision.player = selected


func make_network_state() -> Dictionary:
	var meshes: PackedByteArray = PackedByteArray()
	for mesh: MeshInstance3D in _appearance_meshes:
		meshes.append(1 if is_instance_valid(mesh) and mesh.visible else 0)
	var combat: Node = _actor.get_node_or_null("NPCCombat")
	return {"health": float(combat.health) if combat != null else -1.0, "pose": _actor.global_transform, "velocity": _actor.velocity, "state": _actor.state, "meshes": meshes, "target": _actor.player.get_multiplayer_authority() if is_instance_valid(_actor.player) else 0}


func receive_network_state(state: Dictionary) -> void:
	if _host:
		return
	_target = state.pose
	if not _has_pose:
		_actor.global_transform = _target
	_has_pose = true
	_actor.velocity = state.velocity
	_actor.set_state(state.state)
	var combat: Node = _actor.get_node_or_null("NPCCombat")
	if combat != null:
		combat.health = float(state.get("health", combat.health))
	var meshes: Variant = state.get("meshes", PackedByteArray())
	if meshes is PackedByteArray and meshes.size() == _appearance_meshes.size():
		for index: int in _appearance_meshes.size():
			if is_instance_valid(_appearance_meshes[index]):
				_appearance_meshes[index].visible = meshes[index] != 0


func make_migration_state() -> Dictionary:
	var state: Dictionary = make_network_state()
	if _actor.vision != null:
		state["vision"] = {"detected": _actor.vision.has_detected_player, "progress": _actor.vision.detection_progress,
			"lost": _actor.vision.time_since_lost, "last": _actor.vision.last_seen_position,
			"has_last": _actor.vision.has_last_seen_position, "alerted": _actor.vision._alerted}
	var combat: Node = _actor.get_node_or_null("NPCCombat")
	if combat != null:
		state["combat"] = {"cooldown": combat._cooldown, "aim": combat._aim_elapsed, "burst": combat._burst_shots}
	return state


func restore_migration_state(state: Dictionary) -> void:
	_actor.global_transform = state.pose
	_actor.velocity = state.velocity
	_actor.set_state(state.state)
	var combat: Node = _actor.get_node_or_null("NPCCombat")
	if combat != null:
		combat.health = float(state.get("health", combat.health))
	_actor.player = session.players.get(int(state.get("target", 0))) as CharacterBody3D
	if _actor.vision != null and state.has("vision"):
		_actor.vision.player = _actor.player
		_actor.vision.has_detected_player = state.vision.detected and _actor.player != null
		_actor.vision.detection_progress = state.vision.progress
		_actor.vision.time_since_lost = state.vision.lost
		_actor.vision.last_seen_position = state.vision.last
		_actor.vision.has_last_seen_position = state.vision.has_last
		_actor.vision.set_alerted(state.vision.alerted)
	if combat != null and state.has("combat"):
		combat._cooldown = state.combat.cooldown
		combat._aim_elapsed = state.combat.aim
		combat._burst_shots = state.combat.burst


func _on_shot_fired(end: Vector3) -> void:
	if _host:
		_receive_shot.rpc(end)


@rpc("authority", "call_remote", "unreliable")
func _receive_shot(end: Vector3) -> void:
	if not end.is_finite():
		return
	var combat: Node = _actor.get_node_or_null("NPCCombat")
	if combat != null:
		combat._appearance.show_shot(end)
		combat._audio.play()
