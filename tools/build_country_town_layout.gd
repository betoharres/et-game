@tool
extends SceneTree

## Offline road and river generator. The grid preserves the authored routes;
## native convex footprints bake primary/local intersections without overlaps.
## Asphalt, dirt, sidewalks, curbs and shoulders have separate shared materials.
## No imported road meshes or runtime generation. This generator supports headless.

const Surface: GDScript = preload("res://tools/country_town_road_surface.gd")

const ROAD_SCENE_PATH: String = "res://scenes/CountryTown/Districts/RoadNetwork.tscn"
const RIVER_SCENE_PATH: String = "res://scenes/CountryTown/Districts/RiverWater.tscn"
const WATER_MATERIAL_PATH: String = "res://Materiais/ea_water_countryTown.tres"

## Historical grid spacing, retained to preserve POIs and bridge locations.
const TILE: float = 11.9106
## Cruzamento de onde a grade parte: `x = 62 + i * TILE`, `z = 96 + j * TILE`.
const GRID_ORIGIN: Vector2 = Vector2(62.0, 96.0)

## Retangulo jogavel. O terreno passa dele para as colinas de borda fecharem o
## horizonte, e o rio atravessa essa borda; composicao, nao.
const MAP_SIZE: Vector2 = Vector2(600.0, 450.0)


static func inside_map(point: Vector2) -> bool:
	return point.x >= 0.0 and point.x <= MAP_SIZE.x \
			and point.y >= 0.0 and point.y <= MAP_SIZE.y

## Cota do vale. Marcadores e platos vivem nela, e o terreno e achatado nela
## sob as estradas.
const GROUND_HEIGHT: float = 6.0
## Pavement clearance above terrain; bridge landings use a graded elevation.
const ROAD_PIECE_LIFT: float = 0.06
## Superficie da agua do rio.
const WATER_LEVEL: float = 3.6

## Tracado do rio, do norte (x ~ 350) ao sudoeste. O canal do terreno e os
## planos de agua saem dos mesmos pontos.
##
## Da altura do ancoradouro em diante os pontos ficam mais juntos: a largura e
## constante dentro de cada trecho, entao trecho curto e o que deixa o rio
## abrir em degraus pequenos ate virar lago, em vez de dar um salto de largura
## no meio da agua. As duas pontas nascem e morrem fora do retangulo jogavel,
## dentro do terreno -- o rio some atras das colinas de borda em vez de acabar
## num corte reto.
const RIVER_PATH: Array[Vector2] = [
	Vector2(352.0, -40.0), Vector2(350.0, 25.0), Vector2(340.0, 80.0),
	Vector2(332.0, 135.0), Vector2(312.0, 182.0), Vector2(262.0, 228.0),
	Vector2(216.0, 262.0), Vector2(204.0, 306.0), Vector2(176.0, 336.0),
	Vector2(140.0, 350.0), Vector2(100.0, 356.0), Vector2(66.0, 376.0),
	Vector2(48.0, 393.0), Vector2(36.0, 410.0), Vector2(22.0, 430.0),
	Vector2(8.0, 450.0), Vector2(-6.0, 471.0), Vector2(-20.0, 492.0),
	Vector2(-40.0, 520.0), Vector2(-62.0, 552.0), Vector2(-86.0, 586.0),
]
const WATER_WIDTH: float = 17.0

## O rio alarga trecho a trecho depois do ancoradouro e vira o lago da foz, no
## canto sudoeste -- e por onde a agua sai da regiao jogavel. Chave e o indice
## do trecho (RIVER_PATH[i] a RIVER_PATH[i+1]); fora daqui vale WATER_WIDTH.
##
## O teto de cada trecho ate o 11 e o ancoradouro: `RiversideDock` fica a ~19 m
## do eixo, e o leito escavado mais a margem nao pode alcancar o marcador, ou
## `check_country_town_layout.gd` reprova o POI por diferenca de altura.
const RIVER_WIDTH_OVERRIDES: Dictionary = {
	9: 19.0,
	10: 22.0,
	11: 26.0,
	12: 32.0,
	13: 45.0,
	14: 60.0,
	15: 80.0,
	16: 105.0,
	17: 140.0,
	18: 180.0,
	19: 230.0,
}

