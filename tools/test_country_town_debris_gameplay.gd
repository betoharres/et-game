extends SceneTree

var failures : int = 0
var world : Node3D
var player : CharacterBody3D
var inventory : Node
var hud : CanvasLayer
var last_feedback : String = ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	world = (load("res://scenes/CountryTown/CountryTown.tscn") as PackedScene).instantiate() as Node3D
	# Isola a exploração de ataques e tráfego; preserva geometria e colisões do mapa.
	for node_name : String in ["NPCs", "VehiclesHolder", "EnvironmentAudio"]:
		var node : Node = world.get_node_or_null(node_name)
		if node != null:
			node.free()
	root.add_child(world)
	current_scene = world
	player = world.get_node("Player") as CharacterBody3D
	player.set_physics_process(false)
	inventory = player.get_node("ExplorationInventory")
	hud = player.get_node("PlayerHUD") as CanvasLayer
	inventory.connect("feedback", func(message : String) -> void: last_feedback = message)
	# Este teste cobre a coleta em si, não o objetivo de achar o local da
	# queda (scripts/country_town.gd); revela os destroços direto.
	world.call("reveal_debris")
	for frame : int in range(120):
		await physics_frame
	var locator : AlienTechnologyItem = world.get_node("AlienDebrisTest/DebrisLocator") as AlienTechnologyItem
	_check(await _approach(locator), "Localizador acessível perto do spawn")
	await _press("interact")
	_check(locator.state == AlienTechnologyItem.State.INVENTORY, "E coleta equipamento no mapa")
	await _press("inventory_slot_1")
	var parts : Array[AlienDebris] = []
	for node : Node in get_nodes_in_group("alien_debris"):
		parts.append(node as AlienDebris)
	for cycle : int in range(3):
		var target : AlienDebris = _nearest_small(parts)
		_check(target != null, "Existe próximo alvo")
		if target == null:
			break
		player.global_position = target.global_position + Vector3(0, 0, 12)
		var distant : int = int(DebrisLocator.scan(player)["strength"])
		_check(await _approach(target), "Acesso ao alvo do ciclo %d em %s" % [cycle + 1, target.global_position])
		_check(int(DebrisLocator.scan(player)["strength"]) >= distant, "Sinal aumenta na aproximação")
		hud.call("_physics_process", 0.1)
		var prompt : Label = hud.get("_pickup_prompt") as Label
		_check(prompt.text.begins_with("[E] Coletar"), "Aviso de coleta real no HUD")
		var old_count : int = _world_count(parts)
		await _press("interact")
		_check(target.state == AlienTechnologyItem.State.INVENTORY and not target.visible and target.collision_layer == 0, "Ciclo %d: desaparece e entra no inventário" % (cycle + 1))
		_check(_world_count(parts) == old_count - 1 and DebrisLocator.scan(player)["strength"] > 0, "Ciclo %d: detector busca outro WORLD" % (cycle + 1))
		print("Ciclo %d: localizar -> aproximar -> [E] -> inventário -> novo sinal" % (cycle + 1))
	_check(inventory.call("used_slots") == 4, "Localizador e três partes enchem inventário")
	var extra : AlienDebris = _nearest_small(parts)
	_check(await _approach(extra), "Próximo objeto continua acessível")
	await _press("interact")
	_check(last_feedback == "Inventário cheio." and extra.state == AlienTechnologyItem.State.WORLD and extra.visible, "Inventário cheio mantém objeto no mapa")
	_check((hud.get("_inventory_message") as Label).text == last_feedback, "HUD exibe recusa completa")
	for part : AlienDebris in parts:
		if part.state == AlienTechnologyItem.State.WORLD:
			_check(await _approach(part), "Destroço acessível em %s" % part.global_position)
	var large : AlienDebris = world.get_node("AlienDebrisTest/Debris8") as AlienDebris
	_check(await _approach(large), "Motor grande acessível")
	await _press("interact")
	_check(last_feedback == "Este objeto é grande demais para transportar." and large.state == AlienTechnologyItem.State.WORLD and large.visible, "Motor permanece para recuperação futura mesmo com inventário cheio")
	_check(await _approach(extra), "Volta ao objeto pequeno")
	var wall : StaticBody3D = StaticBody3D.new()
	var shape : CollisionShape3D = CollisionShape3D.new()
	var box : BoxShape3D = BoxShape3D.new()
	box.size = Vector3(0.3, 3, 0.3)
	shape.shape = box
	wall.add_child(shape)
	world.add_child(wall)
	wall.global_position = (player.global_position + player.global_basis.y + extra.global_position) * 0.5
	await physics_frame
	await physics_frame
	_check(player.call("get_pickup_candidate") != extra, "Parede bloqueia aviso e coleta")
	wall.queue_free()
	await physics_frame
	await physics_frame
	player.global_position = extra.global_position + Vector3(0, 0, 3)
	_check(player.call("get_pickup_candidate") != extra, "Fora de alcance não oferece coleta")
	await _press("inventory_slot_1")
	Input.action_press("crouch")
	await _press("interact")
	Input.action_release("crouch")
	_check(locator.state == AlienTechnologyItem.State.WORLD and inventory.call("used_slots") == 3, "Soltar localizador libera slot")
	_check(await _approach(extra), "Reaproxima após liberar espaço")
	await _press("interact")
	_check(extra.state == AlienTechnologyItem.State.INVENTORY, "Coleta funciona após liberar espaço")
	print("Countrytown gameplay: %d falhas" % failures)
	world.queue_free()
	await process_frame
	await process_frame
	quit(1 if failures else 0)


