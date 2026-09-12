extends SceneTree

const SCRAP_SCRIPT: Script = preload("res://scripts/spaceship_scraps.gd")

var failures: int = 0
var world: Node3D
var player: CharacterBody3D
var director: PursuitDirector
var alert: Node
var completed: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	seed(4739)
	alert = root.get_node("PhotoAlertSystem")
	if "--farm" in OS.get_cmdline_user_args():
		await _test_farm_navigation()
	else:
		await _test_system()
	_check(completed, "Roteiro concluiu sem interrupção de script")
	print("Perseguição: %d falhas" % failures)
	world.queue_free()
	await process_frame
	await process_frame
	quit(1 if failures > 0 else 0)


func _test_system() -> void:
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	_box(Vector3(0, -0.5, 0), Vector3(130, 1, 130))
	_box(Vector3(0, 2, 6), Vector3(8, 4, 1))
	player = (load("res://scenes/Player.tscn") as PackedScene).instantiate() as CharacterBody3D
	player.name = "Player"
	player.position = Vector3(-20, 0.1, -20)
	player.set("max_health", 10000.0)
	world.add_child(player)
	player.set_physics_process(false)
	director = (load("res://scenes/PursuitSystem.tscn") as PackedScene).instantiate() as PursuitDirector
	_check(director != null, "Cena de perseguição carrega com script")
	if director == null:
		return
	director.player_path = NodePath("../Player")
	director.initial_response_delay = 0.1
	director.minimum_spawn_distance = 12.0
	director.maximum_spawn_distance = 18.0
	for index: int in range(director.factions.size()):
		director.factions[index] = director.factions[index].duplicate() as PursuitProfile
		director.factions[index].reinforcement_interval = 1.0
	(director.get_node("Navigation") as PursuitNavigation).baking_bounds = AABB(Vector3(-64, -2, -64), Vector3(128, 12, 128))
	world.add_child(director)
	director.set_physics_process(false)
	alert.set_process(false)
	var hud: CanvasLayer = (load("res://scenes/PhotoAlertHUD.tscn") as PackedScene).instantiate() as CanvasLayer
	world.add_child(hud)
	await _frames(3)
	_check(director.active_enemies.is_empty(), "Zero estrelas começa sem reforços")
	await _test_pickups()
	_check((hud.get_node("Interface/AlertPanel/MarginContainer/Content/FactionLabel") as Label).text == "MIB", "HUD acompanha nível 3")
	alert.call("set_photographer_observing", 123, true)
	alert.call("_process", 31.0)
	_check(alert.get_photo_count() == 3, "Fotógrafo impede redução")
	alert.call("unregister_photographer", 123)
	alert.call("set_pursuer_observing", 456, true)
	alert.call("_process", 31.0)
	_check(alert.get_photo_count() == 3, "Perseguidor impede redução")
	alert.call("set_pursuer_observing", 456, false)
	alert.call("_process", 30.0)
	_check(alert.get_photo_count() == 2, "Trinta segundos oculto reduzem uma estrela")
	alert.call("_process", 60.0)
	_check(alert.get_photo_count() == 0, "Alerta pode cair até zero")
	_check((hud.get_node("Interface/AlertPanel/MarginContainer/Content/ObjectiveRow/CountLabel") as Label).text == "0 / 3", "HUD acompanha redução até zero")
	await _wait_navigation()
	director.set_physics_process(true)
	for level: int in range(1, 4):
		alert.register_photo(0, player.global_position)
		var exceeded_cap: bool = false
		for frame: int in range(190):
			await physics_frame
			exceeded_cap = exceeded_cap or director.active_enemies.size() > mini(director.maximum_active_enemies, director.get_profile(level).max_active)
		_check(not exceeded_cap, "Nível %d respeita teto durante ondas" % level)
		_check(director.active_enemies.size() == director.get_profile(level).max_active, "Nível %d recebe reforços até o limite" % level)
		for npc: PursuitNPC in director.active_enemies:
			_check(npc.profile.stars == level and npc.get_health() == npc.profile.max_health, "Facção e vida do reforço no nível %d" % level)
		var ids: Array[int] = []
		for npc: PursuitNPC in director.active_enemies:
			ids.append(npc.get_instance_id())
		await _frames(80)
		for npc: PursuitNPC in director.active_enemies:
			_check(ids.has(npc.get_instance_id()), "Limite cheio não recria NPCs continuamente")
		print("Nível %d: %d reforços ativos" % [level, director.active_enemies.size()])
	if not director.active_enemies.is_empty():
		var victim: PursuitNPC = director.active_enemies[0]
		victim.take_damage(victim.profile.max_health)
		await _frames(2)
		_check(director.active_enemies.size() < 6, "Morte libera vaga")
		await _frames(80)
		_check(director.active_enemies.size() == 6, "Onda seguinte repõe vaga")
	alert.reset()
	await _frames(3)
	_check(director.active_enemies.is_empty() and get_nodes_in_group("pursuit_enemies").is_empty(), "Zero estrelas remove perseguidores")
	director.set_physics_process(false)
	await _test_navigation_and_combat()
	alert.register_photo(0, player.global_position)
	player.call("take_damage", 20000.0)
	_check(alert.get_photo_count() == 0, "Morte do ET encerra alerta")
	director.queue_free()
	await _frames(2)
	_check(not alert.is_observed(), "Saída limpa observadores")
	completed = true