## Meia-largura do leito escavado, em fracao da largura da agua, e a faixa que
## sobe do leito ate a cota do vale. `build_country_town_terrain.gd` escava com
## os dois, e aqui eles dizem quanto o primeiro e o ultimo plano precisam passar
## da ponta do tracado para a borda ficar enterrada.
const RIVER_BED_RATIO: float = 0.353
const RIVER_BANK_WIDTH: float = 9.0

## Vias locais e trilhas: largura total e pontos no plano X/Z. O gerador de
## settlement drapeja estas faixas no terreno existente, sem refazer o rio.
const SECONDARY_PATHS: Array[Dictionary] = [
	{"name": "RiverfrontStreet", "width": 9.0, "urban": true, "points": [Vector2(367, 167.46), Vector2(367, 298.48), Vector2(347.85, 298.48)]},
	{"name": "NorthStreet", "width": 9.0, "urban": true, "points": [Vector2(455.05, 167.46), Vector2(553, 167.46)]},
	{"name": "MarketStreet", "width": 9.0, "urban": true, "points": [Vector2(455.05, 211), Vector2(553, 211)]},
	{"name": "SquareStreet", "width": 9.0, "urban": true, "points": [Vector2(455.05, 238.93), Vector2(553, 238.93)]},
	{"name": "ChurchStreet", "width": 9.0, "urban": true, "points": [Vector2(455.05, 278), Vector2(553, 278)]},
	{"name": "GardenStreet", "width": 9.0, "urban": true, "points": [Vector2(516, 167.46), Vector2(516, 298.48)]},
	{"name": "EastStreet", "width": 9.0, "urban": true, "points": [Vector2(553, 167.46), Vector2(553, 318), Vector2(516, 318), Vector2(516, 298.48)]},
	{"name": "StoreAlley", "width": 9.0, "urban": true, "points": [Vector2(424, 167.4636), Vector2(424, 238.9272)]},
	{"name": "FarmService", "width": 3.0, "urban": false, "points": [Vector2(110, 96), Vector2(110, 142), Vector2(152, 147), Vector2(169, 167.46)]},
	{"name": "PenAccess", "width": 3.0, "urban": false, "points": [Vector2(206, 167.46), Vector2(206, 197), Vector2(185, 207)]},
	{"name": "ShedAccess", "width": 2.8, "urban": false, "points": [Vector2(62, 223), Vector2(48, 223), Vector2(40, 225)]},
	{"name": "MillTrail", "width": 3.0, "urban": false, "points": [Vector2(62, 242), Vector2(85, 246), Vector2(105, 259), Vector2(140, 259), Vector2(151, 274), Vector2(151, 298.48)]},
	{"name": "DockTrail", "width": 3.0, "urban": false, "points": [Vector2(151, 298.48), Vector2(138, 315), Vector2(114, 329), Vector2(85, 344), Vector2(62, 352), Vector2(50, 359)]},
	{"name": "CrashApproach", "width": 9.0, "urban": true, "points": [Vector2(516, 167.46), Vector2(511, 139), Vector2(500, 116), Vector2(508, 92), Vector2(522, 77)]},
	{"name": "DeliveryAccess", "width": 9.0, "urban": true, "points": [Vector2(360, 358.03), Vector2(350, 365), Vector2(350, 375)]},
]

## Patios e praca ficam livres de vegetacao espalhada automaticamente.
const SETTLEMENT_CLEARINGS: Array[Rect2] = [
	Rect2(462, 215, 20, 19), Rect2(522, 287, 22, 31),
	Rect2(113, 126, 15, 12), Rect2(215, 175, 15, 12),
	Rect2(77, 221, 15, 12), Rect2(111, 309, 15, 12),
	Rect2(320, 326, 15, 12), Rect2(533, 335, 15, 12),
]

