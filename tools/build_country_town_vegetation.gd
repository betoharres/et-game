@tool
extends SceneTree

## Planta a vegetacao de fundo do Country Town no instancer do Terrain3D.
##
## Grama, arbustos e arvores de bosque nao viram no de cena: entram como
## instancias do `Terrain3DInstancer`, que guarda as transformacoes dentro das
## proprias regioes do terreno. E a diferenca entre este mapa e `world.tscn`,
## que tem cerca de 7.500 linhas so de tufo de grama instanciado um a um.
##
## O plantio desvia do que ja existe: faixa de rolamento das estradas, leito do
## rio e a area de qualquer colisao dos distritos. Rodar de novo limpa o que
## este script plantou antes -- ele nao acumula.
##
## `3dModelos/SICS Trees/ArrayTrees.tres` so trazia o cartao gerado do id 0 --
## que nao tem textura nenhuma no material e por isso aparece como uma cruz
## branca saindo do chao. Os assets deste mapa sao acrescentados aqui, nos ids
## seguintes, cada um com a cena de vegetacao que ja existe em
## `scenes/Vegetation/`; o id 0 fica intocado, sem ninguem plantado nele.
##
## Rode DEPOIS do build do terreno: aquele reimporta as regioes do zero e
## levaria a vegetacao junto.
##
##     .\tools\godot.cmd --path . --script res://tools/build_country_town_vegetation.gd --resolution 320x240

const Layout := preload("res://tools/build_country_town_layout.gd")

const TERRAIN_DIR: String = "res://scenes/CountryTown/Terrain"
const ASSETS_PATH: String = "res://3dModelos/SICS Trees/ArrayTrees.tres"

const DISTRICT_SCENES: Array[String] = [
	"res://scenes/CountryTown/Districts/FarmDistrict.tscn",
	"res://scenes/CountryTown/Districts/TownDistrict.tscn",
	"res://scenes/CountryTown/Districts/CrashSiteDistrict.tscn",
	"res://scenes/CountryTown/Districts/MinePortalSite.tscn",
	"res://scenes/CountryTown/Districts/DeliveryYard.tscn",
	"res://scenes/CountryTown/Districts/Detailing.tscn",
	"res://scenes/CountryTown/Districts/Fields.tscn",
]

## Ids no `Terrain3DAssets`. O 0 e o cartao gerado que ja existia, e continua
## vazio: sem textura no material, ele desenha uma cruz branca.
const BUSH_ID: int = 1
const TREE_ID: int = 2
const GRASS_ID: int = 3
const BUSH_SCENE: String = "res://scenes/Vegetation/tem_bush_02a.tscn"
const TREE_SCENE: String = "res://scenes/Vegetation/forest_tree_1a.tscn"
const GRASS_SCENE: String = "res://scenes/Vegetation/tem_grass_patch_01a.tscn"

const MAP_WIDTH: float = 600.0
const MAP_DEPTH: float = 450.0

## Nada nasce a menos disso da faixa de rolamento, do eixo do rio ou da
## colisao de um predio.
const ROAD_CLEARANCE: float = 6.5
const RIVER_CLEARANCE: float = 11.0
const BUILDING_CLEARANCE: float = 2.0
## Arbusto e arvore ainda pedem mais espaco que um tufo de grama.
const SHRUB_EXTRA: float = 3.0
const TREE_EXTRA: float = 6.0

## Faixa em que um LOD derrete no seguinte, em metros.
const LOD_FADE_MARGIN: float = 10.0

const GRASS_SPACING: float = 3.6
const BUSH_SPACING: float = 13.0
const TREE_SPACING: float = 7.0

