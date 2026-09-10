@tool
extends SceneTree

## Fotografa as janelas do bairro do Country Town para inspecao visual.
##
## Nao e uma validacao: quem decide se ficou bom e quem olha. A checagem de
## escala e acesso e `tools/check_country_town_neighborhood.gd`. Aqui a camera
## se planta no portao de cada lote, na altura dos olhos, e mira a fachada na
## altura do peitoril -- o angulo em que se ve o comodo atras do vidro.
##
## Precisa de rasterizacao real, entao roda SEM `--headless`:
##
##     .\tools\godot.cmd --path . --script res://tools/shoot_country_town_windows.gd --resolution 1280x720
##
## `HOUSE_SHOT_DIR` troca a pasta de saida.

const SCENE: String = "res://scenes/CountryTown/CountryTown.tscn"
const TOWN: String = "TownDistrict/UrbanInfill"

## Lotes fotografados: casca do kit com vitrine e casa modular em que se entra.
const LOTS: Array[String] = [
	"Casa101", "Casa103", "Casa105", "Casa102", "Casa106", "Casa301",
	"Casa204", "Casa208", "Casa210", "Casa203",
]
## Comercios, vistos da calcada em frente.
const SHOPS: Array[Dictionary] = [
	{"node": "Padaria", "from": Vector2(0.0, 9.0)},
	{"node": "Mercearia", "from": Vector2(0.0, -9.0)},
	{"node": "Cafe", "from": Vector2(0.0, -9.0)},
]

## Altura dos olhos e altura do peitoril do kit.
const EYE: float = 1.7
const SILL: float = 2.4
## De quao longe a janela e fotografada, e o campo que mostra o vao inteiro sem
## virar foto de parede.
const STANDOFF: float = 4.5
const WINDOW_FOV: float = 38.0

## Quadros gastos antes da primeira foto e entre uma foto e a seguinte: o
## terreno e o LOD precisam assentar antes de virar imagem.
const WARMUP_FRAMES: int = 90
const SETTLE_FRAMES: int = 12

var _camera: Camera3D
var _shots: Array[Dictionary] = []
var _frame: int = 0
var _shot: int = 0
var _out: String = ""


func _init() -> void:
	_out = OS.get_environment("HOUSE_SHOT_DIR")
	if _out.is_empty():
		_out = "user://house_shots"
	DirAccess.make_dir_recursive_absolute(_out)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		var packed: PackedScene = load(SCENE) as PackedScene
		if packed == null:
			printerr("Nao carregou %s" % SCENE)
			quit(1)
			return true
		var world: Node = packed.instantiate()
		root.add_child(world)
		_collect(world)
		if _shots.is_empty():
			printerr("Nenhum lote encontrado em %s" % TOWN)
			quit(1)
			return true
		_daylight(root)
		_camera = Camera3D.new()
		_camera.far = 900.0
		_camera.fov = WINDOW_FOV
		root.add_child(_camera)
		_camera.make_current()
		_aim()
		return false
	if _frame < WARMUP_FRAMES:
		return false
	if (_frame - WARMUP_FRAMES) % SETTLE_FRAMES != 0:
		return false
	var image: Image = root.get_texture().get_image()
	var path: String = "%s/%02d-%s.png" % [_out, _shot + 1, _shots[_shot]["name"]]
	if image == null or image.save_png(path) != OK:
		printerr("Nao gravou %s" % path)
		quit(1)
		return true
	print("Foto: %s" % path)
	_shot += 1
	if _shot >= _shots.size():
		quit(0)
		return true
	_aim()
	return false


## Cada lote ja carrega os marcadores de acesso: o portao diz de onde se olha a
## casa, e a entrada diz para onde.
func _collect(world: Node) -> void:
	var town: Node3D = world.get_node_or_null(TOWN) as Node3D
	if town == null:
		return
	for name: String in LOTS:
		var lot: Node3D = town.get_node_or_null(name) as Node3D
		var gate: Marker3D = null if lot == null else lot.get_node_or_null("PedestrianGate") as Marker3D
		var entrance: Marker3D = null if lot == null else lot.get_node_or_null("Entrance") as Marker3D
		if gate == null or entrance == null:
			printerr("Lote sem marcadores: %s" % name)
			continue
		var at: Vector3 = _window_point(lot, gate.global_position)
		if at == Vector3.ZERO:
			at = entrance.global_position + Vector3(0.0, SILL, 0.0)
		var away: Vector3 = gate.global_position - at
		away.y = 0.0
		if away.length() < 0.5:
			away = Vector3.FORWARD
		_shots.append({
			"name": name.to_lower(),
			"from": at + away.normalized() * STANDOFF,
			"at": at,
		})
	for shop: Dictionary in SHOPS:
		var node: Node3D = town.get_node_or_null(shop["node"] as String) as Node3D
		if node == null:
			printerr("Comercio ausente: %s" % shop["node"])
			continue
		var offset: Vector2 = shop["from"]
		var middle: Vector3 = node.global_position
		var at: Vector3 = _window_point(node, middle + Vector3(offset.x, EYE, offset.y))
		if at == Vector3.ZERO:
			at = middle + Vector3(0.0, SILL, 0.0)
		# A vitrine de loja olha para a calcada: a camera se afasta pelo lado de
		# fora, medido do centro do predio para o vao.
		var away: Vector3 = at - middle
		away.y = 0.0
		if away.length() < 0.5:
			away = Vector3(offset.x, 0.0, offset.y)
		_shots.append({
			"name": (shop["node"] as String).to_lower(),
			"from": at + away.normalized() * STANDOFF,
			"at": at,
		})


func _aim() -> void:
	_camera.position = _shots[_shot]["from"]
	_camera.look_at(_shots[_shot]["at"], Vector3.UP)


## Janela mais proxima do portao: a vitrine dos presets e uma malha so, e a
## casa modular traz um caixilho por vao.
func _window_point(lot: Node3D, gate: Vector3) -> Vector3:
	var best: Vector3 = Vector3.ZERO
	var nearest: float = INF
	var showcase: MeshInstance3D = null
	for node: Node in lot.find_children("Vitrine", "MeshInstance3D", true, false):
		showcase = node as MeshInstance3D
		break
	if showcase != null and showcase.mesh != null:
		# So a faixa do peitoril: o comodo tem piso e teto, e mirar no piso vira
		# foto de calcada.
		var low: float = lot.global_position.y + SILL - 0.9
		var high: float = lot.global_position.y + SILL + 0.9
		for point: Vector3 in showcase.mesh.get_faces():
			var world: Vector3 = showcase.global_transform * point
			if world.y < low or world.y > high:
				continue
			var distance: float = world.distance_to(gate)
			if distance < nearest:
				nearest = distance
				best = world
		return best
	for node: Node in lot.find_children("Caixilho*", "MeshInstance3D", true, false):
		var frame: MeshInstance3D = node as MeshInstance3D
		if frame.mesh == null:
			continue
		var center: Vector3 = frame.global_transform * frame.mesh.get_aabb().get_center()
		var distance: float = center.distance_to(gate)
		if distance < nearest:
			nearest = distance
			best = center
	return best


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