## Talhoes compartilhados pelo plantio, cercas, solo e exclusao de vegetacao.
const CROP_FIELDS: Array[Dictionary] = [
	{"kind": "corn", "name": "CornField", "rect": Rect2(144, 24, 148, 76), "step": Vector2(3.4, 5.2), "rows": true, "maze": true},
	{"kind": "wheat", "name": "WheatNorth", "rect": Rect2(82, 30, 53, 49), "step": Vector2(6.6, 6.8), "rows": true},
	{"kind": "wheat", "name": "WheatEast", "rect": Rect2(128, 108, 20, 29), "step": Vector2(6.6, 6.8), "rows": true},
	{"kind": "sunflower", "name": "SunflowersFarmhouse", "rect": Rect2(28, 84, 24, 14), "step": Vector2(2.2, 2.5), "rows": false},
	{"kind": "sunflower", "name": "SunflowersWindmill", "rect": Rect2(116, 266, 20, 13), "step": Vector2(2.2, 2.5), "rows": false},
	{"kind": "wheat", "name": "MillWheat", "rect": Rect2(77, 265, 30, 28), "step": Vector2(6.6, 6.8), "rows": true},
	{"kind": "wheat", "name": "PenPasture", "rect": Rect2(214, 108, 64, 42), "step": Vector2(6.6, 6.8), "rows": true},
	{"kind": "corn", "name": "FarmServiceCrop", "rect": Rect2(154, 108, 42, 31), "step": Vector2(3.6, 6.5), "rows": true},
	{"kind": "sunflower", "name": "TownKitchenGarden", "rect": Rect2(526, 320, 9, 5), "step": Vector2(2.2, 2.5), "rows": false},
	{"kind": "wheat", "name": "WestPasture", "rect": Rect2(23, 257, 26, 57), "step": Vector2(6.6, 6.8), "rows": true},
	{"kind": "wheat", "name": "SouthFarm", "rect": Rect2(78, 182, 27, 32), "step": Vector2(6.6, 6.8), "rows": true},
	{"kind": "wheat", "name": "PenGarden", "rect": Rect2(136, 182, 26, 30), "step": Vector2(6.6, 6.8), "rows": true},
	{"kind": "wheat", "name": "RiverFarm", "rect": Rect2(225, 200, 43, 22), "step": Vector2(6.6, 6.8), "rows": true},
]

## Labirinto autoral fixo dentro do milharal. '#' recebe milho alto; '.' vira
## corredor. O formato e uma receita de dados para depois trocar por uma semente
## sem mudar o gerador de plantio.
const CORN_MAZE: Array[String] = [
	"#####.#########",
	"#...#.........#",
	"#.#.#.#######.#",
	"#.#...#.....#.#",
	"#.#####.###.#.#",
	"#.....#...#...#",
	"#####.###.###.#",
	"#.............#",
	"#########.#####",
]
const CORN_MAZE_RECT: Rect2 = Rect2(158, 33, 120, 54)


static func secondary_segments() -> Array[Dictionary]:
	var segments: Array[Dictionary] = []
	for path: Dictionary in SECONDARY_PATHS:
		var points: Array = path["points"]
		for index: int in points.size() - 1:
			segments.append({"start": points[index], "end": points[index + 1],
				"width": path["width"], "name": path["name"]})
	return segments


static func on_secondary_path(point: Vector2, margin: float = 0.0) -> bool:
	for path: Dictionary in SECONDARY_PATHS:
		var points: Array = path["points"]
		for index: int in points.size() - 1:
			var closest: Vector2 = Geometry2D.get_closest_point_to_segment(point, points[index], points[index + 1])
			if point.distance_to(closest) < float(path["width"]) * 0.5 + margin:
				return true
	return false

## Local connectors: straight, bend, T and terminal, rotated onto the grid.
const ROAD_CONNECTORS: Dictionary = {
	"straight": [Vector2(0.0, 1.0), Vector2(0.0, -1.0)],
	"corner": [Vector2(-1.0, 0.0), Vector2(0.0, -1.0)],
	"t": [Vector2(1.0, 0.0), Vector2(-1.0, 0.0), Vector2(0.0, -1.0)],
	"end": [Vector2(0.0, 1.0)],
}