## Bosques: centro, raio e quanto do disco vira arvore.
const GROVES: Array[Dictionary] = [
	{"center": Vector2(455.0, 110.0), "radius": 62.0, "fill": 0.55},
	{"center": Vector2(150.0, 245.0), "radius": 44.0, "fill": 0.45},
	{"center": Vector2(255.0, 405.0), "radius": 52.0, "fill": 0.5},
	{"center": Vector2(95.0, 160.0), "radius": 28.0, "fill": 0.35},
	{"center": Vector2(560.0, 160.0), "radius": 40.0, "fill": 0.5},
]
## Faixa de mata que acompanha o rio, fora do leito.
const RIVERBANK_MIN: float = 13.0
const RIVERBANK_MAX: float = 26.0
## Cinturao de mata na borda do mapa, que fecha o horizonte.
const RIM_BAND: float = 34.0

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _blockers: Array[Rect2] = []
var _road_segments: Array[Dictionary] = []
var _river_path: Array[Vector2] = []


func _process(_delta: float) -> bool:
	_rng.seed = 20260906
	var ok: bool = _build()
	quit(0 if ok else 1)
	return true


func _build() -> bool:
	var assets: Terrain3DAssets = load(ASSETS_PATH) as Terrain3DAssets
	if assets == null:
		push_error("Nao carregou %s" % ASSETS_PATH)
		return false
	if not _ensure_mesh_assets(assets):
		return false

	var terrain: Terrain3D = Terrain3D.new()
	terrain.assets = assets
	root.add_child(terrain)
	terrain.data_directory = TERRAIN_DIR
	var data: Terrain3DData = terrain.data
	if data == null or data.get_region_count() == 0:
		push_error("Terreno ausente em %s -- rode tools/build_country_town_terrain.gd" % TERRAIN_DIR)
		return false

	_road_segments = Layout.road_segments()
	_river_path = Layout.RIVER_PATH
	_blockers = district_blockers(DISTRICT_SCENES, root)
	print("Colisoes evitadas: %d" % _blockers.size())

	var instancer: Terrain3DInstancer = terrain.instancer
	# O id 0 entra na limpeza porque versoes anteriores deste script plantavam a
	# grama nele: o cartao gerado sem textura, que aparecia como cruz branca.
	for mesh_id: int in [0, BUSH_ID, TREE_ID, GRASS_ID]:
		instancer.clear_by_mesh(mesh_id)

	var grass: Array[Transform3D] = _scatter_grass(data)
	var bushes: Array[Transform3D] = _scatter_bushes(data)
	var trees: Array[Transform3D] = _scatter_trees(data)

	instancer.add_transforms(GRASS_ID, grass, PackedColorArray(), false)
	instancer.add_transforms(BUSH_ID, bushes, PackedColorArray(), false)
	instancer.add_transforms(TREE_ID, trees, PackedColorArray(), true)
	print("Plantado: %d tufos de grama, %d arbustos, %d arvores" % [grass.size(), bushes.size(), trees.size()])

	data.save_directory(TERRAIN_DIR)
	if ResourceSaver.save(assets, ASSETS_PATH) != OK:
		push_error("Nao gravou %s" % ASSETS_PATH)
		return false
	print("Regioes e assets gravados.")
	return true


