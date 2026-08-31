@tool
extends SceneTree

## Confirma que a nave usa somente os assets autorados para sua geometria e
## colisao. Este teste apenas inspeciona recursos serializados; nao cria meshes
## nem shapes.

const SHIP_SCENE_PATH : String = "res://scenes/Space/AlienShip.tscn"
const SHIP_MESH_PATH : String = "res://3dModelos/ET_Alien_Space_Ship.glb"
const COLLISION_MESH_PATH : String = "res://3dModelos/ET_SpaceShip_CustomCollision.glb"
const COLLISION_SHAPE_PATH : String = "res://Materiais/AlienShipExteriorCollision.tres"

var _failed : bool = false


func _initialize() -> void:
	var packed_ship : PackedScene = load(SHIP_SCENE_PATH) as PackedScene
	_require(packed_ship != null, "AlienShip.tscn nao carregou")
	if packed_ship == null:
		quit(1)
		return

	var ship : AlienShip = packed_ship.instantiate() as AlienShip
	_require(ship != null, "AlienShip.tscn nao instancia AlienShip")
	if ship == null:
		quit(1)
		return
	root.add_child(ship)

	var ship_mesh_node : MeshInstance3D = ship.get_node_or_null("ShipMesh") as MeshInstance3D
	var authored_body : StaticBody3D = ship.get_node_or_null("AuthoredCollision") as StaticBody3D
	var collision_node : CollisionShape3D = (
		ship.get_node_or_null("AuthoredCollision/CollisionShape3D") as CollisionShape3D
	)
	_require(ship_mesh_node != null, "ShipMesh ausente")
	_require(authored_body != null, "AuthoredCollision ausente")
	_require(collision_node != null, "CollisionShape3D autorado ausente")
	_require(ship.get_node_or_null("Interior/Shell") == null, "casco procedural antigo ainda existe")

	var ship_mesh : ArrayMesh = load(SHIP_MESH_PATH) as ArrayMesh
	var collision_mesh : ArrayMesh = load(COLLISION_MESH_PATH) as ArrayMesh
	var collision_shape : ConcavePolygonShape3D = (
		load(COLLISION_SHAPE_PATH) as ConcavePolygonShape3D
	)
	_require(ship_mesh != null, "mesh combinado nao carregou")
	_require(collision_mesh != null, "mesh de colisao autorado nao carregou")
	_require(collision_shape != null, "shape de colisao serializado nao carregou")

	if ship_mesh_node != null and ship_mesh != null:
		_require(ship_mesh_node.mesh == ship_mesh, "ShipMesh nao referencia o GLB combinado")
	if collision_node != null and collision_shape != null:
		_require(collision_node.shape == collision_shape, "CollisionShape3D nao referencia o shape autorado")

	if collision_mesh != null and collision_shape != null:
		var source_faces : PackedVector3Array = collision_mesh.get_faces()
		var shape_faces : PackedVector3Array = collision_shape.get_faces()
		_require(not source_faces.is_empty(), "mesh de colisao nao tem faces")
		_require(source_faces.size() == shape_faces.size(), (
			"shape tem %d vertices, mas o GLB autorado tem %d"
			% [shape_faces.size(), source_faces.size()]
		))
		if not source_faces.is_empty() and not shape_faces.is_empty():
			var source_bounds : AABB = _bounds_for(source_faces)
			var shape_bounds : AABB = _bounds_for(shape_faces)
			_require(source_bounds.is_equal_approx(shape_bounds), (
				"bounds da colisao divergem: GLB=%s shape=%s"
				% [source_bounds, shape_bounds]
			))
			print("[alien-ship] mesh=%s colisao=%s vertices=%d" % [
				ship_mesh.get_aabb(),
				shape_bounds,
				shape_faces.size(),
			])

	ship.queue_free()
	if _failed:
		quit(1)
		return
	print("[alien-ship] OK: mesh combinado e colisao autorada estao ligados a cena")
	quit()


func _bounds_for(points : PackedVector3Array) -> AABB:
	var bounds : AABB = AABB(points[0], Vector3.ZERO)
	for point : Vector3 in points:
		bounds = bounds.expand(point)
	return bounds


func _require(condition : bool, message : String) -> void:
	if condition:
		return
	_failed = true
	push_error("[alien-ship] %s" % message)