## [kind, grid axis, fixed coordinate, first cell, last cell, yaw degrees].
const ROAD_RUNS: Array[Array] = [
	# Farm spine: dirt on the west bank.
	["dirt_end", "j", 0, -5, -5, 0],
	["dirt_straight", "j", 0, -4, -1, 0],
	["dirt_t", "j", 0, 0, 0, 270],
	["dirt_straight", "j", 0, 1, 5, 0],
	["dirt_t", "j", 0, 6, 6, 270],
	["dirt_straight", "j", 0, 7, 16, 0],
	["dirt_t", "j", 0, 17, 17, 270],
	["dirt_straight", "j", 0, 18, 20, 0],
	["dirt_end", "j", 0, 21, 21, 180],
	# Barn -> CornField -> MinePortal, ao norte.
	["dirt_straight", "i", 0, 1, 19, 90],
	["dirt_corner", "j", 20, 0, 0, 0],
	["dirt_straight", "j", 20, -5, -1, 0],
	["dirt_corner", "j", 20, -6, -6, 180],
	["dirt_straight", "i", -6, 21, 21, 90],
	["dirt_end", "i", -6, 22, 22, 270],
	# Estrada da cidade, cortada no vao da travessia norte (BridgeNorth).
	["dirt_straight", "i", 6, 1, 18, 90],
	["dirt_end", "i", 6, 19, 19, 270],
	["asphalt_end", "i", 6, 23, 23, 90],
	["asphalt_straight", "i", 6, 24, 28, 90],
	["asphalt_t", "i", 6, 29, 29, 180],
	["asphalt_straight", "i", 6, 30, 32, 90],
	["asphalt_corner", "i", 6, 33, 33, 90],
	# Avenida da cidade, de norte a sul.
	["asphalt_straight", "j", 33, 7, 11, 0],
	["asphalt_t", "j", 33, 12, 12, 90],
	["asphalt_straight", "j", 33, 13, 16, 0],
	["asphalt_t", "j", 33, 17, 17, 270],
	["asphalt_straight", "j", 33, 18, 21, 0],
	["asphalt_t", "j", 33, 22, 22, 90],
	["asphalt_straight", "j", 33, 23, 24, 0],
	["asphalt_corner", "j", 33, 25, 25, 270],
	# Quarteirao do General Store.
	["asphalt_straight", "j", 29, 7, 11, 0],
	["asphalt_corner", "j", 29, 12, 12, 270],
	["asphalt_straight", "i", 12, 30, 32, 90],
	# Ramal da igreja.
	["asphalt_straight", "i", 17, 34, 37, 90],
	["asphalt_end", "i", 17, 38, 38, 270],
	# Saida da cidade.
	["asphalt_straight", "i", 25, 34, 43, 90],
	["asphalt_end", "i", 25, 44, 44, 270],
	# Patio de entrega.
	["asphalt_corner", "j", 24, 17, 17, 90],
	["asphalt_straight", "j", 24, 18, 21, 0],
	["asphalt_t", "j", 24, 22, 22, 270],
	["asphalt_end", "j", 24, 23, 23, 180],
	["asphalt_straight", "i", 22, 25, 32, 90],
	# Estrada do moinho, cortada no vao da travessia sul (BridgeSouth).
	# Dirt west of BridgeSouth, asphalt east of the bridge.
	["dirt_straight", "i", 17, 1, 9, 90],
	["dirt_end", "i", 17, 10, 10, 270],
	["asphalt_end", "i", 17, 14, 14, 90],
	["asphalt_straight", "i", 17, 15, 23, 90],
]


static func grid_position(i: int, j: int) -> Vector2:
	return GRID_ORIGIN + Vector2(float(i) * TILE, float(j) * TILE)


## Surface family: dirt on the farm bank, asphalt on the town bank.
static func family_of(kind: String) -> String:
	return kind.get_slice("_", 0)


## Formato da peca -- `straight`, `corner`, `t` ou `end` --, que decide por
## onde ela encosta nas vizinhas.
static func shape_of(kind: String) -> String:
	return kind.get_slice("_", 1)


