extends RefCounted

## Offline convex polygon union: subtract earlier footprints before triangulating.
## Partitioning at each cutter edge also handles blocks enclosed by road loops.
static func half_plane(poly: PackedVector2Array, a: Vector2, b: Vector2, inside: bool) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	if poly.is_empty():
		return result
	var previous: Vector2 = poly[-1]
	var previous_distance: float = (b - a).cross(previous - a)
	for current: Vector2 in poly:
		var distance: float = (b - a).cross(current - a)
		var current_in: bool = distance >= 0.0 if inside else distance <= 0.0
		var previous_in: bool = previous_distance >= 0.0 if inside else previous_distance <= 0.0
		if current_in != previous_in:
			result.append(previous.lerp(current, previous_distance / (previous_distance - distance)))
		if current_in:
			result.append(current)
		previous = current
		previous_distance = distance
	return result


static func bounds(poly: PackedVector2Array) -> Rect2:
	var rect: Rect2 = Rect2(poly[0], Vector2.ZERO)
	for point: Vector2 in poly:
		rect = rect.expand(point)
	return rect


static func subtract(poly: PackedVector2Array, cutter: PackedVector2Array) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	if not bounds(poly).intersects(bounds(cutter)):
		result.append(poly)
		return result
	var remaining: PackedVector2Array = poly
	for index: int in cutter.size():
		var outside: PackedVector2Array = half_plane(remaining, cutter[index], cutter[(index + 1) % cutter.size()], false)
		if outside.size() >= 3 and not Geometry2D.triangulate_polygon(outside).is_empty():
			result.append(outside)
		remaining = half_plane(remaining, cutter[index], cutter[(index + 1) % cutter.size()], true)
		if remaining.size() < 3:
			break
	return result


static func rectangle(start: Vector2, end: Vector2, width: float) -> PackedVector2Array:
	var side: Vector2 = (end - start).normalized().orthogonal() * width * 0.5
	return PackedVector2Array([start + side, end + side, end - side, start - side])


static func disk(center: Vector2, radius: float) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for index: int in 24:
		points.append(center + Vector2.from_angle(TAU * index / 24.0) * radius)
	return points


static func add_path(polygons: Array[PackedVector2Array], points: Array, width: float) -> void:
	for index: int in points.size() - 1:
		polygons.append(rectangle(points[index], points[index + 1], width))
	for point: Vector2 in points:
		polygons.append(disk(point, width * 0.5))


static func material(color: Color) -> StandardMaterial3D:
	var result: StandardMaterial3D = StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.98
	result.metallic_specular = 0.12
	result.cull_mode = BaseMaterial3D.CULL_DISABLED
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = 731
	noise.frequency = 0.22
	var texture: NoiseTexture2D = NoiseTexture2D.new()
	texture.width = 256
	texture.height = 256
	texture.seamless = true
	texture.noise = noise
	var ramp: Gradient = Gradient.new()
	ramp.colors = PackedColorArray([Color(0.72, 0.72, 0.72), Color(1, 1, 1)])
	texture.color_ramp = ramp
	result.albedo_texture = texture
	return result


