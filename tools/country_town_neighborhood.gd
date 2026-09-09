extends RefCounted
## Receita de lotes em metros, assada pelo settlement. Frente local = -Z.
const TOWN: String = "res://PolygonTown/Prefabs/"
const LOTS: Array[Array] = [
	# numero, centro X/Z, frente Y, largura, profundidade, preset, escala
	[101, 386, 148, 180, 24, 24, 3, 1.08],
	[103, 413, 148, 180, 24, 24, 6, 1.12],
	[105, 440, 148, 180, 24, 24, 9, 1.18],
	[102, 385, 185, 90, 22, 22, 5, 1.08],
	[104, 385, 258, 90, 22, 22, 9, 1.12],
	[106, 385, 282, 90, 22, 22, 10, 1.08],
	[201, 439.5, 188, -90, 26, 16, 10, 1.0],
	# Lote 202 reservado à House01 habitável, instanciada em TownDistrict.
	[204, 497, 189, -90, 26, 22, 6, 1.08],
	[206, 534.5, 189, -90, 26, 23, 7, 1.08],
	[203, 436, 259, -90, 24, 24, 4, 1.08],
	[208, 474, 259, 90, 24, 22, 9, 1.15],
	[210, 497, 259, -90, 24, 22, 5, 1.08],
	[212, 534.5, 259, -90, 24, 23, 6, 1.1],
	[301, 436, 318, -90, 20, 24, 9, 1.12],
	[303, 436, 341, -90, 20, 24, 5, 1.08],
	[302, 474, 318, 90, 24, 22, 4, 1.08],
	[304, 497, 318, -90, 24, 22, 6, 1.08],
	[306, 474, 342, 90, 18, 22, 9, 1.1],
	[308, 497, 342, -90, 18, 22, 5, 1.08],
	[305, 385, 338, 180, 24, 26, 7, 1.12],
	[307, 411.5, 338, 180, 23, 26, 3, 1.12],
]

var failed: bool = false
var _terrain: Terrain3D
var _materials: Dictionary[String, StandardMaterial3D] = {}
var _batches: Dictionary[String, SurfaceTool] = {}


func build(terrain: Terrain3D) -> Node3D:
	_terrain = terrain
	var town: Node3D = Node3D.new()
	town.name = "UrbanInfill"
	town.set_meta("country_town_composition", true)
	for recipe: Array in LOTS:
		_build_home(town, recipe)
	_build_shop(town, "Padaria", Vector2(439, 223), -90, 1)
	_build_shop(town, "Mercearia", Vector2(498, 225), 0, 1)
	_build_shop(town, "Cafe", Vector2(535, 225), 0, 2)
	var forecourt: Node3D = Node3D.new()
	forecourt.name = "ChurchForecourt"
	forecourt.position = Vector3(532, _height(Vector3(532, 0, 289)), 289)
	town.add_child(forecourt)
	_box(forecourt, "Paving", Vector3(16, 0.08, 7), Vector3(0, 0.04, 0), "Paving", Color(0.43, 0.42, 0.37))
	for x: float in [-6.0, 6.0]:
		_asset(forecourt, "Props/SM_Prop_ParkBench_01", "ChurchBench", Vector3(x, 0.08, -2.5), 180)
	_flush(forecourt)
	print("Bairro: %d casas com lotes, 3 comercios e vagas privadas." % LOTS.size())
	return town


func _height(point: Vector3) -> float:
	var value: float = _terrain.data.get_height(point)
	if is_nan(value):
		failed = true
		push_error("Lote fora do terreno: %s" % point)
		return 6.0
	return value


func _material(key: String, color: Color) -> StandardMaterial3D:
	if not _materials.has(key):
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.95
		_materials[key] = material
	return _materials[key]


## Primitivas estaticas agrupadas por material por lote, sem um draw por ripa.
func _box(parent: Node3D, label: String, size: Vector3, point: Vector3, key: String, color: Color, solid: bool = false) -> void:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	if not _batches.has(key):
		var surface: SurfaceTool = SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batches[key] = surface
	_material(key, color)
	_batches[key].append_from(mesh, 0, Transform3D(Basis.IDENTITY, point))
	if solid:
		var body: StaticBody3D = StaticBody3D.new()
		body.name = label
		body.set_meta("country_town_block", true)
		var collider: CollisionShape3D = CollisionShape3D.new()
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = size
		collider.shape = shape
		collider.position = point
		body.add_child(collider)
		parent.add_child(body)