## Registra grama, arbusto e arvore no `Terrain3DAssets`. Cada um aponta para a
## cena de vegetacao que ja existe.
##
## Os alcances de LOD sao generosos de proposito. Apertar o LOD 0 economiza
## pouco -- o instancer ja desenha tudo em `MultiMesh` por regiao -- e cobra
## caro na tela: a troca acontece a poucos passos do jogador, e o mapa parece
## que esta carregando enquanto ele anda. `fade_margin` derrete uma faixa em
## volta de cada troca, para nenhuma delas aparecer como um estalo.
func _ensure_mesh_assets(assets: Terrain3DAssets) -> bool:
	var wanted: Dictionary = {
		BUSH_ID: {
			"name": "country_town_bush", "scene": BUSH_SCENE, "density": 0.6,
			"ranges": [70.0, 200.0],
		},
		TREE_ID: {
			"name": "country_town_tree", "scene": TREE_SCENE, "density": 0.25,
			"ranges": [260.0],
		},
		GRASS_ID: {
			"name": "country_town_grass", "scene": GRASS_SCENE, "density": 1.0,
			"ranges": [35.0, 60.0, 95.0, 145.0, 220.0],
		},
	}
	for mesh_id: int in wanted:
		var scene: PackedScene = load(wanted[mesh_id]["scene"]) as PackedScene
		if scene == null:
			push_error("Nao carregou %s" % wanted[mesh_id]["scene"])
			return false
		var asset: Terrain3DMeshAsset = Terrain3DMeshAsset.new()
		asset.name = wanted[mesh_id]["name"]
		asset.id = mesh_id
		asset.scene_file = scene
		asset.density = wanted[mesh_id]["density"]
		# Massa de fundo nao projeta sombra: sao milhares de instancias e a cena
		# e noturna, com a Lua como fonte principal.
		asset.cast_shadows = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var ranges: Array = wanted[mesh_id]["ranges"]
		var last: int = mini(ranges.size(), asset.get_lod_count()) - 1
		if last < 0:
			push_error("%s nao tem LOD nenhum" % wanted[mesh_id]["scene"])
			return false
		asset.last_lod = last
		asset.last_shadow_lod = last
		asset.fade_margin = LOD_FADE_MARGIN
		for lod: int in last + 1:
			asset.set_lod_range(lod, float(ranges[lod]))
		assets.set_mesh_asset(mesh_id, asset)
		print("Asset de malha %d registrado: %s (LOD 0..%d)" % [mesh_id, asset.name, last])
	return true


## Retangulos em planta de toda colisao dos distritos, para nao plantar dentro
## de predio nem em cima de carga de patio. Estatica: o build de plantacoes
## precisa dos mesmos retangulos.
static func district_blockers(paths: Array[String], parent: Node) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for path: String in paths:
		var packed: PackedScene = load(path) as PackedScene
		if packed == null:
			continue
		var instance: Node = packed.instantiate()
		parent.add_child(instance)
		for node: Node in descendants(instance):
			var collider: CollisionShape3D = node as CollisionShape3D
			if collider == null or collider.shape == null:
				continue
			var debug_mesh: Mesh = collider.shape.get_debug_mesh()
			if debug_mesh == null:
				continue
			var bounds: AABB = collider.global_transform * debug_mesh.get_aabb()
			rects.append(Rect2(bounds.position.x, bounds.position.z, bounds.size.x, bounds.size.z))
		parent.remove_child(instance)
		instance.free()
	return rects


func _scatter_grass(data: Terrain3DData) -> Array[Transform3D]:
	var placed: Array[Transform3D] = []
	var steps_x: int = int(MAP_WIDTH / GRASS_SPACING)
	var steps_z: int = int(MAP_DEPTH / GRASS_SPACING)
	for ix: int in steps_x:
		for iz: int in steps_z:
			var point: Vector2 = Vector2(
					(float(ix) + _rng.randf()) * GRASS_SPACING,
					(float(iz) + _rng.randf()) * GRASS_SPACING)
			if not _is_free(point, 0.0):
				continue
			placed.append(_ground_transform(data, point, _rng.randf_range(0.8, 1.25)))
	return placed


func _scatter_bushes(data: Terrain3DData) -> Array[Transform3D]:
	var placed: Array[Transform3D] = []
	var steps_x: int = int(MAP_WIDTH / BUSH_SPACING)
	var steps_z: int = int(MAP_DEPTH / BUSH_SPACING)
	for ix: int in steps_x:
		for iz: int in steps_z:
			var point: Vector2 = Vector2(
					(float(ix) + _rng.randf()) * BUSH_SPACING,
					(float(iz) + _rng.randf()) * BUSH_SPACING)
			if not _is_free(point, SHRUB_EXTRA):
				continue
			# mais denso perto de mata e da margem, ralo no meio do campo aberto
			var chance: float = 0.25
			if _grove_weight(point) > 0.0 or _is_riverbank(point):
				chance = 0.8
			if _rng.randf() > chance:
				continue
			placed.append(_ground_transform(data, point, _rng.randf_range(0.75, 1.3)))
	return placed


