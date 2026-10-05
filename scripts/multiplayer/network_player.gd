extends "res://scripts/player.gd"

var _target_transform: Transform3D
var _has_snapshot: bool = false
var _portal_epoch: int = 0
var _remote_epoch: int = -1
var _remote_on_floor: bool = true
var life_generation: int = 0
var _combat_revision: int = -1
var _snapshot_sequence: int = 0
var _remote_sequence: int = -1
var _applying_damage: bool = false
var _noise_sequence: int = 0
var _reaction_sequence: int = 0
var _remote_reaction_sequence: int = -1
var _last_reaction: Array = [0, Vector3.ZERO, 1.0]
var _get_up_face_up: bool = false
var _remote_binos: bool = false
var _host_stealth_alert: float = 0.0
var _network_noises: Array[float] = []


func queue_network_noise(decibels: float) -> void:
	if _network_noises.size() < 16:
		_network_noises.append(decibels)


func _trigger_impact_reaction(direction: Vector3, reaction: ImpactReaction, fall_strength: float = 1.0) -> void:
	if is_local_player():
		_reaction_sequence += 1
		_last_reaction = [int(reaction), direction, fall_strength]
	super._trigger_impact_reaction(direction, reaction, fall_strength)


func _begin_stand_up() -> void:
	_get_up_face_up = ragdoll.is_face_up()
	super._begin_stand_up()


func _receive_visual_state(state: Dictionary) -> void:
	var fall: int = state.fall
	if fall != _fall_state:
		if fall == FallState.FALLEN:
			animation_controller.set_ragdoll_active(true)
		elif fall == FallState.STANDING_UP:
			animation_controller.begin_get_up(state.face_up)
		else:
			ragdoll.finish_network_pose()
			animation_controller.set_ragdoll_active(false)
			animation_controller.finish_get_up()
		collision_shape.set_deferred("disabled", fall == FallState.FALLEN)
		_fall_state = fall
	if fall == FallState.FALLEN:
		ragdoll.apply_network_pose(state.pose)
	elif fall == FallState.STANDING_UP:
		ragdoll.apply_recovery(state.recovery)
	if state.reaction_sequence > _remote_reaction_sequence:
		_remote_reaction_sequence = state.reaction_sequence
		var reaction: Array = state.reaction
		if fall == FallState.NONE and reaction[0] == ImpactReaction.STUMBLE:
			animation_controller.trigger_stumble(reaction[1])
	binos_active_visual(state.binos)


func binos_active_visual(active: bool) -> void:
	# Remote goggles are a visual state; their rigs must never swap world materials.
	_remote_binos = active and not predator_cloak_active
	_update_predator_cloak_visuals()


func restore_motion_visual(state: Dictionary) -> void:
	_receive_visual_state(state)
	_fall_timer = float(state.get("fall_time", 0.0))
	_stand_up_elapsed = float(state.get("stand_time", 0.0))
	if is_local_player() and _fall_state == FallState.FALLEN:
		ragdoll.start_comic_fall(Vector3.ZERO, 0.2)
	if is_local_player() and state.binos and can_use_xray_goggles() and is_alive() and not predator_cloak_active:
		camera_pivot.activate_binos()


func _update_predator_cloak_visuals() -> void:
	super._update_predator_cloak_visuals()
	if not is_local_player() and is_instance_valid(farsight_goggles_mesh):
		farsight_goggles_mesh.visible = _remote_binos and is_alive() and not predator_cloak_active
		energy_shield_mesh.visible = energy_shield_mesh.visible and not _remote_binos
		predator_watch_mesh.visible = predator_watch_mesh.visible and not _remote_binos


func debug_add_team_money() -> void:
	get_parent().get_parent().call("debug_add_team_money")


func toggle_predator_cloak() -> void:
	if not is_local_player() or camera_pivot.binos_active:
		return
	get_parent().get_parent().call("request_cloak_toggle")


func apply_host_cloak_toggle() -> void:
	if _remote_binos:
		return
	super.toggle_predator_cloak()


func _update_predator_cloak(_delta: float) -> void:
	return


func _is_in_level_atmosphere() -> bool:
	return false


func _update_oxygen_display() -> void:
	if not is_instance_valid(_oxygen_hud):
		return
	var seconds: float = float(get_parent().get_parent().get("team_radon"))
	_oxygen_hud.text = "TEAM RADON %02d:%02d" % [floori(seconds / 60.0), floori(fmod(seconds, 60.0))]


func take_damage(amount: float, hit_direction: Vector3 = Vector3.ZERO, push_distance: float = 0.0) -> void:
	var session: Node = get_parent().get_parent()
	if multiplayer.is_server():
		session.call("damage_player", get_multiplayer_authority(), amount, hit_direction, push_distance)


