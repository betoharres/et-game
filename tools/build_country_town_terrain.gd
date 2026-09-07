@tool
extends SceneTree

## Gera o relevo do mapa Country Town (`scenes/CountryTown/`) por codigo.
##
## Escreve um heightmap de 1024x1024 em `Image.FORMAT_RF`, importa com
## `Terrain3DData.import_images()` e salva as regioes com
## `Terrain3DData.save_directory()` -- o mesmo par de chamadas de
## `addons/terrain_3d/tools/importer.gd:88` e `:96`.
##
## O destino e EXCLUSIVO deste mapa (`res://scenes/CountryTown/Terrain`). O
## terreno da fazenda vive em `res://scenes` com os `terrain3d_*.res` soltos
## la; este script nunca escreve naquele diretorio.
##
## O relevo se adapta ao layout, e nao o contrario: as clareiras planas saem
## dos marcadores de `Layout/PointsOfInterest.tscn`, e o corredor das estradas
## e o canal do rio saem da grade e do `RIVER_PATH` de
## `tools/build_country_town_layout.gd`. Mexeu no layout, rode este script
## logo depois -- os dois lados precisam contar a mesma historia.
##
## Uso:
##
##     .\tools\godot.cmd --headless --path . --script res://tools/build_country_town_terrain.gd

## Grade das estradas, tracado do rio e cotas do mapa moram no build de layout.
const Layout := preload("res://tools/build_country_town_layout.gd")

const DEST_DIR: String = "res://scenes/CountryTown/Terrain"
const MATERIAL_PATH: String = "res://Materiais/new_terrain_3d_material.tres"
const ASSETS_PATH: String = "res://3dModelos/SICS Trees/ArrayTrees.tres"
const POI_SCENE_PATH: String = "res://scenes/CountryTown/Layout/PointsOfInterest.tscn"

## O heightmap cobre 1280 x 1280 m começando 256 m a oeste e ao norte da origem
## do mapa. 1 pixel = 1 m.
##
## A folga negativa e o que faz as colinas de borda fecharem o horizonte dos
## quatro lados: elas comecam `RIM_INSET` metros para dentro e so saturam
## `RIM_RAMP` metros adiante, ja fora do mapa. Com o heightmap comecando em
## zero, esse trecho de rampa simplesmente nao existia a oeste e ao norte -- o
## terreno acabava no meio da subida, num precipicio. `TERRAIN_ORIGIN` e
## multiplo do `region_size` (256 m) do Terrain3D, senao as regioes nao alinham.
const IMAGE_SIZE: int = 1280
const TERRAIN_ORIGIN: float = -256.0
const MAP_WIDTH: float = 600.0
const MAP_DEPTH: float = 450.0

## Altura do vale. Tudo que e construido -- platos, estradas, clareiras dos
## POIs -- fica exatamente nesta cota, entao os marcadores e as pecas de
## estrada ficam em y = GROUND_HEIGHT sem calculo nenhum.
const GROUND_HEIGHT: float = Layout.GROUND_HEIGHT
## Superficie da agua do rio, igual ao y dos planos de `RiverDistrict.tscn`.
const WATER_LEVEL: float = Layout.WATER_LEVEL
const RIVER_BED_HEIGHT: float = 1.2
## Meia largura do leito e largura da ribanceira que sobe do leito ao vale. As
## duas moram no layout: os planos de agua precisam das mesmas medidas para
## saber quanto avancar nas pontas do tracado.
const RIVER_BED_RATIO: float = Layout.RIVER_BED_RATIO
const RIVER_BANK_WIDTH: float = Layout.RIVER_BANK_WIDTH

## Ondulacao do terreno solto, fora de plato, estrada ou clareira.
const ROLLING_AMPLITUDE: float = 0.55

## Colinas de borda: comecam a RIM_INSET da borda do mapa e saturam RIM_RAMP
## metros adiante, ja fora dele.
const RIM_HEIGHT: float = 26.0
const RIM_INSET: float = 30.0
const RIM_RAMP: float = 120.0

## Raio aplainado em volta de cada marcador de POI e de cada peca de estrada,
## com a transicao que os liga ao terreno solto.
const POI_CLEARING_RADIUS: float = 12.0
const ROAD_CLEARING_RADIUS: float = 8.5
const CLEARING_BLEND: float = 6.0
const PLATEAU_BLEND: float = 15.0

## Zonas construidas, planas de ponta a ponta. Nenhuma encosta no rio.
const PLATEAUS: Array[Rect2] = [
	Rect2(20.0, 20.0, 215.0, 185.0),    # fazenda
	Rect2(350.0, 165.0, 215.0, 175.0),  # cidade
	Rect2(300.0, 335.0, 100.0, 75.0),   # patio de entrega
]

var _heights: PackedFloat32Array = PackedFloat32Array()


