extends RefCounted
## Vitrine de interior para os presets fechados do PolygonTown, usada pelo
## bairro do Country Town. Biblioteca `RefCounted`, nao e uma ferramenta.
##
## O preset e uma casca unica: o vao de janela existe so como painel de vidro
## opaco, e nao ha piso, parede interna nem mobilia. Trocando o painel por vidro
## transparente aparece o vazio da casca -- as paredes do fundo somem por
## back-face culling e ve-se o ceu. Por isso cada painel ganha atras de si um
## comodo raso, e todos os comodos de uma casa saem numa malha unica.

## O vidro do kit e azul e cobre metade do que esta atras: sobre um comodo sem
## lampada ele apaga a vista. O da vitrine e o mesmo vidro mais limpo.
const GLASS_TINT: Color = Color(0.62, 0.72, 0.78, 0.22)
## Material das janelas cegas das casas; o das vitrines de loja ja e translucido
## e so precisa do comodo atras.
const OPAQUE_MARK: String = "Window_Glass_Opaque"
const CLEAR_MARKS: Array[String] = ["Base_Glass", "Window_Glass_mat"]

## Peitoril a 1,75 e verga a 3,21 no terreo; o andar de cima repete 3 m acima.
## O teto do comodo para antes do telhado do preset.
const UPPER_SILL_Y: float = 4.0
const GROUND_FLOOR: float = 0.06
const GROUND_CEILING: float = 3.8
const UPPER_FLOOR: float = 4.0
const UPPER_CEILING: float = 6.9

## O comodo e raso de proposito: numa casa do kit as janelas ficam a pouco mais
## de um metro umas das outras, e em paredes perpendiculares. Fundo profundo
## atravessa a janela vizinha; raso, cada vao mostra so o proprio comodo.
const ROOM_DEPTH: float = 1.3
const ROOM_HALF_WIDTH: float = 0.7
## Folga entre um comodo e o vizinho ja montado.
const ROOM_GAP: float = 0.05
## Folga entre o fundo do comodo e a parede que o raio encontrou.
const WALL_MARGIN: float = 0.08
const MIN_DEPTH: float = 0.35
const MIN_HALF_WIDTH: float = 0.5

## Paletas de parede e piso, uma por casa; a mobilia sorteia dentro da paleta.
## Tons ja pintados como o comodo se ve pela janela: a vitrine nao recebe luz
## da cena, entao a cor de cada face e o valor final.
const WALL_COLORS: Array[Color] = [
	Color(0.50, 0.47, 0.41),
	Color(0.43, 0.46, 0.43),
	Color(0.52, 0.44, 0.37),
	Color(0.40, 0.44, 0.49),
	Color(0.54, 0.51, 0.46),
]
const FLOOR_COLORS: Array[Color] = [
	Color(0.24, 0.17, 0.11),
	Color(0.31, 0.23, 0.15),
	Color(0.20, 0.16, 0.14),
]
const FURNITURE_COLORS: Array[Color] = [
	Color(0.20, 0.15, 0.11),
	Color(0.16, 0.20, 0.24),
	Color(0.28, 0.20, 0.16),
	Color(0.18, 0.23, 0.19),
	Color(0.34, 0.28, 0.20),
]


## Decora todo predio pendurado no no, inclusive portas de vidro em malha
## separada. Devolve quantos comodos foram criados.
func decorate_tree(building: Node3D, variant: int) -> int:
	var rooms: int = 0
	if building is MeshInstance3D:
		rooms += decorate(building as MeshInstance3D, variant)
	for child: Node in building.find_children("*", "MeshInstance3D", true, false):
		rooms += decorate(child as MeshInstance3D, variant + rooms)
	return rooms


