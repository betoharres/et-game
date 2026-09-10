extends SceneTree

const BLD: String = "res://PolygonTown/Prefabs/Buildings/%s.tscn"
const PROP: String = "res://PolygonTown/Prefabs/Props/%s.tscn"
const EXTRACTED: String = "res://PolygonTown/Models/Buildings/extracted/%s.res"
const TOWN_MAT: String = "res://PolygonTown/Materials/PolygonTown_01_A_mat.tres"
const DOOR_PATH: String = "res://scenes/Buildings/HouseDoor.tscn"
const INNER_DOOR_PATH: String = "res://scenes/Buildings/HouseDoorInner.tscn"
const M: float = 2.5
const WIDTH: float = 7.5
const LENGTH: float = 12.5

const FRAME_BOXES: Array[Dictionary] = [
	{"size": Vector3(1.286377, 0.1508789, 0.35180664), "at": Vector3(1.2713623, -0.0690918, 0.15490723)},
	{"size": Vector3(0.1083374, 2.2298584, 0.30969238), "at": Vector3(1.832428, 1.116394, 0.13140869)},
	{"size": Vector3(1.2426147, 0.08531952, 0.30786133), "at": Vector3(1.2711487, 2.2683601, 0.13098145)},
	{"size": Vector3(0.11968994, 2.2456055, 0.30218506), "at": Vector3(0.6980896, 1.119873, 0.13394165)},
]

const LEAF_OFFSET: Vector3 = Vector3(0.74945384, 0.01190729, 0.08475586)

const INNER_BOXES: Array[Dictionary] = [
	{"size": Vector3(0.71660376, 2.8999999, 0.24001281), "at": Vector3(2.1416981, 1.4499999, 0.10000027)},
	{"size": Vector3(0.75691485, 2.8999999, 0.24001281), "at": Vector3(0.37845743, 1.4499999, 0.10000027)},
	{"size": Vector3(2.5, 0.6490016, 0.24001281), "at": Vector3(1.25, 2.5754993, 0.10000027)},
]

const ENTRY_WALL_BOXES: Array[Dictionary] = [
	{"size": Vector3(0.70, 3.9427848, 0.2), "at": Vector3(0.35, 0.92860746, 0.1)},
	{"size": Vector3(0.67, 3.9427848, 0.2), "at": Vector3(2.165, 0.92860746, 0.1)},
	{"size": Vector3(1.13, 0.63, 0.2), "at": Vector3(1.265, 2.585, 0.1)},
]

const INNER_LEAF_OFFSET: Vector3 = Vector3(0.7439499, 0.01190729, 0.07011461)

const GABLE_BASE_Y: float = 2.88

const GABLE_APEX_Y: float = 4.375

const GABLE_X_MIN: float = -0.28

const GABLE_X_MAX: float = 5.28

const GABLE_COLOR: Color = Color(0.80, 0.82, 0.81)

var _house: Node3D
var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_house = Node3D.new()
	_house.name = "House02"
	_build_shell()
	_build_roof()
	_build_porch()
	_build_garage()
	_build_furniture()
	_build_lights()
	_build_activities()
	var result: Error = ERR_CANT_CREATE
	if _failures.is_empty():
		result = _pack(_house, "res://scenes/Buildings/House02.tscn")
	for failure: String in _failures:
		push_error(failure)
	_house.free()
	quit(0 if result == OK and _failures.is_empty() else 1)


