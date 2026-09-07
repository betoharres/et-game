@tool
extends Resource

## Perfil do piso das vias rurais. Hoje ele so cuida das abas de ponte: o chao
## visivel e o terreno, e as marcas de roda sao as curvas de autoria em
## `scripts/terrain/tire_track_3d.gd`. Coordenadas em XZ de mundo.
@export_range(0.006, 0.04, 0.002) var ground_clearance: float = 0.012
@export_range(0.3, 2.0, 0.05) var apron_step: float = 1.0

## Circulos onde o piso antigo fica: so as cabeceiras de ponte, por causa das
## rampas. Fora deles o chao e o terreno.
var _aprons: Array[Vector3] = []


func configure(aprons: Array[Vector3]) -> void:
	_aprons = aprons


## 1 onde o piso ja cedeu lugar ao terreno, 0 no centro de uma cabeceira.
func apron_coverage(point: Vector2) -> float:
	var value: float = 1.0
	for zone: Vector3 in _aprons:
		value = minf(value, smoothstep(zone.z, zone.z + 8.0, point.distance_to(Vector2(zone.x, zone.y))))
	return value


## Recorta o piso antigo, deixando so a aba que encosta nas rampas de ponte, e
## faz essa aba descer ate o terreno na borda de fora: sem faixa larga de terra,
## sem degrau onde ela termina.
func trim_apron(node: MeshInstance3D, height_at: Callable) -> int:
	var original: Mesh = node.get_meta("rural_base_mesh", null) as Mesh
	if original == null:
		original = _welded_base(node)
		node.set_meta("rural_base_mesh", original)
	var faces: PackedVector3Array = original.get_faces()
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var triangles: int = 0
	for index: int in range(0, faces.size(), 3):
		triangles += _emit_apron(surface, faces[index], faces[index + 1], faces[index + 2], height_at)
	var subgrade: Node = node.get_node_or_null("Subgrade")
	if subgrade != null:
		subgrade.free()
	if triangles == 0:
		return 0
	surface.index()
	surface.generate_normals()
	surface.generate_tangents()
	node.mesh = surface.commit()
	for body: Node in node.get_children():
		if body is StaticBody3D:
			for shape: Node in body.get_children():
				if shape is CollisionShape3D:
					(shape as CollisionShape3D).shape = node.mesh.create_trimesh_shape()
	return triangles


## O piso soldado que servia de colisao nao tem as frestas de clipping da malha
## visivel antiga, entao e ele que vira a base da aba.
func _welded_base(node: MeshInstance3D) -> Mesh:
	for body: Node in node.get_children():
		if not body is StaticBody3D:
			continue
		for child: Node in body.get_children():
			if child is CollisionShape3D and (child as CollisionShape3D).shape is ConcavePolygonShape3D:
				var shape: ConcavePolygonShape3D = (child as CollisionShape3D).shape as ConcavePolygonShape3D
				var welded: SurfaceTool = SurfaceTool.new()
				welded.begin(Mesh.PRIMITIVE_TRIANGLES)
				for vertex: Vector3 in shape.get_faces():
					welded.add_vertex(vertex)
				welded.index()
				return welded.commit()
	return node.mesh


func _emit_apron(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, height_at: Callable) -> int:
	var covered: float = minf(apron_coverage(Vector2(a.x, a.z)), minf(apron_coverage(Vector2(b.x, b.z)), apron_coverage(Vector2(c.x, c.z))))
	if covered >= 0.999:
		return 0
	var ab: float = a.distance_squared_to(b)
	var bc: float = b.distance_squared_to(c)
	var ca: float = c.distance_squared_to(a)
	if maxf(ab, maxf(bc, ca)) > apron_step * apron_step:
		if ab >= bc and ab >= ca:
			return _emit_apron(surface, a, (a + b) * 0.5, c, height_at) + _emit_apron(surface, (a + b) * 0.5, b, c, height_at)
		if bc >= ca:
			return _emit_apron(surface, a, b, (b + c) * 0.5, height_at) + _emit_apron(surface, a, (b + c) * 0.5, c, height_at)
		return _emit_apron(surface, a, b, (c + a) * 0.5, height_at) + _emit_apron(surface, (c + a) * 0.5, b, c, height_at)
	for vertex: Vector3 in [a, b, c]:
		var point: Vector2 = Vector2(vertex.x, vertex.z)
		var ground: float = height_at.call(point)
		if not is_nan(ground):
			vertex.y = lerpf(vertex.y, ground + ground_clearance, apron_coverage(point))
		surface.set_uv(point)
		surface.add_vertex(vertex)
	return 1
