extends SceneTree

const Scrap : Script = preload("res://scripts/spaceship_scraps.gd")
var failures : int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world : Node3D = Node3D.new()
	root.add_child(world)
	current_scene = world
	var recovery_scene : PackedScene = load("res://scenes/RecoveryPoint.tscn")
	var point : Node3D = recovery_scene.instantiate()
	world.add_child(point)
	var zone : Area3D = point.get_node("CollectionArea")
	var ship : Node3D = point.get_node("RecoveryShip")
	ship.set_physics_process(false)
	var character : Node3D = Node3D.new()
	world.add_child(character)
	var inside : RigidBody3D = _item(world, Vector3(0, 0.5, 0))
	var outside : RigidBody3D = _item(world, Vector3(4.5, 0.5, 0))
	var untouched : RigidBody3D = _item(world, Vector3(1, 0.5, 0))
	untouched.remove_meta("recovery_dropped")
	var held : RigidBody3D = _item(world, Vector3(0, 1, 0))
	held.call("pickup", character)
	var locator : RigidBody3D = preload("res://scenes/Items/DebrisLocator.tscn").instantiate()
	world.add_child(locator)
	locator.position = Vector3(2, 0.5, 0)
	locator.freeze = true
	locator.set_meta("recovery_dropped", true)
	await physics_frame
	await physics_frame
	await process_frame
	var candidates : Array[RigidBody3D] = zone.call("available_items")
	_check(candidates.size() == 1 and candidates.has(inside), "Somente item largado dentro; exclui externo, carregado, localizador e nunca largado")
	_check(bool(zone.call("contains_position", Vector3(0, 0.2, 0))), "Feedback dentro do volume")
	_check(not bool(zone.call("contains_position", Vector3(4.01, 0.2, 0))), "Limite coincide com o círculo")
	var start : Vector3 = ship.global_position
	ship.call("_physics_process", 0.1)
	_check(ship.global_position.distance_to(start) <= 2.81, "Nave vem da posição atual sem teleporte")
	inside.position = Vector3(8, 0.5, 0)
	_check((zone.call("available_items") as Array).is_empty(), "Item retirado deixa de ser candidato imediatamente")
	ship.call("_physics_process", 0.1)
	_check(not inside.get("being_abducted"), "Retirada antes da chegada cancela coleta")
	inside.position = Vector3(0, 0.5, 0)
	ship.position = Vector3(0, 45, 0)
	var score_before : int = int(root.get_node("GlobalScore").get("score"))
	ship.call("_physics_process", 0.1)
	_check(bool(inside.get("being_abducted")), "Nave inicia coleta ao chegar")
	_check(int(root.get_node("GlobalScore").get("score")) == score_before, "Sem pontuação antes da subida")
	for step : int in range(140):
		ship.call("_physics_process", 0.1)
	await process_frame
	_check(not is_instance_valid(inside), "Carga é removida ao alcançar a nave")
	_check(int(root.get_node("GlobalScore").get("score")) == score_before + 10, "Entrega pontua exatamente uma vez")
	_check(is_instance_valid(outside) and not outside.get("being_abducted"), "Carga externa permanece no mapa")
	var after : Vector3 = ship.position
	ship.call("_physics_process", 0.1)
	_check(ship.position != after, "Retoma voo depois da coleta")
	print("Recovery ship: %d falhas" % failures)
	quit(0 if failures == 0 else 1)


func _item(world : Node3D, position_value : Vector3) -> RigidBody3D:
	var item : RigidBody3D = Scrap.new()
	item.collision_layer = 8
	item.collision_mask = 1
	item.freeze = true
	var shape : CollisionShape3D = CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	item.add_child(shape)
	world.add_child(item)
	item.position = position_value
	item.add_to_group("pickup_items")
	item.set_meta("recovery_dropped", true)
	return item


func _check(condition : bool, message : String) -> void:
	if not condition:
		failures += 1
		push_error(message)