## Uma direcao local girada como a peca: e a rotacao em Y de `Basis`, escrita
## em duas dimensoes.
static func rotate_local(direction: Vector2, angle: float) -> Vector2:
	return Vector2(direction.x * cos(angle) + direction.y * sin(angle),
			-direction.x * sin(angle) + direction.y * cos(angle))


## Uma entrada por celula ocupada da grade:
## `{ "kind": String, "cell": Vector2i, "angle": float }`. E a leitura crua de
## `ROAD_RUNS`, antes de qualquer compensacao de modelo.
static func road_tiles() -> Array[Dictionary]:
	var tiles: Array[Dictionary] = []
	for run: Array in ROAD_RUNS:
		var along_x: bool = run[1] == "i"
		var fixed: int = run[2]
		for step: int in range(int(run[3]), int(run[4]) + 1):
			tiles.append({
				"kind": run[0] as String,
				"cell": Vector2i(step if along_x else fixed, fixed if along_x else step),
				"angle": deg_to_rad(float(run[5])),
			})
	return tiles


## Uma entrada por peca de estrada: `{ "kind": String, "transform": Transform3D }`.
static func road_pieces() -> Array[Dictionary]:
	var pieces: Array[Dictionary] = []
	for tile: Dictionary in road_tiles():
		var kind: String = tile["kind"]
		var cell: Vector2i = tile["cell"]
		var angle: float = tile["angle"]
		var flat: Vector2 = grid_position(cell.x, cell.y)
		pieces.append({
			"kind": kind,
			"transform": Transform3D(Basis(Vector3.UP, angle),
					Vector3(flat.x, GROUND_HEIGHT + ROAD_PIECE_LIFT, flat.y)),
		})
	return pieces


## Eixo de cada trecho reto de estrada, ja esticado ate a borda das pecas das
## pontas: `{ "start": Vector2, "end": Vector2 }`. E o corredor que precisa
## ficar livre de colisao.
static func road_segments() -> Array[Dictionary]:
	var segments: Array[Dictionary] = []
	for run: Array in ROAD_RUNS:
		var along_x: bool = run[1] == "i"
		var fixed: int = run[2]
		var first: Vector2 = grid_position(int(run[3]) if along_x else fixed,
				fixed if along_x else int(run[3]))
		var last: Vector2 = grid_position(int(run[4]) if along_x else fixed,
				fixed if along_x else int(run[4]))
		var reach: Vector2 = Vector2(TILE * 0.5, 0.0) if along_x else Vector2(0.0, TILE * 0.5)
		segments.append({"start": first - reach, "end": last + reach})
	return segments


## Largura da agua no trecho `i` de `RIVER_PATH` (`RIVER_PATH[i]` a
## `RIVER_PATH[i+1]`): `WATER_WIDTH`, exceto nos trechos listados em
## `RIVER_WIDTH_OVERRIDES`.
static func river_width(index: int) -> float:
	return float(RIVER_WIDTH_OVERRIDES.get(index, WATER_WIDTH))


## Traços do rio, ja com a folga de cada cotovelo e o avanco das duas pontas:
## `{ "start": Vector2, "end": Vector2, "width": float }`.
static func water_segments() -> Array[Dictionary]:
	var path: Array[Vector2] = RIVER_PATH
	var last: int = path.size() - 2
	var segments: Array[Dictionary] = []
	for k: int in path.size() - 1:
		var start: Vector2 = path[k]
		var end: Vector2 = path[k + 1]
		var direction: Vector2 = (end - start).normalized()
		var width: float = river_width(k)
		var head: float = _mouth_overshoot(width) if k == 0 else _corner_slack(path, k, width)
		var tail: float = _mouth_overshoot(width) if k == last else _corner_slack(path, k + 1, width)
		segments.append({
			"start": start - direction * head,
			"end": end + direction * tail,
			"width": width,
		})
	return segments