func _test_pickups() -> void:
	var first: RigidBody3D = _scrap(4, false)
	await _frames(2)
	player.call("try_pickup")
	_check(first.get("carried") and alert.get_photo_count() == 1, "Coleta real gera polícia")
	var overflow: RigidBody3D = _scrap(1, false)
	await _frames(2)
	player.call("try_pickup")
	_check(not overflow.get("carried") and alert.get_photo_count() == 1, "Inventário cheio não gera crime")
	overflow.position += Vector3(10, 0, 0)
	player.get_node("ExplorationInventory").call("drop_selected", player)
	first.global_position = player.global_position + Vector3(0, 0.4, 1)
	await _frames(2)
	player.call("try_pickup")
	_check(first.get("carried") and alert.get_photo_count() == 1, "Recoletar mesmo objeto não aumenta alerta")
	first.free()
	overflow.global_position = player.global_position + Vector3(0, 0.4, 1)
	await _frames(2)
	player.call("try_pickup")
	_check(alert.get_photo_count() == 2, "Segundo objeto gera SWAT")
	overflow.free()
	var large: RigidBody3D = _scrap(1, true)
	await _frames(2)
	player.call("try_pickup")
	_check(large.get("carried") and alert.get_photo_count() == 3, "Objeto de duas mãos gera MIB")
	large.free()
	alert.register_photo(0, player.global_position)
	_check(alert.get_photo_count() == 3, "Fotos respeitam teto de três estrelas")


func _test_navigation_and_combat() -> void:
	player.global_position = Vector3(0, 0.1, 12)
	var npc: PursuitNPC = (load("res://scenes/NPCs/Pursuit/PursuitAgent.tscn") as PackedScene).instantiate() as PursuitNPC
	npc.profile = director.get_profile(1).duplicate() as PursuitProfile
	npc.profile.spread_degrees = 0.0
	npc.position = Vector3(0, 0.1, 0)
	world.add_child(npc)
	npc.navigation_agent.set_navigation_map(director.navigation.get_navigation_map())
	var tree: BeehaveTree = npc.get_node("NPCBehaviorTree") as BeehaveTree
	tree.enabled = false
	await _frames(5)
	var combat: NPCRangedCombat = npc.get_node("NPCCombat") as NPCRangedCombat
	# Mesmo uma amostra antiga de visão não autoriza tiro através de parede.
	npc.vision.has_detected_player = true
	npc.vision.is_currently_visible = true
	_check(not combat.can_engage(), "Raycast da arma bloqueia disparo através da parede")
	player.global_position = Vector3(0, 0.1, 45)
	_check(not combat.can_engage(), "Arma respeita alcance")
	player.global_position = Vector3(0, 0.1, 12)
	npc.vision.has_detected_player = false
	npc.vision.is_currently_visible = false
	npc.vision.last_seen_position = player.global_position
	npc.vision.has_last_seen_position = true
	var initial_health: float = float(player.call("get_health"))
	var went_around: bool = false
	var attacked: bool = false
	tree.enabled = true
	for frame: int in range(600):
		await physics_frame
		went_around = went_around or absf(npc.global_position.x) > 4.0
		attacked = float(player.call("get_health")) < initial_health
		if went_around and attacked:
			break
	_check(went_around, "Agente contorna obstáculo via navegação; posição %s" % npc.global_position)
	_check(attacked, "Agente encontra o ET e reduz a vida existente; posição %s" % npc.global_position)
	var before: float = float(player.call("get_health"))
	await _frames(12)
	_check(is_equal_approx(before, float(player.call("get_health"))), "Pistola respeita cooldown após disparo")
	npc.take_damage(npc.profile.max_health - 1.0)
	_check(npc.is_alive() and is_equal_approx(npc.get_health(), 1.0), "Resistência do inimigo absorve dano não letal")
	npc.take_damage(1.0)
	await _frames(2)
	_check(not is_instance_valid(npc), "Dano letal remove inimigo")


