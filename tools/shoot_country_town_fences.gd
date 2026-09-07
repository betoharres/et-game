@tool
extends SceneTree

## Fotografa os cantos de cerca do Country Town para inspecao visual.
##
## Nao e uma validacao: quem decide se ficou bom e quem olha. A checagem de
## verdade e `tools/check_country_town_fences.gd`. Este script so enquadra os
## pontos que costumam quebrar -- canto de talhao, portao, curral, cerca de
## arame -- e grava um PNG de cada um.
##
## Precisa de rasterizacao real, entao roda SEM `--headless`:
##
##     .\tools\godot.cmd --path . --script res://tools/shoot_country_town_fences.gd --resolution 1280x720

const SCENE: String = "res://scenes/CountryTown/CountryTown.tscn"

## Alvo em planta, de onde olhar (offset em planta) e o nome do arquivo.
const SHOTS: Array[Dictionary] = [
	{"at": Vector2(172.0, 176.5), "from": Vector2(-9.0, -9.0), "name": "curral-canto-noroeste"},
	{"at": Vector2(192.0, 191.5), "from": Vector2(9.0, 9.0), "name": "curral-canto-sudeste"},
	{"at": Vector2(80.8, 28.8), "from": Vector2(-8.0, -8.0), "name": "trigo-norte-canto-noroeste"},
	{"at": Vector2(136.2, 80.2), "from": Vector2(8.0, 8.0), "name": "trigo-norte-canto-sudeste"},
	{"at": Vector2(293.2, 22.8), "from": Vector2(9.0, -9.0), "name": "milharal-canto-nordeste"},
	{"at": Vector2(246.0, 106.8), "from": Vector2(0.0, -9.0), "name": "pasto-portao-norte"},
	{"at": Vector2(185.0, 62.0), "from": Vector2(-8.0, -8.0), "name": "arame-canto-noroeste"},
	{"at": Vector2(433.0, 190.0), "from": Vector2(0.0, -8.0), "name": "cerca-branca-quintal"},
	{"at": Vector2(329.0, 400.0), "from": Vector2(-9.0, 9.0), "name": "deposito-canto-sudoeste"},
	{"at": Vector2(115.0, 137.0), "from": Vector2(-7.0, 7.0), "name": "patio-fundo-cercado"},
]

## Quadros gastos antes da primeira foto e entre uma foto e a seguinte: o
## terreno e o LOD precisam assentar antes de virar imagem.
const WARMUP_FRAMES: int = 90
const SETTLE_FRAMES: int = 12

var _camera: Camera3D
var _terrain: Terrain3D
var _frame: int = 0
var _shot: int = 0
var _out: String = ""


func _init() -> void:
	_out = OS.get_environment("FENCE_SHOT_DIR")
	if _out.is_empty():
		_out = "user://fence_shots"
	DirAccess.make_dir_recursive_absolute(_out)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		var packed: PackedScene = load(SCENE) as PackedScene
		if packed == null:
			printerr("Nao carregou %s" % SCENE)
			quit(1)
			return true
		root.add_child(packed.instantiate())
		_terrain = _find_terrain(root)
		_daylight(root)
		_camera = Camera3D.new()
		_camera.far = 900.0
		_camera.fov = 60.0
		root.add_child(_camera)
		_camera.make_current()
		_aim()
		return false
	if _frame < WARMUP_FRAMES:
		return false
	if (_frame - WARMUP_FRAMES) % SETTLE_FRAMES != 0:
		return false
	var image: Image = root.get_texture().get_image()
	var path: String = "%s/%02d-%s.png" % [_out, _shot + 1, SHOTS[_shot]["name"]]
	if image == null or image.save_png(path) != OK:
		printerr("Nao gravou %s" % path)
		quit(1)
		return true
	print("Foto: %s" % path)
	_shot += 1
	if _shot >= SHOTS.size():
		quit(0)
		return true
	_aim()
	return false


func _aim() -> void:
	var shot: Dictionary = SHOTS[_shot]
	var at: Vector2 = shot["at"]
	var from: Vector2 = at + (shot["from"] as Vector2)
	var ground: float = _height(at)
	_camera.position = Vector3(from.x, _height(from) + 3.2, from.y)
	_camera.look_at(Vector3(at.x, ground + 0.7, at.y), Vector3.UP)


## O Country Town e noturno por design. Para conferir geometria a olho, a foto
## precisa de sol: o ambiente vira luz difusa e entra uma direcional.
func _daylight(node: Node) -> void:
	if node is WorldEnvironment:
		var environment: Environment = (node as WorldEnvironment).environment
		if environment != null:
			environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			environment.ambient_light_color = Color(0.78, 0.82, 0.9)
			environment.ambient_light_energy = 1.0
			environment.fog_enabled = false
			environment.volumetric_fog_enabled = false
			environment.adjustment_enabled = false
	for child: Node in node.get_children():
		_daylight(child)
	if node != root:
		return
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	root.add_child(sun)


func _height(point: Vector2) -> float:
	if _terrain == null:
		return 6.0
	var height: float = _terrain.data.get_height(Vector3(point.x, 0.0, point.y))
	return 6.0 if is_nan(height) else height


func _find_terrain(node: Node) -> Terrain3D:
	if node is Terrain3D:
		return node as Terrain3D
	for child: Node in node.get_children():
		var found: Terrain3D = _find_terrain(child)
		if found != null:
			return found
	return null
