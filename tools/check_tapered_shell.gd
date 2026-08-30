@tool
extends SceneTree

## Caca frestas no casco interno da nave.
##
## Monta `SpaceShipInterior.tscn` sozinho contra um fundo magenta, deixa o
## `TaperedShell` deformar as malhas, torna os vidros opacos e fotografa o
## interior de varios pontos. Depois do vidro opaco NENHUM pixel magenta e
## legitimo: cada um deles e um vao por onde o espaco (e a Terra) aparece de
## dentro da nave -- foi assim que a fresta na base da parede de fundo apareceu.
##
## Cada pixel magenta e desprojetado de volta para o mundo, entao o relatorio diz
## em QUE PAREDE e em QUE ALTURA esta o vao, em texto. Nao abra os PNGs para
## descobrir isso: eles sao so um recurso final de inspecao visual.
##
## Uso (precisa de GPU: nao passe --headless, o driver dummy nao desenha nada):
##
##     godot --path . --script tools/check_tapered_shell.gd --resolution 1280x720
##
## As fotos das vistas com vazamento vao para `SHELL_LEAK_DIR` (padrao
## `user://shell_leaks`). Sai com codigo 1 se achar qualquer fresta.

const INTERIOR_SCENE: String = "res://scenes/SpaceshipInterior/SpaceShipInterior.tscn"

## Fundo de teste. Saturado nos dois extremos para nao se confundir com nada
## que o interior possa desenhar.
const LEAK_COLOR: Color = Color(1.0, 0.0, 1.0)

## Alturas de camera, em unidades locais do interior. O casco e piramidal, entao
## o raio util encolhe conforme se sobe -- ver `TaperedShell`.
const CAMERA_HEIGHTS: Array[float] = [0.35, 0.8, 1.3]

## Fracao do inraio local em que a camera fica. Perto o bastante da parede para
## uma fresta de milimetros ocupar mais de um pixel.
const CAMERA_RADIUS_RATIO: float = 0.6

## Normais externas das tres paredes, em 0/120/240 graus, na mesma ordem da
## planta triangular de `TriangularDeck`.
const WALL_NORMALS: Array[Vector3] = [
	Vector3(0.0, 0.0, 1.0),
	Vector3(0.8660254, 0.0, -0.5),
	Vector3(-0.8660254, 0.0, -0.5),
]

const WALL_NAMES: Array[String] = [
	"parede de fundo (sem janela)",
	"parede direita (janela)",
	"parede esquerda (janela)",
]

## Teto de pixels localizados por vista. Uma fresta larga nao precisa ser medida
## pixel a pixel para dizer onde fica; o limite so evita gastar minutos
## desprojetando dezenas de milhares de pontos praticamente iguais.
const LOCATED_PER_VIEW: int = 2000

const INRADIUS: float = 4.7

var _output_dir: String = ""
var _shots: Array = []
var _frames: int = 0
var _leaking: int = 0
var _walls: Dictionary = {}


func _initialize() -> void:
	_output_dir = OS.get_environment("SHELL_LEAK_DIR")
	if _output_dir.is_empty():
		_output_dir = "user://shell_leaks"
	DirAccess.make_dir_recursive_absolute(_output_dir)

	var interior: Node3D = (load(INTERIOR_SCENE) as PackedScene).instantiate()
	root.add_child(interior)
	var shell: TaperedShell = interior.get_node("Shell") as TaperedShell
	set_meta("shell", shell)
	_make_glass_opaque(shell)

	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = LEAK_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.6, 0.7, 0.8)
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world_environment: WorldEnvironment = WorldEnvironment.new()
	world_environment.environment = environment
	root.add_child(world_environment)

	var camera: Camera3D = Camera3D.new()
	camera.fov = 75.0
	camera.near = 0.02
	root.add_child(camera)
	set_meta("camera", camera)

	_build_shots()


## Um vidro transparente deixaria o fundo passar de forma legitima e afogaria o
## sinal. Opaco, todo magenta que sobrar e fresta.
func _make_glass_opaque(node: Node) -> void:
	var mesh_instance: MeshInstance3D = node as MeshInstance3D
	if mesh_instance != null:
		var opaque: StandardMaterial3D = StandardMaterial3D.new()
		opaque.albedo_color = Color(0.2, 0.25, 0.3)
		mesh_instance.material_override = opaque
	for child: Node in node.get_children():
		_make_glass_opaque(child)


