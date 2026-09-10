extends SceneTree

## Monta a casa modular House01 com o kit do PolygonTown e a cena de teste que
## a exercita com o Player e uma moradora.
##
## O kit trabalha num grid de 2,5 m: parede de 2,5 x 2,9 (com 1,04 de base
## enterrada), piso e teto de 2,5 x 2,5, e as águas do telhado sobem 1,75 sobre
## um vão de 3,18 -- por isso a casa tem 5 m de largura, a medida em que o
## telhado de duas águas fecha sem peça cortada.
##
##     .\tools\godot.cmd --headless --path . --script res://tools/build_house_01.gd

const BLD: String = "res://PolygonTown/Prefabs/Buildings/%s.tscn"
const PROP: String = "res://PolygonTown/Prefabs/Props/%s.tscn"
const EXTRACTED: String = "res://PolygonTown/Models/Buildings/extracted/%s.res"
const TOWN_MAT: String = "res://PolygonTown/Materials/PolygonTown_01_A_mat.tres"
const DOOR_SCRIPT: String = "res://scripts/house_door.gd"
const LIGHTS_SCRIPT: String = "res://scripts/house_lights.gd"
const ACTIVITY_SCRIPT: Script = preload("res://scripts/npc/npc_activity.gd")
const ROUTINE_SCRIPT: Script = preload("res://scripts/npc/npc_routine.gd")
const DOOR_PATH: String = "res://scenes/Buildings/HouseDoor.tscn"
const INNER_DOOR_PATH: String = "res://scenes/Buildings/HouseDoorInner.tscn"
const HOUSE_PATH: String = "res://scenes/Buildings/House01.tscn"
const TEST_PATH: String = "res://scenes/Buildings/HouseTest.tscn"
const NAV_PATH: String = "res://scenes/Buildings/HouseTestNavigation.res"

## Grid do kit e planta interna: x de 0 a 5, z de 0 a 10, fachada no z maior.
const M: float = 2.5
const W: float = 5.0
const L: float = 10.0
## Piso interno em y = 0; o gramado encosta na base aparente da casa.
const GROUND_Y: float = -0.4

## Porta de entrada, lida do prefab SM_Bld_House_Door_01.
const FRAME_BOXES: Array[Dictionary] = [
	{"size": Vector3(1.286377, 0.1508789, 0.35180664), "at": Vector3(1.2713623, -0.0690918, 0.15490723)},
	{"size": Vector3(0.1083374, 2.2298584, 0.30969238), "at": Vector3(1.832428, 1.116394, 0.13140869)},
	{"size": Vector3(1.2426147, 0.08531952, 0.30786133), "at": Vector3(1.2711487, 2.2683601, 0.13098145)},
	{"size": Vector3(0.11968994, 2.2456055, 0.30218506), "at": Vector3(0.6980896, 1.119873, 0.13394165)},
]
const LEAF_OFFSET: Vector3 = Vector3(0.74945384, 0.01190729, 0.08475586)
const LEAF_BOX_SIZE: Vector3 = Vector3(1.0447855, 2.2243478, 0.23754603)
const LEAF_BOX_AT: Vector3 = Vector3(0.52239263, 1.1121739, 0.04999995)

## Parede interna com vão, lida do prefab SM_Bld_House_InteriorWall_Door_01.
const INNER_BOXES: Array[Dictionary] = [
	{"size": Vector3(0.71660376, 2.8999999, 0.24001281), "at": Vector3(2.1416981, 1.4499999, 0.10000027)},
	{"size": Vector3(0.75691485, 2.8999999, 0.24001281), "at": Vector3(0.37845743, 1.4499999, 0.10000027)},
	{"size": Vector3(2.5, 0.6490016, 0.24001281), "at": Vector3(1.25, 2.5754993, 0.10000027)},
]
## O módulo de parede com porta vem com colisão de caixa cheia: o vão existe só
## na malha e ninguém atravessa. Estas três caixas recortam a passagem.
const ENTRY_WALL_BOXES: Array[Dictionary] = [
	{"size": Vector3(0.70, 3.9427848, 0.2), "at": Vector3(0.35, 0.92860746, 0.1)},
	{"size": Vector3(0.67, 3.9427848, 0.2), "at": Vector3(2.165, 0.92860746, 0.1)},
	{"size": Vector3(1.13, 0.63, 0.2), "at": Vector3(1.265, 2.585, 0.1)},
]
const INNER_LEAF_OFFSET: Vector3 = Vector3(0.7439499, 0.01190729, 0.07011461)
const INNER_LEAF_BOX_SIZE: Vector3 = Vector3(1.0500414, 2.2724009, 0.237546)
const INNER_LEAF_BOX_AT: Vector3 = Vector3(0.5250206, 1.1362004, 0.06464121)

## A água encosta na parede 0,243 abaixo da origem da peça: sem essa queda
## sobra uma fresta de 24 cm entre o topo da parede e o telhado.
const ROOF_DROP: float = -0.243
## As pontas cobrem a espessura externa das empenas, além do grid das paredes.
const ROOF_END_OVERHANG: float = 0.3
## Perfil da superfície inclinada do kit, já incluindo ROOF_DROP.
## A empena encosta na cobertura; baixar o triângulo abre uma fresta inclinada.
const GABLE_BASE_Y: float = 2.88
const GABLE_APEX_Y: float = 4.375
const GABLE_X_MIN: float = -0.28
const GABLE_X_MAX: float = 5.28
## Cor chapada do revestimento. O atlas do kit é uma paleta: qualquer UV cai
## numa faixa de cor, e nenhuma delas casa com o siding nas duas pontas, então
## a empena é pintada direto no tom da parede.
const GABLE_COLOR: Color = Color(0.80, 0.82, 0.81)

