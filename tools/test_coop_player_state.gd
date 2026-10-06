extends "res://tools/test_coop_campaign.gd"

class HearingProbe:
	extends Node3D
	var heard: int = 0
	func hear_sound(_origin: Vector3, _decibels: float, _radius: float) -> bool:
		heard += 1
		return true
	func is_enemy_listener() -> bool:
		return true

func _run() -> void:
	var scene: PackedScene = load("res://scenes/Multiplayer/PortalCoop.tscn") as PackedScene
	for index: int in 2:
		var viewport: SubViewport = SubViewport.new()
		viewport.name = "StatePeer%d" % index
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
	_check(host.host_game(17086) == OK, "State test host starts")
	_check(guest.join_game("127.0.0.1", 17086) == OK, "State test guest connects")
	if not await _wait(func() -> bool: return guest.players.size() == 2):
		_check(false, "State test roster completes")
		_finish()
		return
	host.set_ready()
	guest.set_ready()
	await _wait(func() -> bool: return host.ready_players.values().count(true) == 2)
	host.start_expedition()
	await _wait(func() -> bool: return guest.mission_phase == &"collecting")
	var id: int = guest.multiplayer.get_unique_id()
	var player: CharacterBody3D = guest.players[id]
	var probes: Array[HearingProbe] = []
	for session: Node3D in _sessions:
		var probe: HearingProbe = HearingProbe.new()
		session.add_child(probe)
		probe.add_to_group(&"npc_hearing_listeners")
		probes.append(probe)
	player.player_noise.emit_jump_noise()
	_check(await _wait(func() -> bool: return probes[0].heard > 0), "Guest jump noise reaches host hearing")
	_check(probes[1].heard == 0, "Client hearing never simulates host noise")
	var crops: Array[Area3D] = []
	for session: Node3D in _sessions:
		var crop: Area3D = Area3D.new()
		crop.set_script(load("res://scripts/vegetation_concealment.gd"))
		crop.set("visibility_multiplier", 0.35)
		crop.collision_layer = 0
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = Vector3(4, 3, 4)
		var collision: CollisionShape3D = CollisionShape3D.new()
		collision.shape = shape
		crop.add_child(collision)
		crop.position = session.players[id].global_position + Vector3.UP
		session.add_child(crop)
		crops.append(crop)
	_check(await _wait(func() -> bool: return is_equal_approx(NPCVision.get_target_visibility(host.players[id]), 0.35) and is_equal_approx(NPCVision.get_target_visibility(player), 0.35)), "Host sensors and owner share crop concealment penalties")
	for crop: Area3D in crops:
		crop.position += Vector3.RIGHT * 100
	_check(await _wait(func() -> bool: return is_equal_approx(NPCVision.get_target_visibility(host.players[id]), 1.0) and is_equal_approx(NPCVision.get_target_visibility(player), 1.0)), "Leaving crops restores visibility on host and owner")
	for crop: Area3D in crops:
		crop.queue_free()
	host.purchases[id] = {&"predator_watch": 1}
	host._publish_economy()
	await _wait(func() -> bool: return player.can_use_predator_watch())
	player.camera_pivot.activate_binos()
	_check(await _wait(func() -> bool: return host.players[id].farsight_goggles_mesh.visible), "Remote goggles follow the owner's Xray state")
	player.toggle_predator_cloak()
	await create_timer(0.15).timeout
	_check(not player.predator_cloak_active and not host.players[id].predator_cloak_active, "Xray blocks the invisibility watch on owner and host")
	_check(not host.players[id].camera_pivot.binos_active, "Remote rig never activates its Xray renderer")
	var material: StandardMaterial3D = StandardMaterial3D.new()
	var geometry: Array[MeshInstance3D] = []
	for session: Node3D in _sessions:
		var mesh: MeshInstance3D = MeshInstance3D.new()
		mesh.mesh = BoxMesh.new()
		mesh.material_override = material
		session.add_child(mesh)
		geometry.append(mesh)
	await process_frame
	_check(geometry[0].material_override == material and geometry[1].material_override == player.camera_pivot.xray_material, "New geometry uses Xray only in its owner's world")
	player.camera_pivot.deactivate_binos()
	_check(geometry[1].material_override == material, "Xray restores the original material")
	player.set_physics_process(false)
	player._fall_state = player.FallState.FALLEN
	_check(await _wait(func() -> bool: return host.players[id]._fall_state == player.FallState.FALLEN and host.players[id].collision_shape.disabled), "Remote fall state disables the standing capsule")
	player._fall_state = player.FallState.NONE
	_check(await _wait(func() -> bool: return host.players[id]._fall_state == player.FallState.NONE and not host.players[id].collision_shape.disabled), "Remote recovery restores the standing capsule")
	player.camera_pivot.activate_binos()
	host.damage_player(id, 1000.0)
	_check(await _wait(func() -> bool: return not player.is_alive()), "Host death reaches the owning player")
	_check(not player.camera_pivot.binos_active and geometry[1].material_override == material, "Death disables Xray and restores materials")
	_finish()
