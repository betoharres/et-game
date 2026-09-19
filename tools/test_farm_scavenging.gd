extends SceneTree

class PhysicsProbe extends Node:
	signal completed
	var task : Callable
	var result : Variant

	func _physics_process(_delta : float) -> void:
		if task.is_valid():
			var callback : Callable = task
			task = Callable()
			result = callback.call()
			completed.emit()

	func run(callback : Callable) -> Variant:
		task = callback
		await completed
		return result

var failures : int = 0
var world : Node3D
var player : CharacterBody3D
var inventory : Node
var delivery : Area3D
var wallet : Node
var probe : PhysicsProbe
var furnishing_rids : Array[RID] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	wallet = root.get_node("GlobalScore")
	world = (load("res://scenes/world.tscn") as PackedScene).instantiate() as Node3D
	# Preserva as colisões reais da fazenda, isolando chegada, combate e coleta automática.
	world.set_script(null)
	for child : Node in world.get_children():
		if child.name not in [&"PropsHolder", &"BuildingsHolder", &"NavigationRegion3D", &"CropFieldsHolder", &"VegetationHolder", &"VehiclesHolder", &"ScrapsHolder", &"FarmScavenging", &"DeliveryArea", &"CharacterBody3D"]:
			child.free()
	root.add_child(world)
	current_scene = world
	player = world.get_node("CharacterBody3D") as CharacterBody3D
	player.set_physics_process(false)
	inventory = player.get_node("ExplorationInventory")
	delivery = world.get_node("DeliveryArea") as Area3D
	delivery.set_process(false)
	delivery.set("signal_hold_duration", 0.1)
	delivery.set("abduction_duration", 0.1)
	probe = PhysicsProbe.new()
	root.add_child(probe)
	for furnishing : Node in world.get_node("FarmScavenging").find_children("*", "StaticBody3D", true, false):
		furnishing_rids.append((furnishing as StaticBody3D).get_rid())
	for frame : int in range(120):
		await physics_frame
	await probe.run(_check_house_access)
	var items : Array[Node] = get_nodes_in_group("farm_scraps")
	var types : Dictionary[String, bool] = {}
	var total_cash : int = 0
	_check(items.size() >= 30, "Objetos distribuídos pela fazenda: %d" % items.size())
	for node : Node in items:
		var item : RigidBody3D = node as RigidBody3D
		types[str(item.get("item_id"))] = true
		total_cash += int(item.get("cash_value"))
		var point : Vector3 = item.global_position
		var support : Dictionary = await probe.run(_ray.bind(point + Vector3.UP * 0.15, point - Vector3.UP * 0.4))
		_check(not support.is_empty(), "%s sem apoio em %s" % [item.name, point])
	_check(types.size() >= 12, "Doze tipos distintos: %d" % types.size())
	_check(total_cash >= 930, "Recompensas permitem comprar os nove níveis: $ %d" % total_cash)
	await _check_pickup_wall(items[0] as RigidBody3D)
	var delivered : int = 0
	for node : Node in items:
		var item : RigidBody3D = node as RigidBody3D
		var item_name : String = str(item.name)
		var value : int = int(item.get("cash_value"))
		if not bool(await probe.run(_approach.bind(item))):
			_check(false, "%s inacessível para coleta em %s" % [item_name, item.global_position])
			continue
		var old_money : int = int(wallet.get("money"))
		await _press("interact")
		_check(item.get("carrier") == player, "%s coletado manualmente" % item_name)
		_check(int(wallet.get("money")) == old_money, "%s não paga só por pegar" % item_name)
		if item.get("carrier") != player:
			continue
		player.global_position = delivery.global_position + Vector3(0, 0.3, -0.8)
		player.global_rotation = Vector3.ZERO
		if bool(item.get("two_handed")):
			player.call("_drop_exploration_item")
		else:
			inventory.call("drop_last", player)
		for frame : int in range(8):
			await physics_frame
		_check(delivery.call("_find_available_item") == item, "%s detectado no ponto de coleta" % item_name)
		Input.action_press("request_abduction")
		delivery.call("_process", 0.01)
		_check(int(wallet.get("money")) == old_money, "%s não paga antes do feixe terminar" % item_name)
		delivery.call("_process", 0.11)
		Input.action_release("request_abduction")
		delivery.call("_process", 0.11)
		_check(int(wallet.get("money")) == old_money + value, "%s paga uma vez na entrega" % item_name)
		delivery.call("_finish_delivery")
		_check(int(wallet.get("money")) == old_money + value, "%s entrega duplicada não paga de novo" % item_name)
		await process_frame
		_check(not is_instance_valid(item), "%s removido após entrega" % item_name)
		delivered += 1
	await _check_legacy_reward()
	var station : Node3D = get_first_node_in_group("upgrade_stations") as Node3D
	_check(station != null, "Totem presente na fazenda")
	if station != null:
		var totem_support : Dictionary = await probe.run(_ray.bind(station.global_position + Vector3.UP * 0.15, station.global_position - Vector3.UP * 0.4))
		_check(not totem_support.is_empty(), "Totem apoiado no chão")
		_check(station.global_position.distance_to(delivery.global_position) > 4.5, "Totem separado da área de entrega")
		player.global_position = station.global_position + Vector3(0, 0.1, 1.6)
		await physics_frame
		await _press("interact")
		_check(bool(station.call("is_open")), "Interação real abre o totem")
		if bool(station.call("is_open")):
			var old_speed : float = float(player.get("speed"))
			station.call("_buy_upgrade", &"movement")
			_check(float(player.get("speed")) > old_speed, "Dinheiro das entregas compra melhoria real")
			station.call("close")
	_check(player.get_node("PlayerHUD").get("_money_label") != null, "Saldo visível na HUD da fazenda")
	print("Farm scavenging: %d objetos, %d tipos, %d entregas, $ %d disponíveis; %d falhas" % [items.size(), types.size(), delivered, total_cash, failures])
	world.queue_free()
	await process_frame
	await process_frame
	quit(1 if failures else 0)