## Quanto o primeiro e o ultimo plano passam da ponta do tracado.
##
## Alem da ponta, o escavador ainda rebaixa um disco de raio igual a meia
## largura do leito, e o terreno so volta a subir acima da linha d'agua depois
## da margem. Um plano que para na ponta deixa esse leito seco a mostra -- e o
## corte reto no meio do nada. Passando disso, a borda do plano cai onde o
## terreno ja subiu e some dentro dele.
static func _mouth_overshoot(width: float) -> float:
	return width * RIVER_BED_RATIO + RIVER_BANK_WIDTH + 4.0


## Quanto um plano precisa passar do vertice para fechar o canto externo da
## curva: meia largura vezes a tangente de meio angulo. Nas pontas, nada.
static func _corner_slack(path: Array[Vector2], index: int, width: float) -> float:
	if index <= 0 or index >= path.size() - 1:
		return 0.0
	var incoming: Vector2 = (path[index] - path[index - 1]).normalized()
	var outgoing: Vector2 = (path[index + 1] - path[index]).normalized()
	var turn: float = absf(incoming.angle_to(outgoing))
	return width * 0.5 * tan(turn * 0.5) + 0.25


func _process(_delta: float) -> bool:
	var ok: bool = _build_roads() and _build_river()
	quit(0 if ok else 1)
	return true


## Primary and local streets are baked together, so crossings have one surface.
func _build_roads() -> bool:
	var network: Node3D = Node3D.new()
	network.name = "RoadNetwork"
	var asphalt: Array[PackedVector2Array] = road_polygons(true)
	var dirt: Array[PackedVector2Array] = road_polygons(false)
	var all_roads: Array[PackedVector2Array] = asphalt + dirt
	var empty: Array[PackedVector2Array] = []
	Surface.build(network, "AsphaltRoadBed", asphalt, empty, GROUND_HEIGHT + ROAD_PIECE_LIFT,
		Surface.material(Color(0.14, 0.15, 0.16)), true, road_height)
	Surface.build(network, "DirtRoadBed", dirt, asphalt, GROUND_HEIGHT + ROAD_PIECE_LIFT,
		Surface.material(Color(0.64, 0.42, 0.22)), true, road_height)
	# Only the outer perimeter is paved: no sidewalk or curb crosses a junction.
	var walks: Array[PackedVector2Array] = road_polygons(true, 2.1, true)
	var curbs: Array[PackedVector2Array] = road_polygons(true, 0.24, true)
	Surface.build(network, "Sidewalks", walks, all_roads + curbs, GROUND_HEIGHT + 0.13,
		Surface.material(Color(0.30, 0.28, 0.24)))
	Surface.build(network, "Curbs", curbs, all_roads, GROUND_HEIGHT + 0.13,
		Surface.material(Color(0.38, 0.36, 0.31)))
	var shoulders: Array[PackedVector2Array] = road_polygons(false, 1.1)
	Surface.build(network, "RuralShoulders", shoulders, all_roads, GROUND_HEIGHT + 0.015,
		Surface.material(Color(0.44, 0.34, 0.21)), false)
	var markings: Array[PackedVector2Array] = []
	for tile: Dictionary in road_tiles():
		if tile["kind"] != "asphalt_straight":
			continue
		var cell: Vector2i = tile["cell"]
		var center: Vector2 = grid_position(cell.x, cell.y)
		if on_secondary_path(center, 5.0):
			continue
		var axis: Vector2 = rotate_local(Vector2(0, 1), tile["angle"])
		markings.append(Surface.rectangle(center - axis * 1.5, center + axis * 1.5, 0.13))
	Surface.build(network, "MainRoadCenterLines", markings, empty, GROUND_HEIGHT + 0.075,
		Surface.material(Color(0.65, 0.51, 0.22)), false)
	return _save_scene(network, ROAD_SCENE_PATH)


## Match the existing bridge deck with a shallow ramp on each bank.
static func road_height(point: Vector2) -> float:
	for bridge: Vector2 in [Vector2(312.1, 167.46), Vector2(204.9, 298.48)]:
		if absf(point.y - bridge.y) > 5.0:
			continue
		var distance: float = absf(point.x - bridge.x)
		if distance < 24.0:
			return lerpf(6.273, GROUND_HEIGHT + ROAD_PIECE_LIFT, clampf((distance - 17.8) / 6.2, 0.0, 1.0))
	return GROUND_HEIGHT + ROAD_PIECE_LIFT


