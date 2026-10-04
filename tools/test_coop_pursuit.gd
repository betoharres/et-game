extends "res://tools/test_coop_campaign.gd"

func _run() -> void:
	var scene: PackedScene = load("res://scenes/Multiplayer/PortalCoop.tscn") as PackedScene
	var directors: Array[Node3D] = []
	for index: int in 2:
		var viewport: SubViewport = SubViewport.new()
		viewport.name = "PursuitPeer%d" % index
		viewport.own_world_3d = true
		root.add_child(viewport)
		set_multiplayer(MultiplayerAPI.create_default_interface(), viewport.get_path())
		var session: Node3D = scene.instantiate() as Node3D
		viewport.add_child(session)
		session.host_migration.enabled = false
		_sessions.append(session)
		_views.append(viewport)
		var director: Node3D = (load("res://scenes/PursuitSystem.tscn") as PackedScene).instantiate() as Node3D
		var agent: PackedScene = director.agent_scene
		var factions: Array[PursuitProfile] = director.factions
		director.set_script(load("res://scripts/multiplayer/coop_pursuit.gd"))
		director.agent_scene = agent
		director.factions = factions
		director.session = session
		director._built_navigation = true
		session.add_child(director)
		session.npcs[&"pursuit"] = director
		directors.append(director)
	var host: Node3D = _sessions[0]
	var guest: Node3D = _sessions[1]
	_check(host.host_game(17089) == OK, "Pursuit host starts")
	_check(guest.join_game("127.0.0.1", 17089) == OK, "Pursuit guest connects")
	if not await _wait(func() -> bool: return guest.players.size() == 2):
		_check(false, "Pursuit roster completes")
		_finish()
		return
	host.set_ready()
	guest.set_ready()
	await _wait(func() -> bool: return host.ready_players.values().count(true) == 2)
	host.start_expedition()
	await _wait(func() -> bool: return guest.mission_phase == &"collecting")
	var guest_id: int = guest.multiplayer.get_unique_id()
	var solo_alert: Node = root.get_node("PhotoAlertSystem")
	var original_stars: int = solo_alert.photo_count
	directors[0].report_theft(host.items[&"scrap_01"], host.players[guest_id])
	_check(await _wait(func() -> bool: return directors[1]._alert.photo_count == 1), "A teammate's theft raises shared wanted stars")
	directors[0].report_theft(host.items[&"scrap_01"], host.players[guest_id])
	_check(directors[0]._alert.photo_count == 1, "The same item cannot raise wanted stars twice")
	_check(solo_alert.photo_count == original_stars, "Co-op alerts preserve the SP alert state")
	var pose: Transform3D = Transform3D(Basis.IDENTITY, Vector3(6, 0, 6))
	var record: Dictionary = directors[0].make_migration_state()
	record.units = {"Pursuer_0": {"profile": "res://scenes/NPCs/Pursuit/Police.tres", "pose": pose}}
	record.next = 1
	record.reinforce = 1000.0
	directors[0].restore_migration_state(record)
	_check(await _wait(func() -> bool: return guest.npcs.has(&"pursuit/Pursuer_0")), "Guests instantiate the host's reinforcement roster")
	_check(directors[1].active_enemies.size() == 1 and not directors[1].active_enemies[0].is_physics_processing(), "Reinforcements simulate only on the host")
	var checkpoint: Dictionary = host.host_migration.capture()
	_check(checkpoint.npcs[&"pursuit"].units.has("Pursuer_0") and checkpoint.npcs.has(&"pursuit/Pursuer_0"), "Migration captures faction roster and individual NPC state")
	directors[0]._alert.reset()
	_check(await _wait(func() -> bool: return directors[1].active_enemies.is_empty() and not guest.npcs.has(&"pursuit/Pursuer_0")), "Wanted decay retires reinforcement replicas")
	_finish()
