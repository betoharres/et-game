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


func debug_add_team_money() -> void:
	get_parent().get_parent().call("debug_add_team_money")


func toggle_predator_cloak() -> void:
	get_parent().get_parent().call("request_cloak_toggle")


func apply_host_cloak_toggle() -> void:
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
	predator_cloak_energy = state["cloak_energy"]
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
	set_eye_light_enabled(state["eye_light"], true)