func _build_shell() -> void:
	var shell: Node3D = _group(_house, "Estrutura", _house)
	var timber: StandardMaterial3D = StandardMaterial3D.new()
	timber.albedo_color = Color(0.7176471, 0.5686275, 0.4392157)
	timber.roughness = 0.9
	var tile: StandardMaterial3D = StandardMaterial3D.new()
	tile.albedo_color = Color(0.8352941, 0.8117647, 0.7803922)
	tile.roughness = 0.7
	for column: int in 3:
		for row: int in 5:
			var at: Vector3 = Vector3(column * M, 0, (row + 1) * M)
			var floor_mesh: MeshInstance3D = _add(shell, BLD % "SM_Bld_House_Interior_Floor_01", "Piso%d%d" % [column, row], at) as MeshInstance3D
			floor_mesh.set_surface_override_material(0, tile if column == 2 and row in [0, 3] else timber)
			_add(shell, BLD % "SM_Bld_House_Interior_Ceiling_01", "Teto%d%d" % [column, row], at)
	# A laje dá espessura ao piso do kit e alcança a soleira da entrada.
	var slab: StaticBody3D = StaticBody3D.new()
	slab.name = "PisoColisao"
	shell.add_child(slab)
	slab.owner = _house
	var collider: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(WIDTH, 0.2, LENGTH + 0.25)
	collider.shape = box
	collider.position = Vector3(WIDTH / 2, -0.1, (LENGTH + 0.25) / 2)
	slab.add_child(collider)
	collider.owner = _house
	for column: int in 3:
		_wall(shell, "Norte%d" % column, Vector3((column + 1) * M, 0, 0), 180, true)
		if column == 2:
			_entry_door(shell, "ParedeEntrada", Vector3(column * M, 0, LENGTH), 0)
		else:
			_wall(shell, "Sul%d" % column, Vector3(column * M, 0, LENGTH), 0, true)
	for row: int in 5:
		if row == 3:
			_inner_door(shell, "AcessoGaragem", Vector3(0, 0, row * M), -90, true)
			(shell.get_node("AcessoGaragem/FolhaAcessoGaragem") as Node3D).set("open_direction", -1)
		else:
			_wall(shell, "Oeste%d" % row, Vector3(0, 0, row * M), -90, row in [0, 2])
		_wall(shell, "Leste%d" % row, Vector3(WIDTH, 0, (row + 1) * M), 90, row in [1, 3, 4])
	for corner: Dictionary in [
		{"at": Vector3(0, 0, LENGTH), "yaw": 0.0},
		{"at": Vector3(WIDTH, 0, LENGTH), "yaw": 90.0},
		{"at": Vector3(WIDTH, 0, 0), "yaw": 180.0},
		{"at": Vector3(0, 0, 0), "yaw": -90.0},
	]:
		_add(shell, BLD % "SM_Bld_House_ExteriorWall_GroundFloor_Corner_01", "Canto%d" % int(corner["yaw"]), corner["at"], corner["yaw"])
	var inner: Node3D = _group(_house, "Divisorias", _house)
	_add(inner, BLD % "SM_Bld_House_InteriorWall_01", "LateralQuartoCasal", Vector3(5, 0, 0), -90)
	_inner_door(inner, "PortaQuartoCasal", Vector3(5, 0, 2.5), -90, true)
	_inner_door(inner, "PortaQuartoSolteiro", Vector3(5, 0, 5), -90, true)
	_inner_door(inner, "PortaBanheiro", Vector3(5, 0, 2.5), 0, true)
	for column: int in 2:
		_add(inner, BLD % "SM_Bld_House_InteriorWall_01", "EntreQuartos%d" % column, Vector3(column * M, 0, 5))
		_add(inner, BLD % "SM_Bld_House_InteriorWall_01", "ParedeSala%d" % column, Vector3(column * M, 0, 7.5))


func _wall(parent: Node3D, label: String, at: Vector3, yaw: float, window: bool) -> void:
	var piece: String = "SM_Bld_House_ExteriorWall_GroundFloor_Window_01" if window else "SM_Bld_House_ExteriorWall_GroundFloor_01"
	_add(parent, BLD % piece, "Parede" + label, at, yaw)
	if window:
		_add(parent, BLD % "SM_Bld_House_Window_01", "Caixilho" + label, at, yaw)
		if label == "Norte2":
			_add(parent, BLD % "SM_Bld_House_Window_Blinds_Closed_01", "PersianaBanheiro", at, yaw)


func _build_roof() -> void:
	var roof: Node3D = _group(_house, "Telhado", _house)
	# Só a cobertura alarga o vão de 5 m; paredes e portas mantêm o grid do kit.
	for row: int in 5:
		var start: float = row * M - (0.3 if row == 0 else 0.0)
		var end: float = (row + 1) * M + (0.3 if row == 4 else 0.0)
		var west: Node3D = _add(roof, BLD % "SM_Bld_House_Roof_Angled_Gutter_01", "AguaOeste%d" % row, Vector3(0, -0.243, start), -90)
		var east: Node3D = _add(roof, BLD % "SM_Bld_House_Roof_Angled_Gutter_01", "AguaLeste%d" % row, Vector3(5, -0.243, end), 90)
		for module: Node3D in [west, east]:
			module.scale.x = (end - start) / M
			module.transform = Transform3D(Basis.from_scale(Vector3(1.5, 1, 1)), Vector3.ZERO) * module.transform
	_gable(roof, "EmpenaNorte", -0.2, 0)
	_gable(roof, "EmpenaSul", LENGTH + 0.2, LENGTH)
	(roof.get_node("EmpenaNorte") as Node3D).scale.x = 1.5
	(roof.get_node("EmpenaSul") as Node3D).scale.x = 1.5