func _flush(parent: Node3D) -> void:
	for key: String in _batches:
		var visual: MeshInstance3D = MeshInstance3D.new()
		visual.name = key
		visual.mesh = _batches[key].commit()
		visual.material_override = _materials[key]
		visual.layers = 512
		visual.visibility_range_end = 190.0
		visual.visibility_range_end_margin = 20.0
		parent.add_child(visual)
	_batches.clear()


func _asset(parent: Node3D, path: String, label: String, point: Vector3, yaw: float = 0.0, scale_factor: float = 1.0) -> Node3D:
	var packed: PackedScene = load(TOWN + path + ".tscn") as PackedScene
	if packed == null:
		failed = true
		push_error("Asset de bairro ausente: %s" % path)
		return null
	var node: Node3D = packed.instantiate() as Node3D
	node.scene_file_path = ""
	node.set_meta("source_scene", TOWN + path + ".tscn")
	node.name = label
	node.position = point
	node.rotation_degrees.y = yaw
	node.scale = Vector3.ONE * scale_factor
	node.set_meta("country_town_block", true)
	parent.add_child(node)
	_set_ranges(node, 150.0, 512)
	return node


func _parked_collision(car: Node3D) -> void:
	# Rodas, volante e vidro nao precisam de corpos separados num carro cenario.
	for node: Node in car.find_children("*", "StaticBody3D", true, false):
		node.free()
	var mesh_node: MeshInstance3D = car as MeshInstance3D
	var bounds: AABB = mesh_node.mesh.get_aabb()
	var body: StaticBody3D = StaticBody3D.new()
	var collider: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(bounds.size.x * 0.94, bounds.size.y, bounds.size.z * 0.95)
	collider.shape = shape
	collider.position = Vector3(bounds.get_center().x, bounds.size.y * 0.5, bounds.get_center().z)
	body.add_child(collider)
	car.add_child(body)


func _set_ranges(node: Node, distance: float, layer: int) -> void:
	if node is GeometryInstance3D:
		var visual: GeometryInstance3D = node as GeometryInstance3D
		visual.visibility_range_end = distance
		visual.visibility_range_end_margin = 15.0
		visual.layers = layer
		visual.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	for child: Node in node.get_children():
		_set_ranges(child, distance, layer)


func _marker(parent: Node3D, label: String, point: Vector3) -> Marker3D:
	var marker: Marker3D = Marker3D.new()
	marker.name = label
	marker.position = point
	parent.add_child(marker)
	return marker


func _fence(parent: Node3D, start: Vector2, end: Vector2, color: Color, key: String) -> void:
	var length: float = start.distance_to(end)
	if length < 0.1:
		return
	var along_x: bool = absf(end.x - start.x) > absf(end.y - start.y)
	var center: Vector2 = (start + end) * 0.5
	var span: Vector3 = Vector3(length, 0.1, 0.09) if along_x else Vector3(0.09, 0.1, length)
	for y: float in [0.32, 0.78]:
		_box(parent, "Rail", span, Vector3(center.x, y, center.y), key, color)
	var posts: int = maxi(1, ceili(length / 2.5))
	for i: int in posts + 1:
		var p: Vector2 = start.lerp(end, float(i) / posts)
		_box(parent, "Post", Vector3(0.16, 1.12, 0.16), Vector3(p.x, 0.55, p.y), key, color)
	var slats: int = maxi(1, ceili(length / 0.28))
	for i: int in slats:
		var p: Vector2 = start.lerp(end, (float(i) + 0.5) / slats)
		_box(parent, "Picket", Vector3(0.11, 0.85, 0.08) if along_x else Vector3(0.08, 0.85, 0.11), Vector3(p.x, 0.52, p.y), key, color)
	# Uma colisao por trecho, independente do numero de ripas.
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "FenceCollision"
	body.set_meta("country_town_block", true)
	var collider: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(length, 1.1, 0.12) if along_x else Vector3(0.12, 1.1, length)
	collider.shape = shape
	collider.position = Vector3(center.x, 0.55, center.y)
	body.add_child(collider)
	parent.add_child(body)