var _house: Node3D
var _test: Node3D
var _activities: Node3D
var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var result: Error = _save_door(DOOR_PATH, "SM_Bld_House_Door", LEAF_BOX_SIZE, LEAF_BOX_AT)
	if result == OK:
		result = _save_door(INNER_DOOR_PATH, "SM_Bld_House_InteriorWall_Door_02", INNER_LEAF_BOX_SIZE, INNER_LEAF_BOX_AT)
	if result == OK:
		result = _save_house()
	if result == OK:
		result = await _save_test()
	for failure: String in _failures:
		push_error(failure)
	var ok: bool = result == OK and _failures.is_empty()
	print("House01: %s" % ("ok" if ok else "falhou"))
	quit(0 if ok else 1)


# --- portas ------------------------------------------------------------------


func _save_door(path: String, leaf_mesh: String, box_size: Vector3, box_at: Vector3) -> Error:
	var door: Node3D = Node3D.new()
	door.name = "HouseDoor"
	door.set_script(load(DOOR_SCRIPT))
	var leaf: AnimatableBody3D = AnimatableBody3D.new()
	leaf.name = "Folha"
	leaf.sync_to_physics = false
	door.add_child(leaf)
	leaf.owner = door
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.name = "Malha"
	mesh.mesh = load(EXTRACTED % leaf_mesh)
	mesh.set_surface_override_material(0, load(TOWN_MAT))
	leaf.add_child(mesh)
	mesh.owner = door
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var box: BoxShape3D = BoxShape3D.new()
	box.size = box_size
	shape.shape = box
	shape.position = box_at
	leaf.add_child(shape)
	shape.owner = door
	var trigger: Area3D = Area3D.new()
	trigger.name = "Trigger"
	trigger.position = Vector3(0.5, 1.0, 0.05)
	trigger.monitorable = false
	door.add_child(trigger)
	trigger.owner = door
	# O raio real é escrito em _ready a partir de trigger_radius.
	var trigger_shape: CollisionShape3D = CollisionShape3D.new()
	trigger_shape.name = "CollisionShape3D"
	trigger_shape.shape = SphereShape3D.new()
	trigger.add_child(trigger_shape)
	trigger_shape.owner = door
	return _pack(door, path)


# --- casa --------------------------------------------------------------------


func _save_house() -> Error:
	_house = Node3D.new()
	_house.name = "House01"
	_build_shell()
	_build_roof()
	_build_porch()
	_build_furniture()
	_build_lights()
	_build_activities()
	_apply_proportions()
	return _pack(_house, HOUSE_PATH)



## Ajuste dimensional sobre o grid original; raiz, alturas e luzes preservadas.
## Cada m?dulo leva sua malha e colis?o juntas. M?veis mant?m os mesmos lados
## dos c?modos, com deslocamentos que acompanham as paredes correspondentes.
func _apply_proportions() -> void:
	var footprint: Vector3 = Vector3(1.2, 1.0, 1.08)
	for group_name: String in ["Estrutura", "Divisorias", "Telhado"]:
		for child: Node in _house.get_node(group_name).get_children():
			var module: Node3D = child as Node3D
			module.transform = Transform3D(Basis.from_scale(footprint), Vector3.ZERO) * module.transform
	for child: Node in _house.get_node("Varanda").get_children():
		var module: Node3D = child as Node3D
		module.position.x *= footprint.x
		module.position.z += 0.8
		if not String(module.name).begins_with("Poste"):
			module.scale.x *= footprint.x
	# Folhas giram em eixos ortonormais; a largura fica na malha e na caixa,
	# n?o no piv?, para n?o deformar a porta durante a abertura.
	for child: Node in _house.find_children("*", "HouseDoor", true, false):
		var door: Node3D = child as Node3D
		door.scale = Vector3(1.0 / 1.2, 1.0, 1.0 / 1.08)
		var mesh: Node3D = door.get_node("Folha/Malha") as Node3D
		mesh.scale.x = 1.2
		var collider: CollisionShape3D = door.get_node("Folha/CollisionShape3D") as CollisionShape3D
		var box: BoxShape3D = collider.shape.duplicate() as BoxShape3D
		box.size.x *= 1.2
		collider.shape = box
		collider.position.x *= 1.2
		# Estas sobrescritas pertencem ? casa, n?o aos prefabs compartilhados.
		for node: Node in door.find_children("*", "", true, false):
			node.owner = _house
	var positions: Dictionary[String, Vector3] = {
		"Cama": Vector3(0.85, 0, 1.5), "Criado": Vector3(1.7, 0, 0.65),
		"Guarda-roupa": Vector3(2.55, 0, 3.25), "TapeteQuarto": Vector3(1.45, 0, 3.5),
		"Banheira": Vector3(4.5, 0, 0.75), "Vaso": Vector3(3.45, 0, 2.2),
		"Pia": Vector3(5.7, 0.95, 2.1), "BancadaPia": Vector3(6, 0, 4.35),
		"Geladeira": Vector3(3.45, 0, 3.35), "Microondas": Vector3(5.5, 0.95, 3.7),
		"Sofa": Vector3(0.65, 0, 9.6), "Rack": Vector3(5.6, 0, 9.2),
		"MesaCentro": Vector3(2.05, 0, 9.6), "TapeteSala": Vector3(2.2, 0, 9.6),
		"MesaJantar": Vector3(1.85, 0, 7.2), "CadeiraLeste": Vector3(3.25, 0, 7.2),
		"Estante": Vector3(5.68, 0, 7.05), "Abajur": Vector3(0.45, 0, 8.15),
		"Planta": Vector3(5.7, 0, 5.9),
	}
	for furniture_name: String in positions:
		var furniture: Node3D = _house.get_node("Moveis/" + furniture_name) as Node3D
		furniture.position = positions[furniture_name]
	# Estante na parede leste sem janela; mesa de centro acompanha o sof?.
	(_house.get_node("Moveis/Estante") as Node3D).rotation.y = deg_to_rad(-90.0)
	(_house.get_node("Moveis/MesaCentro") as Node3D).rotation.y = deg_to_rad(90.0)
	(_house.get_node("Moveis/Cama") as Node3D).scale = Vector3(0.65, 0.9, 0.8)
	(_house.get_node("Moveis/MesaJantar") as Node3D).scale = Vector3.ONE * 0.85
	(_house.get_node("Moveis/CadeiraLeste") as Node3D).scale = Vector3.ONE * 0.88
	for child: Node in _house.get_node("Atividades").get_children():
		var point: Node3D = child as Node3D
		point.position *= footprint
		if point.name == &"Varanda":
			point.position.z = 12.2


