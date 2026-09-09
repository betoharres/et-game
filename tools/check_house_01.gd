extends SceneTree

## Verifica que a House01 é habitável de verdade: a navegação liga o jardim a
## cada ponto de atividade, a porta de entrada abre com alguém por perto e a
## moradora atravessa a porta e chega à cama.
##
##     .\tools\godot.cmd --headless --path . --script res://tools/check_house_01.gd

const TEST_PATH: String = "res://scenes/Buildings/HouseTest.tscn"
const SPAWN: Vector3 = Vector3(2.0, -0.3, 16.0)
## Quanto a moradora tem para sair do jardim e chegar à cama.
const WALK_TIMEOUT: float = 75.0

var _world: Node3D
var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_world = (load(TEST_PATH) as PackedScene).instantiate() as Node3D
	root.add_child(_world)
	for frame: int in 8:
		await physics_frame

	# A rotina sai de cena: senão a moradora já anda durante os outros testes e
	# o passeio começa de um lugar imprevisível.
	var brain: Node = _world.get_node_or_null("Moradora/NPCBehaviorTree")
	if brain != null:
		brain.process_mode = Node.PROCESS_MODE_DISABLED

	_check_paths()
	await _check_door()
	await _check_walk()

	for failure: String in _failures:
		push_error(failure)
	print("check_house_01: %s" % ("ok" if _failures.is_empty() else "%d falha(s)" % _failures.size()))
	quit(0 if _failures.is_empty() else 1)


func _check_paths() -> void:
	var map: RID = _world.get_viewport().find_world_3d().navigation_map
	var activities: Node3D = _world.get_node("House01/Atividades") as Node3D
	for node: Node in activities.get_children():
		var point: Node3D = node as Node3D
		var target: Vector3 = point.global_position
		var path: PackedVector3Array = NavigationServer3D.map_get_path(map, SPAWN, target, true)
		if path.is_empty():
			_failures.append("Sem caminho do jardim ate %s" % point.name)
			continue
		var reached: float = path[path.size() - 1].distance_to(target)
		if reached > 1.0:
			_failures.append("Caminho ate %s para a %.2f m do destino" % [point.name, reached])
			continue
		print("Caminho ate %-11s %2d pontos, %.1f m" % [point.name, path.size(), _length(path)])


func _check_door() -> void:
	var doors: Array[Node] = _world.find_children("*", "HouseDoor", true, false)
	if doors.size() != 3:
		_failures.append("Esperava 3 portas com folha, achei %d" % doors.size())
	var walker: CharacterBody3D = CharacterBody3D.new()
	walker.add_to_group(&"characters")
	var shape: CollisionShape3D = CollisionShape3D.new()
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = 0.2
	capsule.height = 1.7
	shape.shape = capsule
	walker.add_child(shape)
	_world.add_child(walker)
	for door: Node in doors:
		var handle: Node3D = door as Node3D
		walker.global_position = handle.global_position + Vector3(0.5, 0.9, 0.6)
		for frame: int in 90:
			await physics_frame
		if not handle.call("is_open"):
			_failures.append("Porta %s nao abriu com alguem ao lado" % handle.name)
		else:
			print("Porta %s abre por proximidade" % handle.name)
		walker.global_position = Vector3(0, 40, 0)
		for frame: int in 30:
			await physics_frame
	walker.queue_free()


func _check_walk() -> void:
	var actor: NPCActor = _world.get_node("Moradora") as NPCActor
	var bed: Node3D = _world.get_node("House01/Atividades/Cama") as Node3D
	# O passeio é dirigido (a rotina já está desligada), para medir só
	# navegação, colisão e porta.
	actor.global_position = SPAWN
	for frame: int in 10:
		await physics_frame
	print("Moradora parte de %s rumo a cama em %s" % [actor.global_position, bed.global_position])
	var elapsed: float = 0.0
	var arrived: bool = false
	var entered: bool = false
	while elapsed < WALK_TIMEOUT and not arrived:
		arrived = actor.move_toward_point(bed.global_position, actor.walk_speed)
		if actor.navigation_failed:
			_failures.append("Navegacao da moradora falhou em %s" % actor.global_position)
			return
		if actor.global_position.z < 9.8:
			entered = true
		await physics_frame
		elapsed += 1.0 / float(Engine.physics_ticks_per_second)
	if not entered:
		_failures.append("A moradora nao atravessou a porta em %.0f s" % WALK_TIMEOUT)
	if not arrived:
		_failures.append("A moradora nao chegou a cama em %.0f s (parou em %s)" % [WALK_TIMEOUT, actor.global_position])
		return
	print("Moradora saiu do jardim e chegou a cama em %.1f s" % elapsed)


func _length(path: PackedVector3Array) -> float:
	var total: float = 0.0
	for index: int in path.size() - 1:
		total += path[index].distance_to(path[index + 1])
	return total