func _build_home(town: Node3D, recipe: Array) -> void:
	var number: int = recipe[0]
	var width: float = recipe[4]
	var depth: float = recipe[5]
	var lot: Node3D = Node3D.new()
	lot.name = "Casa%d" % number
	lot.set_meta("country_town_composition", true)
	lot.set_meta("lot_size", Vector2(width, depth))
	lot.position = Vector3(recipe[1], 0, recipe[2])
	lot.position.y = _height(lot.position)
	lot.rotation_degrees.y = recipe[3]
	town.add_child(lot)
	var front: float = -depth * 0.5
	var back: float = depth * 0.5
	var drive_x: float = width * 0.5 - 2.7
	var house: MeshInstance3D = _asset(lot, "Buildings/Presets/SM_Bld_House_Preset_%02d" % int(recipe[6]), "House", Vector3.ZERO, 0, recipe[7]) as MeshInstance3D
	if house == null:
		return
	var bounds: AABB = house.mesh.get_aabb()
	var house_size: Vector3 = bounds.size * float(recipe[7])
	var house_x: float = -width * 0.5 + 1.0 + house_size.x * 0.5
	var house_front: float = front + 5.0
	house.position = Vector3(house_x - bounds.get_center().x * float(recipe[7]), 0.06 - bounds.position.y * float(recipe[7]), house_front - bounds.position.z * float(recipe[7]))
	_set_ranges(house, 650.0, 128)
	if house_size.x > width - 6.5 or house_size.z > depth - 6.4:
		failed = true
		push_error("Casa %d nao cabe no lote: %s" % [number, house_size])
	var entry_x: float = house_x
	var concrete: Color = Color(0.43, 0.42, 0.37)
	var gravel: Color = Color(0.32, 0.29, 0.24)
	var wood: Color = Color(0.68, 0.66, 0.54) if number % 3 == 0 else Color(0.34, 0.25, 0.16)
	var fence_key: String = "PaleFence" if number % 3 == 0 else "WoodFence"
	_box(lot, "Driveway", Vector3(3.6, 0.08, depth - 2), Vector3(drive_x, 0.025, -0.7), "Gravel", gravel)
	_box(lot, "EntrancePath", Vector3(1.8, 0.08, 5.6), Vector3(entry_x, 0.035, front + 2.2), "Paving", concrete)
	_box(lot, "Porch", Vector3(house_size.x - 0.6, 0.1, 1.8), Vector3(house_x, 0.04, house_front - 0.6), "Paving", concrete)
	_box(lot, "BackPatio", Vector3(width - 2, 0.08, 1.6), Vector3(0, 0.025, back - 1.2), "Paving", concrete)
	# Caminho e entrada da garagem continuam ate a calcada, fora da cerca.
	_box(lot, "DriveApron", Vector3(3.6, 0.08, 1.4), Vector3(drive_x, 0.035, front - 0.6), "Paving", concrete)
	_box(lot, "WalkApron", Vector3(1.8, 0.08, 1.4), Vector3(entry_x, 0.035, front - 0.6), "Paving", concrete)
	_fence(lot, Vector2(-width / 2, front), Vector2(-width / 2, back), wood, fence_key)
	_fence(lot, Vector2(width / 2, front), Vector2(width / 2, back), wood, fence_key)
	_fence(lot, Vector2(-width / 2, back), Vector2(width / 2, back), wood, fence_key)
	_fence(lot, Vector2(-width / 2, front), Vector2(entry_x - 1.0, front), wood, fence_key)
	_fence(lot, Vector2(entry_x + 1.0, front), Vector2(drive_x - 1.9, front), wood, fence_key)
	_fence(lot, Vector2(drive_x + 1.9, front), Vector2(width / 2, front), wood, fence_key)
	# Folhas abertas para dentro: vao livre de 2 m a pe e 3,8 m para o carro.
	_fence(lot, Vector2(entry_x - 1.0, front), Vector2(entry_x - 1.0, front + 1.75), wood, fence_key)
	_fence(lot, Vector2(drive_x - 1.9, front), Vector2(drive_x - 1.9, front + 1.7), wood, fence_key)
	_fence(lot, Vector2(drive_x + 1.9, front), Vector2(drive_x + 1.9, front + 1.7), wood, fence_key)
	_asset(lot, "Props/SM_Prop_LetterBox_01", "Mailbox", Vector3(entry_x + 1.3, 0.06, front + 0.3))
	_asset(lot, "Props/SM_Prop_RubbishBin_01", "CollectionBin", Vector3(drive_x - 2.5, 0.06, front + 0.7))
	for x: float in [entry_x - 1.4, entry_x + 1.4]:
		_asset(lot, "Props/SM_Prop_PotPlant_04", "PorchPlant", Vector3(x, 0.08, house_front - 1.0), number, 1.7)
	var garden_x: float = -width * 0.5 + 1.5
	_box(lot, "FlowerBed", Vector3(1.4, 0.12, 2.8), Vector3(garden_x, 0.06, front + 2.6), "GardenSoil", Color(0.18, 0.125, 0.075))
	for z: float in [front + 1.8, front + 2.6, front + 3.4]:
		_asset(lot, "Props/SM_Prop_PotPlant_04", "GardenPlant", Vector3(garden_x, 0.12, z), number * 13, 1.35)
	if number % 4 != 0:
		var car: Node3D = _asset(lot, "Vehicles/SM_Veh_Pickup_01" if number % 3 == 0 else "Vehicles/SM_Veh_Convertable_01", "ParkedCar", Vector3(drive_x, 0.08, front + 6.5), 180 if number % 2 == 0 else 0)
		if car != null:
			_set_ranges(car, 230.0, 8)
			_parked_collision(car)
	else:
		_box(lot, "WheelStop", Vector3(1.8, 0.13, 0.2), Vector3(drive_x, 0.09, front + 9), "Paving", concrete)
	if number % 2 == 0:
		_asset(lot, "Props/SM_Prop_ParkBench_01", "PorchBench", Vector3(house_x + 2.5, 0.1, house_front - 0.8))
	else:
		_asset(lot, "Props/SM_Prop_Barbeque_01", "FamilyBarbeque", Vector3(drive_x, 0.06, back - 1.3))
	_marker(lot, "PedestrianGate", Vector3(entry_x, 0.1, front))
	_marker(lot, "VehicleGate", Vector3(drive_x, 0.1, front))
	_marker(lot, "ParkingSpace", Vector3(drive_x, 0.1, front + 6.5))
	_marker(lot, "Entrance", Vector3(entry_x, 0.15, house_front - 0.9))
	var interior: Marker3D = _marker(lot, "FutureInterior", house.position + Vector3(0, 0.1, 0))
	interior.set_meta("available_footprint", Vector2(house_size.x - 1.0, house_size.z - 1.0))
	interior.set_meta("floor_height", 2.8)
	var address: Label3D = Label3D.new()
	address.name = "HouseNumber"
	address.text = str(number)
	address.font_size = 48
	address.pixel_size = 0.007
	address.position = Vector3(entry_x + 1.35, 1.15, front - 0.08)
	address.rotation.y = PI
	address.modulate = Color(0.9, 0.86, 0.69)
	address.no_depth_test = false
	address.visibility_range_end = 40.0
	lot.add_child(address)
	_flush(lot)