## Troca o vidro cego por vidro transparente e pendura a vitrine na casa.
## Devolve quantos comodos foram criados.
func decorate(house: MeshInstance3D, variant: int) -> int:
	var mesh: ArrayMesh = house.mesh as ArrayMesh
	if mesh == null:
		return 0
	var glass: int = -1
	for surface: int in mesh.get_surface_count():
		var material: Material = house.get_surface_override_material(surface)
		if material == null:
			continue
		if material.resource_path.contains(OPAQUE_MARK):
			glass = surface
			house.set_surface_override_material(surface, _glass())
			continue
		for mark: String in CLEAR_MARKS:
			if material.resource_path.contains(mark):
				glass = surface
	if glass < 0:
		return 0
	var walls: PackedVector3Array = _wall_triangles(mesh, glass)
	var panels: Array[Dictionary] = _panels(mesh, glass)
	if panels.is_empty():
		return 0
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(variant)
	var wall_color: Color = WALL_COLORS[variant % WALL_COLORS.size()]
	var floor_color: Color = FLOOR_COLORS[variant % FLOOR_COLORS.size()]
	var surface_tool: SurfaceTool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Cada vao reserva o nicho atras de si antes de qualquer comodo ser montado:
	# assim o comodo do vizinho nunca cobre esta janela, so encolhe.
	var rooms: Array[AABB] = []
	var guards: Array[AABB] = []
	for panel: Dictionary in panels:
		guards.append(_guard(panel))
	for index: int in panels.size():
		var blockers: Array[AABB] = rooms.duplicate()
		for other: int in guards.size():
			if other != index:
				blockers.append(guards[other])
		_room(surface_tool, panels[index], walls, rooms, blockers, rng, wall_color, floor_color)
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.name = "Vitrine"
	visual.mesh = surface_tool.commit()
	visual.material_override = _material()
	# O comodo so existe para ser visto pela janela: nao projeta sombra nem
	# entra no GI, e some antes da casa porque o vao tem menos de um metro.
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	visual.layers = 128
	visual.visibility_range_end = 120.0
	visual.visibility_range_end_margin = 15.0
	house.add_child(visual)
	return panels.size()


func _glass() -> StandardMaterial3D:
	var glass: StandardMaterial3D = StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = GLASS_TINT
	glass.roughness = 0.35
	glass.metallic_specular = 0.35
	# Sem escrever profundidade o vidro nao corta o comodo que esta atras dele.
	glass.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	return glass


func _material() -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	# Nao ha lampada dentro da casca do preset, e o bairro e noturno: iluminado
	# pela cena o comodo seria uma mancha preta, e sob o sol da inspecao, uma
	# mancha branca. Pintado, ele se le igual a qualquer hora e nao custa luz.
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# O comodo e uma casca aberta na janela: sem culling ele fecha visualmente
	# de qualquer angulo de onde a janela deixa ver.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


# --- leitura da malha do preset ----------------------------------------------


func _wall_triangles(mesh: ArrayMesh, glass: int) -> PackedVector3Array:
	var triangles: PackedVector3Array = PackedVector3Array()
	for surface: int in mesh.get_surface_count():
		if surface == glass:
			continue
		var arrays: Array = mesh.surface_get_arrays(surface)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			triangles.append_array(points)
			continue
		for index: int in indices:
			triangles.append(points[index])
	return triangles


func _root_of(parent: PackedInt32Array, item: int) -> int:
	var root: int = item
	while parent[root] != root:
		root = parent[root]
	return root