## O trabalho espera o primeiro quadro: as cenas de layout so entregam
## `global_position` depois que a arvore existe.
func _process(_delta: float) -> bool:
	var ok: bool = _build()
	quit(0 if ok else 1)
	return true


func _build() -> bool:
	_heights.resize(IMAGE_SIZE * IMAGE_SIZE)
	_fill_base()
	_carve_plateaus()

	var poi_points: PackedVector2Array = _collect_marker_points()
	if poi_points.is_empty():
		push_error("Nenhum marcador em %s" % POI_SCENE_PATH)
		return false
	_flatten_around(poi_points, POI_CLEARING_RADIUS)
	print("Clareiras de POI: %d" % poi_points.size())

	var road_points: PackedVector2Array = _road_points()
	if road_points.is_empty():
		push_error("Nenhuma peca de estrada em ROAD_RUNS")
		return false
	_flatten_around(road_points, ROAD_CLEARING_RADIUS)
	print("Corredor de estrada: %d pecas" % road_points.size())

	# Local urban streets share the primary network elevation.
	var local_points: PackedVector2Array = PackedVector2Array()
	for path: Dictionary in Layout.SECONDARY_PATHS:
		if not path["urban"]:
			continue
		var points: Array = path["points"]
		for index: int in points.size() - 1:
			var start: Vector2 = points[index]
			var end: Vector2 = points[index + 1]
			var steps: int = ceili(start.distance_to(end) / 2.0)
			for step: int in steps + 1:
				local_points.append(start.lerp(end, float(step) / steps))
	_flatten_around(local_points, 7.5)
	_carve_river()
	return _save_terrain()


## Vale quase plano, com ondulacao suave e colinas subindo nas bordas.
func _fill_base() -> void:
	for pz: int in IMAGE_SIZE:
		var z: float = _world_of(pz)
		var rim_z: float = maxf(RIM_INSET - z, z - (MAP_DEPTH - RIM_INSET))
		for px: int in IMAGE_SIZE:
			var x: float = _world_of(px)
			var rolling: float = sin(x * 0.031) * cos(z * 0.027) * 0.6 + sin((x + z) * 0.013) * 0.4
			var rim: float = maxf(rim_z, maxf(RIM_INSET - x, x - (MAP_WIDTH - RIM_INSET)))
			var rim_t: float = smoothstep(0.0, 1.0, clampf(rim / RIM_RAMP, 0.0, 1.0))
			_heights[pz * IMAGE_SIZE + px] = GROUND_HEIGHT \
					+ rolling * ROLLING_AMPLITUDE \
					+ RIM_HEIGHT * rim_t


## Achata as zonas construidas, com uma saia de transicao para o terreno solto.
func _carve_plateaus() -> void:
	for plateau: Rect2 in PLATEAUS:
		var grown: Rect2 = plateau.grow(PLATEAU_BLEND)
		var x0: int = _pixel_of(grown.position.x)
		var z0: int = _pixel_of(grown.position.y)
		var x1: int = _pixel_of(grown.end.x)
		var z1: int = _pixel_of(grown.end.y)
		for pz: int in range(z0, z1 + 1):
			for px: int in range(x0, x1 + 1):
				var point: Vector2 = Vector2(_world_of(px), _world_of(pz))
				var outside: float = _distance_outside_rect(point, plateau)
				if outside > PLATEAU_BLEND:
					continue
				var index: int = pz * IMAGE_SIZE + px
				var t: float = smoothstep(0.0, 1.0, outside / PLATEAU_BLEND)
				_heights[index] = lerpf(GROUND_HEIGHT, _heights[index], t)


## Achata um disco em volta de cada ponto -- clareira de POI ou peca de estrada.
func _flatten_around(points: PackedVector2Array, radius: float) -> void:
	var reach: float = radius + CLEARING_BLEND
	for point: Vector2 in points:
		var x0: int = _pixel_of(point.x - reach)
		var z0: int = _pixel_of(point.y - reach)
		var x1: int = _pixel_of(point.x + reach)
		var z1: int = _pixel_of(point.y + reach)
		for pz: int in range(z0, z1 + 1):
			for px: int in range(x0, x1 + 1):
				var distance: float = point.distance_to(Vector2(_world_of(px), _world_of(pz)))
				if distance > reach:
					continue
				var index: int = pz * IMAGE_SIZE + px
				var t: float = smoothstep(0.0, 1.0, clampf((distance - radius) / CLEARING_BLEND, 0.0, 1.0))
				_heights[index] = lerpf(GROUND_HEIGHT, _heights[index], t)