func apply_host_damage(amount: float, direction: Vector3, push: float) -> void:
	_applying_damage = true
	super.take_damage(amount, direction, push)
	_applying_damage = false


func _die(direction: Vector3 = Vector3.ZERO) -> void:
	if not _applying_damage:
		return
	var mouse_mode: Input.MouseMode = Input.mouse_mode
	super._die(direction)
	if not is_local_player():
		Input.mouse_mode = mouse_mode


func _update_energy_shield(delta: float) -> void:
	# Shield recovery belongs to the host, including for remote players.
	if _applying_damage:
		super._update_energy_shield(delta)


func recover_host_shield(delta: float) -> bool:
	var previous: float = energy_shield
	_applying_damage = true
	_update_energy_shield(delta)
	super._update_predator_cloak(delta)
	_applying_damage = false
	return not is_equal_approx(previous, energy_shield)


func receive_combat_state(state: Dictionary) -> void:
	if int(state["generation"]) != life_generation or int(state["revision"]) <= _combat_revision:
		return
	_combat_revision = state["revision"]
	var previous: float = health
	var previous_shield: float = energy_shield
	health = state["health"]
	energy_shield = state["shield"]
	predator_cloak_active = state["cloak"]
	if is_local_player() and predator_cloak_active and camera_pivot.binos_active:
		camera_pivot.deactivate_binos()
	predator_cloak_energy = state["cloak_energy"]
	_host_stealth_alert = float(state.get("stealth", 0.0))
	stealth_alert_changed.emit(get_stealth_alert())
	predator_cloak_energy_changed.emit(predator_cloak_energy, PREDATOR_CLOAK_MAX_ENERGY)
	health_changed.emit(health, max_health)
	energy_shield_changed.emit(energy_shield, ENERGY_SHIELD_MAX)
	if energy_shield < previous_shield:
		_energy_shield_effect_timer = energy_shield_effect_duration
	_update_predator_cloak_visuals()
	if health < previous:
		damaged.emit(previous - health, state["direction"])
		if health > 0.0:
			_trigger_impact_reaction(state["direction"], ImpactReaction.HIT)
	if health <= 0.0 and not _is_dead:
		_applying_damage = true
		_die(state["direction"])
		_applying_damage = false


func _owned_purchases() -> Dictionary:
	var session: Node = get_parent().get_parent()
	var owned: Dictionary = session.get("purchases")
	return owned.get(get_multiplayer_authority(), {})


func _apply_purchased_upgrades(_upgrade_id: StringName = &"", _level: int = 0) -> void:
	var owned: Dictionary = _owned_purchases()
	var movement: float = 1.0 + 0.1 * int(owned.get(&"movement", 0))
	for property: StringName in [&"speed", &"sprint_speed", &"crouch_speed"]:
		set(property, _base_upgrade_stats[property] * movement)
	max_stamina = _base_upgrade_stats[&"max_stamina"] + 25.0 * int(owned.get(&"stamina", 0))
	stamina_recovery_per_second = _base_upgrade_stats[&"stamina_recovery_per_second"] * (1.0 + 0.25 * int(owned.get(&"recovery", 0)))
	stamina = minf(stamina, max_stamina)
	stamina_changed.emit(stamina, max_stamina)


func can_use_xray_goggles() -> bool:
	return _owned_purchases().has(&"xray_goggles")


func can_use_energy_shield() -> bool:
	return _owned_purchases().has(&"energy_shield")


func can_use_predator_watch() -> bool:
	return _owned_purchases().has(&"predator_watch")


func grant_xray_goggles() -> void:
	_update_predator_cloak_visuals()
	_sync_equipment_inventory_slots()


func grant_energy_shield() -> void:
	grant_xray_goggles()
	energy_shield_changed.emit(energy_shield, ENERGY_SHIELD_MAX)


func grant_predator_watch() -> void:
	grant_xray_goggles()
	predator_cloak_energy_changed.emit(predator_cloak_energy, PREDATOR_CLOAK_MAX_ENERGY)


func apply_team_purchases() -> void:
	_apply_purchased_upgrades()
	grant_xray_goggles()


func is_local_player() -> bool:
	return is_multiplayer_authority()


func request_noise(decibels: float) -> void:
	if not is_local_player():
		return
	_noise_sequence += 1
	var session: Node = get_parent().get_parent()
	session.call("request_player_noise", decibels, _noise_sequence, life_generation)


func get_pickup_candidate() -> RigidBody3D:
	if not is_local_player() or _movement_locked:
		return null
	var session: Node = get_parent().get_parent()
	var candidates: Dictionary = session.get("items")
	var closest: RigidBody3D = null
	var nearest: float = INF
	for item: RigidBody3D in candidates.values():
		var distance: float = global_position.distance_squared_to(item.global_position)
		if distance < nearest and bool(item.call("can_pickup", self)):
			closest = item
			nearest = distance
	return closest


