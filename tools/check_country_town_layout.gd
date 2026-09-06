@tool
extends SceneTree

## Confere o layout do mapa Country Town (`scenes/CountryTown/`).
##
## Cada marcador de `Layout/PointsOfInterest.tscn` precisa: existir com o nome
## exato, estar no grupo `country_town_poi`, cair dentro do retangulo de
## 600 x 450 m do mapa, pousar no terreno gerado por
## `tools/build_country_town_terrain.gd` e ficar acima da linha d'agua dos
## planos de `Districts/RiverWater.tscn`.
##
## Um marcador que boia ou afunda em relacao ao terreno tambem e falha: e o
## sintoma de layout e relevo terem saido de sincronia -- rode o build de novo.
##
## A malha de estradas tambem e conferida, celula a celula: duas pecas na mesma
## celula e falha, e todo conector de peca -- as pontas de uma reta, os dois
## bracos de uma curva, os tres de um T -- precisa achar do outro lado uma peca
## que encoste de volta. Conector solto e o buraco por onde a estrada some.
##
## Uso:
##
##     .\tools\godot.cmd --headless --path . --script res://tools/check_country_town_layout.gd
##
## Sai com codigo 1 e imprime as coordenadas de cada marcador reprovado.

const Layout := preload("res://tools/build_country_town_layout.gd")

const POI_SCENE_PATH: String = "res://scenes/CountryTown/Layout/PointsOfInterest.tscn"
const RIVER_SCENE_PATH: String = "res://scenes/CountryTown/Districts/RiverWater.tscn"
const TERRAIN_DIR: String = "res://scenes/CountryTown/Terrain"

const MAP_WIDTH: float = 600.0
const MAP_DEPTH: float = 450.0
const POI_GROUP: String = "country_town_poi"

## Os 14 pontos de interesse do mapa, mais o nascedouro do jogador.
const REQUIRED_POIS: Array[String] = [
	"Farmhouse", "Barn", "CornField", "MinePortal", "AlienCrashSite",
	"LivestockPen", "OldShed", "Windmill", "RiversideDock", "GeneralStore",
	"TownSquare", "Church", "DeliveryPoint", "TownExit",
]
const SPAWN_MARKER: String = "PlayerSpawn"

## Folga entre o y do marcador e a altura do terreno sob ele.
const HEIGHT_TOLERANCE: float = 0.75

var _failures: Array[String] = []


## A conferencia espera o primeiro quadro: as cenas de layout so entregam
## `global_position` depois que a arvore existe.
func _process(_delta: float) -> bool:
	_run()
	return true


func _run() -> void:
	var water_level: float = _read_water_level()
	if is_nan(water_level):
		_fail("Nao achei nenhum plano de agua em %s" % RIVER_SCENE_PATH)
		_report()
		return

	var markers: Dictionary = _read_markers()
	if markers.is_empty():
		_fail("Nao achei nenhum marcador em %s" % POI_SCENE_PATH)
		_report()
		return

	var terrain: Terrain3D = Terrain3D.new()
	root.add_child(terrain)
	terrain.data_directory = TERRAIN_DIR
	var data: Terrain3DData = terrain.data
	if data == null or data.get_region_count() == 0:
		_fail("Terreno ausente em %s -- rode tools/build_country_town_terrain.gd" % TERRAIN_DIR)
		_report()
		return

	print("Linha d'agua: %.2f m | regioes de terreno: %d" % [water_level, data.get_region_count()])

	_check_road_network()

	for name: String in REQUIRED_POIS + [SPAWN_MARKER]:
		if not markers.has(name):
			_fail("Marcador ausente: %s" % name)
			continue
		var marker: Marker3D = markers[name] as Marker3D
		var position: Vector3 = marker.global_position

		if not marker.is_in_group(POI_GROUP):
			_fail("%s (%.1f, %.1f) fora do grupo %s" % [name, position.x, position.z, POI_GROUP])

		if position.x < 0.0 or position.x > MAP_WIDTH or position.z < 0.0 or position.z > MAP_DEPTH:
			_fail("%s (%.1f, %.1f) fora do mapa de %.0f x %.0f m"
					% [name, position.x, position.z, MAP_WIDTH, MAP_DEPTH])

		if position.y <= water_level:
			_fail("%s (%.1f, %.1f) em y = %.2f m, na linha d'agua de %.2f m ou abaixo"
					% [name, position.x, position.z, position.y, water_level])

		var ground: float = data.get_height(Vector3(position.x, 0.0, position.z))
		if is_nan(ground):
			_fail("%s (%.1f, %.1f) esta fora das regioes de terreno"
					% [name, position.x, position.z])
			continue

		if ground <= water_level:
			_fail("%s (%.1f, %.1f) tem terreno em %.2f m, submerso pela agua de %.2f m"
					% [name, position.x, position.z, ground, water_level])

		if absf(ground - position.y) > HEIGHT_TOLERANCE:
			_fail("%s (%.1f, %.1f) em y = %.2f m com terreno em %.2f m (folga de %.2f m)"
					% [name, position.x, position.z, position.y, ground, absf(ground - position.y)])

	_report()