func _check_pickup_wall(item : RigidBody3D) -> void:
	if not bool(await probe.run(_approach.bind(item))):
		_check(false, "Objeto inicial deve permitir conferir bloqueio por parede")
		return
	var wall : StaticBody3D = StaticBody3D.new()
	var collider : CollisionShape3D = CollisionShape3D.new()
	var box : BoxShape3D = BoxShape3D.new()
	box.size = Vector3(3.0, 3.0, 0.1)
	collider.shape = box
	wall.add_child(collider)
	world.add_child(wall)
	var target : Vector3 = item.call("get_pickup_target_position") as Vector3
	wall.global_position = (player.global_position + Vector3.UP + target) * 0.5
	wall.look_at(target)
	await physics_frame
	await physics_frame
	var candidate : RigidBody3D = await probe.run(Callable(player, "get_pickup_candidate"))
	_check(candidate != item, "Centro do objeto continua respeitando paredes na coleta")
	wall.queue_free()
	await physics_frame
	await physics_frame


func _check_legacy_reward() -> void:
	var legacy : RigidBody3D = (load("res://scenes/Spaceship_Scraps1.tscn") as PackedScene).instantiate() as RigidBody3D
	world.add_child(legacy)
	legacy.freeze = true
	legacy.global_position = delivery.global_position + Vector3.UP * 0.8
	player.global_position = delivery.global_position + Vector3(0, 0.3, -0.8)
	var old_money : int = int(wallet.get("money"))
	var value : int = int(legacy.get("score_value"))
	for frame : int in range(4):
		await physics_frame
	Input.action_press("request_abduction")
	delivery.call("_process", 0.11)
	Input.action_release("request_abduction")
	delivery.call("_process", 0.11)
	_check(int(wallet.get("money")) == old_money + value, "Destroço anterior da fazenda também recompensa pela entrega")
	await process_frame
	_check(not is_instance_valid(legacy), "Destroço anterior removido após entrega")


