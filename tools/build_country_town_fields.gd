@tool
extends SceneTree

## Gera `scenes/CountryTown/Districts/Fields.tscn`: o milharal, os talhoes de
## trigo e os canteiros de girassol do Country Town.
##
## Os talhoes sao retangulos em `FIELDS`, preenchidos em grade. O script poda o
## que cai perto demais de estrada, de rio ou da colisao de um predio, entao da
## para desenhar um talhao generoso sem conferir cada canto a mao.
##
## O tamanho de um talhao e limitado pela malha, nao pela area: um pe de milho
## do Synty tem 1438 triangulos e a cena `corn_field_root` empilha dez deles em
## 2,2 x 5,2 m. Por isso cada instancia sai daqui com `visibility_range` e
## `active_radius` ajustados -- e o que deixa o campo grande sem cobrar o campo
## inteiro em cada quadro. Ver `scripts/reactive_crop.gd`.
##
## Rode depois do build de terreno: cada planta pousa na altura do terreno.
##
##     .\tools\godot.cmd --path . --script res://tools/build_country_town_fields.gd --resolution 320x240

const Layout := preload("res://tools/build_country_town_layout.gd")
const Vegetation := preload("res://tools/build_country_town_vegetation.gd")

const FIELDS_SCENE_PATH: String = "res://scenes/CountryTown/Districts/Fields.tscn"
const TERRAIN_DIR: String = "res://scenes/CountryTown/Terrain"
const DIRT_ROWS_MESH: String = "res://PolygonFarm/Models/SM_Env_Dirt_Rows_01.fbx"
const DIRT_ROWS_MATERIAL: String = "res://Materiais/PolygonFarm1A.tres"

const CROP_SCENES: Dictionary = {
	"corn": "res://scenes/AnimatedCrops/corn_field_root.tscn",
	"wheat": "res://scenes/AnimatedCrops/WheatField.tscn",
	"sunflower": "res://scenes/AnimatedCrops/SunflowersPatch.tscn",
}

## Ate onde cada especie e desenhada, e a partir de onde ela para de calcular
## vergadura. Milho e o mais caro por metro quadrado, entao e o mais curto.
const CROP_RANGES: Dictionary = {
	"corn": {"visibility": 80.0, "active": 40.0},
	"wheat": {"visibility": 110.0, "active": 45.0},
	"sunflower": {"visibility": 130.0, "active": 45.0},
}

## Talhoes do mapa: retangulo em planta e o passo da grade dentro dele. O passo
## e maior que a cena de proposito -- a faixa que sobra entre uma instancia e a
## seguinte e o sulco por onde se anda dentro da plantacao.
const FIELDS: Array[Dictionary] = Layout.CROP_FIELDS

## Sulcos de terra sob o milharal: o modelo mede 5 x 5 m e nasce no canto.
const DIRT_ROWS_TILE: float = 5.0

const DISTRICT_SCENES: Array[String] = [
	"res://scenes/CountryTown/Districts/FarmDistrict.tscn",
	"res://scenes/CountryTown/Districts/TownDistrict.tscn",
	"res://scenes/CountryTown/Districts/DeliveryYard.tscn",
]

## Folga minima de cada planta ate a faixa de rolamento, o eixo do rio e a
## colisao de um predio.
const ROAD_CLEARANCE: float = 6.0
const RIVER_CLEARANCE: float = 12.0
const BUILDING_CLEARANCE: float = 1.5

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _blockers: Array[Rect2] = []
var _road_segments: Array[Dictionary] = []


func _process(_delta: float) -> bool:
	_rng.seed = 20260906
	var ok: bool = _build()
	quit(0 if ok else 1)
	return true