func _approach(item : AlienTechnologyItem) -> bool:
	if item == null:
		return false
	var terrain : Terrain3D = world.get_node("NavigationRegion3D/Terrain3D") as Terrain3D
	for index : int in range(16):
		var angle : float = float(index) * TAU / 16.0
		var point : Vector3 = item.global_position + Vector3(cos(angle), 0, sin(angle)) * 1.5
		point.y = terrain.data.get_height(point) + 0.1
		player.global_position = point
		player.velocity = Vector3.ZERO
		await physics_frame
		var clearance : PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
		var capsule : CapsuleShape3D = CapsuleShape3D.new()
		capsule.radius = 0.3
		capsule.height = 1.4
		clearance.shape = capsule
		clearance.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * 0.85)
		clearance.collision_mask = 1
		clearance.exclude = [player.get_rid()]
		if not player.get_world_3d().direct_space_state.intersect_shape(clearance, 1).is_empty():
			continue
		if player.call("get_pickup_candidate") == item:
			return true
	return false


func _press(action : String) -> void:
	# Entrada fora da física reproduz o teclado com Jolt em outra thread.
	await process_frame
	var event : InputEventKey = InputMap.action_get_events(action)[0].duplicate() as InputEventKey
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	event = event.duplicate() as InputEventKey
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	player.set_physics_process(true)
	await physics_frame
	await process_frame
	player.set_physics_process(false)
	await physics_frame


func _nearest_small(parts : Array[AlienDebris]) -> AlienDebris:
	var nearest : AlienDebris = null
	var distance : float = INF
	for part : AlienDebris in parts:
		if part.state != AlienTechnologyItem.State.WORLD or not part.definition.transportable:
			continue
		var candidate : float = player.global_position.distance_to(part.global_position)
		if candidate < distance:
			nearest = part
			distance = candidate
	return nearest


func _world_count(parts : Array[AlienDebris]) -> int:
	var count : int = 0
	for part : AlienDebris in parts:
		if part.state == AlienTechnologyItem.State.WORLD:
			count += 1
	return count


func _check(condition : bool, message : String) -> void:
	if not condition:
		failures += 1
		push_error(message)
