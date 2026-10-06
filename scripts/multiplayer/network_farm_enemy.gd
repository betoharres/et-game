extends "res://scripts/multiplayer/network_npc.gd"

@export var photographer: bool = false
var photo_count: int = 0
var _focus: float = 0.0
var _effect: Node3D


func _ready() -> void:
	super._ready()
	_effect = find_child("CameraFlash" if photographer else "MuzzleFlash", true, false) as Node3D
	if _effect != null:
		_effect.hide()


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if photographer and _session == null:
		PhotoAlertSystem.set_photographer_observing(get_instance_id(), vision.is_currently_visible)


func _exit_tree() -> void:
	if photographer and _session == null:
		PhotoAlertSystem.unregister_photographer(get_instance_id())


func attack_target() -> bool:
	if not _host_simulation or not is_instance_valid(player) or not is_player_alive() or not vision.has_detected_player or not vision.is_currently_visible or global_position.distance_to(player.global_position) > attack_range:
		_focus = 0.0
		return false
	stop_moving()
	face_direction(player.global_position - global_position)
	set_state(&"attack")
	if _cooldown > 0.0:
		return true
	_focus += get_physics_process_delta_time()
	if photographer and _focus < 1.2:
		return true
	_focus = 0.0
	_cooldown = attack_interval
	if photographer:
		photo_count += 1
		if _session != null and _session.campaign != null and _session.campaign.pursuit != null:
			_session.campaign.pursuit.report_photo(self, player)
		elif _session == null:
			PhotoAlertSystem.register_photo(get_instance_id(), player.global_position)
		var actors: Array[Node] = get_tree().get_nodes_in_group("npc_actors")
		for node: Node in actors:
			var npc: NPCActor = node as NPCActor
			if npc == null:
				npc = node.get_parent() as NPCActor
			if npc != null and npc != self and npc.get_world_3d() == get_world_3d() and npc.vision != null:
				npc.vision.set_alerted(true)
	else:
		_damage_target(attack_damage)
	_show_effect(photo_count)
	if _session != null and multiplayer.has_multiplayer_peer():
		_show_effect.rpc(photo_count)
	return true


@rpc("authority", "call_remote", "reliable")
func _show_effect(count: int) -> void:
	photo_count = count
	if _effect == null:
		return
	_effect.show()
	var audio: AudioStreamPlayer3D = find_child("GunshotAudio", true, false) as AudioStreamPlayer3D
	if audio != null:
		audio.play()
	await get_tree().create_timer(0.12).timeout
	if is_instance_valid(_effect):
		_effect.hide()


func make_network_state() -> Dictionary:
	var snapshot: Dictionary = super.make_network_state()
	snapshot["photos"] = photo_count
	return snapshot


func receive_network_state(snapshot: Dictionary) -> void:
	super.receive_network_state(snapshot)
	photo_count = snapshot.get("photos", 0)


func make_migration_state() -> Dictionary:
	var snapshot: Dictionary = super.make_migration_state()
	snapshot["focus"] = _focus
	return snapshot


func restore_migration_state(snapshot: Dictionary) -> void:
	super.restore_migration_state(snapshot)
	photo_count = snapshot.photos
	_focus = snapshot.focus