## Escava o canal por ultimo, para o rio cortar plato, estrada e colina de
## borda: e assim que os vaos das pontes e a foz nas bordas ficam abertos.
##
## A meia-largura do leito acompanha `Layout.river_width()`: nos trechos que
## alargam para o lago da foz, o leito alarga na mesma proporcao. A margem de
## transicao fica fixa -- alarga-la junto faria o lago puxar o terreno para
## baixo bem longe da agua, ate debaixo do ancoradouro.
func _carve_river() -> void:
	var river_path: Array[Vector2] = Layout.RIVER_PATH
	for i: int in river_path.size() - 1:
		var half_width: float = Layout.river_width(i) * RIVER_BED_RATIO
		var reach: float = half_width + RIVER_BANK_WIDTH
		var a: Vector2 = river_path[i]
		var b: Vector2 = river_path[i + 1]
		var x0: int = _pixel_of(minf(a.x, b.x) - reach)
		var z0: int = _pixel_of(minf(a.y, b.y) - reach)
		var x1: int = _pixel_of(maxf(a.x, b.x) + reach)
		var z1: int = _pixel_of(maxf(a.y, b.y) + reach)
		for pz: int in range(z0, z1 + 1):
			for px: int in range(x0, x1 + 1):
				var point: Vector2 = Vector2(_world_of(px), _world_of(pz))
				var distance: float = _distance_to_segment(point, a, b)
				if distance > reach:
					continue
				var index: int = pz * IMAGE_SIZE + px
				var target: float = RIVER_BED_HEIGHT
				if distance > half_width:
					var t: float = smoothstep(0.0, 1.0, (distance - half_width) / RIVER_BANK_WIDTH)
					target = lerpf(RIVER_BED_HEIGHT, _heights[index], t)
				_heights[index] = minf(_heights[index], target)


## Coordenada de mundo de um pixel do heightmap, em qualquer um dos dois eixos.
func _world_of(pixel: int) -> float:
	return float(pixel) + TERRAIN_ORIGIN


## Pixel do heightmap de uma coordenada de mundo, preso as bordas da imagem.
func _pixel_of(world: float) -> int:
	return clampi(int(round(world - TERRAIN_ORIGIN)), 0, IMAGE_SIZE - 1)


func _distance_outside_rect(point: Vector2, rect: Rect2) -> float:
	var dx: float = maxf(rect.position.x - point.x, point.x - rect.end.x)
	var dz: float = maxf(rect.position.y - point.y, point.y - rect.end.y)
	return Vector2(maxf(dx, 0.0), maxf(dz, 0.0)).length()


func _distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	return point.distance_to(Geometry2D.get_closest_point_to_segment(point, a, b))


## Posicoes XZ dos marcadores de POI, em coordenadas de mundo. O layout mora na
## cena: mover um marcador no editor move a clareira do terreno junto.
func _collect_marker_points() -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	var packed: PackedScene = load(POI_SCENE_PATH) as PackedScene
	if packed == null:
		push_error("Nao carregou %s" % POI_SCENE_PATH)
		return points
	var instance: Node = packed.instantiate()
	root.add_child(instance)
	for child: Node in instance.get_children():
		var marker: Marker3D = child as Marker3D
		if marker != null:
			points.append(Vector2(marker.global_position.x, marker.global_position.z))
	root.remove_child(instance)
	instance.free()
	return points


## Centro de cada peca de estrada, direto da grade -- as pecas viram MultiMesh
## na cena, entao ler a cena de volta custaria decodificar o buffer.
func _road_points() -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for piece: Dictionary in Layout.road_pieces():
		var origin: Vector3 = (piece["transform"] as Transform3D).origin
		points.append(Vector2(origin.x, origin.z))
	return points


func _save_terrain() -> bool:
	if DirAccess.make_dir_recursive_absolute(DEST_DIR) != OK and not DirAccess.dir_exists_absolute(DEST_DIR):
		push_error("Nao criou %s" % DEST_DIR)
		return false

	var terrain: Terrain3D = Terrain3D.new()
	terrain.material = load(MATERIAL_PATH)
	terrain.assets = load(ASSETS_PATH)
	root.add_child(terrain)
	# Apontar o diretorio de destino e o que inicializa os dados do terreno.
	terrain.data_directory = DEST_DIR
	var data: Terrain3DData = terrain.data
	if data == null:
		push_error("Terrain3D nao inicializou os dados em headless")
		return false

	var height_map: Image = Image.create_from_data(IMAGE_SIZE, IMAGE_SIZE, false,
			Image.FORMAT_RF, _heights.to_byte_array())
	var images: Array[Image] = []
	images.resize(Terrain3DRegion.TYPE_MAX)
	images[Terrain3DRegion.TYPE_HEIGHT] = height_map
	data.import_images(images, Vector3(TERRAIN_ORIGIN, 0.0, TERRAIN_ORIGIN), 0.0, 1.0)
	data.save_directory(DEST_DIR)

	var range_min_max: Vector2 = Terrain3DUtil.get_min_max(height_map)
	print("Regioes salvas em %s: %d" % [DEST_DIR, data.get_region_count()])
	print("Altura do terreno: %.2f m a %.2f m (agua em %.2f m)"
			% [range_min_max.x, range_min_max.y, WATER_LEVEL])
	root.remove_child(terrain)
	terrain.free()
	return true