## Cada janela e uma ilha de triangulos na superficie de vidro. Solda por
## posicao antes de unir, senao a UV duplicada parte a ilha em dois.
func _panels(mesh: ArrayMesh, glass: int) -> Array[Dictionary]:
	var arrays: Array = mesh.surface_get_arrays(glass)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if points.is_empty() or indices.is_empty():
		return []
	var welded: Dictionary[String, int] = {}
	var weld_of: PackedInt32Array = PackedInt32Array()
	weld_of.resize(points.size())
	for i: int in points.size():
		var key: String = "%.3f_%.3f_%.3f" % [points[i].x, points[i].y, points[i].z]
		if not welded.has(key):
			welded[key] = welded.size()
		weld_of[i] = welded[key]
	var parent: PackedInt32Array = PackedInt32Array()
	parent.resize(welded.size())
	for i: int in welded.size():
		parent[i] = i
	for triangle: int in indices.size() / 3:
		var first: int = _root_of(parent, weld_of[indices[triangle * 3]])
		for corner: int in [1, 2]:
			var other: int = _root_of(parent, weld_of[indices[triangle * 3 + corner]])
			if first != other:
				parent[other] = first
	var islands: Dictionary[int, Dictionary] = {}
	for i: int in points.size():
		var root: int = _root_of(parent, weld_of[i])
		if not islands.has(root):
			islands[root] = {"box": AABB(points[i], Vector3.ZERO), "normal": Vector3.ZERO}
		islands[root]["box"] = (islands[root]["box"] as AABB).expand(points[i])
		islands[root]["normal"] = (islands[root]["normal"] as Vector3) + normals[i]
	var panels: Array[Dictionary] = []
	for root: int in islands:
		var box: AABB = islands[root]["box"]
		var normal: Vector3 = islands[root]["normal"]
		normal.y = 0.0
		if normal.length() < 0.001:
			continue
		panels.append({"center": box.get_center(), "normal": normal.normalized(), "size": box.size})
	return panels


## Distancia ate a primeira parede, ou -1 sem encontro. Os triangulos da casca
## sao de face unica, entao o teste roda nas duas orientacoes.
func _distance_to_wall(walls: PackedVector3Array, from: Vector3, direction: Vector3, limit: float) -> float:
	var nearest: float = -1.0
	for triangle: int in walls.size() / 3:
		var a: Vector3 = walls[triangle * 3]
		var b: Vector3 = walls[triangle * 3 + 1]
		var c: Vector3 = walls[triangle * 3 + 2]
		var hit: Variant = Geometry3D.ray_intersects_triangle(from, direction, a, b, c)
		if hit == null:
			hit = Geometry3D.ray_intersects_triangle(from, direction, a, c, b)
		if hit == null:
			continue
		var distance: float = from.distance_to(hit)
		if distance > 0.05 and distance <= limit and (nearest < 0.0 or distance < nearest):
			nearest = distance
	return nearest


# --- comodo ------------------------------------------------------------------