func _approach(item : RigidBody3D) -> bool:
	var obstacles : Dictionary[String, bool] = {}
	for radius : float in [0.8, 1.15, 1.5]:
		for index : int in range(16):
			var angle : float = float(index) * TAU / 16.0
			var point : Vector3 = item.global_position + Vector3(cos(angle), 0, sin(angle)) * radius
			# Procura o piso sob os móveis; uma pose em cima da mesa não prova acesso a pé.
			var floor_query : PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.35, point - Vector3.UP * 2.0, 1)
			floor_query.exclude = furnishing_rids + [player.get_rid()]
			var floor_hit : Dictionary = player.get_world_3d().direct_space_state.intersect_ray(floor_query)
			if floor_hit.is_empty() or (floor_hit["normal"] as Vector3).y < 0.75:
				continue
			point.y = (floor_hit["position"] as Vector3).y + 0.03
			var clearance : PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
			var capsule : CapsuleShape3D = CapsuleShape3D.new()
			capsule.radius = 0.3
			capsule.height = 1.4
			clearance.shape = capsule
			clearance.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * 0.73)
			clearance.collision_mask = 1
			clearance.exclude = [player.get_rid()]
			var collisions : Array[Dictionary] = player.get_world_3d().direct_space_state.intersect_shape(clearance, 1)
			if not collisions.is_empty():
				obstacles[str((collisions[0]["collider"] as Node).get_path())] = true
				continue
			player.global_position = point
			player.velocity = Vector3.ZERO
			if player.call("get_pickup_candidate") == item:
				return true
			var target : Vector3 = item.call("get_pickup_target_position") as Vector3
			var obstruction : Dictionary = _ray(point + Vector3.UP, target)
			if not obstruction.is_empty():
				obstacles[str((obstruction["collider"] as Node).get_path())] = true
	print("Acesso de %s bloqueado por %s" % [item.name, obstacles.keys()])
	return false


func _check_house_access() -> void:
	var route : Node3D = world.get_node("FarmScavenging/Farmhouse/Interior/AccessPath") as Node3D
	var previous : Vector3 = (route.get_child(0) as Node3D).global_position
	var previous_floor : float = previous.y
	var capsule : CapsuleShape3D = (player.get_node("CollisionShape3D") as CollisionShape3D).shape as CapsuleShape3D
	for marker : Node in route.get_children():
		var target : Vector3 = (marker as Node3D).global_position
		var samples : int = maxi(1, ceili(previous.distance_to(target) / 0.12))
		for index : int in range(1, samples + 1):
			var point : Vector3 = previous.lerp(target, float(index) / samples)
			var floor_hit : Dictionary = _ray(point + Vector3.UP * 0.3, point - Vector3.UP * 0.4)
			if floor_hit.is_empty():
				_check(false, "Acesso à casa sem piso rumo a %s em %s" % [marker.name, point])
				break
			point.y = (floor_hit["position"] as Vector3).y
			_check(point.y - previous_floor <= float(player.get("max_step_height")) + 0.02, "Degrau acessível rumo a %s em %s" % [marker.name, point])
			previous_floor = point.y
			var clearance : PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
			clearance.shape = capsule
			clearance.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * (capsule.height * 0.5 + float(player.get("max_step_height")) + 0.03))
			clearance.collision_mask = 1
			clearance.exclude = [player.get_rid()]
			var collisions : Array[Dictionary] = player.get_world_3d().direct_space_state.intersect_shape(clearance, 1)
			if not collisions.is_empty():
				_check(false, "Passagem da casa rumo a %s em %s bloqueada por %s" % [marker.name, point, (collisions[0]["collider"] as Node).get_path()])
		previous = target


func _ray(from : Vector3, to : Vector3) -> Dictionary:
	var query : PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, 1, [player.get_rid()])
	return player.get_world_3d().direct_space_state.intersect_ray(query)


func _press(action : String) -> void:
	await process_frame
	var event : InputEvent = InputMap.action_get_events(action)[0].duplicate() as InputEvent
	event.set("pressed", true)
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	event = event.duplicate() as InputEvent
	event.set("pressed", false)
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	player.set_physics_process(true)
	await physics_frame
	await process_frame
	player.set_physics_process(false)
	await physics_frame


func _check(condition : bool, message : String) -> void:
	if not condition:
		failures += 1
		push_error(message)
