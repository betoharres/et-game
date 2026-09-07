@tool
extends Resource

## Reusable offline profile. Coordinates/segments are in the input mesh's XZ space.
## The original mesh is retained as metadata, so rebaking never compounds relief.
@export_range(1.0, 2.4, 0.05) var wheel_spacing: float = 1.6
@export_range(0.2, 0.8, 0.05) var track_width: float = 0.5
@export_range(0.0, 0.12, 0.005) var rut_depth: float = 0.055
@export_range(0.0, 0.08, 0.005) var wave_height: float = 0.025
@export_range(3.0, 20.0, 0.5) var wave_length: float = 8.0
@export_range(0.0, 0.05, 0.005) var hollow_depth: float = 0.015
@export_range(0.0, 0.08, 0.005) var crown_height: float = 0.025
@export_range(0.05, 0.2, 0.005) var base_lift: float = 0.095
@export_range(0.3, 1.0, 0.05) var mesh_step: float = 0.5
@export var surface_material: Material

var _segments: Array[Dictionary] = []
var _protected: Array[Vector3] = []
var _cache: Dictionary[Vector2i, Array] = {}
var _samples: Dictionary[Vector2i, Vector3] = {}


func configure(segments: Array[Dictionary], protected: Array[Vector3]) -> void:
	_segments = segments
	_protected = protected
	_cache.clear()
	_samples.clear()
	for segment: Dictionary in segments:
		var a: Vector2 = segment["start"]
		var b: Vector2 = segment["end"]
		var margin: float = float(segment["width"]) * 0.5 + 2.0
		var bounds: Rect2 = Rect2(a, Vector2.ZERO).expand(b).grow(margin)
		var first: Vector2i = Vector2i((bounds.position / 16.0).floor())
		var last: Vector2i = Vector2i((bounds.end / 16.0).floor())
		for y: int in range(first.y, last.y + 1):
			for x: int in range(first.x, last.x + 1):
				var key: Vector2i = Vector2i(x, y)
				if not _cache.has(key):
					_cache[key] = []
				_cache[key].append(segment)


## Returns tire wear, corridor influence and physical elevation above base mesh.
func sample(point: Vector2) -> Vector3:
	var key: Vector2i = Vector2i((point * 1000.0).round())
	if _samples.has(key):
		return _samples[key]
	var edge: float = 0.0
	var rut: float = 0.0
	var width_variation: float = 1.0 + 0.12 * sin(point.x * 0.37 + point.y * 0.29)
	var bucket: Array = _cache.get(Vector2i((point / 16.0).floor()), [])
	for segment: Dictionary in bucket:
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(point, segment["start"], segment["end"])
		var candidate: float = point.distance_to(closest)
		var half_width: float = float(segment["width"]) * 0.5
		var influence: float = 1.0 - smoothstep(maxf(half_width - 0.8, 0.1), half_width, candidate)
		# Union of influences: selecting the nearest route creates a height jump
		# where a narrow trail meets a wider road's influence.
		edge = maxf(edge, influence)
		rut = maxf(rut, (1.0 - smoothstep(track_width * 0.22, track_width * width_variation, absf(candidate - wheel_spacing * 0.5))) * influence)
	if bucket.is_empty():
		return Vector3.ZERO
	var transition: float = 1.0
	for zone: Vector3 in _protected:
		transition = minf(transition, smoothstep(zone.z, zone.z + 8.0, point.distance_to(Vector2(zone.x, zone.y))))
	var wave: float = (sin(point.x * TAU / wave_length + 1.7) * 0.55 + sin(point.y * TAU / (wave_length * 1.31)) * 0.45) * wave_height
	var hollow: float = smoothstep(0.78, 0.98, sin(point.x * 0.41 + 0.8) * sin(point.y * 0.33)) * hollow_depth
	# The base terrain stays below the entire road, including the bottoms of ruts.
	var elevation: float = maxf(0.008, base_lift + wave + crown_height * (1.0 - rut) - rut_depth * rut - hollow)
	var result: Vector3 = Vector3(rut, edge, elevation * edge * transition)
	_samples[key] = result
	return result


func bake(node: MeshInstance3D, solid: bool = true) -> void:
	var original: Mesh = node.get_meta("rural_base_mesh", node.mesh) as Mesh
	if solid and not node.has_meta("rural_base_mesh"):
		# The road generator's welded floor closes millimetre clipping seams.
		# Use it for BOTH the new visible surface and physics, not only physics.
		for body: Node in node.get_children():
			if not body is StaticBody3D:
				continue
			for child: Node in body.get_children():
				if child is CollisionShape3D and (child as CollisionShape3D).shape is ConcavePolygonShape3D:
					var shape: ConcavePolygonShape3D = (child as CollisionShape3D).shape as ConcavePolygonShape3D
					var base: SurfaceTool = SurfaceTool.new()
					base.begin(Mesh.PRIMITIVE_TRIANGLES)
					for vertex: Vector3 in shape.get_faces():
						base.add_vertex(vertex)
					base.index()
					original = base.commit()
	node.set_meta("rural_base_mesh", original)
	var faces: PackedVector3Array = original.get_faces()
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in range(0, faces.size(), 3):
		_emit(surface, faces[i], faces[i + 1], faces[i + 2], solid)
	surface.index()
	surface.generate_normals()
	surface.generate_tangents()
	node.mesh = surface.commit()
	node.material_override = surface_material
	node.set_meta("rural_profile", self)
	var subgrade: MeshInstance3D = node.get_node_or_null("Subgrade") as MeshInstance3D
	if subgrade != null:
		subgrade.mesh = node.mesh
		subgrade.material_override = surface_material
	if solid:
		for body: Node in node.get_children():
			if body is StaticBody3D:
				for shape: Node in body.get_children():
					if shape is CollisionShape3D:
						(shape as CollisionShape3D).shape = node.mesh.create_trimesh_shape()
	print("Rural surface %s: %d triangles, relief and collision baked together" % [node.name, node.mesh.get_faces().size() / 3])


func _emit(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, relief: bool) -> void:
	var ab: float = a.distance_squared_to(b)
	var bc: float = b.distance_squared_to(c)
	var ca: float = c.distance_squared_to(a)
	var step: float = mesh_step if relief else maxf(mesh_step, 1.5)
	if maxf(ab, maxf(bc, ca)) > step * step:
		if ab >= bc and ab >= ca:
			_emit(surface, a, (a + b) * 0.5, c, relief)
			_emit(surface, (a + b) * 0.5, b, c, relief)
		elif bc >= ca:
			_emit(surface, a, b, (b + c) * 0.5, relief)
			_emit(surface, a, (b + c) * 0.5, c, relief)
		else:
			_emit(surface, a, b, (c + a) * 0.5, relief)
			_emit(surface, (c + a) * 0.5, b, c, relief)
		return
	for vertex: Vector3 in [a, b, c]:
		var point: Vector2 = Vector2(vertex.x, vertex.z)
		var data: Vector3 = sample(point)
		if relief:
			vertex.y += data.z
		surface.set_color(Color(data.x, data.y, 0.0, 1.0))
		surface.set_uv(point)
		surface.add_vertex(vertex)