func _scatter_trees(data: Terrain3DData) -> Array[Transform3D]:
	var placed: Array[Transform3D] = []
	var steps_x: int = int(MAP_WIDTH / TREE_SPACING)
	var steps_z: int = int(MAP_DEPTH / TREE_SPACING)
	for ix: int in steps_x:
		for iz: int in steps_z:
			var point: Vector2 = Vector2(
					(float(ix) + _rng.randf()) * TREE_SPACING,
					(float(iz) + _rng.randf()) * TREE_SPACING)
			if not _is_free(point, TREE_EXTRA):
				continue
			var chance: float = _grove_weight(point)
			if _is_riverbank(point):
				chance = maxf(chance, 0.35)
			if _is_map_rim(point):
				chance = maxf(chance, 0.7)
			if chance <= 0.0 or _rng.randf() > chance:
				continue
			placed.append(_ground_transform(data, point, _rng.randf_range(0.85, 1.45)))
	return placed


## Quanto de bosque cobre este ponto: cheio no centro, esgarcado na borda.
func _grove_weight(point: Vector2) -> float:
	var best: float = 0.0
	for grove: Dictionary in GROVES:
		var distance: float = point.distance_to(grove["center"])
		var radius: float = grove["radius"]
		if distance > radius:
			continue
		var falloff: float = 1.0 - smoothstep(0.45, 1.0, distance / radius)
		best = maxf(best, float(grove["fill"]) * falloff)
	return best


func _is_riverbank(point: Vector2) -> bool:
	var distance: float = _distance_to_river(point)
	return distance > RIVERBANK_MIN and distance < RIVERBANK_MAX


func _is_map_rim(point: Vector2) -> bool:
	return point.x < RIM_BAND or point.x > MAP_WIDTH - RIM_BAND \
			or point.y < RIM_BAND or point.y > MAP_DEPTH - RIM_BAND


func _is_free(point: Vector2, extra: float) -> bool:
	for field: Dictionary in Layout.CROP_FIELDS:
		if (field["rect"] as Rect2).grow(2.0 + extra).has_point(point):
			return false
	if Layout.on_secondary_path(point, 1.5 + extra):
		return false
	for clearing: Rect2 in Layout.SETTLEMENT_CLEARINGS:
		if clearing.grow(extra).has_point(point):
			return false
	# O nucleo construido recebe jardins autorais, sem mato aleatorio nas
	# calcadas. A borda continua com grama e arbustos de transicao.
	if Rect2(340, 137, 220, 211).has_point(point):
		return false
	if _distance_to_river(point) < RIVER_CLEARANCE + extra:
		return false
	for segment: Dictionary in _road_segments:
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(
				point, segment["start"], segment["end"])
		if point.distance_to(closest) < ROAD_CLEARANCE + extra:
			return false
	for rect: Rect2 in _blockers:
		if rect.grow(BUILDING_CLEARANCE + extra).has_point(point):
			return false
	return true


func _distance_to_river(point: Vector2) -> float:
	var best: float = INF
	for i: int in _river_path.size() - 1:
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(
				point, _river_path[i], _river_path[i + 1])
		best = minf(best, point.distance_to(closest))
	return best


func _ground_transform(data: Terrain3DData, point: Vector2, scale: float) -> Transform3D:
	var height: float = data.get_height(Vector3(point.x, 0.0, point.y))
	if is_nan(height):
		height = 0.0
	var basis: Basis = Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * scale)
	return Transform3D(basis, Vector3(point.x, height, point.y))


static func descendants(node: Node) -> Array[Node]:
	var found: Array[Node] = [node]
	for child: Node in node.get_children():
		found.append_array(descendants(child))
	return found
