@tool
extends SceneTree

## Confere a geometria do tabuleiro das pontes do Country Town
## (`scenes/CountryTown/Blocks/RiverBridge.tscn`).
##
## A ponte e montada a mao com modulos do PolygonCity, e cada modulo tem a sua
## propria cota de origem: o `Underside` entrega o piso no topo, o `Edge` entrega
## o piso um palmo abaixo do parapeito, e `Support` e `Pillar` sao estrutura, que
## mora sob o tabuleiro. Errar a cota de um deles nao quebra nada -- so deixa um
## degrau ou uma viga furando o chao da ponte, que e como o mapa estava.
##
## Por isso a checagem amostra a faixa de rolamento e cobra tres coisas:
##
## 1. Piso em todo ponto da faixa: buraco no tabuleiro e falha.
## 2. Piso na cota do tabuleiro: degrau acima da tolerancia e falha.
## 3. Nada acima do piso dentro da faixa: e viga ou pilar atravessando.
##
## E confere que os dois parapeitos existem de ponta a ponta -- sem eles a ponte
## e uma tabua sobre o rio.
##
## Uso:
##
##     .\tools\godot.cmd --headless --path . --script res://tools/check_country_town_bridge.gd

const BRIDGE_SCENE_PATH: String = "res://scenes/CountryTown/Blocks/RiverBridge.tscn"

## Faixa de rolamento: meio comprimento do tabuleiro e meia largura util, ja
## descontada a folga junto ao parapeito.
const DECK_HALF_LENGTH: float = 17.5
const DECK_HALF_WIDTH: float = 2.4
const DECK_HEIGHT: float = 0.0
## Degrau que o ET sobe sem notar. Acima disso e defeito.
const DECK_TOLERANCE: float = 0.06
const SAMPLE_STEP: float = 0.5
## A amostragem nao encosta na aresta do tabuleiro: um ponto exatamente sobre o
## vertice de um triangulo cai fora dele por arredondamento.
const SAMPLE_MARGIN: float = 0.05

## Onde o parapeito tem de aparecer, e a que altura acima do tabuleiro.
const PARAPET_MIN_Z: float = 2.5
const PARAPET_MAX_Z: float = 3.3
const PARAPET_MIN_HEIGHT: float = 1.0

var _failures: Array[String] = []
## Triangulos horizontais em baldes de um metro, para nao testar a malha toda
## em cada amostra.
var _buckets: Dictionary = {}


func _process(_delta: float) -> bool:
	_run()
	return true


func _run() -> void:
	var packed: PackedScene = load(BRIDGE_SCENE_PATH) as PackedScene
	if packed == null:
		_fail("Nao carregou %s" % BRIDGE_SCENE_PATH)
		_report()
		return
	var bridge: Node = packed.instantiate()
	root.add_child(bridge)

	var triangles: int = _collect_triangles(bridge)
	if triangles == 0:
		_fail("A ponte nao tem nenhuma face horizontal")
		_report()
		return
	print("Faces horizontais na ponte: %d" % triangles)

	_check_deck()
	_check_parapets()
	_report()


func _check_deck() -> void:
	var holes: int = 0
	var steps: int = 0
	var obstacles: int = 0
	var worst_step: float = 0.0
	var worst_obstacle: float = 0.0
	var samples: int = 0
	var x: float = -DECK_HALF_LENGTH + SAMPLE_MARGIN
	while x <= DECK_HALF_LENGTH - SAMPLE_MARGIN:
		var z: float = -DECK_HALF_WIDTH + SAMPLE_MARGIN
		while z <= DECK_HALF_WIDTH - SAMPLE_MARGIN:
			samples += 1
			var top: float = _height_at(x, z, INF)
			if is_nan(top):
				holes += 1
				if holes <= 3:
					_fail("Buraco no tabuleiro em (%.2f, %.2f)" % [x, z])
			elif top > DECK_HEIGHT + DECK_TOLERANCE:
				obstacles += 1
				worst_obstacle = maxf(worst_obstacle, top - DECK_HEIGHT)
				if obstacles <= 3:
					_fail("Estrutura %.2f m acima do tabuleiro em (%.2f, %.2f)"
							% [top - DECK_HEIGHT, x, z])
			elif top < DECK_HEIGHT - DECK_TOLERANCE:
				steps += 1
				worst_step = maxf(worst_step, DECK_HEIGHT - top)
				if steps <= 3:
					_fail("Degrau de %.2f m no tabuleiro em (%.2f, %.2f)"
							% [DECK_HEIGHT - top, x, z])
			z += SAMPLE_STEP
		x += SAMPLE_STEP
	print("Tabuleiro: %d amostras, %d buracos, %d degraus (pior %.2f m), %d obstaculos (pior %.2f m)"
			% [samples, holes, steps, worst_step, obstacles, worst_obstacle])


