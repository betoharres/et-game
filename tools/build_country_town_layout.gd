@tool
extends SceneTree

## Gera as cenas de estrada e de rio do mapa Country Town, e guarda os dados de
## layout que `tools/build_country_town_terrain.gd` consome.
##
## As estradas saem como um `MultiMeshInstance3D` por tipo de peca -- um punhado
## de draw calls em vez de uma por peca -- mais o `RoadBed`, a chapa de terra
## que fecha por baixo a costura entre duas pecas. Nenhum dos dois projeta
## sombra: sao chapas no chao. A agua sai como planos com sobreposicao minima nos cotovelos,
## calculada pelo angulo da curva: transparencia sobreposta paga o fragmento
## duas vezes. So a lamina de agua e gerada: pontes e ancoradouro vivem em
## `Districts/RiverDistrict.tscn`, que e montada a mao e instancia esta cena.
##
## Este script e a fonte da verdade do tracado. Editou `ROAD_RUNS` ou
## `RIVER_PATH`, rode ele e logo depois o build do terreno, que refaz as
## clareiras e o canal.
##
## NAO passe `--headless` aqui: o buffer de um `MultiMesh` mora no servidor de
## render, e o driver dummy devolve ele vazio -- a cena sairia com as pecas
## contadas e nenhuma transformacao. O build do terreno, esse sim, e headless.
##
##     .\tools\godot.cmd --path . --script res://tools/build_country_town_layout.gd --resolution 320x240
##     .\tools\godot.cmd --headless --path . --script res://tools/build_country_town_terrain.gd

const ROAD_SCENE_PATH: String = "res://scenes/CountryTown/Districts/RoadNetwork.tscn"
const RIVER_SCENE_PATH: String = "res://scenes/CountryTown/Districts/RiverWater.tscn"
const ROAD_MATERIAL_PATH: String = "res://Materiais/PolygonFarm1A.tres"
const WATER_MATERIAL_PATH: String = "res://Materiais/ea_water_countryTown.tres"

## Passo modular das pecas `SM_Env_Road_*`: elas encaixam em +-5.9553 m.
const TILE: float = 11.9106
## Cruzamento de onde a grade parte: `x = 62 + i * TILE`, `z = 96 + j * TILE`.
const GRID_ORIGIN: Vector2 = Vector2(62.0, 96.0)

## Cota do vale. Marcadores e platos vivem nela, e o terreno e achatado nela
## sob as estradas.
const GROUND_HEIGHT: float = 6.0
## As pecas de estrada pousam um palmo acima do vale, e o leito de terra fica
## entre elas e o chao. Sem essa folga as tres superficies brigam pelo mesmo
## pixel.
const ROAD_PIECE_LIFT: float = 0.06
const ROAD_BED_LIFT: float = 0.03
## Superficie da agua do rio.
const WATER_LEVEL: float = 3.6

## Tracado do rio, do norte (x ~ 350) ao sudoeste. O canal do terreno e os
## planos de agua saem dos mesmos pontos.
const RIVER_PATH: Array[Vector2] = [
	Vector2(352.0, -40.0), Vector2(350.0, 25.0), Vector2(340.0, 80.0),
	Vector2(332.0, 135.0), Vector2(312.0, 182.0), Vector2(262.0, 228.0),
	Vector2(216.0, 262.0), Vector2(204.0, 306.0), Vector2(176.0, 336.0),
	Vector2(140.0, 350.0), Vector2(100.0, 356.0), Vector2(66.0, 376.0),
	Vector2(36.0, 410.0), Vector2(8.0, 450.0), Vector2(-20.0, 492.0),
]
const WATER_WIDTH: float = 17.0