## Monta um comodo atras do painel e guarda a caixa que ele ocupa, para os
## proximos se afastarem.
func _room(surface_tool: SurfaceTool, panel: Dictionary, walls: PackedVector3Array, rooms: Array[AABB], blockers: Array[AABB], rng: RandomNumberGenerator, wall_color: Color, floor_color: Color) -> void:
	var center: Vector3 = panel["center"]
	var normal: Vector3 = panel["normal"]
	var inward: Vector3 = -normal
	var right: Vector3 = Vector3.UP.cross(normal).normalized()
	var upper: bool = center.y > UPPER_SILL_Y
	var floor_y: float = UPPER_FLOOR if upper else GROUND_FLOOR
	var ceiling_y: float = UPPER_CEILING if upper else GROUND_CEILING
	var probe: Vector3 = center + inward * 0.05
	# Raio sem encontro quer dizer caminho livre: o comodo cabe inteiro.
	var reach: float = _distance_to_wall(walls, probe, inward, ROOM_DEPTH + WALL_MARGIN)
	var depth: float = ROOM_DEPTH if reach < 0.0 else maxf(MIN_DEPTH, reach - WALL_MARGIN)
	# Comodo pelo menos tao largo quanto o vao, senao a vitrine de loja mostra
	# a borda do quarto dentro do proprio vidro.
	var span: Vector3 = panel["size"]
	var wanted: float = maxf(ROOM_HALF_WIDTH, (absf(span.x * right.x) + absf(span.z * right.z)) * 0.5 + 0.3)
	var side: Vector3 = probe + inward * minf(0.4, depth * 0.5)
	var left_half: float = wanted
	var right_half: float = wanted
	var to_left: float = _distance_to_wall(walls, side, -right, wanted + WALL_MARGIN)
	if to_left >= 0.0:
		left_half = maxf(MIN_HALF_WIDTH, to_left - WALL_MARGIN)
	var to_right: float = _distance_to_wall(walls, side, right, wanted + WALL_MARGIN)
	if to_right >= 0.0:
		right_half = maxf(MIN_HALF_WIDTH, to_right - WALL_MARGIN)
	var base: Vector3 = Vector3(center.x, 0.0, center.z)
	var near: float = 0.02
	var limits: Vector3 = _clip(base, right, inward, Vector3(left_half, right_half, depth), floor_y, ceiling_y, blockers)
	left_half = limits.x
	right_half = limits.y
	depth = limits.z
	if depth < MIN_DEPTH or left_half + right_half < 0.4:
		return
	var corner: Vector3 = base + right * -left_half + Vector3(0.0, floor_y, 0.0)
	var box: AABB = AABB(corner, Vector3.ZERO)
	box = box.expand(base + right * right_half + inward * depth + Vector3(0.0, ceiling_y, 0.0))
	rooms.append(box)
	var faces: PackedVector3Array = PackedVector3Array()
	# Fundo, laterais, piso e teto; a face da janela fica aberta.
	_wall(surface_tool, faces, base, right, inward,
		[Vector2(-left_half, depth), Vector2(right_half, depth)], floor_y, ceiling_y, wall_color, normal)
	_wall(surface_tool, faces, base, right, inward,
		[Vector2(-left_half, near), Vector2(-left_half, depth)], floor_y, ceiling_y, wall_color.darkened(0.3), right)
	_wall(surface_tool, faces, base, right, inward,
		[Vector2(right_half, near), Vector2(right_half, depth)], floor_y, ceiling_y, wall_color.darkened(0.3), -right)
	_deck(surface_tool, faces, base, right, inward, -left_half, right_half, near, depth, floor_y, floor_color, Vector3.UP)
	_deck(surface_tool, faces, base, right, inward, -left_half, right_half, near, depth, ceiling_y, wall_color.lightened(0.22), Vector3.DOWN)
	_furnish(surface_tool, faces, base, right, inward, left_half, right_half, floor_y, ceiling_y, center.y, depth, rng)


## Nicho reservado por um vao: o pedaco logo atras do vidro que nenhum comodo
## vizinho pode ocupar, senao a janela mostraria a parede do quarto do lado.
func _guard(panel: Dictionary) -> AABB:
	var center: Vector3 = panel["center"]
	var span: Vector3 = panel["size"]
	var inward: Vector3 = -(panel["normal"] as Vector3)
	var half: Vector3 = Vector3(maxf(span.x, 0.12), maxf(span.y, 0.5), maxf(span.z, 0.12)) * 0.5
	var guard: AABB = AABB(center - half, half * 2.0)
	return guard.merge(AABB(center + inward * (MIN_DEPTH + ROOM_GAP) - half, half * 2.0))


## Encolhe o comodo desejado ate ele nao invadir nenhuma caixa ja marcada.
## Toda janela do kit olha para um eixo, entao as caixas sao alinhadas e o
## recorte e uma conta em duas dimensoes: largura para os lados, fundo a frente.
## Cada estorvo corta de um jeito so, o que tira menos do comodo.
func _clip(base: Vector3, right: Vector3, inward: Vector3, wanted: Vector3, floor_y: float, ceiling_y: float, blockers: Array[AABB]) -> Vector3:
	var left_half: float = wanted.x
	var right_half: float = wanted.y
	var depth: float = wanted.z
	for box: AABB in blockers:
		if box.end.y < floor_y + 0.05 or box.position.y > ceiling_y - 0.05:
			continue
		var first: Vector3 = box.position - base
		var last: Vector3 = box.end - base
		var side: Vector2 = _range(first.dot(right), last.dot(right))
		var ahead: Vector2 = _range(first.dot(inward), last.dot(inward))
		if ahead.y <= 0.0 or ahead.x >= depth or side.x >= right_half or side.y <= -left_half:
			continue
		var by_depth: float = (ahead.x - ROOM_GAP) / wanted.z if ahead.x > 0.0 else -1.0
		var by_right: float = (side.x - ROOM_GAP) / wanted.y if side.x > 0.0 else -1.0
		var by_left: float = (-side.y - ROOM_GAP) / wanted.x if side.y < 0.0 else -1.0
		if by_depth >= by_right and by_depth >= by_left:
			depth = minf(depth, ahead.x - ROOM_GAP)
		elif by_right >= by_left:
			right_half = minf(right_half, side.x - ROOM_GAP)
		else:
			left_half = minf(left_half, -side.y - ROOM_GAP)
	return Vector3(maxf(left_half, 0.0), maxf(right_half, 0.0), maxf(depth, 0.0))