func try_pickup() -> void:
	var item: RigidBody3D = get_pickup_candidate()
	if item != null:
		item.call("pickup", self)


func _enter_tree() -> void:
	if is_local_player():
		return
	get_node("PlayerHUD").hide()
	get_node("PlayerHUD").process_mode = Node.PROCESS_MODE_DISABLED
	get_node("ET/ETArmature/Skeleton3D/CharacterProportions").use_saved_appearance = false
	for node: Node in find_children("*", "Camera3D", true, false):
		(node as Camera3D).current = false
	remove_from_group(&"debug_player")


func _ready() -> void:
	var previous_mouse_mode: Input.MouseMode = Input.mouse_mode
	super._ready()
	var hud: Node = get_node("PlayerHUD")
	if died.is_connected(hud._on_player_died):
		died.disconnect(hud._on_player_died)
	if not is_local_player():
		# Inherited scene connections also fire for replicas on this peer.
		var death_effect: CanvasLayer = get_node("DeathEffect") as CanvasLayer
		var death_audio: AudioStreamPlayer = get_node("DeathEffect/DeathAudio") as AudioStreamPlayer
		died.disconnect(death_effect.show)
		died.disconnect(death_audio.play)
	died.connect(func() -> void: get_parent().get_parent().call("on_player_death", get_multiplayer_authority()))
	if is_local_player():
		camera_pivot.get_camera().make_current()
	else:
		Input.mouse_mode = previous_mouse_mode
		set_process_input(false)
		camera_pivot.set_process_input(false)
		energy_pool.process_mode = Node.PROCESS_MODE_DISABLED


func _input(event: InputEvent) -> void:
	if is_local_player():
		super._input(event)


func _physics_process(delta: float) -> void:
	for decibels: float in _network_noises:
		player_noise.play_network_action(decibels)
	_network_noises.clear()
	if has_meta("coop_arrival"):
		_update_camera_target()
		return
	if has_meta("coop_seated"):
		_update_camera_target()
		return
	if is_local_player():
		super._physics_process(delta)
		return
	_update_energy_shield_effect(delta)
	if not _has_snapshot:
		return
	global_transform = global_transform.interpolate_with(_target_transform, 1.0 - exp(-20.0 * delta))
	_update_camera_target()
	animation_controller.set_motion_state(velocity, _remote_on_floor, _is_sprinting, is_crouching, _jump_state)


func try_carry_character() -> bool:
	# Dead teammates use the shared corpse item, so a second local body cannot be picked up.
	return false


func apply_portal_transform(mapping: Transform3D) -> void:
	if is_local_player():
		super.apply_portal_transform(mapping)
		_portal_epoch += 1


func make_snapshot() -> Dictionary:
	_snapshot_sequence += 1
	return {
		"sequence": _snapshot_sequence,
		"transform": global_transform, "velocity": velocity,
		"on_floor": is_on_floor(), "sprinting": _is_sprinting,
		"crouching": is_crouching, "jump": _jump_state,
		"eye_light": is_eye_light_enabled(), "epoch": _portal_epoch,
		"yaw": camera_yaw, "pitch": camera_pitch,
		"generation": life_generation,
		"visual": {"fall": _fall_state, "face_up": _get_up_face_up,
			"fall_time": _fall_timer, "stand_time": _stand_up_elapsed,
			"recovery": clampf(_stand_up_elapsed / maxf(ragdoll_pose_blend_duration, 0.001), 0.0, 1.0),
			"pose": ragdoll.capture_network_pose(), "reaction_sequence": _reaction_sequence,
			"reaction": _last_reaction, "binos": camera_pivot.binos_active},
	}


func receive_snapshot(state: Dictionary) -> void:
	if is_local_player() or not is_alive() or int(state.get("generation", -1)) != life_generation:
		return
	if int(state.get("sequence", -1)) <= _remote_sequence or int(state["epoch"]) < _remote_epoch:
		return
	_remote_sequence = state["sequence"]
	_target_transform = state["transform"]
	var epoch: int = state["epoch"]
	# Portal crossings must jump directly to the exit instead of sliding through the map.
	if not _has_snapshot or epoch != _remote_epoch:
		global_transform = _target_transform
	_remote_epoch = epoch
	_has_snapshot = true
	velocity = state["velocity"]
	_remote_on_floor = state["on_floor"]
	_is_sprinting = state["sprinting"]
	is_crouching = state["crouching"]
	_jump_state = state["jump"]
	camera_yaw = state["yaw"]
	camera_pitch = state["pitch"]
	_receive_visual_state(state["visual"])
	set_eye_light_enabled(state["eye_light"], true)


func get_stealth_alert() -> float:
	return super.get_stealth_alert() if multiplayer.is_server() else _host_stealth_alert