func _build() -> bool:
	var terrain: Terrain3D = Terrain3D.new()
	root.add_child(terrain)
	terrain.data_directory = TERRAIN_DIR
	var data: Terrain3DData = terrain.data
	if data == null or data.get_region_count() == 0:
		push_error("Terreno ausente em %s -- rode tools/build_country_town_terrain.gd" % TERRAIN_DIR)
		return false

	_road_segments = Layout.road_segments()
	_blockers = Vegetation.district_blockers(DISTRICT_SCENES, root)
	print("Colisoes evitadas: %d" % _blockers.size())

	var fields: Node3D = Node3D.new()
	fields.name = "Fields"
	var rows_rects: Array[Rect2] = []
	var total: int = 0

	for field: Dictionary in FIELDS:
		var scene: PackedScene = load(CROP_SCENES[field["kind"]]) as PackedScene
		if scene == null:
			push_error("Nao carregou %s" % CROP_SCENES[field["kind"]])
			return false
		var group: Node3D = Node3D.new()
		group.name = field["name"]
		fields.add_child(group)
		group.owner = fields

		var rect: Rect2 = field["rect"]
		var step: Vector2 = field["step"]
		var ranges: Dictionary = CROP_RANGES[field["kind"]]
		var planted: int = 0
		var z: float = rect.position.y + step.y * 0.5
		while z <= rect.end.y:
			var x: float = rect.position.x + step.x * 0.5
			while x <= rect.end.x:
				var point: Vector2 = Vector2(x, z)
				if _is_free(point, field):
					var plant: Node3D = scene.instantiate() as Node3D
					plant.name = "%s%03d" % [String(field["kind"]).capitalize(), planted]
					group.add_child(plant)
					plant.owner = fields
					var height: float = data.get_height(Vector3(point.x, 0.0, point.y))
					if is_nan(height):
						height = Layout.GROUND_HEIGHT
					# Girassol e canteiro: gira solto. Milho e trigo sao
					# plantados em fileira, e fileira torta nao parece lavoura.
					var angle: float = 0.0
					if field["kind"] == "sunflower":
						angle = _rng.randf_range(0.0, TAU)
					elif field["kind"] == "wheat":
						angle = float(_rng.randi_range(0, 3)) * PI * 0.5
					plant.transform = Transform3D(Basis(Vector3.UP, angle),
							Vector3(point.x, height, point.y))
					plant.set("visibility_range", ranges["visibility"])
					plant.set("active_radius", ranges["active"])
					planted += 1
				x += step.x
			z += step.y
		if field.get("rows", false):
			rows_rects.append(rect)
		total += planted
		print("%s: %d instancias de %s" % [field["name"], planted, field["kind"]])
		_build_far_field(fields, field, data)

	if not _build_dirt_rows(fields, rows_rects, data):
		return false

	var packed: PackedScene = PackedScene.new()
	if packed.pack(fields) != OK:
		push_error("Nao empacotou %s" % FIELDS_SCENE_PATH)
		return false
	if ResourceSaver.save(packed, FIELDS_SCENE_PATH) != OK:
		push_error("Nao gravou %s" % FIELDS_SCENE_PATH)
		return false
	print("Plantacoes: %d instancias em %s" % [total, FIELDS_SCENE_PATH])
	fields.free()
	return true


## Sulcos sob os talhoes que pedem chao de terra, num `MultiMesh` so.
func _build_dirt_rows(fields: Node3D, rects: Array[Rect2], data: Terrain3DData) -> bool:
	if rects.is_empty():
		return true
	var mesh: Mesh = load(DIRT_ROWS_MESH) as Mesh
	var material: Material = load(DIRT_ROWS_MATERIAL) as Material
	if mesh == null or material == null:
		push_error("Nao carregou o modelo ou o material dos sulcos")
		return false

	var transforms: Array[Transform3D] = []
	for rect: Rect2 in rects:
		var z: float = rect.position.y
		while z < rect.end.y:
			var x: float = rect.position.x
			while x < rect.end.x:
				var center: Vector2 = Vector2(x + DIRT_ROWS_TILE * 0.5, z + DIRT_ROWS_TILE * 0.5)
				if x + DIRT_ROWS_TILE <= rect.end.x and z + DIRT_ROWS_TILE <= rect.end.y and _is_free(center):
					var height: float = data.get_height(Vector3(center.x, 0, center.y))
					transforms.append(Transform3D(Basis(), Vector3(x, height + 0.05, z)))
				x += DIRT_ROWS_TILE
			z += DIRT_ROWS_TILE

	var multi_mesh: MultiMesh = MultiMesh.new()
	multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
	multi_mesh.mesh = mesh
	multi_mesh.instance_count = transforms.size()
	for index: int in transforms.size():
		multi_mesh.set_instance_transform(index, transforms[index])
	if multi_mesh.buffer.is_empty():
		push_error("MultiMesh dos sulcos voltou sem buffer: rode este script SEM --headless")
		return false

	var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
	node.name = "DirtRows"
	node.multimesh = multi_mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fields.add_child(node)
	node.owner = fields
	print("DirtRows: %d sulcos" % transforms.size())
	return true


