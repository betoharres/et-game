@tool
extends SceneTree

## Confere se da para andar pelo mapa Country Town.
##
## Junta a colisao de todos os distritos e mede duas coisas:
##
## 1. Nenhuma colisao pode invadir a faixa de rolamento das estradas de
##    `RoadNetwork` -- isso e falha, o mapa fica intransitavel de veiculo.
## 2. Vaos entre colisoes de blocos diferentes menores que a largura do ET
##    viram aviso, nao falha: passagem apertada as vezes e de proposito
##    (dois predios encostados, um anel de pedras). O aviso serve para o
##    autor olhar cada caso no editor. Enfeite miudo -- luminaria de parede,
##    canteiro, seixo -- nao entra: da para contornar sem pensar.
##
## 3. Colisao que flutua sobre o terreno tambem e falha: um predio no ar e
##    pior do que um predio meio enterrado, que ainda passa por afloramento.
##
## A ponte e o ancoradouro ficam de fora dos testes de estrada e de terreno: o
## tabuleiro da ponte E a continuacao da estrada sobre o rio, e os dois vivem
## suspensos por definicao.
##
## Uso:
##
##     .\tools\godot.cmd --headless --path . --script res://tools/check_country_town_clearance.gd

const Layout := preload("res://tools/build_country_town_layout.gd")

const DISTRICT_SCENES: Array[String] = [
	"res://scenes/CountryTown/Districts/FarmDistrict.tscn",
	"res://scenes/CountryTown/Districts/TownDistrict.tscn",
	"res://scenes/CountryTown/Districts/RiverDistrict.tscn",
	"res://scenes/CountryTown/Districts/CrashSiteDistrict.tscn",
	"res://scenes/CountryTown/Districts/MinePortalSite.tscn",
	"res://scenes/CountryTown/Districts/DeliveryYard.tscn",
	"res://scenes/CountryTown/Districts/Fields.tscn",
	"res://scenes/CountryTown/Districts/Vegetation.tscn",
	"res://scenes/CountryTown/Districts/Detailing.tscn",
	"res://scenes/CountryTown/Districts/NightLights.tscn",
]

## Nos cujo nome comeca assim cruzam estrada e ficam suspensos de proposito.
const SUSPENDED: Array[String] = ["Bridge", "Dock"]

const TERRAIN_DIR: String = "res://scenes/CountryTown/Terrain"

## Abaixo disto em planta, a colisao e enfeite: nao estreita passagem nenhuma.
const TRINKET_SHORT_SIDE: float = 0.6
const TRINKET_LONG_SIDE: float = 1.6

## Meia largura da faixa de rolamento mais larga (cascalho).
const ROAD_HALF_WIDTH: float = 4.7
## Vao minimo confortavel para o ET passar entre duas colisoes.
const WALK_GAP: float = 1.5
## Passo com que cada eixo de estrada e amostrado.
const SAMPLE_STEP: float = 1.0
## Quanto a base de uma colisao pode subir acima do terreno antes de virar
## flutuacao, e quanto pode afundar antes de virar afloramento improvavel.
const FLOAT_TOLERANCE: float = 0.4
const SINK_TOLERANCE: float = 3.5

var _failures: Array[String] = []
var _warnings: Array[String] = []


func _process(_delta: float) -> bool:
	var blockers: Array[Dictionary] = _collect_collisions()
	if blockers.is_empty():
		printerr("Nenhuma colisao encontrada nos distritos.")
		quit(1)
		return true
	print("Colisoes conferidas: %d" % blockers.size())

	_check_roads(blockers)
	_check_gaps(blockers)
	_check_ground(blockers)

	for index: int in mini(_warnings.size(), 20):
		print("  aviso: %s" % _warnings[index])
	if _warnings.size() > 20:
		print("  ... e mais %d avisos" % (_warnings.size() - 20))
	if _failures.is_empty():
		print("Passagem do Country Town OK (%d avisos de vao apertado)." % _warnings.size())
		quit(0)
		return true
	printerr("Passagem do Country Town reprovada em %d ponto(s):" % _failures.size())
	for failure: String in _failures:
		printerr("  - %s" % failure)
	quit(1)
	return true


