extends SceneTree
## Mede os acessos contra as colisoes salvas, sem render ou simulacao de NPCs.

## A casca do kit e larga; a casa modular em que se entra e mais estreita e so
## precisa caber no lote com recuo.
const MIN_PRESET: Vector2 = Vector2(9.0, 8.0)
const MIN_LIVEABLE: Vector2 = Vector2(6.0, 10.0)
## Cobertura de varanda e agua de telhado cruzam o caminho por cima: o que
## comeca acima disto nao barra ninguem.
const HEADROOM: float = 2.1

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene: PackedScene = load("res://scenes/CountryTown/Districts/UrbanInfill.tscn") as PackedScene
	if scene == null:
		quit(1)
		return
	var town: Node3D = scene.instantiate() as Node3D
	root.add_child(town)
	var footprints: Array[Rect2] = []
	var houses: int = 0
	var parked: int = 0
	for node: Node in town.get_children():
		if not node.has_node("House"):
			continue
		var lot: Node3D = node as Node3D
		houses += 1
		parked += int(lot.has_node("ParkedCar"))
		var size: Vector2 = lot.get_meta("lot_size")
		var bounds: AABB = lot.transform * AABB(Vector3(-size.x / 2, 0, -size.y / 2), Vector3(size.x, 1, size.y))
		var footprint: Rect2 = Rect2(bounds.position.x, bounds.position.z, bounds.size.x, bounds.size.z)
		for other: Rect2 in footprints:
			if footprint.grow(0.1).intersects(other):
				_failures.append("%s sobrepoe outro lote em %s" % [lot.name, footprint])
		footprints.append(footprint)
		var house: Node3D = lot.get_node("House") as Node3D
		var mesh_house: MeshInstance3D = house as MeshInstance3D
		# Lote com casa modular traz a cena inteira, nao a casca de uma malha so.
		var house_bounds: AABB = house.transform * mesh_house.mesh.get_aabb() if mesh_house != null else _visual_bounds(house)
		var floor_area: Vector2 = MIN_PRESET if mesh_house != null else MIN_LIVEABLE
		if house_bounds.size.x < floor_area.x or house_bounds.size.z < floor_area.y:
			_failures.append("%s tem casa pequena demais: %s" % [lot.name, house_bounds.size])
		if not Rect2(-size / 2, size).encloses(Rect2(house_bounds.position.x, house_bounds.position.z, house_bounds.size.x, house_bounds.size.z)):
			_failures.append("%s tem casa fora da divisa" % lot.name)
		_check_access(lot, "PedestrianGate", "Entrance", 0.55, false)
		_check_access(lot, "VehicleGate", "ParkingSpace", 1.25, true)
	for failure: String in _failures:
		printerr(failure)
	print("Lotes: %d casas, %d carros estacionados, %d falhas de escala/divisa/acesso." % [houses, parked, _failures.size()])
	town.free()
	quit(0 if _failures.is_empty() and houses > 0 else 1)


func _check_access(lot: Node3D, from: String, to: String, radius: float, skip_car: bool) -> void:
	var start: Marker3D = lot.get_node_or_null(from) as Marker3D
	var end: Marker3D = lot.get_node_or_null(to) as Marker3D
	if start == null or end == null:
		_failures.append("%s sem acesso %s/%s" % [lot.name, from, to])
		return
	for node: Node in lot.find_children("*", "CollisionShape3D", true, false):
		var collider: CollisionShape3D = node as CollisionShape3D
		if collider.disabled or collider.shape == null or collider.get_parent() is Area3D:
			continue
		if skip_car and lot.has_node("ParkedCar") and lot.get_node("ParkedCar").is_ancestor_of(collider):
			continue
		var bounds: AABB = _relative_transform(lot, collider) * collider.shape.get_debug_mesh().get_aabb()
		if bounds.end.y < 0.25 or bounds.position.y > HEADROOM:
			continue
		var rect: Rect2 = Rect2(bounds.position.x, bounds.position.z, bounds.size.x, bounds.size.z).grow(radius)
		for step: int in 33:
			var point: Vector3 = start.position.lerp(end.position, float(step) / 32.0)
			if rect.has_point(Vector2(point.x, point.z)):
				_failures.append("%s: %s obstrui %s em %s" % [lot.name, lot.get_path_to(collider), from, lot.to_global(point)])
				break


func _visual_bounds(node: Node, parent_transform: Transform3D = Transform3D.IDENTITY) -> AABB:
	var local: Transform3D = parent_transform
	if node is Node3D:
		local *= (node as Node3D).transform
	var bounds: AABB = AABB()
	var started: bool = false
	var visual: MeshInstance3D = node as MeshInstance3D
	if visual != null and visual.mesh != null and visual.visible:
		bounds = local * visual.mesh.get_aabb()
		started = true
	for child: Node in node.get_children():
		var sub: AABB = _visual_bounds(child, local)
		if sub.size == Vector3.ZERO:
			continue
		bounds = sub if not started else bounds.merge(sub)
		started = true
	return bounds


## As portas da casa modular trazem colisores que ainda nao entraram na arvore
## quando a checagem roda, e `global_transform` deles sairia zerado.
func _relative_transform(lot: Node3D, node: Node3D) -> Transform3D:
	var stack: Transform3D = Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != lot:
		if current is Node3D:
			stack = (current as Node3D).transform * stack
		current = current.get_parent()
	return stack
