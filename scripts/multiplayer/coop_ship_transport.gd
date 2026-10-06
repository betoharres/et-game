extends Node3D

@export_range(1.0, 5.0, 0.1) var interaction_radius: float = 2.5
@export var ship_spawn: NodePath = NodePath("../../SpawnPoint")

var session: Node3D
var ground_position: Vector3
var _cooldowns: Dictionary[int, int] = {}

func configure(owner_session: Node3D, landing_position: Vector3) -> void:
	session = owner_session
	ground_position = landing_position
	add_to_group("upgrade_stations")
	$GroundPrompt.global_position = ground_position + Vector3.UP * 1.8
	$GroundPrompt.visible = true

func reserves_interaction_for(character: Node3D) -> bool:
	return session != null and character != null and character.get_world_3d() == get_world_3d() and (
		character.global_position.distance_to(global_position) <= interaction_radius
		or character.global_position.distance_to(ground_position) <= interaction_radius)

func get_interaction_prompt(character: Node3D) -> String:
	if not reserves_interaction_for(character):
		return ""
	return "[E] Descend to ground" if character.global_position.distance_to(global_position) <= interaction_radius else "[E] Board ship"

func _input(event: InputEvent) -> void:
	if session == null or get_tree().paused or not event.is_action_pressed("interact") or event.is_echo():
		return
	var player: CharacterBody3D = session.players.get(multiplayer.get_unique_id()) as CharacterBody3D
	if not reserves_interaction_for(player) or not player.is_alive() or player._movement_locked:
		return
	request_transport()
	get_viewport().set_input_as_handled()

func request_transport() -> void:
	if session == null:
		return
	if multiplayer.is_server():
		_transport(multiplayer.get_unique_id())
	else:
		_request_transport.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func _request_transport() -> void:
	if multiplayer.is_server():
		_transport(multiplayer.get_remote_sender_id())

func _transport(peer_id: int) -> void:
	var player: CharacterBody3D = session.players.get(peer_id) as CharacterBody3D
	if session.host_migration.active or session.mission_phase != &"collecting" or not reserves_interaction_for(player):
		return
	if not player.is_alive() or player.has_meta("coop_seated") or player._movement_locked or Time.get_ticks_msec() < _cooldowns.get(peer_id, 0):
		return
	var aboard: bool = player.global_position.distance_to(ground_position) <= interaction_radius
	var destination: Vector3 = (get_node(ship_spawn) as Node3D).global_position if aboard else ground_position
	var slot: int = session._slots[peer_id]
	destination += Vector3(float(slot % 2) * 0.7, 0.1, float(slot / 2) * 0.7)
	var epoch: int = maxi(player._portal_epoch, player._remote_epoch) + 1
	_cooldowns[peer_id] = Time.get_ticks_msec() + 500
	_apply_transport.rpc(peer_id, destination, epoch, aboard, session.mission_round, player.life_generation)
	_apply_transport(peer_id, destination, epoch, aboard, session.mission_round, player.life_generation)

@rpc("authority", "call_remote", "reliable")
func _apply_transport(peer_id: int, destination: Vector3, epoch: int, aboard: bool, round_id: int, generation: int) -> void:
	var player: CharacterBody3D = session.players.get(peer_id) as CharacterBody3D
	if player == null or session.mission_round != round_id or player.life_generation != generation:
		return
	# Advance the portal epoch so delayed movement cannot drag a passenger back.
	player._portal_epoch = epoch
	player._remote_epoch = epoch
	player.global_position = destination
	player._target_transform = player.global_transform
	player.velocity = Vector3.ZERO
	if player.is_local_player():
		session.campaign._ship.set_player_inside(player, aboard)
	player._update_camera_target()
