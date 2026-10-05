extends "res://scripts/delivery_area.gd"

var session: Node3D
var _host: bool = false
var _signals: Dictionary[int, int] = {}
var _heartbeat: float = 0.0


func set_host_simulation(enabled: bool) -> void:
	_host = enabled


func request_signal(held: bool) -> void:
	var id: int = multiplayer.get_unique_id()
	if not session.players.has(id):
		return
	if multiplayer.is_server():
		_accept_signal(id, held, session.players[id].life_generation)
	else:
		_signal.rpc_id(1, held, session.players[id].life_generation)


@rpc("any_peer", "call_remote", "reliable")
func _signal(held: bool, generation: int) -> void:
	if multiplayer.is_server():
		_accept_signal(multiplayer.get_remote_sender_id(), held, generation)


func _accept_signal(id: int, held: bool, generation: int) -> void:
	if not session.players.has(id) or session.players[id].life_generation != generation:
		return
	if held and session.players[id].is_alive() and _nearby_characters.has(session.players[id]) and session.mission_phase == &"collecting":
		_signals[id] = Time.get_ticks_msec()
	else:
		_signals.erase(id)


func _process(delta: float) -> void:
	if session.host_migration.active or session.mission_phase != &"collecting":
		prompt_root.hide()
		return
	_cleanup_tracked_bodies()
	var id: int = multiplayer.get_unique_id()
	var local: CharacterBody3D = session.players.get(id) as CharacterBody3D
	var available: RigidBody3D = _find_available_item()
	var nearby: bool = local != null and local.is_alive() and _nearby_characters.has(local)
	prompt_root.visible = nearby and (available != null or _state == DeliveryState.CHARGING)
	if prompt_root.visible:
		_update_key_icon()
		if _state == DeliveryState.CHARGING:
			_update_charge_prompt()
		else:
			_update_waiting_prompt()
	_heartbeat += delta
	if _heartbeat >= 0.1:
		_heartbeat = 0.0
		request_signal(nearby and not session._menu_open and Input.is_action_pressed("request_abduction"))
	if not _host:
		return
	if _state == DeliveryState.ABDUCTING:
		_state_elapsed += delta
		_update_abduction(delta)
		return
	if _automatic_request and _state == DeliveryState.CHARGING:
		_update_automatic_charge(delta)
		return
	var signaling: CharacterBody3D = null
	for peer: int in _signals:
		if Time.get_ticks_msec() - _signals[peer] <= 600 and session.players.has(peer) and session.players[peer].is_alive() and _nearby_characters.has(session.players[peer]):
			signaling = session.players[peer]
			break
	if signaling == null or available == null:
		_cancel_charge()
		return
	if _state == DeliveryState.IDLE:
		_begin_charge(available, signaling)
	if not _is_charge_still_valid():
		_cancel_charge()
		return
	_state_elapsed = minf(_state_elapsed + delta, signal_hold_duration)
	_update_signal_effect()
	_update_ufo_approach()
	if _state_elapsed >= signal_hold_duration:
		_complete_charge()


func _prepare_ufo_approach() -> void:
	_ufo = _find_ufo()
	if _ufo == null:
		return
	_ufo_start_position = _ufo.global_position
	if _ufo.has_method("begin_external_movement"):
		_ufo.call("begin_external_movement")
	_ufo_target_position = Vector3(abduction_origin.global_position.x, _ufo_start_position.y, abduction_origin.global_position.z)
	if _ufo.has_method("configure_external_beam"):
		_ufo.call("configure_external_beam", beam_spotlight, beam_ground_light, beam_volume)
	_beam_base_energy = beam_spotlight.light_energy
	_beam_ground_base_energy = beam_ground_light.light_energy


func _credit_delivery(item: RigidBody3D, _score: int) -> void:
	session.credit_shared_delivery(item)


func make_network_state() -> Dictionary:
	var cargo: Array[StringName] = []
	for item: RigidBody3D in _abduction_items:
		if is_instance_valid(item):
			cargo.append(item.network_id)
	return {"state": _state, "elapsed": _state_elapsed, "target": _signaling_character.get_multiplayer_authority() if is_instance_valid(_signaling_character) else 0,
		"item": _target_item.network_id if is_instance_valid(_target_item) else &"", "cargo": cargo,
		"ship_active": is_instance_valid(_ufo), "ship": _ufo.global_transform if is_instance_valid(_ufo) else Transform3D.IDENTITY}


func receive_network_state(state: Dictionary) -> void:
	if _host:
		return
	_set_character_signal_pose(false)
	_state = state.state
	_state_elapsed = state.elapsed
	_signaling_character = session.players.get(state.target) as CharacterBody3D
	_set_character_signal_pose(_state == DeliveryState.CHARGING)
	_target_item = session.items.get(state.item) as RigidBody3D
	_ufo = _find_ufo()
	if _ufo != null and state.get("ship_active", false):
		_ufo.global_transform = state.ship
		var action: String = "begin_external_movement" if _state != DeliveryState.IDLE else "end_external_movement"
		if _ufo.has_method(action):
			_ufo.call(action)
	signal_marker.visible = _state == DeliveryState.CHARGING
	abduction_beam.visible = _state == DeliveryState.ABDUCTING
	interference_source.set_interference_enabled(_state != DeliveryState.IDLE)
	if _state == DeliveryState.CHARGING:
		_update_signal_effect()
	elif _state == DeliveryState.ABDUCTING:
		_configure_beam()


func make_migration_state() -> Dictionary:
	var state: Dictionary = make_network_state()
	state.merge({"starts": _abduction_start_positions.duplicate(), "start": _ufo_start_position,
		"destination": _ufo_target_position, "automatic": _automatic_request})
	return state


func restore_migration_state(state: Dictionary) -> void:
	var was_host: bool = _host
	_host = false
	receive_network_state(state)
	_host = was_host
	_abduction_start_positions.assign(state.starts)
	_ufo_start_position = state.start
	_ufo_target_position = state.destination
	_automatic_request = state.automatic
	_abduction_items.clear()
	for id: StringName in state.cargo:
		var item: RigidBody3D = session.items.get(id) as RigidBody3D
		if item != null and not item.network_consumed:
			_abduction_items.append(item)
			item.being_abducted = true
			item.freeze = true
			item.collision_layer = 0
			item.collision_mask = 0
	if _signaling_character != null:
		_signals[_signaling_character.get_multiplayer_authority()] = Time.get_ticks_msec()


func _find_ufo() -> Node3D:
	for node: Node in get_tree().get_nodes_in_group(&"ufo_lighting"):
		if node is Node3D and session.campaign.world.is_ancestor_of(node):
			return node as Node3D
	return null


func _start_abduction() -> void:
	if _abduction_items.is_empty() and is_instance_valid(_target_item):
		_abduction_items.append(_target_item)
		_abduction_start_positions.append(_target_item.global_position)
	super._start_abduction()


func _cleanup_tracked_bodies() -> void:
	super._cleanup_tracked_bodies()
	for item: RigidBody3D in _candidate_items.duplicate():
		if session.recovery.victims.has(item.network_id):
			_candidate_items.erase(item)