func _build_porch() -> void:
	var porch: Node3D = _group(_house, "Varanda", _house)
	for column: int in [1, 2]:
		_add(porch, BLD % "SM_Bld_House_Deck_01", "Deck%d" % column, Vector3(column * M, 0, LENGTH + 0.07))
		_add(porch, BLD % "SM_Bld_House_Deck_Roof_01", "Cobertura%d" % column, Vector3(column * M, 0, LENGTH + 0.07))
	for x: float in [2.6, 7.4]:
		_add(porch, BLD % "SM_Bld_House_Deck_Post_01", "Poste%d" % int(x * 10), Vector3(x, 0, LENGTH + 0.07))


func _build_garage() -> void:
	var garage: Node3D = _group(_house, "Garagem", _house)
	# A garagem avança além da fachada; a parede leste é compartilhada com a casa.
	for row: int in 3:
		_wall(garage, "GaragemOeste%d" % row, Vector3(-5, 0, 7.5 + row * M), -90, row == 0)
	for column: int in 2:
		_wall(garage, "GaragemFundo%d" % column, Vector3(-2.5 + column * M, 0, 7.5), 180, false)
	_wall(garage, "GaragemLeste", Vector3(0, 0, 15), 90, false)
	for corner: Dictionary in [
		{"at": Vector3(-5, 0, 15), "yaw": 0.0},
		{"at": Vector3(0, 0, 15), "yaw": 90.0},
		{"at": Vector3(-5, 0, 7.5), "yaw": -90.0},
	]:
		_add(garage, BLD % "SM_Bld_House_ExteriorWall_GroundFloor_Corner_01", "Canto%d" % int(corner["yaw"]), corner["at"], corner["yaw"])
	for column: int in 2:
		for row: int in 3:
			var roof: Node3D = _add(garage, BLD % "SM_Bld_House_Roof_Flat_01", "Cobertura%d%d" % [column, row], Vector3(-5 + column * M - (0.2 if column == 0 else 0.0), 0, 10 + row * M))
			roof.scale.x = 1.08
			if row == 0:
				roof.scale.z = 1.16
	var concrete: StandardMaterial3D = StandardMaterial3D.new()
	concrete.albedo_color = Color(0.43, 0.45, 0.46)
	concrete.roughness = 0.95
	_box(garage, "Piso", Vector3(-2.5, -0.5, 11.25), Vector3(5, 0.2, 7.5), concrete)
	_box(garage, "EntradaCarro", Vector3(-2.5, -0.5, 17), Vector3(5, 0.2, 4), concrete)
	_box(garage, "DegrauCasa", Vector3(-0.3, -0.3, 8.76), Vector3(0.6, 0.2, 1.6), concrete)
	var frame: Node3D = _add(garage, BLD % "SM_Bld_House_ExteriorWall_GarageDoor_01", "Portao", Vector3(-5, 0, 15))
	# Folha recolhida sob o teto, com a própria colisão, deixando o acesso livre.
	var leaf: Node3D = frame.get_node("SM_Bld_House_Wall_GarageDoor_02") as Node3D
	leaf.position.y = 2.65
	leaf.rotation.x = PI / 2
	for node: Node in [leaf] + leaf.find_children("*", "", true, false):
		node.owner = _house
	var light: OmniLight3D = OmniLight3D.new()
	light.name = "LuzGaragem"
	light.position = Vector3(-2.5, 2.45, 10.5)
	light.light_color = Color(0.92, 0.95, 1)
	light.light_energy = 0.8
	light.omni_range = 5
	light.shadow_enabled = true
	garage.add_child(light)
	light.owner = _house


func _box(parent: Node3D, label: String, at: Vector3, size: Vector3, material: Material) -> void:
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.name = label
	visual.position = at
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.material_override = material
	parent.add_child(visual)
	visual.owner = _house
	var body: StaticBody3D = StaticBody3D.new()
	visual.add_child(body)
	body.owner = _house
	var collider: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	collider.owner = _house