## A malha de estradas: uma peca por celula, e todo conector encostando em uma
## peca que encosta de volta.
func _check_road_network() -> void:
	var tiles: Array[Dictionary] = Layout.road_tiles()
	var by_cell: Dictionary = {}
	for tile: Dictionary in tiles:
		var cell: Vector2i = tile["cell"]
		if by_cell.has(cell):
			_fail("Celula (%d, %d) tem duas pecas: %s e %s"
					% [cell.x, cell.y, by_cell[cell]["kind"], tile["kind"]])
			continue
		by_cell[cell] = tile

	var open_ends: int = 0
	for cell: Vector2i in by_cell:
		var tile: Dictionary = by_cell[cell]
		for direction: Vector2 in Layout.ROAD_CONNECTORS[Layout.shape_of(tile["kind"])]:
			var step: Vector2 = Layout.rotate_local(direction, tile["angle"])
			var neighbour_cell: Vector2i = cell + Vector2i(roundi(step.x), roundi(step.y))
			if not by_cell.has(neighbour_cell):
				open_ends += 1
				_fail("%s em (%d, %d) encosta em (%d, %d), onde nao ha peca"
						% [tile["kind"], cell.x, cell.y, neighbour_cell.x, neighbour_cell.y])
				continue
			if not _connects_back(by_cell[neighbour_cell], neighbour_cell, cell):
				_fail("%s em (%d, %d) encosta em %s (%d, %d), que nao encosta de volta"
						% [tile["kind"], cell.x, cell.y,
						by_cell[neighbour_cell]["kind"], neighbour_cell.x, neighbour_cell.y])

	if open_ends == 0:
		print("Malha de estradas: %d pecas, todos os conectores fechados." % tiles.size())


func _connects_back(tile: Dictionary, from_cell: Vector2i, to_cell: Vector2i) -> bool:
	for direction: Vector2 in Layout.ROAD_CONNECTORS[Layout.shape_of(tile["kind"])]:
		var step: Vector2 = Layout.rotate_local(direction, tile["angle"])
		if from_cell + Vector2i(roundi(step.x), roundi(step.y)) == to_cell:
			return true
	return false


func _read_water_level() -> float:
	var packed: PackedScene = load(RIVER_SCENE_PATH) as PackedScene
	if packed == null:
		return NAN
	var instance: Node = packed.instantiate()
	root.add_child(instance)
	var level: float = NAN
	for child: Node in instance.get_children():
		var mesh: MeshInstance3D = child as MeshInstance3D
		if mesh == null:
			continue
		level = mesh.global_position.y if is_nan(level) else minf(level, mesh.global_position.y)
	root.remove_child(instance)
	instance.free()
	return level


func _read_markers() -> Dictionary:
	var markers: Dictionary = {}
	var packed: PackedScene = load(POI_SCENE_PATH) as PackedScene
	if packed == null:
		return markers
	var instance: Node = packed.instantiate()
	root.add_child(instance)
	for child: Node in instance.get_children():
		var marker: Marker3D = child as Marker3D
		if marker != null:
			markers[marker.name] = marker
	return markers


func _fail(message: String) -> void:
	_failures.append(message)


func _report() -> void:
	if _failures.is_empty():
		print("Layout do Country Town OK: %d POIs conferidos." % (REQUIRED_POIS.size() + 1))
		quit(0)
		return
	printerr("Layout do Country Town reprovado em %d ponto(s):" % _failures.size())
	for failure: String in _failures:
		printerr("  - %s" % failure)
	quit(1)
