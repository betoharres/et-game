extends SceneTree

class FakePlayer:
	extends CharacterBody3D
	var visibility: float = 1.0
	var damage_taken: float = 0.0

	func is_alive() -> bool:
		return true

	func can_emit_player_noise() -> bool:
		return true

	func get_stealth_visibility() -> float:
		return visibility

	func set_vision_contact(_source: Object, _contact: bool) -> void:
		pass

	func take_damage(amount: float, _direction: Vector3, _push: float) -> void:
		damage_taken += amount


var failures: int = 0
var world: Node3D
var player: FakePlayer
var noise: PlayerNoise
var alert: Node
var heard_event: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	alert = root.get_node("PhotoAlertSystem")
	alert.set_process(false)
	_build_navigation()
	player = FakePlayer.new()
	player.add_to_group(&"characters")
	player.position = Vector3(60, 0, 60)
	world.add_child(player)
	player.set_physics_process(true)
	noise = PlayerNoise.new()
	noise.name = "PlayerNoise"
	player.add_child(noise)
	noise.noise_emitted.connect(_on_noise_emitted)
	await physics_frame
	await physics_frame
	for scene_path: String in ["res://scenes/NPCs/SmellyFarmer.tscn", "res://scenes/NPCs/Photographer.tscn"]:
		await _test_enemy(scene_path)
	alert.reset()
	world.queue_free()
	await process_frame
	print("Percepção dos inimigos legados: %d falhas" % failures)
	quit(1 if failures > 0 else 0)


func _test_enemy(scene_path: String) -> void:
	alert.reset()
	player.position = Vector3(60, 0, 60)
	var enemy: CharacterBody3D = (load(scene_path) as PackedScene).instantiate() as CharacterBody3D
	world.add_child(enemy)
	enemy.set_physics_process(false)
	var awareness: LegacyEnemyAwareness = enemy.get_node("EnemyAwareness") as LegacyEnemyAwareness
	awareness.set_physics_process(false)
	var navigation: NavigationAgent3D = enemy.get_node("NavigationAgent3D") as NavigationAgent3D
	# A malha sintética está nos pés; o offset da cena deslocaria seus waypoints para baixo.
	navigation.path_height_offset = 0.0
	await physics_frame
	_check(enemy.call("get_awareness_state") == &"neutral", scene_path + " começa neutro")
	var origin: Vector3 = Vector3(-6, 0, -2)
	player.global_position = origin
	heard_event = false
	noise.emit_noise(noise.run_decibels)
	_check(heard_event, scene_path + " confirma ao HUD que ouviu o ruído")
	_check(not bool(enemy.get("has_detected_player")), scene_path + " não confunde som com visão")
	_check(enemy.call("get_awareness_state") == &"alert", scene_path + " fica alerta ao ouvir")
	player.global_position = Vector3(60, 0, 60)
	enemy.call("_physics_process", 1.0 / 60.0)
	_check(navigation.target_position.is_equal_approx(origin), scene_path + " investiga a origem do som")
	var closest_distance: float = enemy.global_position.distance_to(origin)
	var damage_before: float = player.damage_taken
	for frame: int in range(300):
		await physics_frame
		enemy.call("_physics_process", 1.0 / 60.0)
		closest_distance = minf(closest_distance, enemy.global_position.distance_to(origin))
	_check(closest_distance < 1.2, scene_path + " alcança o ponto ouvido; distância %.2f" % closest_distance)
	_check(is_equal_approx(player.damage_taken, damage_before) and alert.get_photo_count() == 0,
		scene_path + " não atira nem fotografa jogador escondido só por ouvi-lo")
	_check(enemy.call("get_awareness_state") == &"neutral", scene_path + " conclui investigação sem enxergar o jogador")
	alert.register_photo(0, player.global_position)
	_check(enemy.call("get_awareness_state") == &"alert", scene_path + " reage à primeira estrela")
	_check(is_equal_approx(float(enemy.call("get_effective_sight_distance")), NPCVision.ALERT_SIGHT_DISTANCE)
		and is_equal_approx(float(enemy.call("get_effective_sight_half_angle_degrees")), NPCVision.ALERT_SIGHT_HALF_ANGLE_DEGREES),
		scene_path + " usa cone comum durante alerta global")
	player.visibility = 0.25
	_check(is_equal_approx(float(enemy.call("get_effective_sight_distance")), NPCVision.ALERT_SIGHT_DISTANCE * 0.25),
		scene_path + " preserva efeito de furtividade no cone comum")
	player.visibility = 1.0
	alert.reset()
	_check(is_equal_approx(float(enemy.call("get_effective_sight_distance")), float(enemy.get("sight_distance")))
		and is_equal_approx(float(enemy.call("get_effective_sight_half_angle_degrees")), float(enemy.get("sight_half_angle_degrees"))),
		scene_path + " restaura cone neutro sem estrelas")
	player.global_position = enemy.global_position + enemy.global_basis.z * 4.0
	enemy.set("detection_time", 0.0)
	enemy.call("_physics_process", 0.01)
	_check(enemy.call("get_awareness_state") == &"pursuit", scene_path + " persegue após confirmação visual")
	player.global_position = Vector3(60, 0, 60)
	enemy.call("_physics_process", 0.01)
	_check(enemy.call("get_awareness_state") == &"alert", scene_path + " volta a alerta ao perder contato visual")
	origin = enemy.global_position + Vector3.LEFT * 6.0
	awareness.hear_sound(origin, noise.run_decibels, PlayerNoise.radius_for_decibels(noise.run_decibels))
	enemy.call("_physics_process", 0.01)
	_check(navigation.target_position.is_equal_approx(origin), scene_path + " prioriza novo som sobre memória visual antiga")
	enemy.queue_free()
	await process_frame


func _build_navigation() -> void:
	var region: NavigationRegion3D = NavigationRegion3D.new()
	var mesh: NavigationMesh = NavigationMesh.new()
	mesh.vertices = PackedVector3Array([
		Vector3(-30, 0, -30), Vector3(-30, 0, 30), Vector3(30, 0, 30), Vector3(30, 0, -30)
	])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_mesh = mesh
	world.add_child(region)


func _on_noise_emitted(_origin: Vector3, _decibels: float, _radius: float, heard: bool) -> void:
	heard_event = heard


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