func _build_shell() -> void:
	# Cores da paleta PolygonTown_Texture_01_A, sem alterar o atlas compartilhado.
	# Pixels: seco (55, 1330), cozinha (135, 1280), banheiro (205, 1330).
	var dry_floor: StandardMaterial3D = StandardMaterial3D.new()
	dry_floor.resource_name = "Piso seco - marrom quente PolygonTown"
	dry_floor.albedo_color = Color(0.7176471, 0.5686275, 0.4392157, 1.0)
	dry_floor.roughness = 0.9
	var kitchen_floor: StandardMaterial3D = StandardMaterial3D.new()
	kitchen_floor.resource_name = "Piso cozinha - ceramica bege PolygonTown"
	kitchen_floor.albedo_color = Color(0.8352941, 0.8117647, 0.7803922, 1.0)
	kitchen_floor.roughness = 0.65
	var bathroom_floor: StandardMaterial3D = StandardMaterial3D.new()
	bathroom_floor.resource_name = "Piso banheiro - ceramica cinza PolygonTown"
	bathroom_floor.albedo_color = Color(0.6627451, 0.6549020, 0.6470588, 1.0)
	bathroom_floor.roughness = 0.7
	var shell: Node3D = _group(_house, "Estrutura", _house)
	for column: int in 2:
		for row: int in 4:
			var at: Vector3 = Vector3(column * M, 0.0, row * M + M)
			var floor_mesh: MeshInstance3D = _add(shell, BLD % "SM_Bld_House_Interior_Floor_01", "Piso%d%d" % [column, row], at) as MeshInstance3D
			var finish: StandardMaterial3D = dry_floor
			if column == 1 and row == 0:
				finish = bathroom_floor
			elif column == 1 and row == 1:
				finish = kitchen_floor
			floor_mesh.set_surface_override_material(0, finish)
			_add(shell, BLD % "SM_Bld_House_Interior_Ceiling_01", "Teto%d%d" % [column, row], at)

	# O piso do kit tem colisão de espessura zero: não sustenta o Player nem
	# gera navegação. A laje abaixo dele resolve os dois, com o topo em y = 0.
	var slab: StaticBody3D = StaticBody3D.new()
	slab.name = "PisoColisao"
	shell.add_child(slab)
	slab.owner = _house
	var slab_shape: CollisionShape3D = CollisionShape3D.new()
	slab_shape.name = "CollisionShape3D"
	var slab_box: BoxShape3D = BoxShape3D.new()
	# Avança 25 cm além da fachada: sem chão sob a soleira sobra um vão de 20 cm
	# na espessura da parede, e a navegação de dentro não encosta na varanda.
	slab_box.size = Vector3(W, 0.2, L + 0.25)
	slab_shape.shape = slab_box
	slab_shape.position = Vector3(W * 0.5, -0.1, (L + 0.25) * 0.5)
	slab.add_child(slab_shape)
	slab_shape.owner = _house

	# Perímetro: a peça cresce em +X e a espessura fica no lado de fora.
	var walls: Array[Dictionary] = [
		{"n": "ParedeSulJanela", "p": "Window_01", "at": Vector3(0, 0, L), "yaw": 0.0},
		{"n": "ParedeSulPorta", "p": "Door_01", "at": Vector3(M, 0, L), "yaw": 0.0},
		{"n": "ParedeNorteQuarto", "p": "Window_02", "at": Vector3(M, 0, 0), "yaw": 180.0},
		{"n": "ParedeNorteBanheiro", "p": "Window_02", "at": Vector3(W, 0, 0), "yaw": 180.0},
		{"n": "ParedeOesteQuarto", "p": "Window_01", "at": Vector3(0, 0, 0), "yaw": -90.0},
		{"n": "ParedeOesteQuarto2", "p": "", "at": Vector3(0, 0, M), "yaw": -90.0},
		{"n": "ParedeOesteSala", "p": "Window_01", "at": Vector3(0, 0, 2 * M), "yaw": -90.0},
		{"n": "ParedeOesteSala2", "p": "", "at": Vector3(0, 0, 3 * M), "yaw": -90.0},
		{"n": "ParedeLesteBanheiro", "p": "", "at": Vector3(W, 0, M), "yaw": 90.0},
		{"n": "ParedeLesteCozinha", "p": "Window_01", "at": Vector3(W, 0, 2 * M), "yaw": 90.0},
		{"n": "ParedeLesteSala", "p": "", "at": Vector3(W, 0, 3 * M), "yaw": 90.0},
		{"n": "ParedeLesteSala2", "p": "Window_01", "at": Vector3(W, 0, L), "yaw": 90.0},
	]
	for wall: Dictionary in walls:
		var kind: String = wall["p"]
		var piece: String = "SM_Bld_House_ExteriorWall_GroundFloor_01"
		if kind != "":
			piece = "SM_Bld_House_ExteriorWall_GroundFloor_%s" % kind
		var at: Vector3 = wall["at"]
		var yaw: float = wall["yaw"]
		var label: String = String(wall["n"]).substr(6)
		# Caixilho, vidro e cortina entram na mesma transform do módulo.
		if kind.begins_with("Door"):
			_entry_door(shell, wall["n"], at, yaw)
			continue
		_add(shell, BLD % piece, wall["n"], at, yaw)
		if kind.begins_with("Window"):
			var window_asset: String = "SM_Bld_House_Window_01"
			if label.contains("Quarto"):
				window_asset = "SM_Bld_House_Window_03"
			elif label.contains("Cozinha"):
				window_asset = "SM_Bld_House_Window_02"
			_add(shell, BLD % window_asset, "Caixilho" + label, at, yaw)
			if label.contains("Banheiro"):
				_add(shell, BLD % "SM_Bld_House_Window_Blinds_Closed_01", "Persiana" + label, at, yaw)
			elif not label.contains("Cozinha"):
				_add(shell, BLD % "SM_Bld_House_Window_Curtains_01", "Cortina" + label, at, yaw)

	for corner: Dictionary in [
		{"n": "CantoSudoeste", "at": Vector3(0, 0, L), "yaw": 0.0},
		{"n": "CantoSudeste", "at": Vector3(W, 0, L), "yaw": 90.0},
		{"n": "CantoNordeste", "at": Vector3(W, 0, 0), "yaw": 180.0},
		{"n": "CantoNoroeste", "at": Vector3(0, 0, 0), "yaw": -90.0},
	]:
		_add(shell, BLD % "SM_Bld_House_ExteriorWall_GroundFloor_Corner_01", corner["n"], corner["at"], corner["yaw"])

	# Divisórias: quarto a oeste, banheiro e cozinha a leste, sala na frente.
	var inner: Node3D = _group(_house, "Divisorias", _house)
	_add(inner, BLD % "SM_Bld_House_InteriorWall_01", "ParedeQuartoNorte", Vector3(M, 0, 0), -90.0)
	_add(inner, BLD % "SM_Bld_House_InteriorWall_01", "ParedeQuartoSul", Vector3(M, 0, M), -90.0)
	# O prefab do vão traz a folha fechada junto: a parede é montada à mão para
	# a folha virar HouseDoor, e a passagem da cozinha fica sem folha nenhuma.
	_inner_door(inner, "PortaBanheiro", Vector3(M, 0, M), 0.0, true)
	_inner_door(inner, "PortaQuarto", Vector3(0, 0, 2 * M), 0.0, true)
	_inner_door(inner, "PassagemCozinha", Vector3(M, 0, 2 * M), 0.0, false)

	# Acabamentos locais: apenas a superficie Interior do perimetro.
	# As divisorias compartilhadas mantem o creme dos ambientes secos.
	# Cores do atlas A: (135, 1280), (120, 20) e (810, 1080).
	var dry_wall: StandardMaterial3D = StandardMaterial3D.new()
	dry_wall.resource_name = "Parede seca - creme fosco PolygonTown"
	dry_wall.albedo_color = Color(0.8352941, 0.8117647, 0.7803922, 1.0)
	dry_wall.roughness = 0.95
	var kitchen_wall: StandardMaterial3D = StandardMaterial3D.new()
	kitchen_wall.resource_name = "Parede cozinha - claro acetinado PolygonTown"
	kitchen_wall.albedo_color = Color(0.8392157, 0.8549020, 0.8470588, 1.0)
	kitchen_wall.roughness = 0.6
	var bathroom_wall: StandardMaterial3D = StandardMaterial3D.new()
	bathroom_wall.resource_name = "Parede banheiro - cinza esverdeado PolygonTown"
	bathroom_wall.albedo_color = Color(0.6705882, 0.6980392, 0.6745098, 1.0)
	bathroom_wall.roughness = 0.65
	for wall: Dictionary in walls:
		var wall_name: String = wall["n"]
		var visual: MeshInstance3D = shell.get_node(wall_name) as MeshInstance3D
		var finish: StandardMaterial3D = dry_wall
		if wall_name.contains("Banheiro"):
			finish = bathroom_wall
		elif wall_name.contains("Cozinha"):
			finish = kitchen_wall
		for surface: int in visual.mesh.get_surface_count():
			var original: Material = visual.mesh.surface_get_material(surface)
			if original != null and original.resource_name.begins_with("Interior"):
				visual.set_surface_override_material(surface, finish)
	for child: Node in inner.get_children():
		var visual: MeshInstance3D = child as MeshInstance3D
		if visual != null:
			visual.set_surface_override_material(0, dry_wall)