func _build_shop(town: Node3D, title: String, point: Vector2, yaw: float, preset: int) -> void:
	var shop: Node3D = Node3D.new()
	shop.name = title
	shop.set_meta("country_town_composition", true)
	shop.position = Vector3(point.x, _height(Vector3(point.x, 0, point.y)), point.y)
	shop.rotation_degrees.y = yaw
	town.add_child(shop)
	var building: MeshInstance3D = _asset(shop, "Buildings/SM_Bld_Shop_%02d" % preset, "Shop", Vector3.ZERO) as MeshInstance3D
	if building == null:
		return
	_set_ranges(building, 600.0, 128)
	var bounds: AABB = building.mesh.get_aabb()
	var front: float = bounds.position.z
	# Toldos e tabuleiros ficam junto a fachada, sem fechar a calcada.
	_box(shop, "Awning", Vector3(6, 0.12, 1.1), Vector3(0, 2.7, front - 0.3), "Canvas", Color(0.34, 0.43, 0.28))
	var sign: Label3D = Label3D.new()
	sign.name = "ShopSign"
	sign.text = title.to_upper()
	sign.position = Vector3(0, 3.35, front - 0.08)
	sign.rotation.y = PI
	sign.font_size = 64
	sign.pixel_size = 0.009
	sign.modulate = Color(0.95, 0.88, 0.65)
	sign.visibility_range_end = 100.0
	shop.add_child(sign)
	_asset(shop, "Props/SM_Prop_PotPlant_04", "DoorPlant", Vector3(-3.8, 0.04, front - 0.3), 0, 1.8)
	_marker(shop, "Entrance", Vector3(0, 0.1, front - 0.2))
	_flush(shop)