func _test_farm_navigation() -> void:
	world = (load("res://scenes/world.tscn") as PackedScene).instantiate() as Node3D
	world.set_script(null)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(world)
	current_scene = world
	player = world.get_node("CharacterBody3D") as CharacterBody3D
	director = world.get_node("PursuitSystem") as PursuitDirector
	alert.set_process(false)
	await _wait_navigation()
	if not director.navigation.is_ready_for_paths():
		return
	var terrain: Terrain3D = world.get_node("NavigationRegion3D/Terrain3D") as Terrain3D
	for point: Vector3 in [Vector3(-64, 0, -13), Vector3(-14, 0, 7), Vector3(43, 0, 26)]:
		point.y = terrain.data.get_height(point) + 0.1
		player.global_position = point
		alert.register_photo(0, point)
		await _frames(2)
		var valid: int = 0
		for index: int in range(32):
			var angle: float = TAU * float(index) / 32.0
			var candidate: Vector3 = point + Vector3(cos(angle), 0.0, sin(angle)) * 28.0
			if director.find_spawn_position(candidate).is_finite():
				valid += 1
		print("Fazenda: %d pontos válidos de reforço ao redor de %s" % [valid, point])
		if valid == 0:
			_print_spawn_failure(point)
		_check(valid > 0, "Fazenda tem spawn livre e caminho conectado perto de %s" % point)
	completed = true


func _print_spawn_failure(target: Vector3) -> void:
	var map: RID = director.navigation.get_navigation_map()
	var start: Vector3 = NavigationServer3D.map_get_closest_point(map, target + Vector3(28, 0, 0))
	var destination: Vector3 = NavigationServer3D.map_get_closest_point(map, target)
	var path: PackedVector3Array = NavigationServer3D.map_get_path(map, start, destination, true)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(start + Vector3.UP, start - Vector3.UP * 2.0, 1)
	print("Falha espacial: início=%s destino=%s jogador=%s relato=%s caminho=%s chão=%s" % [start, destination, player.global_position, director.get("_last_reported_position"), path, world.get_world_3d().direct_space_state.intersect_ray(query)])


func _wait_navigation() -> void:
	for frame: int in range(1800):
		await physics_frame
		if director.navigation.is_ready_for_paths():
			break
	_check(director.navigation.is_ready_for_paths(), "Malha de navegação assada e sincronizada")


func _scrap(cost: int, two_handed: bool) -> RigidBody3D:
	var item: RigidBody3D = SCRAP_SCRIPT.new() as RigidBody3D
	item.set("slot_cost", cost)
	item.set("two_handed", two_handed)
	item.collision_layer = 8
	item.collision_mask = 1
	item.freeze = true
	item.position = player.global_position + Vector3(0, 0.4, 1)
	world.add_child(item)
	item.add_to_group("pickup_items")
	return item


func _box(position: Vector3, size: Vector3) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.position = position
	body.add_child(shape)
	world.add_child(body)


func _frames(count: int) -> void:
	for frame: int in range(count):
		await physics_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