func _entry_door(parent: Node3D, node_name: String, at: Vector3, yaw: float) -> void:
	# A parede não vem do prefab: a dele é uma caixa cheia e fecharia o vão.
	_mesh_body(parent, node_name, "SM_Bld_House_ExteriorWall_GroundFloor_Door_01", ENTRY_WALL_BOXES, at, yaw)
	var frame: MeshInstance3D = _mesh_body(parent, "BatentePorta", "SM_Bld_House_Door_01", FRAME_BOXES, at, yaw)
	var leaf: Node3D = (load(DOOR_PATH) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node3D
	leaf.name = "PortaEntrada"
	leaf.position = LEAF_OFFSET
	# Abre para a varanda: aberta para dentro, a folha fica bem no caminho de
	# quem entra e trava o NPC contra ela.
	leaf.set("open_direction", -1)
	# A casa começa fechada: a moradora leva chave e destranca ao passar, e o
	# ET só entra pela porta depois disso, ou destrancando por dentro.
	leaf.set("starts_locked", true)
	frame.add_child(leaf)
	leaf.owner = _house


func _inner_door(parent: Node3D, node_name: String, at: Vector3, yaw: float, with_leaf: bool) -> void:
	var wall: MeshInstance3D = _mesh_body(parent, node_name, "SM_Bld_House_InteriorWall_Door_01", INNER_BOXES, at, yaw)
	if not with_leaf:
		return
	var leaf: Node3D = (load(INNER_DOOR_PATH) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node3D
	leaf.name = "Folha" + node_name
	leaf.position = INNER_LEAF_OFFSET
	wall.add_child(leaf)
	leaf.owner = _house


func _mesh_body(parent: Node3D, node_name: String, mesh_name: String, boxes: Array[Dictionary], at: Vector3, yaw: float) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = node_name
	node.mesh = load(EXTRACTED % mesh_name)
	for surface: int in node.mesh.get_surface_count():
		node.set_surface_override_material(surface, load(TOWN_MAT))
	node.position = at
	node.rotation.y = deg_to_rad(yaw)
	parent.add_child(node)
	node.owner = _house
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "Colisao"
	node.add_child(body)
	body.owner = _house
	for index: int in boxes.size():
		var shape: CollisionShape3D = CollisionShape3D.new()
		shape.name = "CollisionShape3D%d" % index
		var box: BoxShape3D = BoxShape3D.new()
		box.size = boxes[index]["size"]
		shape.shape = box
		shape.position = boxes[index]["at"]
		body.add_child(shape)
		shape.owner = _house
	return node


func _build_roof() -> void:
	var roof: Node3D = _group(_house, "Telhado", _house)
	# Água oeste sobe do beiral até a cumeeira em x = 2,5; a leste é a mesma
	# peça espelhada pelo yaw.
	for row: int in 4:
		var start: float = row * M - (ROOF_END_OVERHANG if row == 0 else 0.0)
		var end: float = (row + 1) * M + (ROOF_END_OVERHANG if row == 3 else 0.0)
		var west: Node3D = _add(roof, BLD % "SM_Bld_House_Roof_Angled_Gutter_01", "AguaOeste%d" % row, Vector3(0, ROOF_DROP, start), -90.0)
		var east: Node3D = _add(roof, BLD % "SM_Bld_House_Roof_Angled_Gutter_01", "AguaLeste%d" % row, Vector3(W, ROOF_DROP, end), 90.0)
		west.scale.x = (end - start) / M
		east.scale.x = (end - start) / M
	_gable(roof, "EmpenaNorte", -0.2, 0.0)
	_gable(roof, "EmpenaSul", L + 0.2, L)


func _gable(parent: Node3D, node_name: String, z_out: float, z_in: float) -> void:
	# O kit não traz oitão para vão de 5 m, então o triângulo entre o topo da
	# parede e a cumeeira é gerado aqui, com a cor da parede.
	var apex_out: Vector3 = Vector3(2.5, GABLE_APEX_Y, z_out)
	var apex_in: Vector3 = Vector3(2.5, GABLE_APEX_Y, z_in)
	var west_out: Vector3 = Vector3(GABLE_X_MIN, GABLE_BASE_Y, z_out)
	var west_in: Vector3 = Vector3(GABLE_X_MIN, GABLE_BASE_Y, z_in)
	var east_out: Vector3 = Vector3(GABLE_X_MAX, GABLE_BASE_Y, z_out)
	var east_in: Vector3 = Vector3(GABLE_X_MAX, GABLE_BASE_Y, z_in)
	var face: Vector3 = Vector3(0, 0, signf(z_out - z_in))
	var rise: float = GABLE_APEX_Y - GABLE_BASE_Y
	var west_normal: Vector3 = Vector3(-rise, 2.5 - GABLE_X_MIN, 0).normalized()
	var east_normal: Vector3 = Vector3(rise, GABLE_X_MAX - 2.5, 0).normalized()
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_tri(tool, west_out, east_out, apex_out, face)
	_tri(tool, east_in, west_in, apex_in, -face)
	_quad(tool, west_out, apex_out, apex_in, west_in, west_normal)
	_quad(tool, apex_out, east_out, east_in, apex_in, east_normal)
	_quad(tool, east_out, west_out, west_in, east_in, Vector3.DOWN)
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = node_name
	node.mesh = tool.commit()
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = GABLE_COLOR
	material.roughness = 0.9
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	node.set_surface_override_material(0, material)
	parent.add_child(node)
	node.owner = _house
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "Colisao"
	node.add_child(body)
	body.owner = _house
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	shape.shape = node.mesh.create_trimesh_shape()
	body.add_child(shape)
	shape.owner = _house


func _tri(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> void:
	for point: Vector3 in [a, b, c]:
		tool.set_normal(normal)
		tool.add_vertex(point)


func _quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	_tri(tool, a, b, c, normal)
	_tri(tool, a, c, d, normal)


func _build_porch() -> void:
	var porch: Node3D = _group(_house, "Varanda", _house)
	for column: int in 2:
		_add(porch, BLD % "SM_Bld_House_Deck_01", "Deck%d" % column, Vector3(column * M, 0, L + 0.07))
		_add(porch, BLD % "SM_Bld_House_Deck_Roof_01", "CoberturaDeck%d" % column, Vector3(column * M, 0, L + 0.07))
	_add(porch, BLD % "SM_Bld_House_Deck_Post_01", "PosteOeste", Vector3(0.2, 0, L + 0.07))
	_add(porch, BLD % "SM_Bld_House_Deck_Post_01", "PosteLeste", Vector3(W - 0.1, 0, L + 0.07))
	# Sem degraus: o deck fica 26 cm acima do gramado, altura que o Player e o
	# NavigationAgent sobem direto. Degrau do kit tem 50 cm e ficaria enterrado.


func _build_furniture() -> void:
	var room: Node3D = _group(_house, "Moveis", _house)
	# Quarto (x 0..2,5 / z 0..5). Cama de solteiro: a de casal tem 2,09 de
	# largura e não sobra corredor num cômodo de 2,5.
	_add(room, PROP % "SM_Prop_Bed_Single_01", "Cama", Vector3(0.85, 0, 1.5), 0.0)
	_add(room, PROP % "SM_Prop_BedsideTable_01", "Criado", Vector3(2.1, 0, 0.4), 0.0)
	_add(room, PROP % "SM_Prop_Wardrobe_01", "Guarda-roupa", Vector3(2.05, 0, 4.3), -90.0)
	_add(room, PROP % "SM_Prop_Rug_02", "TapeteQuarto", Vector3(1.2, 0, 3.3), 0.0)
	# Banheiro (x 2,5..5 / z 0..2,5)
	_add(room, PROP % "SM_Prop_Bath_01", "Banheira", Vector3(3.75, 0, 0.75), 0.0)
	_add(room, PROP % "SM_Prop_Toilet_01", "Vaso", Vector3(2.95, 0, 2.0), -90.0)
	var sink: Node3D = _add(room, PROP % "SM_Prop_BathroomSink_01", "Pia", Vector3(4.7, 0, 1.9), 90.0)
	sink.position.y = 0.95
	# Cozinha (x 2,5..5 / z 2,7..5): só a bancada na parede leste e a geladeira
	# no canto norte. O cômodo tem 2,5 m: com armário nos dois lados sobrava
	# meio metro de corredor e o vão da porta fechava na navegação.
	_add(room, PROP % "SM_Prop_Kitchen_CounterSink_01", "BancadaPia", Vector3(W, 0, 3.95), -90.0)
	_add(room, PROP % "SM_Prop_Kitchen_Fridge_01", "Geladeira", Vector3(2.95, 0, 3.15), 180.0)
	_add(room, PROP % "SM_Prop_Microwave_01", "Microondas", Vector3(4.5, 0.95, 3.3), -90.0)
	# Sala (x 0..5 / z 5..10)
	# Tudo encostado nas paredes: sobra um corredor de ~1 m da porta de entrada
	# até o vão do quarto, largura que a moradora atravessa sem raspar.
	_add(room, PROP % "SM_Prop_Couch_01", "Sofa", Vector3(0.9, 0, 8.8), 90.0)
	_add(room, PROP % "SM_Prop_TVCabinet_01", "Rack", Vector3(4.6, 0, 8.4), -90.0)
	_add(room, PROP % "SM_Prop_CoffeeTable_01", "MesaCentro", Vector3(2.1, 0, 8.8), 0.0)
	_add(room, PROP % "SM_Prop_Rug_01", "TapeteSala", Vector3(2.2, 0, 8.8), 0.0)
	# Jantar encostado a oeste: a faixa leste (x 3,3 a 5) fica livre da porta de
	# entrada até o vão da cozinha, e a travessia para o quarto passa em z 5,2.
	_add(room, PROP % "SM_Prop_DiningTable_01", "MesaJantar", Vector3(1.6, 0, 7.0), 0.0)
	_add(room, PROP % "SM_Prop_DiningChair_01", "CadeiraLeste", Vector3(2.95, 0, 7.0), -90.0)
	_add(room, PROP % "SM_Prop_Bookshelf_01", "Estante", Vector3(0.35, 0, 6.3), 90.0)
	_add(room, PROP % "SM_Prop_LampStanding_01", "Abajur", Vector3(0.4, 0, 9.7), 0.0)
	_add(room, PROP % "SM_Prop_PotPlant_01", "Planta", Vector3(4.7, 0, 5.5), 0.0)


func _build_lights() -> void:
	var lights: Node3D = _group(_house, "Luzes", _house)
	lights.set_script(load(LIGHTS_SCRIPT))
	lights.set("window_light_energy", 1.1)
	lights.set("light_range", 5.5)
	lights.set("flicker_amount", 0.0)
	# Todas com sombra: sem isso a luz atravessa o teto e pinta o telhado e a
	# empena de laranja por fora.
	lights.set("shadow_light_indices", PackedInt32Array([0, 1, 2, 3, 4]))
	# Posições na planta atual; cozinha linear, plafons e pendente sobre a mesa.
	for spot: Dictionary in [
		{"n": "LuzSala", "at": Vector3(2.3, 0, 9.25), "fixture": "02", "bulb_y": -0.27, "color": Color(1, 0.86, 0.7), "energy": 0.75, "range": 4.4},
		{"n": "LuzJantar", "at": Vector3(1.85, 0, 7.2), "fixture": "01", "bulb_y": -0.75, "color": Color(1, 0.9, 0.78), "energy": 0.6, "range": 3.5},
		{"n": "LuzQuarto", "at": Vector3(1.5, 0, 2.7), "fixture": "02", "bulb_y": -0.27, "color": Color(1, 0.85, 0.7), "energy": 0.65, "range": 3.7},
		{"n": "LuzCozinha", "at": Vector3(4.8, 0, 4.05), "fixture": "03", "bulb_y": -0.27, "color": Color(1, 0.97, 0.9), "energy": 1.05, "range": 3.3},
		{"n": "LuzBanheiro", "at": Vector3(4.65, 0, 1.45), "fixture": "02", "bulb_y": -0.27, "color": Color(0.94, 0.97, 1), "energy": 0.85, "range": 2.9},
	]:
		var at: Vector3 = spot["at"]
		var fixture: Node3D = _add(lights, PROP % ("SM_Prop_CeilingLight_" + String(spot["fixture"])), spot["n"], at + Vector3.UP * 2.9)
		var bulb: OmniLight3D = OmniLight3D.new()
		bulb.name = "Omni"
		bulb.position = Vector3(0, float(spot["bulb_y"]), 0)
		bulb.light_color = spot["color"]
		bulb.light_energy = float(spot["energy"])
		bulb.omni_range = float(spot["range"])
		bulb.shadow_enabled = true
		bulb.set_meta("room_lighting", true)
		fixture.add_child(bulb)
		bulb.owner = _house


func _build_activities() -> void:
	var points: Node3D = _group(_house, "Atividades", _house)
	# O NPC para no ponto e encara o +Z local; o yaw aponta para o móvel.
	for point: Dictionary in [
		{"n": "Cama", "at": Vector3(1.95, 0, 1.6), "yaw": -90.0, "kind": &"home", "min": 30.0, "max": 70.0},
		{"n": "Sofa", "at": Vector3(2.9, 0, 8.7), "yaw": -90.0, "kind": &"observe", "min": 25.0, "max": 55.0},
		{"n": "Cozinha", "at": Vector3(3.6, 0, 4.3), "yaw": 90.0, "kind": &"work", "min": 20.0, "max": 45.0},
		{"n": "MesaJantar", "at": Vector3(2.6, 0, 5.9), "yaw": 0.0, "kind": &"wait", "min": 15.0, "max": 35.0},
		{"n": "Varanda", "at": Vector3(2.0, 0, 11.4), "yaw": 0.0, "kind": &"observe", "min": 12.0, "max": 30.0},
	]:
		var activity: NPCActivity = ACTIVITY_SCRIPT.new() as NPCActivity
		activity.name = point["n"]
		activity.activity = point["kind"]
		activity.duration_min = point["min"]
		activity.duration_max = point["max"]
		activity.position = point["at"]
		activity.rotation.y = deg_to_rad(point["yaw"])
		points.add_child(activity)
		activity.owner = _house


# --- cena de teste -----------------------------------------------------------


func _save_test() -> Error:
	_test = Node3D.new()
	_test.name = "HouseTest"
	root.add_child(_test)

	var env: WorldEnvironment = WorldEnvironment.new()
	env.name = "WorldEnvironment"
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky: Sky = Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.6
	env.environment = environment
	_test.add_child(env)
	env.owner = _test

	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.name = "Sol"
	sun.rotation = Vector3(deg_to_rad(-48.0), deg_to_rad(38.0), 0.0)
	sun.shadow_enabled = true
	sun.light_energy = 1.1
	_test.add_child(sun)
	sun.owner = _test

	var ground: Node3D = _group(_test, "Terreno", _test)
	ground.position.y = GROUND_Y
	var plane: MeshInstance3D = MeshInstance3D.new()
	plane.name = "Grama"
	var plane_mesh: PlaneMesh = PlaneMesh.new()
	plane_mesh.size = Vector2(60, 60)
	plane.mesh = plane_mesh
	plane.position = Vector3(2.5, 0, 5)
	var grass: StandardMaterial3D = StandardMaterial3D.new()
	grass.albedo_color = Color(0.36, 0.45, 0.26)
	grass.roughness = 0.95
	plane.set_surface_override_material(0, grass)
	ground.add_child(plane)
	plane.owner = _test
	var floor_body: StaticBody3D = StaticBody3D.new()
	floor_body.name = "Chao"
	ground.add_child(floor_body)
	floor_body.owner = _test
	var floor_shape: CollisionShape3D = CollisionShape3D.new()
	floor_shape.name = "CollisionShape3D"
	var floor_box: BoxShape3D = BoxShape3D.new()
	floor_box.size = Vector3(60, 1, 60)
	floor_shape.shape = floor_box
	floor_shape.position = Vector3(2.5, -0.5, 5)
	floor_body.add_child(floor_shape)
	floor_shape.owner = _test

	var house: Node3D = (load(HOUSE_PATH) as PackedScene).instantiate() as Node3D
	house.name = "House01"
	_test.add_child(house)
	house.owner = _test
	_activities = house.get_node("Atividades") as Node3D

	await process_frame
	var region: NavigationRegion3D = NavigationRegion3D.new()
	region.name = "NavigationRegion3D"
	var nav: NavigationMesh = _bake_navigation(house)
	if nav.get_polygon_count() == 0:
		_failures.append("Navegacao da casa saiu vazia")
		return FAILED
	region.navigation_mesh = nav
	_test.add_child(region)
	region.owner = _test

	var player: Node3D = (load("res://scenes/Player.tscn") as PackedScene).instantiate() as Node3D
	player.name = "Player"
	player.position = Vector3(2.5, GROUND_Y + 0.2, 16.0)
	player.rotation.y = deg_to_rad(180.0)
	_test.add_child(player)
	player.owner = _test

	var pause: Node = (load("res://scenes/Menu/PauseMenu.tscn") as PackedScene).instantiate()
	pause.name = "PauseMenu"
	_test.add_child(pause)
	pause.owner = _test

	_add_resident()

	var result: Error = ResourceSaver.save(nav, NAV_PATH)
	if result == OK:
		nav.take_over_path(NAV_PATH)
		result = _pack(_test, TEST_PATH)
	print("Navegacao da casa: %d poligonos" % nav.get_polygon_count())
	return result


func _add_resident() -> void:
	var actor: NPCActor = (load("res://scenes/NPCs/Townsperson.tscn") as PackedScene).instantiate() as NPCActor
	actor.name = "Moradora"
	actor.require_navigation = true
	actor.grounded = true
	actor.walk_speed = 1.4
	actor.position = Vector3(2.0, GROUND_Y + 0.1, 13.5)
	_test.add_child(actor)
	actor.owner = _test
	var routine: NPCRoutine = ROUTINE_SCRIPT.new() as NPCRoutine
	routine.name = "NPCRoutine"
	for point: String in ["Varanda", "Sofa", "Cozinha", "MesaJantar", "Cama"]:
		routine.activity_paths.append(NodePath("../../House01/Atividades/" + point))
	routine.refuge_path = routine.activity_paths[0]
	actor.add_child(routine)
	routine.owner = _test
	actor.patrol_points = []
	for point: Node in _activities.get_children():
		actor.patrol_points.append((point as Node3D).position)


func _bake_navigation(house: Node3D) -> NavigationMesh:
	# As folhas de porta saem da árvore antes do bake: fechadas, elas recortam
	# o vão e a moradora nunca acharia caminho para dentro.
	var leaves: Array[Node] = []
	for node: Node in house.find_children("*", "HouseDoor", true, false):
		leaves.append(node)
	var parents: Array[Node] = []
	for leaf: Node in leaves:
		parents.append(leaf.get_parent())
		leaf.get_parent().remove_child(leaf)

	# Móveis também saem da geometria: o Recast trata tampo de mesa e bancada
	# como chão e gera ilhas soltas em cima deles. Cada um vira um obstáculo
	# com a mesma pegada, que recorta a área ocupada sem virar plataforma.
	var furniture: Node3D = house.get_node("Moveis") as Node3D
	var blockers: Node3D = Node3D.new()
	blockers.name = "ObstaculosDeBake"
	_test.add_child(blockers)
	for child: Node in furniture.get_children():
		var box: AABB = _visual_bounds(child as Node3D)
		if box.size.y < 0.3 or box.size.x <= 0.0 or box.size.z <= 0.0:
			continue
		var obstacle: NavigationObstacle3D = NavigationObstacle3D.new()
		obstacle.affect_navigation_mesh = true
		obstacle.carve_navigation_mesh = true
		obstacle.height = maxf(box.size.y, 0.5)
		var half_x: float = box.size.x * 0.5
		var half_z: float = box.size.z * 0.5
		obstacle.vertices = PackedVector3Array([
			Vector3(-half_x, 0, -half_z), Vector3(half_x, 0, -half_z),
			Vector3(half_x, 0, half_z), Vector3(-half_x, 0, half_z),
		])
		blockers.add_child(obstacle)
		obstacle.global_position = Vector3(box.get_center().x, box.position.y, box.get_center().z)
	house.remove_child(furniture)

	var nav: NavigationMesh = NavigationMesh.new()
	nav.cell_size = 0.1
	nav.cell_height = 0.06
	# O corpo da moradora tem raio 0,186: 0,22 deixa ela passar nos vãos de
	# 1 m entre móvel e parede sem abrir buraco na navegação.
	nav.agent_radius = 0.22
	nav.agent_height = 1.8
	nav.agent_max_climb = 0.35
	nav.agent_max_slope = 35.0
	nav.region_min_size = 0.6
	nav.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	# Teto (2,9) e telhado ficam fora: só o que dá para pisar entra no bake.
	nav.filter_baking_aabb = AABB(Vector3(-25, GROUND_Y - 1.5, -25), Vector3(60, 3.9, 60))
	var source: NavigationMeshSourceGeometryData3D = NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nav, source, _test)
	NavigationServer3D.bake_from_source_geometry_data(nav, source)

	house.add_child(furniture)
	blockers.queue_free()
	for index: int in leaves.size():
		parents[index].add_child(leaves[index])
	return nav


func _visual_bounds(node: Node3D) -> AABB:
	var box: AABB = AABB()
	var found: bool = false
	for child: Node in [node] + node.find_children("*", "VisualInstance3D", true, false):
		var visual: VisualInstance3D = child as VisualInstance3D
		if visual == null:
			continue
		var world_box: AABB = visual.global_transform * visual.get_aabb()
		box = world_box if not found else box.merge(world_box)
		found = true
	return box


# --- utilidades --------------------------------------------------------------


func _group(parent: Node3D, group_name: String, scene_root: Node3D) -> Node3D:
	var node: Node3D = Node3D.new()
	node.name = group_name
	parent.add_child(node)
	node.owner = scene_root
	return node


func _add(parent: Node3D, path: String, node_name: String, at: Vector3, yaw: float = 0.0) -> Node3D:
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		_failures.append("Peca ausente: %s" % path)
		return null
	var node: Node3D = packed.instantiate() as Node3D
	node.name = node_name
	node.position = at
	node.rotation.y = deg_to_rad(yaw)
	# Alguns prefabs do kit vêm sem material: sem isso a peça sai branca.
	var visual: MeshInstance3D = node as MeshInstance3D
	if visual != null and visual.get_surface_override_material(0) == null:
		visual.set_surface_override_material(0, load(TOWN_MAT))
	parent.add_child(node)
	node.owner = _house
	return node


func _pack(node: Node, path: String) -> Error:
	var packed: PackedScene = PackedScene.new()
	var result: Error = packed.pack(node)
	if result != OK:
		_failures.append("Nao empacotou %s" % path)
		return result
	result = ResourceSaver.save(packed, path)
	if result != OK:
		_failures.append("Nao gravou %s" % path)
	else:
		print("Gravado: %s" % path)
	return result