func _check_parapets() -> void:
	for side: float in [1.0, -1.0]:
		var missing: int = 0
		var x: float = -DECK_HALF_LENGTH + SAMPLE_MARGIN
		while x <= DECK_HALF_LENGTH - SAMPLE_MARGIN:
			var best: float = -INF
			var z: float = PARAPET_MIN_Z
			while z <= PARAPET_MAX_Z:
				var top: float = _height_at(x, z * side, INF)
				if not is_nan(top):
					best = maxf(best, top)
				z += 0.1
			if best < DECK_HEIGHT + PARAPET_MIN_HEIGHT:
				missing += 1
				if missing <= 3:
					_fail("Parapeito em z %s falta ou e baixo demais em x = %.2f"
							% ["positivo" if side > 0.0 else "negativo", x])
			x += SAMPLE_STEP
		if missing == 0:
			print("Parapeito em z %s: inteiro" % ["positivo" if side > 0.0 else "negativo"])


## Superficie mais alta abaixo de `ceiling` no ponto, ou NAN se nao ha nenhuma.
func _height_at(x: float, z: float, ceiling: float) -> float:
	var key: Vector2i = Vector2i(int(floor(x)), int(floor(z)))
	if not _buckets.has(key):
		return NAN
	var best: float = NAN
	for triangle: PackedVector3Array in _buckets[key]:
		var a: Vector3 = triangle[0]
		var v0: Vector2 = Vector2(triangle[2].x - a.x, triangle[2].z - a.z)
		var v1: Vector2 = Vector2(triangle[1].x - a.x, triangle[1].z - a.z)
		var v2: Vector2 = Vector2(x - a.x, z - a.z)
		var denominator: float = v0.x * v1.y - v1.x * v0.y
		if absf(denominator) < 0.000001:
			continue
		var u: float = (v2.x * v1.y - v1.x * v2.y) / denominator
		var v: float = (v0.x * v2.y - v2.x * v0.y) / denominator
		if u < 0.0 or v < 0.0 or u + v > 1.0:
			continue
		var height: float = a.y + u * (triangle[2].y - a.y) + v * (triangle[1].y - a.y)
		if height > ceiling:
			continue
		if is_nan(best) or height > best:
			best = height
	return best


## Guarda as faces por onde da para pisar -- as quase horizontais -- em baldes
## de um metro em planta.
func _collect_triangles(node: Node) -> int:
	var total: int = 0
	for descendant: Node in _descendants(node):
		var instance: MeshInstance3D = descendant as MeshInstance3D
		if instance == null or instance.mesh == null:
			continue
		var transform: Transform3D = instance.global_transform
		for surface: int in instance.mesh.get_surface_count():
			var arrays: Array = instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for i: int in range(0, indices.size(), 3):
				var a: Vector3 = transform * vertices[indices[i]]
				var b: Vector3 = transform * vertices[indices[i + 1]]
				var c: Vector3 = transform * vertices[indices[i + 2]]
				var cross: Vector3 = (b - a).cross(c - a)
				if cross.length() < 0.000001 or absf(cross.normalized().y) < 0.5:
					continue
				var triangle: PackedVector3Array = PackedVector3Array([a, b, c])
				var x0: int = int(floor(minf(a.x, minf(b.x, c.x))))
				var x1: int = int(floor(maxf(a.x, maxf(b.x, c.x))))
				var z0: int = int(floor(minf(a.z, minf(b.z, c.z))))
				var z1: int = int(floor(maxf(a.z, maxf(b.z, c.z))))
				for cx: int in range(x0, x1 + 1):
					for cz: int in range(z0, z1 + 1):
						var key: Vector2i = Vector2i(cx, cz)
						if not _buckets.has(key):
							_buckets[key] = ([] as Array[PackedVector3Array])
						_buckets[key].append(triangle)
				total += 1
	return total


func _descendants(node: Node) -> Array[Node]:
	var found: Array[Node] = [node]
	for child: Node in node.get_children():
		found.append_array(_descendants(child))
	return found


func _fail(message: String) -> void:
	_failures.append(message)


func _report() -> void:
	if _failures.is_empty():
		print("Ponte do Country Town OK: tabuleiro continuo, plano e desobstruido.")
		quit(0)
		return
	printerr("Ponte do Country Town reprovada em %d ponto(s):" % _failures.size())
	for failure: String in _failures:
		printerr("  - %s" % failure)
	quit(1)
