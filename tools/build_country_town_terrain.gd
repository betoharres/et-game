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
const MATERIAL_PATH: String = "res://Materiais/country_terrain_material.tres"
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
var _rural_offsets: Dictionary[Vector2i, float] = {}


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
	_carve_rural_wear()
	return _save_terrain()


## Relevo permanente sob as curvas existentes; a grade de 1 m pede sulcos
## largos e rasos. Maximos por pixel evitam somar profundidade em cruzamentos.
func _carve_rural_wear() -> void:
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = 4817
	noise.frequency = 0.055
	var cuts: Dictionary[Vector2i, float] = {}
	var banks: Dictionary[Vector2i, float] = {}
	for district: String in ["RoadNetwork", "SecondaryPaths"]:
		var packed: PackedScene = load("res://scenes/CountryTown/Districts/%s.tscn" % district) as PackedScene
		var scene: Node = packed.instantiate()
		var tracks: Node = scene.get_node_or_null("TireTracks")
		if tracks == null:
			scene.free()
			continue
		for child: Node in tracks.get_children():
			var track: Path3D = child as Path3D
			if track == null or track.curve == null:
				continue
			# Passagens secundarias ficam visuais; arcos de manobra tambem escavam.
			if str(track.name).ends_with("PassB") or str(track.name).ends_with("PassC"):
				continue
			var length: float = track.curve.get_baked_length()
			for station: int in ceili(length) + 1:
				var along: float = minf(float(station), length)
				var local: Vector3 = track.curve.sample_baked(along)
				var ahead: Vector3 = track.curve.sample_baked(minf(along + 2.0, length))
				var behind: Vector3 = track.curve.sample_baked(maxf(along - 2.0, 0.0))
				var direction: Vector3 = (ahead - behind).normalized()
				var side: Vector3 = direction.cross(Vector3.UP).normalized()
				var center: Vector3 = track.transform * local
				var end_weight: float = smoothstep(0.0, 5.0, minf(along, length - along))
				var protection: float = 1.0
				for bridge: Vector2 in [Vector2(318.18723, 167.46), Vector2(204.9, 298.48)]:
					protection *= smoothstep(32.0, 42.0, Vector2(center.x, center.z).distance_to(bridge))
				var patch: float = smoothstep(-0.35, 0.45, noise.get_noise_2d(center.x, center.z))
				var bend: float = 1.0 - (ahead - local).normalized().dot((local - behind).normalized())
				var depth: float = (0.025 + 0.085 * patch + minf(bend, 0.5) * 0.04) * end_weight * protection
				for lane: int in int(track.get("lanes")):
					var offset: float = float(track.get("lane_offset")) + (float(lane) - float(int(track.get("lanes")) - 1) * 0.5) * float(track.get("lane_spacing"))
					var wheel: Vector3 = center + side * offset
					for z: int in range(_pixel_of(wheel.z - 2.0), _pixel_of(wheel.z + 2.0) + 1):
						for x: int in range(_pixel_of(wheel.x - 2.0), _pixel_of(wheel.x + 2.0) + 1):
							var delta: Vector2 = Vector2(_world_of(x) - wheel.x, _world_of(z) - wheel.z)
							var longitudinal: float = absf(delta.dot(Vector2(direction.x, direction.z)))
							var lateral: float = absf(delta.dot(Vector2(side.x, side.z)))
							var fade: float = 1.0 - smoothstep(0.4, 1.4, longitudinal)
							var key: Vector2i = Vector2i(x, z)
							var cut: float = depth * (1.0 - smoothstep(0.15, 1.0, lateral)) * fade
							var bank: float = depth * 0.25 * (1.0 - smoothstep(0.0, 0.7, absf(lateral - 1.25))) * fade
							cuts[key] = maxf(cuts.get(key, 0.0), cut)
							banks[key] = maxf(banks.get(key, 0.0), bank)
		scene.free()
	for key: Vector2i in cuts:
		var offset: float = float(banks[key]) - float(cuts[key])
		if absf(offset) < 0.0001:
			continue
		_rural_offsets[key] = offset
	print("Rural wear: %d height samples; shallow ruts and displaced soil." % _rural_offsets.size())


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
	var rural_only: bool = OS.get_cmdline_user_args().has("--rural-only")
	if not rural_only:
		terrain.material = load(MATERIAL_PATH)
		terrain.assets = load(ASSETS_PATH)
	root.add_child(terrain)
	# Apontar o diretorio de destino e o que inicializa os dados do terreno.
	terrain.data_directory = DEST_DIR
	var data: Terrain3DData = terrain.data
	if data == null:
		push_error("Terrain3D nao inicializou os dados em headless")
		return false

	# Retira o perfil anterior antes de aplicar o novo, preservando o relevo
	# existente (inclusive rampas de trilhas feitas pelo settlement).
	if rural_only:
		if data.get_region_count() == 0:
			push_error("Missing existing terrain for --rural-only")
			return false
		for region: Terrain3DRegion in data.get_regions_active():
			var previous: Dictionary = region.get_meta("rural_wear_offsets", {})
			for key: Vector2i in previous:
				var point: Vector3 = Vector3(_world_of(key.x), 0.0, _world_of(key.y))
				data.set_height(point, data.get_height(point) - float(previous[key]))
			if not previous.is_empty():
				region.remove_meta("rural_wear_offsets")
		for key: Vector2i in _rural_offsets:
			var point: Vector3 = Vector3(_world_of(key.x), 0.0, _world_of(key.y))
			data.set_height(point, data.get_height(point) + _rural_offsets[key])
		_record_rural_offsets(data)
		data.update_maps(Terrain3DRegion.TYPE_HEIGHT)
		data.save_directory(DEST_DIR)
		terrain.free()
		return true

	for key: Vector2i in _rural_offsets:
		_heights[key.y * IMAGE_SIZE + key.x] += _rural_offsets[key]
	var height_map: Image = Image.create_from_data(IMAGE_SIZE, IMAGE_SIZE, false,
			Image.FORMAT_RF, _heights.to_byte_array())
	var images: Array[Image] = []
	images.resize(Terrain3DRegion.TYPE_MAX)
	images[Terrain3DRegion.TYPE_HEIGHT] = height_map
	data.import_images(images, Vector3(TERRAIN_ORIGIN, 0.0, TERRAIN_ORIGIN), 0.0, 1.0)
	_record_rural_offsets(data)
	data.save_directory(DEST_DIR)

	var range_min_max: Vector2 = Terrain3DUtil.get_min_max(height_map)
	print("Regioes salvas em %s: %d" % [DEST_DIR, data.get_region_count()])
	print("Altura do terreno: %.2f m a %.2f m (agua em %.2f m)"
			% [range_min_max.x, range_min_max.y, WATER_LEVEL])
	root.remove_child(terrain)
	terrain.free()
	return true


## Guarda so o deslocamento aplicado, para atualizacoes sem acumulo de relevo.
func _record_rural_offsets(data: Terrain3DData) -> void:
	for region: Terrain3DRegion in data.get_regions_active():
		var offsets: Dictionary[Vector2i, float] = {}
		for key: Vector2i in _rural_offsets:
			var point: Vector3 = Vector3(_world_of(key.x), 0.0, _world_of(key.y))
			if data.get_region_location(point) == region.location:
				offsets[key] = _rural_offsets[key]
		if not offsets.is_empty():
			region.set_meta("rural_wear_offsets", offsets)
			region.modified = true