static func build(parent: Node3D, label: String, polygons: Array[PackedVector2Array], exclusions: Array[PackedVector2Array], height: float, mat: Material, solid: bool = true, height_at: Callable = Callable()) -> void:
	var occupied: Array[PackedVector2Array] = exclusions.duplicate()
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count: int = 0
	for polygon: PackedVector2Array in polygons:
		var pieces: Array[PackedVector2Array] = [polygon]
		for cutter: PackedVector2Array in occupied:
			if not bounds(polygon).intersects(bounds(cutter)):
				continue
			var next: Array[PackedVector2Array] = []
			for piece: PackedVector2Array in pieces:
				next.append_array(subtract(piece, cutter))
			pieces = next
			if pieces.is_empty():
				break
		occupied.append(polygon)
		for piece: PackedVector2Array in pieces:
			var indices: PackedInt32Array = Geometry2D.triangulate_polygon(piece)
			for index: int in range(0, indices.size(), 3):
				count += emit_triangle(surface, piece[indices[index]], piece[indices[index + 1]], piece[indices[index + 2]], height, height_at)
	if count == 0:
		return
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = label
	surface.index()
	node.mesh = surface.commit()
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	node.owner = parent
	if solid:
		node.create_trimesh_collision()
		if height_at.is_valid():
			# Physics uses the unsplit footprint. Millimetre overlaps close ray/
			# contact cracks caused by float32 clipping; rendered faces stay unique.
			var floor_surface: SurfaceTool = SurfaceTool.new()
			floor_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			for polygon: PackedVector2Array in polygons:
				var center: Vector2 = Vector2.ZERO
				for point: Vector2 in polygon:
					center += point
				center /= polygon.size()
				for index: int in polygon.size():
					var a: Vector2 = polygon[index]
					var b: Vector2 = polygon[(index + 1) % polygon.size()]
					a += (a - center).normalized() * 0.004
					b += (b - center).normalized() * 0.004
					emit_triangle(floor_surface, center, a, b, height, height_at)
			floor_surface.index()
			var floor_mesh: ArrayMesh = floor_surface.commit()
			var collider: CollisionShape3D = node.get_child(0).get_child(0) as CollisionShape3D
			collider.shape = floor_mesh.create_trimesh_shape()
			# A matching subgrade, following the welded road footprint, prevents
			# terrain-coloured pinholes at subpixel clipping seams. It is below
			# the finished surface, never coplanar with it.
			var subgrade: MeshInstance3D = MeshInstance3D.new()
			subgrade.name = "Subgrade"
			subgrade.mesh = floor_mesh
			subgrade.material_override = mat
			subgrade.position.y = -0.012
			subgrade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.add_child(subgrade)
			subgrade.owner = parent
		for body: Node in node.get_children():
			body.owner = parent
			for shape: Node in body.get_children():
				shape.owner = parent
	print("%s: %d triangles on finished surface" % [label, count / 3])


## Millimetre welding removes numerical slivers from diagonal clipping. Short
## triangles follow bridge ramps and rural terrain instead of spanning slopes.
static func emit_triangle(surface: SurfaceTool, a: Vector2, b: Vector2, c: Vector2, height: float, height_at: Callable) -> int:
	var ab: float = a.distance_squared_to(b)
	var bc: float = b.distance_squared_to(c)
	var ca: float = c.distance_squared_to(a)
	# Near-collinear fragments are numerical residue, not curb/road surface.
	# Keeping them can put a raised curb collision across a tile boundary.
	if absf((b - a).cross(c - a)) < sqrt(maxf(ab, maxf(bc, ca))) * 0.002:
		return 0
	if height_at.is_valid() and maxf(ab, maxf(bc, ca)) > 4.0:
		if ab >= bc and ab >= ca:
			var middle: Vector2 = (a + b) * 0.5
			return emit_triangle(surface, a, middle, c, height, height_at) + emit_triangle(surface, middle, b, c, height, height_at)
		if bc >= ca:
			var middle: Vector2 = (b + c) * 0.5
			return emit_triangle(surface, a, b, middle, height, height_at) + emit_triangle(surface, a, middle, c, height, height_at)
		var middle: Vector2 = (c + a) * 0.5
		return emit_triangle(surface, a, b, middle, height, height_at) + emit_triangle(surface, middle, b, c, height, height_at)
	var points: PackedVector2Array = PackedVector2Array([a.snapped(Vector2.ONE * 0.001), b.snapped(Vector2.ONE * 0.001), c.snapped(Vector2.ONE * 0.001)])
	var area: float = (points[1] - points[0]).cross(points[2] - points[0])
	if absf(area) < 0.000001:
		return 0
	if area < 0:
		points.reverse()
	for point: Vector2 in points:
		surface.set_normal(Vector3.UP)
		surface.set_uv(point / 3.0)
		var elevation: float = height_at.call(point) if height_at.is_valid() else height
		surface.add_vertex(Vector3(point.x, snappedf(elevation, 0.0001), point.y))
	return 3