## Vias locais e trilhas: largura total e pontos no plano X/Z. O gerador de
## settlement drapeja estas faixas no terreno existente, sem refazer o rio.
const SECONDARY_PATHS: Array[Dictionary] = [
	{"name": "RiverfrontStreet", "width": 5.0, "urban": true, "points": [Vector2(367, 167.46), Vector2(367, 298.48), Vector2(347.85, 298.48)]},
	{"name": "NorthStreet", "width": 6.0, "urban": true, "points": [Vector2(455.05, 167.46), Vector2(553, 167.46)]},
	{"name": "MarketStreet", "width": 5.0, "urban": true, "points": [Vector2(455.05, 211), Vector2(553, 211)]},
	{"name": "SquareStreet", "width": 6.0, "urban": true, "points": [Vector2(455.05, 238.93), Vector2(553, 238.93)]},
	{"name": "ChurchStreet", "width": 5.0, "urban": true, "points": [Vector2(455.05, 278), Vector2(553, 278)]},
	{"name": "GardenStreet", "width": 5.0, "urban": true, "points": [Vector2(516, 167.46), Vector2(516, 298.48)]},
	{"name": "EastStreet", "width": 5.0, "urban": true, "points": [Vector2(553, 167.46), Vector2(553, 318), Vector2(516, 318), Vector2(516, 298.48)]},
	{"name": "StoreAlley", "width": 3.0, "urban": true, "points": [Vector2(408, 183), Vector2(424, 183), Vector2(424, 238.93)]},
	{"name": "FarmService", "width": 3.0, "urban": false, "points": [Vector2(110, 96), Vector2(110, 142), Vector2(152, 147), Vector2(169, 167.46)]},
	{"name": "PenAccess", "width": 3.0, "urban": false, "points": [Vector2(206, 167.46), Vector2(206, 197), Vector2(185, 207)]},
	{"name": "ShedAccess", "width": 2.8, "urban": false, "points": [Vector2(62, 223), Vector2(48, 223), Vector2(40, 225)]},
	{"name": "MillTrail", "width": 3.0, "urban": false, "points": [Vector2(62, 242), Vector2(85, 246), Vector2(105, 259), Vector2(140, 259), Vector2(151, 274), Vector2(151, 298.48)]},
	{"name": "DockTrail", "width": 3.0, "urban": false, "points": [Vector2(151, 298.48), Vector2(138, 315), Vector2(114, 329), Vector2(85, 344), Vector2(62, 352), Vector2(50, 359)]},
	{"name": "CrashApproach", "width": 3.5, "urban": false, "points": [Vector2(516, 167.46), Vector2(511, 139), Vector2(500, 116), Vector2(508, 92), Vector2(522, 77)]},
	{"name": "DeliveryAccess", "width": 5.0, "urban": true, "points": [Vector2(360, 358.03), Vector2(350, 365), Vector2(350, 375)]},
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

const ROAD_MESHES: Dictionary = {
	"dirt_straight": "res://PolygonFarm/Models/SM_Env_Road_Dirt_Straight_01.fbx",
	"dirt_corner": "res://PolygonFarm/Models/SM_Env_Road_Dirt_Corner_01.fbx",
	"dirt_t": "res://PolygonFarm/Models/SM_Env_Road_Dirt_T_Section_01.fbx",
	"dirt_end": "res://PolygonFarm/Models/SM_Env_Road_Dirt_End_01.fbx",
	"gravel_straight": "res://PolygonFarm/Models/SM_Env_Road_Gravel_Straight_01.fbx",
	"gravel_corner": "res://PolygonFarm/Models/SM_Env_Road_Gravel_Corner_01.fbx",
	"gravel_t": "res://PolygonFarm/Models/SM_Env_Road_Gravel_T_Section_01.fbx",
	"gravel_end": "res://PolygonFarm/Models/SM_Env_Road_Gravel_End_01.fbx",
	# O PolygonCity fornece a placa asfaltada lisa. Ela e um tile de 5 m;
	# _city_asphalt_transform amplia e centraliza no mesmo modulo das pecas rurais.
	"asphalt_straight": "res://PolygonCity/FBX/SM_Env_Road_01.fbx",
	"asphalt_corner": "res://PolygonCity/FBX/SM_Env_Road_01.fbx",
	"asphalt_t": "res://PolygonCity/FBX/SM_Env_Road_01.fbx",
	"asphalt_end": "res://PolygonCity/FBX/SM_Env_Road_01.fbx",
}

const ROAD_NODE_NAMES: Dictionary = {
	"dirt_straight": "DirtStraight",
	"dirt_corner": "DirtCorner",
	"dirt_t": "DirtTSection",
	"dirt_end": "DirtEnd",
	"gravel_straight": "GravelStraight",
	"gravel_corner": "GravelCorner",
	"gravel_t": "GravelTSection",
	"gravel_end": "GravelEnd",
	"asphalt_straight": "AsphaltStraight",
	"asphalt_corner": "AsphaltCorner",
	"asphalt_t": "AsphaltTSection",
	"asphalt_end": "AsphaltEnd",
}

## As pecas de T tem a barra fora do centro do tile, em Z local; compensar isso
## e o que alinha o T com as retas vizinhas.
const T_AXIS_OFFSET: Dictionary = {
	"dirt_t": 1.169,
	"gravel_t": 1.383,
	"asphalt_t": 1.383,
}

## Por onde cada formato de peca encosta na vizinha, em direcao local. Sai da
## forma do modelo: `Corner` liga -X e -Z, `T_Section` tem a barra em X e o ramo
## em -Z, `End` conecta so em +Z. E o que desenha o leito e o que
## `tools/check_country_town_layout.gd` usa para cobrar continuidade da malha.
const ROAD_CONNECTORS: Dictionary = {
	"straight": [Vector2(0.0, 1.0), Vector2(0.0, -1.0)],
	"corner": [Vector2(-1.0, 0.0), Vector2(0.0, -1.0)],
	"t": [Vector2(1.0, 0.0), Vector2(-1.0, 0.0), Vector2(0.0, -1.0)],
	"end": [Vector2(0.0, 1.0)],
}

## Largura do leito de terra por familia, um palmo mais larga que a via: sobra
## como acostamento e nao deixa a costura aparecer nem de vies.
const ROAD_BED_WIDTH: Dictionary = {
	"dirt": 8.0,
	"gravel": 9.8,
	"asphalt": 9.8,
}

## UV da superficie da via no atlas do PolygonFarm, medida no proprio modelo.
## O atlas e de cor chapada, entao o leito sai exatamente da cor da estrada.
const ROAD_BED_UV: Dictionary = {
	"dirt": Vector2(0.05, 0.67),
	"gravel": Vector2(0.15, 0.16),
	"asphalt": Vector2(0.15, 0.16),
}

## Orientacao das pecas, em graus de rotacao em Y, a partir de como cada modelo
## sai do FBX: `Corner` liga -X e -Z, `T_Section` tem a barra em X e o ramo em
## -Z, `End` conecta em +Z e abre a clareira em -Z.
##
## Cada linha e um trecho reto da malha: [peca, eixo, fixo, de, ate, rotacao].
## Com eixo "i" o trecho corre em X na linha `fixo`; com "j" corre em Z na
## coluna `fixo`.
const ROAD_RUNS: Array[Array] = [
	# Espinha da fazenda: Farmhouse ao sul, ate o ancoradouro do rio.
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
	["asphalt_straight", "i", 6, 1, 18, 90],
	["asphalt_end", "i", 6, 19, 19, 270],
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
	["dirt_straight", "i", 17, 1, 9, 90],
	["dirt_end", "i", 17, 10, 10, 270],
	["dirt_end", "i", 17, 14, 14, 90],
	["dirt_straight", "i", 17, 15, 23, 90],
]


static func grid_position(i: int, j: int) -> Vector2:
	return GRID_ORIGIN + Vector2(float(i) * TILE, float(j) * TILE)


## Familia da peca -- `dirt`, `gravel` ou `asphalt` --, que decide material e leito.
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
		if T_AXIS_OFFSET.has(kind):
			flat += rotate_local(Vector2(0.0, -1.0), angle) * float(T_AXIS_OFFSET[kind])
		pieces.append({
			"kind": kind,
			"transform": Transform3D(Basis(Vector3.UP, angle),
					Vector3(flat.x, GROUND_HEIGHT + ROAD_PIECE_LIFT, flat.y)),
		})
	return pieces


## Chapas do leito, uma por trecho; terra na fazenda e asfalto na cidade:
## `{ "family": String, "center": Vector2, "axis": Vector2, "half": Vector2 }`.
##
## As pontas das pecas Synty afinam de oito metros para meio metro na costura, e
## duas pontas vizinhas nao se completam: entre uma peca e a seguinte fica um
## entalhe por onde o terreno aparece. O leito e a chapa continua que fecha esse
## entalhe por baixo, e sai da grade -- nao da geometria das pecas --, entao ele
## segue o eixo da via mesmo onde o modelo esta deslocado, como no T.
static func road_bed_quads() -> Array[Dictionary]:
	var quads: Array[Dictionary] = []
	for tile: Dictionary in road_tiles():
		var family: String = family_of(tile["kind"])
		var width: float = ROAD_BED_WIDTH[family]
		var center: Vector2 = grid_position((tile["cell"] as Vector2i).x, (tile["cell"] as Vector2i).y)
		var angle: float = tile["angle"]
		quads.append({
			"family": family,
			"center": center,
			"axis": Vector2(1.0, 0.0),
			"half": Vector2(width * 0.5, width * 0.5),
		})
		var arm: float = TILE * 0.5 - width * 0.5
		if arm <= 0.01:
			continue
		for direction: Vector2 in ROAD_CONNECTORS[shape_of(tile["kind"])]:
			var axis: Vector2 = rotate_local(direction, angle)
			quads.append({
				"family": family,
				"center": center + axis * (width * 0.5 + arm * 0.5),
				"axis": axis,
				"half": Vector2(arm * 0.5, width * 0.5),
			})
	return quads


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


## Traços do rio recortados na regiao de terreno, ja com a folga de cada
## cotovelo: `{ "start": Vector2, "end": Vector2 }`.
static func water_segments() -> Array[Dictionary]:
	var path: Array[Vector2] = _clipped_river_path()
	var segments: Array[Dictionary] = []
	for k: int in path.size() - 1:
		var start: Vector2 = path[k]
		var end: Vector2 = path[k + 1]
		var direction: Vector2 = (end - start).normalized()
		segments.append({
			"start": start - direction * _corner_slack(path, k),
			"end": end + direction * _corner_slack(path, k + 1),
		})
	return segments


## Quanto um plano precisa passar do vertice para fechar o canto externo da
## curva: meia largura vezes a tangente de meio angulo. Nas pontas, nada.
static func _corner_slack(path: Array[Vector2], index: int) -> float:
	if index <= 0 or index >= path.size() - 1:
		return 0.0
	var incoming: Vector2 = (path[index] - path[index - 1]).normalized()
	var outgoing: Vector2 = (path[index + 1] - path[index]).normalized()
	var turn: float = absf(incoming.angle_to(outgoing))
	return WATER_WIDTH * 0.5 * tan(turn * 0.5) + 0.25


## O rio nasce e morre fora da regiao de terreno; o que fica de fora nao vira
## plano de agua, seria uma lamina boiando no vazio.
static func _clipped_river_path() -> Array[Vector2]:
	var clipped: Array[Vector2] = []
	for point: Vector2 in RIVER_PATH:
		clipped.append(point)
	while clipped.size() > 1 and clipped[0].y < 0.0:
		var head: Vector2 = clipped[0]
		var next: Vector2 = clipped[1]
		clipped.remove_at(0)
		if next.y > 0.0:
			clipped.insert(0, head.lerp(next, (0.0 - head.y) / (next.y - head.y)))
	while clipped.size() > 1 and clipped[clipped.size() - 1].x < 0.0:
		var tail: Vector2 = clipped[clipped.size() - 1]
		var previous: Vector2 = clipped[clipped.size() - 2]
		clipped.remove_at(clipped.size() - 1)
		if previous.x > 0.0:
			clipped.append(tail.lerp(previous, (0.0 - tail.x) / (previous.x - tail.x)))
	return clipped


func _process(_delta: float) -> bool:
	var ok: bool = _build_roads() and _build_river()
	quit(0 if ok else 1)
	return true


func _build_roads() -> bool:
	var material: Material = load(ROAD_MATERIAL_PATH) as Material
	if material == null:
		push_error("Nao carregou %s" % ROAD_MATERIAL_PATH)
		return false

	var by_kind: Dictionary = {}
	for piece: Dictionary in road_pieces():
		var kind: String = piece["kind"]
		if not by_kind.has(kind):
			by_kind[kind] = ([] as Array[Transform3D])
		var transform: Transform3D = piece["transform"]
		if kind.begins_with("asphalt"):
			transform = _city_asphalt_transform(transform)
		by_kind[kind].append(transform)

	var network: Node3D = Node3D.new()
	network.name = "RoadNetwork"
	var total: int = 0
	for kind: String in ROAD_MESHES:
		if not by_kind.has(kind):
			continue
		var transforms: Array[Transform3D] = by_kind[kind]
		var mesh: Mesh = load(ROAD_MESHES[kind]) as Mesh
		if mesh == null:
			push_error("Nao carregou %s" % ROAD_MESHES[kind])
			return false
		var multi_mesh: MultiMesh = MultiMesh.new()
		multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
		multi_mesh.mesh = mesh
		multi_mesh.instance_count = transforms.size()
		for index: int in transforms.size():
			multi_mesh.set_instance_transform(index, transforms[index])
		if multi_mesh.buffer.is_empty():
			push_error("MultiMesh de %s voltou sem buffer: rode este script SEM --headless" % kind)
			return false
		var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
		node.name = ROAD_NODE_NAMES[kind]
		node.multimesh = multi_mesh
		# O asset da cidade ja traz a superficie asfaltada; o atlas da fazenda
		# continua reservado para terra e cascalho rurais.
		node.material_override = null if kind.begins_with("asphalt") else material
		# Chapas no chao: a sombra que elas projetam nao aparece e custa.
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		network.add_child(node)
		node.owner = network
		total += transforms.size()
		print("%s: %d pecas" % [node.name, transforms.size()])

	if not _build_road_bed(network, material):
		return false

	var saved: bool = _save_scene(network, ROAD_SCENE_PATH)
	print("Estradas: %d pecas em %d draw calls" % [total, network.get_child_count()])
	return saved


## Chapa de terra sob as pecas, uma malha so. O material sai do mesmo atlas das
## estradas, com as duas faces desenhadas: a chapa e horizontal e vista sempre
## de cima, mas assim ela nunca some por causa da ordem dos vertices.
func _build_road_bed(network: Node3D, road_material: Material) -> bool:
	var quads: Array[Dictionary] = road_bed_quads()
	if quads.is_empty():
		push_error("Leito de estrada vazio")
		return false

	var height: float = GROUND_HEIGHT + ROAD_BED_LIFT
	for family: String in ["dirt", "gravel", "asphalt"]:
		var family_quads: Array[Dictionary] = []
		for quad: Dictionary in quads:
			if quad["family"] == family:
				family_quads.append(quad)
		if family_quads.is_empty():
			continue
		var surface: SurfaceTool = SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for quad: Dictionary in family_quads:
			var center: Vector2 = quad["center"]
			var axis: Vector2 = quad["axis"]
			var side: Vector2 = Vector2(-axis.y, axis.x)
			var half: Vector2 = quad["half"]
			var corners: Array[Vector3] = []
			for corner: Vector2 in [Vector2(-1.0, -1.0), Vector2(1.0, -1.0), Vector2(1.0, 1.0), Vector2(-1.0, 1.0)]:
				var flat: Vector2 = center + axis * (corner.x * half.x) + side * (corner.y * half.y)
				corners.append(Vector3(flat.x, height, flat.y))
			surface.set_normal(Vector3.UP)
			surface.set_uv(ROAD_BED_UV[family])
			for index: int in [0, 1, 3, 1, 2, 3]:
				surface.add_vertex(corners[index])
		var mesh: ArrayMesh = surface.commit()
		if mesh == null or mesh.get_surface_count() == 0:
			push_error("Leito de estrada nao gerou malha")
			return false
		var bed_material: Material = _road_material(family + "_straight", road_material)
		var node: MeshInstance3D = MeshInstance3D.new()
		node.name = family.capitalize() + "RoadBed"
		node.mesh = mesh
		node.material_override = bed_material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		network.add_child(node)
		node.owner = network
	print("RoadBed: %d chapas de terra sob as costuras" % quads.size())
	return true


func _road_material(kind: String, fallback: Material) -> Material:
	if not kind.begins_with("asphalt"):
		return fallback
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.resource_name = "CountryTown_Asphalt"
	material.albedo_color = Color(0.055, 0.062, 0.068)
	material.roughness = 0.92
	material.metallic = 0.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _city_asphalt_transform(base: Transform3D) -> Transform3D:
	var scale: float = TILE / 5.0
	var basis: Basis = base.basis.scaled(Vector3(scale, 1.0, scale))
	# O tile PolygonCity ocupa x=[0,5], z=[-5,0]; centralize antes de girar.
	var local_offset: Vector3 = Vector3(-2.5 * scale, 0.0, 2.5 * scale)
	return Transform3D(basis, base.origin + base.basis * local_offset)


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
		var span: Vector2 = end - start
		var length: float = span.length()

		var plane: PlaneMesh = PlaneMesh.new()
		plane.size = Vector2(WATER_WIDTH, length)
		plane.subdivide_width = 4
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
	return true