func _range(a: float, b: float) -> Vector2:
	return Vector2(minf(a, b), maxf(a, b))


## Parede vertical entre dois pontos em planta, do piso ao teto.
func _wall(surface_tool: SurfaceTool, faces: PackedVector3Array, base: Vector3, right: Vector3, inward: Vector3, ends: Array[Vector2], y0: float, y1: float, color: Color, normal: Vector3) -> void:
	var a: Vector3 = base + right * ends[0].x + inward * ends[0].y
	var b: Vector3 = base + right * ends[1].x + inward * ends[1].y
	_face(surface_tool, faces,
		a + Vector3(0.0, y0, 0.0), b + Vector3(0.0, y0, 0.0),
		b + Vector3(0.0, y1, 0.0), a + Vector3(0.0, y1, 0.0), color, normal)


## Piso ou teto na altura `y`.
func _deck(surface_tool: SurfaceTool, faces: PackedVector3Array, base: Vector3, right: Vector3, inward: Vector3, a0: float, a1: float, b0: float, b1: float, y: float, color: Color, normal: Vector3) -> void:
	var height: Vector3 = Vector3(0.0, y, 0.0)
	_face(surface_tool, faces,
		base + right * a0 + inward * b0 + height, base + right * a1 + inward * b0 + height,
		base + right * a1 + inward * b1 + height, base + right * a0 + inward * b1 + height, color, normal)


## O peitoril corta a vista: pela janela so se ve do meio do comodo para cima,
## entao a mobilia que conta e a alta e o que esta pendurado na parede do fundo.
func _furnish(surface_tool: SurfaceTool, faces: PackedVector3Array, base: Vector3, right: Vector3, inward: Vector3, left_half: float, right_half: float, floor_y: float, ceiling_y: float, sill_y: float, depth: float, rng: RandomNumberGenerator) -> void:
	var color: Color = FURNITURE_COLORS[rng.randi() % FURNITURE_COLORS.size()]
	var span: float = left_half + right_half
	if span < 0.6 or depth < 0.5:
		return
	# Armario ou estante encostada no fundo: o topo passa do peitoril.
	var width: float = minf(span - 0.3, rng.randf_range(0.8, 1.3))
	var height: float = rng.randf_range(sill_y + 0.2, sill_y + 0.8) - floor_y
	var thickness: float = minf(depth - 0.15, rng.randf_range(0.35, 0.55))
	if width > 0.2 and thickness > 0.1:
		# Perto do eixo da janela: o vao so deixa ver a faixa central do fundo.
		var room: float = maxf(0.0, minf(left_half, right_half) - width * 0.5)
		var slide: float = rng.randf_range(-room, room) * 0.6
		var away: float = depth - thickness * 0.5 - 0.05
		var middle: Vector3 = base + right * slide + inward * away + Vector3(0.0, floor_y + height * 0.5, 0.0)
		_solid(surface_tool, faces, middle, right, inward, width, height, thickness, color)
	# Quadro na parede do fundo, na altura dos olhos de quem olha de fora.
	if rng.randf() < 0.75:
		var art_width: float = minf(span * 0.5, rng.randf_range(0.5, 0.9))
		var art_height: float = rng.randf_range(0.4, 0.65)
		var art_slide: float = rng.randf_range(-0.25, 0.25)
		var art: Vector3 = base + right * art_slide + inward * (depth - 0.03) + Vector3(0.0, sill_y + 0.25, 0.0)
		_quad(surface_tool, faces, art - Vector3(0.0, art_height * 0.5, 0.0), right, inward, -art_width * 0.5, art_width * 0.5, 0.0, art_height, 0.0, 0.0, color.lightened(0.35), -inward)
	# Pendente sobre o meio do comodo, logo abaixo do teto.
	if rng.randf() < 0.6:
		var lamp: Vector3 = base + inward * (depth * 0.55) + Vector3(0.0, ceiling_y - 0.42, 0.0)
		_solid(surface_tool, faces, lamp, right, inward, 0.3, 0.22, 0.3, Color(0.88, 0.84, 0.70))
		_solid(surface_tool, faces, lamp + Vector3(0.0, 0.27, 0.0), right, inward, 0.05, 0.32, 0.05, Color(0.25, 0.24, 0.22))