func _build_shots() -> void:
	var shell: TaperedShell = get_meta("shell")
	# Doze azimutes cobrem as tres paredes, os tres cantos e os meios de cada
	# metade -- o passo mais grosso ja deixou passar a fresta da parede de fundo.
	for azimuth_index: int in range(12):
		var azimuth: float = TAU * azimuth_index / 12.0
		var outward: Vector3 = Vector3(sin(azimuth), 0.0, cos(azimuth))
		for height: float in CAMERA_HEIGHTS:
			var local_inradius: float = INRADIUS * shell.radial_scale(height)
			var origin: Vector3 = outward * (-local_inradius * CAMERA_RADIUS_RATIO)
			origin.y = height
			for target_height: float in [0.0, shell.height]:
				_shots.append([
					"az%02d_h%.2f_t%.2f" % [azimuth_index, height, target_height],
					origin,
					outward * INRADIUS * shell.radial_scale(target_height)
						+ Vector3.UP * target_height,
				])


func _process(_delta: float) -> bool:
	_frames += 1
	# Uma passada para posicionar a camera, a seguinte para ler o quadro ja
	# desenhado com ela: `get_image()` sempre devolve o ultimo frame.
	if _frames < 3:
		return false

	var step: int = _frames - 3
	var pending: int = step / 2
	if step % 2 == 1:
		if pending < _shots.size():
			var camera: Camera3D = get_meta("camera")
			camera.global_position = _shots[pending][1]
			camera.look_at(_shots[pending][2], Vector3.UP)
		return false

	var previous: int = pending - 1
	if previous >= 0 and previous < _shots.size():
		_inspect(_shots[previous][0], root.get_texture().get_image())
	if pending < _shots.size():
		return false

	return _report()


func _report() -> bool:
	if _leaking == 0:
		print("casco estanque: nenhuma fresta em %d vistas" % _shots.size())
		return true

	print("%d de %d vistas vazam:" % [_leaking, _shots.size()])
	var walls: Array = _walls.keys()
	walls.sort()
	for wall: int in walls:
		var entry: Dictionary = _walls[wall]
		print("  %s: y de %+.2f a %+.2f (%d pontos, ex. vista %s)" % [
			WALL_NAMES[wall],
			entry["min"],
			entry["max"],
			entry["count"],
			entry["view"],
		])
	print("fotos das vistas que vazam em %s" % _output_dir)
	quit(1)
	return true


func _inspect(shot_name: String, image: Image) -> void:
	var camera: Camera3D = get_meta("camera")
	var leaked: int = 0
	var located: int = 0
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var pixel: Color = image.get_pixel(x, y)
			if pixel.r < 0.5 or pixel.g > 0.25 or pixel.b < 0.5:
				continue
			leaked += 1
			if located >= LOCATED_PER_VIEW:
				continue
			located += 1
			var spot: Variant = _locate(
				camera.global_position,
				camera.project_ray_normal(Vector2(x, y))
			)
			if spot != null:
				_record(spot[0], spot[1], shot_name)

	if leaked == 0:
		return
	_leaking += 1
	image.save_png("%s/%s.png" % [_output_dir, shot_name])


## Onde o raio que escapou cruza o cone do casco -- ou seja, por onde ele saiu.
## Devolve `[indice da parede, altura]`, ou null se o raio nunca cruza o cone
## (aponta para longe do casco e nao diz nada sobre a fresta).
func _locate(origin: Vector3, direction: Vector3) -> Variant:
	var shell: TaperedShell = get_meta("shell")
	var gradient: float = (shell.top_radius_ratio - 1.0) / shell.height

	var best_distance: float = INF
	var best_height: float = 0.0
	var best_wall: int = -1
	for index: int in range(WALL_NORMALS.size()):
		var normal: Vector3 = WALL_NORMALS[index]
		# dot(p, n) = INRADIUS * radial_scale(p.y) e linear nos dois lados,
		# entao o cruzamento sai direto, sem iterar.
		var denominator: float = (
			direction.dot(normal) - INRADIUS * gradient * direction.y
		)
		if absf(denominator) < 0.00001:
			continue
		var distance: float = (
			INRADIUS * (1.0 + gradient * origin.y) - origin.dot(normal)
		) / denominator
		if distance <= 0.0 or distance >= best_distance:
			continue

		# So conta se o ponto cai mesmo nesta face, e nao na prolongacao dela
		# para fora do triangulo.
		var point: Vector3 = origin + direction * distance
		var on_face: bool = true
		for other: Vector3 in WALL_NORMALS:
			if other != normal and point.dot(other) > point.dot(normal) + 0.0001:
				on_face = false
				break
		if not on_face:
			continue

		best_distance = distance
		best_height = point.y
		best_wall = index

	if best_wall < 0:
		return null
	return [best_wall, best_height]


func _record(wall: int, height: float, shot_name: String) -> void:
	var entry: Dictionary = _walls.get(wall, {
		"count": 0,
		"min": INF,
		"max": -INF,
		"view": shot_name,
	})
	entry["count"] = int(entry["count"]) + 1
	entry["min"] = minf(entry["min"], height)
	entry["max"] = maxf(entry["max"], height)
	_walls[wall] = entry
