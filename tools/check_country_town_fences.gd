@tool
extends SceneTree

## Confere se as cercas do Country Town fecham.
##
## Cada modulo reto de cerca vira um segmento em planta e cada poste, um ponto.
## Uma ponta de segmento esta certa quando encosta na ponta de outro modulo,
## quando cai em cima de um poste, ou quando existe outra ponta solta na mesma
## reta a distancia de uma entrada -- o vao de portao e de proposito.
##
## Ponta solta sem nada disso e falha: e o canto que nao fecha, a tabua que
## termina no ar. O relatorio sai em coordenada de mundo, para achar no editor.
##
## Uso:
##
##     .\tools\godot.cmd --headless --path . --script res://tools/check_country_town_fences.gd

const SCENE: String = "res://scenes/CountryTown/CountryTown.tscn"

## Peca mais curta que isto em planta e poste, nao lance de cerca.
const POST_LENGTH: float = 0.8
## Ate onde duas pontas contam como emendadas.
const JOINT_TOLERANCE: float = 0.4
## Ate onde um poste remata a ponta de um lance.
const POST_TOLERANCE: float = 0.8
## Vao aceito como entrada, e o quanto a ponta oposta pode sair da reta.
const GATE_MIN: float = 1.2
const GATE_MAX: float = 9.0
const GATE_DRIFT: float = 0.6

var _ends: Array[Dictionary] = []
var _posts: Array[Vector2] = []


func _process(_delta: float) -> bool:
	var packed: PackedScene = load(SCENE) as PackedScene
	if packed == null:
		printerr("Nao carregou %s" % SCENE)
		quit(1)
		return true
	var world: Node = packed.instantiate()
	root.add_child(world)
	_collect(world, Transform3D.IDENTITY)
	print("Cercas conferidas: %d lances, %d postes" % [_ends.size() / 2, _posts.size()])
	if _ends.is_empty():
		printerr("Nenhuma cerca encontrada em %s" % SCENE)
		quit(1)
		return true

	var loose: Array[Dictionary] = []
	for entry: Dictionary in _ends:
		if not _joined(entry):
			loose.append(entry)
	var gates: int = 0
	var broken: Array[Dictionary] = []
	for entry: Dictionary in loose:
		if _facing_gap(entry, loose):
			gates += 1
		else:
			broken.append(entry)
	print("Entradas reconhecidas: %d" % (gates / 2))
	if broken.is_empty():
		print("Cercas do Country Town fechadas.")
		quit(0)
		return true
	printerr("Pontas soltas de cerca: %d" % broken.size())
	for index: int in mini(broken.size(), 40):
		var entry: Dictionary = broken[index]
		var point: Vector2 = entry["point"]
		printerr("  - %s em (%.1f, %.1f)" % [entry["path"], point.x, point.y])
	if broken.size() > 40:
		printerr("  ... e mais %d" % (broken.size() - 40))
	quit(1)
	return true


func _collect(node: Node, parent: Transform3D) -> void:
	var here: Transform3D = parent
	if node is Node3D:
		here = parent * (node as Node3D).transform
	if node is MeshInstance3D:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh != null and mesh.resource_path.contains("Fence"):
			_register(node.get_path(), mesh.get_aabb(), here)
	for child: Node in node.get_children():
		_collect(child, here)


## Um modulo de cerca e uma barra: o eixo horizontal mais longo do AABB e o
## comprimento, e as duas pontas ficam no meio da espessura.
func _register(path: NodePath, bounds: AABB, world: Transform3D) -> void:
	var along_x: bool = bounds.size.x >= bounds.size.z
	var length: float = bounds.size.x if along_x else bounds.size.z
	var center: Vector3 = bounds.get_center()
	if length < POST_LENGTH:
		_posts.append(_flat(world * center))
		return
	var reach: Vector3 = Vector3(length * 0.5, 0.0, 0.0) if along_x else Vector3(0.0, 0.0, length * 0.5)
	var first: Vector2 = _flat(world * (center - reach))
	var last: Vector2 = _flat(world * (center + reach))
	var axis: Vector2 = (last - first).normalized()
	_ends.append({"path": String(path), "point": first, "axis": -axis})
	_ends.append({"path": String(path), "point": last, "axis": axis})


func _flat(point: Vector3) -> Vector2:
	return Vector2(point.x, point.z)


func _joined(entry: Dictionary) -> bool:
	var point: Vector2 = entry["point"]
	for post: Vector2 in _posts:
		if post.distance_to(point) < POST_TOLERANCE:
			return true
	for other: Dictionary in _ends:
		if other["path"] == entry["path"]:
			continue
		if (other["point"] as Vector2).distance_to(point) < JOINT_TOLERANCE:
			return true
	return false


## Entrada: a ponta oposta do vao esta na mesma reta, virada para ca.
func _facing_gap(entry: Dictionary, loose: Array[Dictionary]) -> bool:
	var point: Vector2 = entry["point"]
	var axis: Vector2 = entry["axis"]
	for other: Dictionary in loose:
		if other["path"] == entry["path"]:
			continue
		var delta: Vector2 = (other["point"] as Vector2) - point
		var along: float = delta.dot(axis)
		if along < GATE_MIN or along > GATE_MAX:
			continue
		if absf(delta.dot(Vector2(-axis.y, axis.x))) > GATE_DRIFT:
			continue
		if (other["axis"] as Vector2).dot(axis) > -0.9:
			continue
		return true
	return false