## Parede vertical: `first` corre de a0 a a1, `second` fica entre b0 e b1.
func _quad(surface_tool: SurfaceTool, faces: PackedVector3Array, base: Vector3, first: Vector3, second: Vector3, a0: float, a1: float, y0: float, y1: float, b0: float, b1: float, color: Color, normal: Vector3) -> void:
	var p0: Vector3 = base + first * a0 + second * b0 + Vector3(0.0, y0, 0.0)
	var p1: Vector3 = base + first * a1 + second * b1 + Vector3(0.0, y0, 0.0)
	var p2: Vector3 = base + first * a1 + second * b1 + Vector3(0.0, y1, 0.0)
	var p3: Vector3 = base + first * a0 + second * b0 + Vector3(0.0, y1, 0.0)
	_face(surface_tool, faces, p0, p1, p2, p3, color, normal)


## Piso ou teto na altura `y`.
func _slab(surface_tool: SurfaceTool, faces: PackedVector3Array, base: Vector3, right: Vector3, inward: Vector3, a0: float, a1: float, b0: float, b1: float, y: float, color: Color, normal: Vector3) -> void:
	var height: Vector3 = Vector3(0.0, y, 0.0)
	var p0: Vector3 = base + right * a0 + inward * b0 + height
	var p1: Vector3 = base + right * a1 + inward * b0 + height
	var p2: Vector3 = base + right * a1 + inward * b1 + height
	var p3: Vector3 = base + right * a0 + inward * b1 + height
	_face(surface_tool, faces, p0, p1, p2, p3, color, normal)


func _solid(surface_tool: SurfaceTool, faces: PackedVector3Array, middle: Vector3, right: Vector3, inward: Vector3, width: float, height: float, thickness: float, color: Color) -> void:
	var half_width: float = width * 0.5
	var half_thickness: float = thickness * 0.5
	var base: Vector3 = middle - Vector3(0.0, height * 0.5, 0.0)
	_quad(surface_tool, faces, base, right, inward, -half_width, half_width, 0.0, height, -half_thickness, -half_thickness, color, -inward)
	_quad(surface_tool, faces, base, right, inward, -half_width, half_width, 0.0, height, half_thickness, half_thickness, color, inward)
	_quad(surface_tool, faces, base, inward, right, -half_thickness, half_thickness, 0.0, height, -half_width, -half_width, color.darkened(0.1), -right)
	_quad(surface_tool, faces, base, inward, right, -half_thickness, half_thickness, 0.0, height, half_width, half_width, color.darkened(0.1), right)
	_slab(surface_tool, faces, base, right, inward, -half_width, half_width, -half_thickness, half_thickness, height, color.lightened(0.08), Vector3.UP)


func _face(surface_tool: SurfaceTool, faces: PackedVector3Array, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, color: Color, normal: Vector3) -> void:
	for point: Vector3 in [p0, p1, p2, p0, p2, p3]:
		surface_tool.set_color(color)
		surface_tool.set_normal(normal)
		surface_tool.add_vertex(point)
		faces.append(point)