## Cada colisao vira `{ "name", "block", "rect": Rect2, "exempt": bool }`, com o
## retangulo em planta, no mundo.
func _collect_collisions() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for path: String in DISTRICT_SCENES:
		var packed: PackedScene = load(path) as PackedScene
		if packed == null:
			_fail("Nao carregou %s" % path)
			continue
		var instance: Node = packed.instantiate()
		root.add_child(instance)
		for node: Node in _descendants(instance):
			var collider: CollisionShape3D = node as CollisionShape3D
			if collider == null or collider.shape == null or collider.disabled:
				continue
			# Area3D e sensor, nao parede: a area de ocultacao de um tufo de
			# milho encosta na do tufo vizinho e nao atrapalha ninguem.
			if collider.get_parent() is Area3D:
				continue
			var debug_mesh: Mesh = collider.shape.get_debug_mesh()
			if debug_mesh == null:
				continue
			var bounds: AABB = collider.global_transform * debug_mesh.get_aabb()
			# Um objeto instanciado e uma peca so: boia inteiro ou nao boia, e
			# suas partes encostam uma na outra por construcao. Sem cena por
			# perto -- os shapes soltos do StaticBody3D do distrito -- cada um
			# responde por si.
			var block: Node = _owning_block(collider, instance)
			var block_name: String = "%s/%s" % [instance.name, block.name]
			found.append({
				"name": "%s/%s" % [instance.name, instance.get_path_to(collider)],
				"block": block_name,
				"group": "%s#%d" % [block_name, block.get_instance_id()],
				"rect": Rect2(bounds.position.x, bounds.position.z, bounds.size.x, bounds.size.z),
				"floor": bounds.position.y,
				"exempt": _is_suspended(String(block.name)),
			})
	return found


## A cena instanciada de onde a colisao desce -- e a peca que o autor move no
## editor, entao e o nome que interessa num relatorio. No de agrupamento nao
## serve: juntar num bloco so as arvores de um `YardTrees` daria um retangulo
## que nao existe em lugar nenhum.
func _owning_block(node: Node, district: Node) -> Node:
	var current: Node = node
	var block: Node = node
	while current != null and current != district:
		if current.get_meta("country_town_block", false):
			return current
		if not current.scene_file_path.is_empty() and not current.get_meta("country_town_composition", false):
			block = current
		current = current.get_parent()
	return block


func _is_suspended(block: String) -> bool:
	for prefix: String in SUSPENDED:
		if block.begins_with(prefix):
			return true
	return false


func _check_roads(blockers: Array[Dictionary]) -> void:
	var segments: Array[Dictionary] = Layout.road_segments()
	segments.append_array(Layout.secondary_segments())
	for segment: Dictionary in segments:
		var half_width: float = float(segment["width"]) * 0.5 if segment.has("width") else ROAD_HALF_WIDTH
		var start: Vector2 = segment["start"]
		var end: Vector2 = segment["end"]
		var length: float = start.distance_to(end)
		var steps: int = maxi(1, int(ceil(length / SAMPLE_STEP)))
		for blocker: Dictionary in blockers:
			if blocker["exempt"]:
				continue
			var rect: Rect2 = blocker["rect"]
			var closest: float = INF
			var closest_at: Vector2 = Vector2.ZERO
			for step: int in steps + 1:
				var point: Vector2 = start.lerp(end, float(step) / float(steps))
				var distance: float = _distance_to_rect(point, rect)
				if distance < closest:
					closest = distance
					closest_at = point
			if closest < half_width:
				_fail("%s invade a estrada em (%.1f, %.1f): fica a %.2f m do eixo, faixa tem %.2f m"
						% [blocker["name"], closest_at.x, closest_at.y, closest, half_width])