## Convex footprints with round ends. Grid arms meet exactly at tile boundaries;
## widened copies form curbs/shoulders, then the complete road union cuts them.
static func road_polygons(urban: bool, margin: float = 0.0, built_only: bool = false) -> Array[PackedVector2Array]:
	var polygons: Array[PackedVector2Array] = []
	for tile: Dictionary in road_tiles():
		if (family_of(tile["kind"]) == "asphalt") != urban:
			continue
		var cell: Vector2i = tile["cell"]
		var center: Vector2 = grid_position(cell.x, cell.y)
		if built_only and (center.x < 340 or center.y > 365):
			continue
		var width: float = (9.0 if urban else 8.0) + margin * 2.0
		polygons.append(Surface.disk(center, width * 0.5))
		for direction: Vector2 in ROAD_CONNECTORS[shape_of(tile["kind"])]:
			var axis: Vector2 = rotate_local(direction, tile["angle"])
			polygons.append(Surface.rectangle(center, center + axis * TILE * 0.5, width))
		# Four bridge landings taper from the road to the existing 5 m deck.
		if cell in [Vector2i(19, 6), Vector2i(23, 6), Vector2i(10, 17), Vector2i(14, 17)]:
			var sign_x: float = 1.0 if cell.x in [19, 10] else -1.0
			var landing: Vector2 = center + Vector2(sign_x * (TILE * 0.5 + 0.1), 0)
			var taper: PackedVector2Array = PackedVector2Array([
				center + Vector2(0, -width * 0.5), landing + Vector2(0, -2.5),
				landing + Vector2(0, 2.5), center + Vector2(0, width * 0.5)])
			if sign_x < 0:
				taper.reverse()
			polygons.append(taper)
	for path: Dictionary in SECONDARY_PATHS:
		if not path["urban"] or not urban:
			continue # Rural trails follow the terrain in SecondaryPaths.
		if built_only and path["name"] in ["CrashApproach", "DeliveryAccess"]:
			continue
		Surface.add_path(polygons, path["points"], float(path["width"]) + margin * 2.0)
	return polygons


func _build_river() -> bool:
	var material: Material = load(WATER_MATERIAL_PATH) as Material
	if material == null:
		push_error("Nao carregou %s" % WATER_MATERIAL_PATH)
		return false

	var district: Node3D = Node3D.new()
	district.name = "RiverWater"
	var segments: Array[Dictionary] = water_segments()
	for index: int in segments.size():
		var start: Vector2 = segments[index]["start"]
		var end: Vector2 = segments[index]["end"]
		var width: float = segments[index]["width"]
		var span: Vector2 = end - start
		var length: float = span.length()

		var plane: PlaneMesh = PlaneMesh.new()
		plane.size = Vector2(width, length)
		plane.subdivide_width = maxi(4, int(width / 8.0))
		plane.subdivide_depth = maxi(4, int(length / 6.0))

		var node: MeshInstance3D = MeshInstance3D.new()
		node.name = "WaterPlane%02d" % (index + 1)
		node.mesh = plane
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var middle: Vector2 = start + span * 0.5
		node.transform = Transform3D(Basis(Vector3.UP, atan2(span.x, span.y)),
				Vector3(middle.x, WATER_LEVEL, middle.y))
		district.add_child(node)
		node.owner = district

	var saved: bool = _save_scene(district, RIVER_SCENE_PATH)
	print("Rio: %d planos de agua" % segments.size())
	return saved


func _save_scene(node: Node, path: String) -> bool:
	var packed: PackedScene = PackedScene.new()
	if packed.pack(node) != OK:
		push_error("Nao empacotou %s" % path)
		return false
	if ResourceSaver.save(packed, path) != OK:
		push_error("Nao gravou %s" % path)
		return false
	print("Gravado %s" % path)
	node.free()
	return true