## Silhueta distante em blocos de 20m: hastes de oito triangulos, sem Area3D
## ou processo. As plantas reativas continuam sendo usadas de perto.
func _build_far_field(fields: Node3D, field: Dictionary, data: Terrain3DData) -> void:
	var kind: String = field["kind"]
	var tall: float = 2.0 if kind == "corn" else (1.1 if kind == "sunflower" else 0.8)
	var prism: PrismMesh = PrismMesh.new()
	prism.size = Vector3(0.7, tall, 0.7)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.39, 0.40, 0.12) if kind == "corn" else Color(0.58, 0.45, 0.16)
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	var rect: Rect2 = field["rect"]
	for ix: int in ceili(rect.size.x / 20.0):
		for iz: int in ceili(rect.size.y / 20.0):
			var origin: Vector2 = rect.position + Vector2(ix, iz) * 20.0
			var end: Vector2 = Vector2(minf(origin.x + 20, rect.end.x), minf(origin.y + 20, rect.end.y))
			var center: Vector2 = (origin + end) * 0.5
			var transforms: Array[Transform3D] = []
			var point: Vector2 = origin + Vector2(0.8, 0.8)
			while point.y < end.y:
				point.x = origin.x + 0.8
				while point.x < end.x:
					if _is_free(point, field):
						var height: float = data.get_height(Vector3(point.x, 0, point.y))
						var scale_y: float = 0.85 + 0.15 * sin(point.x * 2.7 + point.y)
						transforms.append(Transform3D(Basis().scaled(Vector3(1, scale_y, 1)), Vector3(point.x - center.x, height + tall * scale_y * 0.5, point.y - center.y)))
					point.x += 1.25
				point.y += 1.8
			if transforms.is_empty():
				continue
			var multi: MultiMesh = MultiMesh.new()
			multi.transform_format = MultiMesh.TRANSFORM_3D
			multi.mesh = prism
			multi.instance_count = transforms.size()
			for index: int in transforms.size():
				multi.set_instance_transform(index, transforms[index])
			var proxy: MultiMeshInstance3D = MultiMeshInstance3D.new()
			proxy.name = "%sDistant_%d_%d" % [field["name"], ix, iz]
			proxy.position = Vector3(center.x, 0, center.y)
			proxy.multimesh = multi
			proxy.material_override = material
			proxy.layers = 2
			proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			proxy.visibility_range_begin = float(CROP_RANGES[kind]["visibility"]) - 25.0
			proxy.visibility_range_begin_margin = 15.0
			proxy.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			fields.add_child(proxy)
			proxy.owner = fields


func _is_free(point: Vector2, field: Dictionary = {}) -> bool:
	if field.get("maze", false) and Layout.CORN_MAZE_RECT.has_point(point):
		var cell_x: int = clampi(int((point.x - Layout.CORN_MAZE_RECT.position.x) / (Layout.CORN_MAZE_RECT.size.x / Layout.CORN_MAZE[0].length())), 0, Layout.CORN_MAZE[0].length() - 1)
		var cell_z: int = clampi(int((point.y - Layout.CORN_MAZE_RECT.position.y) / (Layout.CORN_MAZE_RECT.size.y / Layout.CORN_MAZE.size())), 0, Layout.CORN_MAZE.size() - 1)
		if Layout.CORN_MAZE[cell_z].substr(cell_x, 1) == ".":
			return false
	if Layout.on_secondary_path(point, 2.0):
		return false
	for clearing: Rect2 in Layout.SETTLEMENT_CLEARINGS:
		if clearing.has_point(point):
			return false
	for segment: Dictionary in _road_segments:
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(
				point, segment["start"], segment["end"])
		if point.distance_to(closest) < ROAD_CLEARANCE:
			return false
	for i: int in Layout.RIVER_PATH.size() - 1:
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(
				point, Layout.RIVER_PATH[i], Layout.RIVER_PATH[i + 1])
		if point.distance_to(closest) < RIVER_CLEARANCE:
			return false
	for rect: Rect2 in _blockers:
		if rect.grow(BUILDING_CLEARANCE).has_point(point):
			return false
	return true