func _check_gaps(blockers: Array[Dictionary]) -> void:
	for i: int in blockers.size():
		for j: int in range(i + 1, blockers.size()):
			var a: Dictionary = blockers[i]
			var b: Dictionary = blockers[j]
			# partes do mesmo bloco encostam por construcao
			if a["block"] == b["block"]:
				continue
			if _is_trinket(a["rect"]) or _is_trinket(b["rect"]):
				continue
			var gap: float = _rect_gap(a["rect"], b["rect"])
			if gap <= 0.0 or gap >= WALK_GAP:
				continue
			var center: Vector2 = (a["rect"] as Rect2).get_center()
			var size_a: Vector2 = (a["rect"] as Rect2).size
			var size_b: Vector2 = (b["rect"] as Rect2).size
			_warn("vao de %.2f m em (%.1f, %.1f): %s (%.1f x %.1f m) e %s (%.1f x %.1f m)"
					% [gap, center.x, center.y, a["name"], size_a.x, size_a.y,
					b["name"], size_b.x, size_b.y])


## A colisao mais baixa de cada bloco contra a altura do terreno sob ele. O
## teste e por bloco, e nao por shape: uma porta de sotao ou uma placa de
## fachada ficam alto de proposito, e so o predio inteiro pode boiar.
func _check_ground(blockers: Array[Dictionary]) -> void:
	var terrain: Terrain3D = Terrain3D.new()
	root.add_child(terrain)
	terrain.data_directory = TERRAIN_DIR
	var data: Terrain3DData = terrain.data
	if data == null or data.get_region_count() == 0:
		_fail("Terreno ausente em %s -- rode tools/build_country_town_terrain.gd" % TERRAIN_DIR)
		return

	var lowest: Dictionary = {}
	for blocker: Dictionary in blockers:
		if blocker["exempt"]:
			continue
		var key: String = blocker["group"]
		var rect: Rect2 = blocker["rect"]
		if not lowest.has(key):
			lowest[key] = {"floor": blocker["floor"], "rect": rect}
			continue
		var entry: Dictionary = lowest[key]
		entry["floor"] = minf(float(entry["floor"]), float(blocker["floor"]))
		entry["rect"] = (entry["rect"] as Rect2).merge(rect)

	for key: String in lowest:
		var entry: Dictionary = lowest[key]
		var center: Vector2 = (entry["rect"] as Rect2).get_center()
		var ground: float = data.get_height(Vector3(center.x, 0.0, center.y))
		if is_nan(ground):
			continue
		var clearance: float = float(entry["floor"]) - ground
		if clearance > FLOAT_TOLERANCE:
			_fail("%s flutua %.2f m acima do terreno em (%.1f, %.1f)"
					% [key, clearance, center.x, center.y])
		elif clearance < -SINK_TOLERANCE:
			_warn("%s afunda %.2f m no terreno em (%.1f, %.1f)"
					% [key, -clearance, center.x, center.y])


## Pegada pequena demais em planta para estreitar caminho.
func _is_trinket(rect: Rect2) -> bool:
	var short_side: float = minf(rect.size.x, rect.size.y)
	var long_side: float = maxf(rect.size.x, rect.size.y)
	return short_side < TRINKET_SHORT_SIDE and long_side < TRINKET_LONG_SIDE


func _distance_to_rect(point: Vector2, rect: Rect2) -> float:
	var dx: float = maxf(maxf(rect.position.x - point.x, point.x - rect.end.x), 0.0)
	var dz: float = maxf(maxf(rect.position.y - point.y, point.y - rect.end.y), 0.0)
	return Vector2(dx, dz).length()


## Folga entre dois retangulos em planta. Negativa quando eles se sobrepoem.
func _rect_gap(a: Rect2, b: Rect2) -> float:
	var dx: float = maxf(a.position.x - b.end.x, b.position.x - a.end.x)
	var dz: float = maxf(a.position.y - b.end.y, b.position.y - a.end.y)
	if dx <= 0.0 and dz <= 0.0:
		return -1.0
	return Vector2(maxf(dx, 0.0), maxf(dz, 0.0)).length()


func _descendants(node: Node) -> Array[Node]:
	var found: Array[Node] = [node]
	for child: Node in node.get_children():
		found.append_array(_descendants(child))
	return found


func _fail(message: String) -> void:
	_failures.append(message)


func _warn(message: String) -> void:
	_warnings.append(message)