func _build_furniture() -> void:
	var room: Node3D = _group(_house, "Moveis", _house)
	for item: Array in [
		["Bed_Double_01", "CamaCasal", Vector3(2, 0, 1.6), 0],
		["BedsideTable_01", "CriadoCasal", Vector3(3.6, 0, 0.6), 0],
		["Wardrobe_01", "GuardaRoupaCasal", Vector3(0.6, 0, 4.1), 90],
		["Rug_02", "TapeteCasal", Vector3(2.7, 0, 3.8), 0],
		["Bed_Single_01", "CamaSolteiro", Vector3(1.5, 0, 6.15), 90],
		["BedsideTable_01", "CriadoSolteiro", Vector3(0.55, 0, 7.23), 0],
		["Bookshelf_01", "EstanteQuarto", Vector3(3.5, 0, 7.1), 180],
		["Bath_01", "Banheira", Vector3(6.3, 0, 0.7), 0],
		["Toilet_01", "Vaso", Vector3(5.45, 0, 1.9), -90],
		["BathroomSink_01", "PiaBanheiro", Vector3(7.2, 0.95, 1.85), 90],
		["Kitchen_CounterSink_01", "Bancada", Vector3(7.5, 0, 8.9), -90],
		["Kitchen_Fridge_01", "Geladeira", Vector3(6.95, 0, 7.4), 180],
		["Microwave_01", "Microondas", Vector3(7, 0.95, 8.2), -90],
		["Couch_01", "Sofa", Vector3(0.7, 0, 11.1), 90],
		["CoffeeTable_01", "MesaCentro", Vector3(2.25, 0, 11.1), 90],
		["Rug_01", "TapeteSala", Vector3(2.25, 0, 11.1), 0],
		["TVCabinet_01", "Rack", Vector3(4.35, 0, 10.95), -90],
		["DiningTable_01", "MesaJantar", Vector3(2.6, 0, 8.75), 0],
		["DiningChair_01", "CadeiraOeste", Vector3(1.3, 0, 8.75), 90],
		["DiningChair_01", "CadeiraLeste", Vector3(3.9, 0, 8.75), -90],
		["LampStanding_01", "Abajur", Vector3(0.45, 0, 9.8), 0],
		["PotPlant_01", "Planta", Vector3(7.1, 0, 11.9), 0],
	]:
		_add(room, PROP % ("SM_Prop_" + String(item[0])), item[1], item[2], float(item[3]))
	(room.get_node("Banheira") as Node3D).scale.x = 0.88


func _build_lights() -> void:
	var lights: Node3D = _group(_house, "Luzes", _house)
	lights.set_script(load("res://scripts/house_lights.gd"))
	lights.set("flicker_amount", 0.0)
	for spot: Array in [
		["Casal", Vector3(2.5, 2.9, 2.5)], ["Solteiro", Vector3(2.5, 2.9, 6.25)],
		["Banheiro", Vector3(6.25, 2.9, 1.25)], ["Corredor", Vector3(6.25, 2.9, 5)],
		["Cozinha", Vector3(6.25, 2.9, 8.75)], ["Sala", Vector3(2.5, 2.9, 10.5)],
	]:
		var fixture: Node3D = _add(lights, PROP % "SM_Prop_CeilingLight_02", "Luz" + String(spot[0]), spot[1])
		var bulb: OmniLight3D = OmniLight3D.new()
		bulb.name = "Omni"
		bulb.position.y = -0.27
		bulb.light_color = Color(1, 0.9, 0.78)
		bulb.light_energy = 0.8
		bulb.omni_range = 4.0
		bulb.shadow_enabled = true
		bulb.set_meta("room_lighting", true)
		fixture.add_child(bulb)
		bulb.owner = _house


func _build_activities() -> void:
	var points: Node3D = _group(_house, "Atividades", _house)
	for point: Array in [
		["Cama", Vector3(3.6, 0, 2.1), "home", -90],
		["CamaSolteiro", Vector3(3.6, 0, 6.2), "home", -90],
		["Sofa", Vector3(2.9, 0, 10.1), "observe", -90],
		["Cozinha", Vector3(6, 0, 8.9), "work", 90],
		["MesaJantar", Vector3(2.6, 0, 9.6), "wait", 180],
		["Varanda", Vector3(3.5, 0, 13.9), "observe", 0],
	]:
		var activity: Marker3D = Marker3D.new()
		activity.set_script(load("res://scripts/npc/npc_activity.gd"))
		activity.name = point[0]
		activity.position = point[1]
		activity.set("activity", StringName(point[2]))
		activity.rotation.y = deg_to_rad(float(point[3]))
		points.add_child(activity)
		activity.owner = _house


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
	leaf.set("starts_locked", false)
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
