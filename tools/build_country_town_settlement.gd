@tool
extends SceneTree

## Composicao deterministica com assets locais. Gera cenas editaveis; nenhum
## gerador roda durante a partida. Pode rodar headless (nao usa MultiMesh).
## Rode apos o terreno e antes dos campos/vegetacao. Nao sobrescreve distritos
## manuais: os complementos e seus blocos sao as saidas deste script.
const Layout: GDScript = preload("res://tools/build_country_town_layout.gd")
const BASE: String = "res://scenes/CountryTown/"
const FARM: String = "res://PolygonFarm/Models/"
const TOWN: String = "res://PolygonTown/Prefabs/"
const FARM_MATERIAL: String = "res://Materiais/PolygonFarm1A.tres"
## Cercas de talhao: o modulo do PolygonFarm mede ~2,5 m e e distribuido nos
## trechos livres de cada lado. A entrada larga deixa passar um trator; a
## estreita, so quem vai a pe.
const FENCE_GATE_WIDE: float = 5.0
const FENCE_GATE_WIDE_SIDE: float = 20.0
const FENCE_GATE_NARROW: float = 2.5
const FENCE_GATE_NARROW_SIDE: float = 10.0
## Trecho menor que isto nao vira cerca: sairia um modulo esmagado.
const FENCE_MIN_RUN: float = 0.8
## Quanto a base afunda no terreno, para nao abrir fresta na encosta.
const FENCE_SINK: float = 0.06
## Recuos de um metro testados quando o lado cai sobre estrada, rio ou predio.
const FENCE_SETBACK_STEPS: int = 7
const LOTS: Array[Array] = [
	# nome, preset (H=casa, S=loja), X, Z, rotacao Y
	["Bakery", "S01", 436, 179, -90],
	["MarketHouse", "H04", 475, 184, 90],
	["CornerHouse", "H07", 535, 185, 90],
	["ProduceShop", "S01", 494, 225, 0],
	["EastCottage", "H02", 535, 225, -90],
	["GardenHouse", "H06", 535, 256, 90],
	["SquareCottage", "H01", 476, 256, -90],
	["RiversideHouse", "H01", 388, 193, -90],
	["WestCottage", "H02", 388, 280, 0],
	["ChurchLaneHouse", "H07", 436, 285, -90],
	["SouthTownHouse", "H10", 436, 321, -90],
	["SouthCornerShop", "S03", 476, 313, 90],
	["SouthGardenHouse", "H04", 476, 337, -90],
	["EastFarmhouse", "H02", 540, 328, 0],
]

var _terrain: Terrain3D
var _failed: bool = false
var _serial: int = 0
var _meshes: Dictionary[String, Mesh] = {}
var _occupied: Array[Rect2] = []
var _frontage_count: int = 0
var _fence_posts: Array[Vector2] = []


func _process(_delta: float) -> bool:
	_terrain = Terrain3D.new()
	root.add_child(_terrain)
	_terrain.data_directory = BASE + "Terrain"
	if _terrain.data.get_region_count() == 0:
		push_error("Terreno ausente: gere o terreno antes do settlement.")
		quit(1)
		return true
	# Alguns assets antigos eram usados como Mesh, mas sao importados como
	# PackedScene. Extraimos uma malha local sem alterar os imports compartilhados.
	DirAccess.make_dir_recursive_absolute(BASE + "Blocks/Meshes")
	for model: String in ["SM_Bld_Shelter_01", "SM_Prop_Trough_01", "SM_Bld_Greenhouse_01", "SM_Bld_ProduceStand_01", "SM_Bld_Outhouse_01"]:
		_farm_mesh(model)
	var silo: Node3D = _group("FarmSilo")
	var silo_mesh: MeshInstance3D = _prop(silo, "SM_Bld_Silo_02", Vector3.ZERO)
	if silo_mesh != null:
		silo_mesh.layers = 128
		silo_mesh.visibility_range_end = 420.0
	_save(silo, "Blocks/FarmSilo.tscn")
	_build_grain_mill()
	_build_dock_shelter()
	_build_cargo()
	_build_workyard()
	_build_town()
	_build_rural()
	_build_paths()
	_build_wreck()
	quit(1 if _failed else 0)
	return true


func _group(label: String, parent: Node = null) -> Node3D:
	var node: Node3D = Node3D.new()
	node.name = label
	if parent != null:
		parent.add_child(node)
	return node


func _height(point: Vector2) -> float:
	var height: float = _terrain.data.get_height(Vector3(point.x, 0, point.y))
	if is_nan(height):
		_failed = true
		push_error("Settlement fora do terreno: %s" % point)
		return Layout.GROUND_HEIGHT
	return height


func _instance(parent: Node, path: String, label: String, point: Vector3, yaw: float = 0.0) -> Node3D:
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		_failed = true
		push_error("Asset ausente: %s" % path)
		return null
	var node: Node3D = scene.instantiate() as Node3D
	node.name = label
	node.set_meta("country_town_block", true)
	node.position = point
	node.rotation.y = deg_to_rad(yaw)
	parent.add_child(node)
	return node


func _at(parent: Node, path: String, label: String, point: Vector2, yaw: float = 0.0) -> Node3D:
	return _instance(parent, path, label, Vector3(point.x, _height(point), point.y), yaw)


## Os FBX do PolygonFarm sao importados como ArrayMesh neste projeto.
## AABB posiciona a base da peca; colisao simples so nos objetos de obstaculo.
func _prop(parent: Node, model: String, point: Vector3, yaw: float = 0.0, solid: bool = true) -> MeshInstance3D:
	var mesh: Mesh = _farm_mesh(model)
	if mesh == null:
		_failed = true
		push_error("Malha ausente: %s" % model)
		return null
	var node: MeshInstance3D = MeshInstance3D.new()
	_serial += 1
	node.name = model.trim_prefix("SM_") + str(_serial)
	node.mesh = mesh
	node.set_meta("country_town_block", true)
	node.material_override = load(FARM_MATERIAL) as Material
	node.layers = 512
	node.position = point
	node.rotation.y = deg_to_rad(yaw)
	var bounds: AABB = mesh.get_aabb()
	node.position.y -= bounds.position.y
	# Volumes rurais precisam participar da paisagem, inclusive vistos de longe.
	node.visibility_range_end = 650.0 if bounds.size.length() > 3.0 else 230.0
	node.visibility_range_end_margin = 30.0
	parent.add_child(node)
	if solid:
		var body: StaticBody3D = StaticBody3D.new()
		var shape: CollisionShape3D = CollisionShape3D.new()
		var box: BoxShape3D = BoxShape3D.new()
		box.size = bounds.size
		shape.shape = box
		shape.position = bounds.get_center()
		body.add_child(shape)
		node.add_child(body)
	return node


func _farm_mesh(model: String) -> Mesh:
	if _meshes.has(model):
		return _meshes[model]
	var resource: Resource = load(FARM + model + ".fbx")
	if resource is Mesh:
		_meshes[model] = resource as Mesh
	elif resource is PackedScene:
		var source: Node = (resource as PackedScene).instantiate()
		var surface: SurfaceTool = SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		_append_meshes(source, Transform3D.IDENTITY, surface)
		var mesh: ArrayMesh = surface.commit()
		source.free()
		var path: String = BASE + "Blocks/Meshes/" + model + ".res"
		if mesh == null or ResourceSaver.save(mesh, path) != OK:
			_failed = true
			return null
		mesh.take_over_path(path)
		_meshes[model] = mesh
	return _meshes.get(model) as Mesh


func _append_meshes(node: Node, parent_transform: Transform3D, surface: SurfaceTool) -> void:
	var transform: Transform3D = parent_transform
	if node is Node3D:
		transform *= (node as Node3D).transform
	if node is MeshInstance3D:
		var mesh_node: MeshInstance3D = node as MeshInstance3D
		if mesh_node.mesh != null and mesh_node.visible:
			for index: int in mesh_node.mesh.get_surface_count():
				surface.append_from(mesh_node.mesh, index, transform)
	for child: Node in node.get_children():
		_append_meshes(child, transform, surface)


func _build_cargo() -> void:
	var cargo: Node3D = _group("CargoStack")
	_prop(cargo, "SM_Prop_Barrel_01", Vector3(-1.2, 0, 0))
	_prop(cargo, "SM_Prop_Box_Apple_01", Vector3(0.3, 0, 0.1), 12)
	_prop(cargo, "SM_Prop_Box_Potato_01", Vector3(1.1, 0, 0), -8)
	_prop(cargo, "SM_Prop_Box_Apple_02", Vector3(0.4, 0.6, 0.1), -4, false)
	_save(cargo, "Blocks/CargoStack.tscn")


## Marco do moinho de graos: corpo largo e quatro velas, como na referencia.
## Primitivas locais, porta Synty e AnimationPlayer nativo; sem script por frame.
func _build_grain_mill() -> void:
	var mill: Node3D = _group("GrainMill")
	mill.set_meta("country_town_block", true)
	var stone: StandardMaterial3D = StandardMaterial3D.new()
	stone.albedo_color = Color(0.38, 0.32, 0.22)
	stone.roughness = 1.0
	var wood: StandardMaterial3D = StandardMaterial3D.new()
	wood.albedo_color = Color(0.19, 0.12, 0.065)
	wood.roughness = 1.0
	var cloth: StandardMaterial3D = StandardMaterial3D.new()
	cloth.albedo_color = Color(0.61, 0.55, 0.38)
	cloth.roughness = 1.0
	var tower: CylinderMesh = CylinderMesh.new()
	tower.bottom_radius = 3.8
	tower.top_radius = 2.6
	tower.height = 9.0
	tower.radial_segments = 16
	_primitive(mill, "StoneTower", tower, Vector3(0, 4.5, 0), stone)
	var roof: CylinderMesh = CylinderMesh.new()
	roof.bottom_radius = 3.2
	roof.top_radius = 0.0
	roof.height = 3.0
	roof.radial_segments = 16
	_primitive(mill, "TimberRoof", roof, Vector3(0, 10.5, 0), wood)
	for level: int in 3:
		var ring: CylinderMesh = CylinderMesh.new()
		ring.bottom_radius = 3.85 - level * 0.40
		ring.top_radius = ring.bottom_radius
		ring.height = 0.22
		ring.radial_segments = 16
		_primitive(mill, "TimberBand%d" % level, ring, Vector3(0, 0.6 + level * 3.0, 0), wood)
	_instance(mill, TOWN + "Buildings/SM_Bld_House_Door_01.tscn", "MillDoor", Vector3(0, 0, -3.8))
	var rotor: Node3D = _group("Rotor", mill)
	rotor.position = Vector3(0, 8.0, -3.85)
	for index: int in 4:
		var sail: Node3D = _group("Sail%d" % index, rotor)
		sail.rotation.z = index * PI * 0.5
		var spar: BoxMesh = BoxMesh.new()
		spar.size = Vector3(0.20, 6.2, 0.22)
		_primitive(sail, "Spar", spar, Vector3(0, 2.8, 0), wood)
		for rib: int in 7:
			var panel: BoxMesh = BoxMesh.new()
			panel.size = Vector3(1.6, 0.44, 0.06)
			_primitive(sail, "Canvas%d" % rib, panel, Vector3(0.7, 2.2 + rib * 0.53, -0.15), cloth)
	var body: StaticBody3D = StaticBody3D.new()
	var collider: CollisionShape3D = CollisionShape3D.new()
	var cylinder: CylinderShape3D = CylinderShape3D.new()
	cylinder.radius = 3.8
	cylinder.height = 9.0
	collider.shape = cylinder
	collider.position.y = 4.5
	body.add_child(collider)
	mill.add_child(body)
	var animation: Animation = Animation.new()
	animation.length = 42.0
	animation.loop_mode = Animation.LOOP_LINEAR
	var track: int = animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, NodePath("Rotor:rotation"))
	animation.track_insert_key(track, 0.0, Vector3(0, 0, 0))
	animation.track_insert_key(track, 42.0, Vector3(0, 0, TAU))
	var library: AnimationLibrary = AnimationLibrary.new()
	library.add_animation("turn", animation)
	var player: AnimationPlayer = AnimationPlayer.new()
	player.name = "SailsAnimation"
	player.add_animation_library("", library)
	player.autoplay = "turn"
	mill.add_child(player)
	_save(mill, "Blocks/GrainMill.tscn")


func _primitive(parent: Node, label: String, mesh: Mesh, point: Vector3, material: Material) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	node.position = point
	node.material_override = material
	node.layers = 128
	parent.add_child(node)
	return node


func _build_dock_shelter() -> void:
	var shelter: Node3D = _group("DockShelter")
	var timber: StandardMaterial3D = StandardMaterial3D.new()
	timber.albedo_color = Color(0.23, 0.16, 0.10)
	timber.roughness = 1.0
	var roof: PrismMesh = PrismMesh.new()
	roof.size = Vector3(4.8, 1.7, 5.5)
	_primitive(shelter, "GabledRoof", roof, Vector3(0, 3.8, 2.5), timber)
	for x: float in [-1.8, 1.8]:
		for z: float in [0.3, 4.7]:
			var post: BoxMesh = BoxMesh.new()
			post.size = Vector3(0.18, 3.1, 0.18)
			_primitive(shelter, "Post%d" % shelter.get_child_count(), post, Vector3(x, 1.55, z), timber)
	_save(shelter, "Blocks/DockShelter.tscn")


func _build_workyard() -> void:
	var yard: Node3D = _group("RuralWorkyard")
	_prop(yard, "SM_Bld_Shelter_01", Vector3(0, 0, 1), 90)
	_prop(yard, "SM_Prop_Hay_Bale_Round_01", Vector3(-4, 0, 2), 15)
	_prop(yard, "SM_Prop_Hay_Bale_Square_01", Vector3(-4, 0, 0), -5)
	_prop(yard, "SM_Prop_Wheelbarrow_01", Vector3(4, 0, 1), 35)
	_prop(yard, "SM_Prop_Trough_01", Vector3(3, 0, 3), 90)
	_instance(yard, BASE + "Blocks/CargoStack.tscn", "Supplies", Vector3(4, 0, -2))
	# Costas cercadas; frente e laterais abertas para o jogador atravessar.
	for x: int in 4:
		_instance(yard, TOWN + "Environment/SM_Env_Fence_White_Straight_01.tscn",
			"BackFence%d" % x, Vector3(-5 + x * 2.5, 0, 5))
	for x: float in [-5.0, 5.0]:
		_instance(yard, TOWN + "Environment/SM_Env_Fence_White_Post_01.tscn",
			"BackFencePost%d" % yard.get_child_count(), Vector3(x, 0, 5))
	_save(yard, "Blocks/RuralWorkyard.tscn")


func _build_town() -> void:
	var town: Node3D = _group("UrbanInfill")
	town.set_meta("country_town_composition", true)
	for lot: Array in LOTS:
		var code: String = lot[1]
		var asset: String = "Buildings/Presets/SM_Bld_House_Preset_%s.tscn" % code.substr(1)
		if code.begins_with("S"):
			asset = "Buildings/SM_Bld_Shop_%s.tscn" % code.substr(1)
		var building: Node3D = _at(town, TOWN + asset, lot[0], Vector2(lot[2], lot[3]), lot[4])
		if building is MeshInstance3D:
			(building as MeshInstance3D).layers = 128
	for point: Vector2 in [Vector2(501, 219), Vector2(434, 175), Vector2(486, 316), Vector2(505, 262)]:
		_at(town, BASE + "Blocks/CargoStack.tscn", "ShopCargo%d" % town.get_child_count(), point, 90)
	# Calçadas continuas nos dois lados da avenida e das ruas locais.
	# Sidewalks are baked with RoadNetwork, including junction cutouts.
	_strip(town, "ChurchForecourt", [Vector2(524, 289), Vector2(540, 289)], 7.0, Color(0.38, 0.37, 0.32), 0.08)
	for point: Vector2 in [Vector2(482, 231), Vector2(526, 285), Vector2(540, 285)]:
		_at(town, TOWN + "Props/SM_Prop_ParkBench_01.tscn", "Bench%d" % town.get_child_count(), point, 180)
	# Pequenos quintais nas bordas: deixam o centro compacto e a periferia rural.
	for point: Vector2 in [Vector2(540, 198), Vector2(540, 266), Vector2(427, 330), Vector2(502, 342)]:
		for index: int in 3:
			_at(town, TOWN + "Environment/SM_Env_Fence_White_Straight_01.tscn", "YardFence%d" % town.get_child_count(), point + Vector2(index * 2.5, 0))
		for edge: float in [0.0, 7.5]:
			_at(town, TOWN + "Environment/SM_Env_Fence_White_Post_01.tscn", "YardPost%d" % town.get_child_count(), point + Vector2(edge, 0))
	var lights: Node3D = _group("StreetLights", town)
	lights.set_script(load("res://scripts/house_lights.gd"))
	lights.add_to_group("debug_house_lighting", true)
	lights.set("window_light_color", Color(1.0, 0.82, 0.57))
	lights.set("window_light_energy", 0.7)
	lights.set("light_range", 13.0)
	lights.set("shadow_light_indices", PackedInt32Array())
	for point: Vector2 in [Vector2(508, 174), Vector2(546, 204), Vector2(508, 232), Vector2(546, 271)]:
		_at(town, TOWN + "Props/SM_Prop_LampStanding_02.tscn", "StreetLamp%d" % town.get_child_count(), point)
		var light: OmniLight3D = OmniLight3D.new()
		light.position = Vector3(point.x, _height(point) + 1.75, point.y)
		light.light_color = Color(1.0, 0.82, 0.57)
		light.light_energy = 0.7
		light.omni_range = 13.0
		light.distance_fade_enabled = true
		light.distance_fade_begin = 100.0
		light.distance_fade_length = 20.0
		lights.add_child(light)
	_build_frontages(town)
	_save(town, "Districts/UrbanInfill.tscn")


func _build_rural() -> void:
	var rural: Node3D = _group("RuralInfill")
	rural.set_meta("country_town_composition", true)
	for point: Vector2 in [Vector2(120, 132), Vector2(222, 181), Vector2(84, 227), Vector2(118, 315), Vector2(327, 332), Vector2(540, 341)]:
		_at(rural, BASE + "Blocks/RuralWorkyard.tscn", "Workyard%d" % rural.get_child_count(), point)
		_strip(rural, "YardSoil%d" % rural.get_child_count(), [point + Vector2(-6, 0), point + Vector2(6, 0)], 9.0, Color(0.24, 0.18, 0.11), 0.04)
	# Pomar ao lado dos caminhos agricolas e horta na periferia da cidade.
	for origin: Vector2 in [Vector2(113, 183), Vector2(91, 311), Vector2(524, 350)]:
		for ix: int in 3:
			for iz: int in 2:
				var point: Vector2 = origin + Vector2(ix * 6, iz * 7)
				var tree: MeshInstance3D = _prop(rural, "SM_Env_Tree_Apple_Grown_01", Vector3(point.x, _height(point), point.y), ix * 31 + iz * 17, false)
				if tree != null:
					tree.layers = 2
					# Tronco apenas; uma caixa envolvendo a copa impediria passar embaixo.
					var body: StaticBody3D = StaticBody3D.new()
					var collider: CollisionShape3D = CollisionShape3D.new()
					var trunk: CylinderShape3D = CylinderShape3D.new()
					trunk.radius = 0.3
					trunk.height = 2.0
					collider.shape = trunk
					collider.position.y = 1.0
					body.add_child(collider)
					tree.add_child(body)
	for point: Vector2 in [Vector2(136, 130), Vector2(198, 191), Vector2(91, 234), Vector2(130, 307), Vector2(335, 340)]:
		_prop(rural, "SM_Prop_Hay_Bale_Round_02", Vector3(point.x, _height(point), point.y), 25)
	for point: Vector2 in [Vector2(128, 194), Vector2(180, 120), Vector2(103, 280)]:
		_prop(rural, "SM_Prop_Scarecrow_01", Vector3(point.x, _height(point), point.y), 20, false)
	# Silos baixos repetem a linguagem de fazenda sem competir com a igreja/moinho.
	for point: Vector2 in [Vector2(230, 189), Vector2(322, 342)]:
		_prop(rural, "SM_Bld_Silo_Small_01", Vector3(point.x, _height(point), point.y))
	# Margens em manchas, com interrupcoes nas travessias e nas trilhas.
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20260906
	for index: int in range(1, Layout.RIVER_PATH.size() - 2):
		var start: Vector2 = Layout.RIVER_PATH[index]
		var end: Vector2 = Layout.RIVER_PATH[index + 1]
		var normal: Vector2 = (end - start).normalized().orthogonal()
		var margin: float = Layout.river_width(index) * 0.5
		for step: int in 5:
			for side: float in [-1.0, 1.0]:
				var point: Vector2 = start.lerp(end, (step + 0.5) / 5.0) + normal * side * (margin + rng.randf_range(1.5, 6.0))
				if not Layout.inside_map(point) or Layout.on_secondary_path(point, 2.0) or _near_main_road(point, 10.0):
					continue
				var model: String = "SM_Env_Reeds_02" if step % 3 != 0 else "SM_Env_Pebbles_02"
				_prop(rural, model, Vector3(point.x, _height(point), point.y), rng.randf_range(0, 360), false)
	_build_estates(rural)
	_save(rural, "Districts/RuralInfill.tscn")


## Ocupacao medida a partir dos assets e das colisoes, sem assumir tamanhos.
func _reserve_shapes(node: Node, parent_transform: Transform3D = Transform3D.IDENTITY) -> void:
	var transform: Transform3D = parent_transform
	if node is Node3D:
		transform *= (node as Node3D).transform
	if node is CollisionShape3D and not node.get_parent() is Area3D:
		var collider: CollisionShape3D = node as CollisionShape3D
		if collider.shape != null and not collider.disabled:
			var bounds: AABB = transform * collider.shape.get_debug_mesh().get_aabb()
			_occupied.append(Rect2(bounds.position.x, bounds.position.z, bounds.size.x, bounds.size.z))
	for child: Node in node.get_children():
		_reserve_shapes(child, transform)


func _reserve_authored() -> void:
	_occupied.clear()
	for path: String in ["TownDistrict", "FarmDistrict", "Detailing", "NightLights", "Vegetation", "DeliveryYard"]:
		var scene: Node = (load(BASE + "Districts/" + path + ".tscn") as PackedScene).instantiate()
		# A geracao anterior nao participa das reservas da nova geracao.
		for label: String in ["UrbanInfill", "RuralInfill"]:
			var generated: Node = scene.get_node_or_null(label)
			if generated != null:
				generated.free()
		_reserve_shapes(scene)
		scene.free()
	for clearing: Rect2 in Layout.SETTLEMENT_CLEARINGS:
		_occupied.append(clearing)


func _visual_bounds(node: Node, parent_transform: Transform3D = Transform3D.IDENTITY) -> AABB:
	var transform: Transform3D = parent_transform
	if node is Node3D:
		transform *= (node as Node3D).transform
	var bounds: AABB = AABB()
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		bounds = transform * (node as MeshInstance3D).mesh.get_aabb()
	for child: Node in node.get_children():
		var child_bounds: AABB = _visual_bounds(child, transform)
		if child_bounds.size != Vector3.ZERO:
			bounds = child_bounds if bounds.size == Vector3.ZERO else bounds.merge(child_bounds)
	return bounds


func _crosses_rect(rect: Rect2, start: Vector2, end: Vector2) -> bool:
	if rect.has_point(start) or rect.has_point(end):
		return true
	var corners: Array[Vector2] = [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for index: int in 4:
		if Geometry2D.segment_intersects_segment(start, end, corners[index], corners[(index + 1) % 4]) != null:
			return true
	return false


func _free_footprint(rect: Rect2, margin: float = 0.7) -> bool:
	for occupied: Rect2 in _occupied:
		if rect.grow(margin).intersects(occupied):
			return false
	for segment: Dictionary in Layout.road_segments():
		if _crosses_rect(rect.grow(5.8), segment["start"], segment["end"]):
			return false
	for segment: Dictionary in Layout.secondary_segments():
		if _crosses_rect(rect.grow(float(segment["width"]) * 0.5 + 1.2), segment["start"], segment["end"]):
			return false
	for index: int in Layout.RIVER_PATH.size() - 1:
		if _crosses_rect(rect.grow(13.0), Layout.RIVER_PATH[index], Layout.RIVER_PATH[index + 1]):
			return false
	return true


func _build_frontages(town: Node3D) -> void:
	_reserve_authored()
	_reserve_shapes(town)
	var fronts: Node3D = _group("StreetFrontages", town)
	# As linhas seguem ruas existentes; a pegada real escolhe o que cabe.
	var rows: Array[Array] = [
		[Vector2(352, 181), Vector2(352, 284), -90],
		[Vector2(384, 179), Vector2(384, 284), 90],
		[Vector2(380, 150), Vector2(544, 150), 180],
		[Vector2(438, 176), Vector2(438, 342), -90],
		[Vector2(476, 177), Vector2(476, 340), 90],
		[Vector2(504, 179), Vector2(504, 266), -90],
		[Vector2(534, 178), Vector2(534, 267), 90],
		[Vector2(385, 344), Vector2(434, 344), 180],
		[Vector2(388, 310), Vector2(436, 310), 0],
		[Vector2(389, 263), Vector2(432, 263), 180],
	]
	for row: Array in rows:
		var start: Vector2 = row[0]
		var end: Vector2 = row[1]
		var length: float = start.distance_to(end)
		var steps: int = int(length / 4.0)
		for step: int in steps + 1:
			var point: Vector2 = start.lerp(end, float(step) / steps)
			var choices: Array[String] = ["H10", "H09", "S02", "H05", "H01", "S01", "H02"]
			for choice: int in choices.size():
				var code: String = choices[(choice + _frontage_count) % choices.size()]
				var asset: String = "Buildings/Presets/SM_Bld_House_Preset_%s.tscn" % code.substr(1)
				if code.begins_with("S"):
					asset = "Buildings/SM_Bld_Shop_%s.tscn" % code.substr(1)
				var building: Node3D = (load(TOWN + asset) as PackedScene).instantiate() as Node3D
				building.position = Vector3(point.x, _height(point), point.y)
				building.rotation_degrees.y = row[2]
				building.scale = Vector3.ONE * 1.15
				var bounds: AABB = _visual_bounds(building)
				var rect: Rect2 = Rect2(bounds.position.x, bounds.position.z, bounds.size.x, bounds.size.z)
				if not _free_footprint(rect):
					building.free()
					continue
				_frontage_count += 1
				building.name = "Frontage%02d_%s" % [_frontage_count, code]
				building.set_meta("country_town_block", true)
				if building is MeshInstance3D:
					(building as MeshInstance3D).layers = 128
				fronts.add_child(building)
				_occupied.append(rect.grow(1.2))
				# Solo ocupado: o lote deixa de parecer uma casa largada na grama.
				_strip(town, "LotGround%02d" % _frontage_count,
					[Vector2(rect.position.x - 1, rect.get_center().y), Vector2(rect.end.x + 1, rect.get_center().y)],
					rect.size.y + 2, Color(0.30, 0.255, 0.18), 0.035)
				break
	# Lotes originais tambem recebem solo de quintal e acesso visivel.
	for lot: Array in LOTS:
		var point: Vector2 = Vector2(lot[2], lot[3])
		_strip(town, "AuthoredLot" + str(lot[0]), [point - Vector2(6, 0), point + Vector2(6, 0)], 13.0, Color(0.30, 0.255, 0.18), 0.035)
	# Feira em um patio amplo ao lado da praca, com toldos e mercadoria.
	for point: Vector2 in [Vector2(487, 220), Vector2(487, 230), Vector2(505, 224)]:
		var stand: MeshInstance3D = _prop(town, "SM_Bld_ProduceStand_01", Vector3(point.x, _height(point), point.y), 90)
		if stand != null:
			stand.visibility_range_end = 500.0
	for point: Vector2 in [Vector2(398, 182), Vector2(398, 250), Vector2(482, 201), Vector2(509, 283), Vector2(525, 272)]:
		_at(town, BASE + "Blocks/CargoStack.tscn", "StreetCargo%d" % town.get_child_count(), point)
	# Fundos dos quarteiroes: anexos, pilhas de lenha e hortas cercadas.
	for point: Vector2 in [Vector2(396, 269), Vector2(493, 283), Vector2(525, 333), Vector2(415, 334)]:
		var shed: Node3D = (load(TOWN + "Buildings/SM_Bld_GardenShed_01.tscn") as PackedScene).instantiate() as Node3D
		place_if_free(town, shed, point, "BackyardShed")
	_fence_line(town, Vector2(521, 284), Vector2(546, 284))
	_fence_line(town, Vector2(546, 285), Vector2(546, 313))
	print("Composicao urbana: %d fachadas adicionais, %d construcoes com as 24 existentes" % [_frontage_count, _frontage_count + 24])


func place_if_free(parent: Node, node: Node3D, point: Vector2, label: String) -> bool:
	node.position = Vector3(point.x, _height(point), point.y)
	var bounds: AABB = _visual_bounds(node)
	var rect: Rect2 = Rect2(bounds.position.x, bounds.position.z, bounds.size.x, bounds.size.z)
	if not _free_footprint(rect):
		node.free()
		return false
	node.name = label + str(parent.get_child_count())
	node.set_meta("country_town_block", true)
	parent.add_child(node)
	_occupied.append(rect)
	return true


func _build_estates(rural: Node3D) -> void:
	# Cada plantacao agora e uma propriedade: solo trabalhado, limite, portao.
	_reserve_authored()
	_reserve_shapes(rural)
	for field: Dictionary in Layout.CROP_FIELDS:
		var rect: Rect2 = field["rect"]
		_strip(rural, String(field["name"]) + "Soil",
			[Vector2(rect.position.x, rect.get_center().y), Vector2(rect.end.x, rect.get_center().y)],
			rect.size.y, Color(0.24, 0.17, 0.085), 0.025)
		# Cerca de volta fechada, com a entrada no meio de cada lado: passagem
		# marcada por postes em vez de cerca invisivel.
		_fence_ring(rural, rect.grow(1.2))
	# Conjuntos de trabalho com volumes de tamanho real e anexos assimetricos.
	for point: Vector2 in [Vector2(264, 45), Vector2(241, 184), Vector2(86, 239), Vector2(160, 317), Vector2(321, 373)]:
		var barn: Node3D = _group("HarvestBarn")
		_prop(barn, "SM_Bld_Barn_03", Vector3.ZERO, 90)
		if place_if_free(rural, barn, point, "HarvestBarn"):
			var yard: Vector2 = point + Vector2(10, 7)
			_strip(rural, "HarvestYard%d" % rural.get_child_count(), [yard - Vector2(12, 0), yard + Vector2(12, 0)], 15.0, Color(0.26, 0.19, 0.105), 0.035)
	# Maquinas estacionadas e lenha perto dos galpoes, sem scripts de veiculo.
	for point: Vector2 in [Vector2(134, 154), Vector2(235, 155), Vector2(77, 250), Vector2(140, 326), Vector2(323, 382)]:
		var machine: Node3D = _group("ParkedTractor")
		_prop(machine, "SM_Veh_TractorOld_01", Vector3.ZERO, 25)
		place_if_free(rural, machine, point, "ParkedTractor")
	# Grupos de fardos marcam limites de propriedades e os caminhos de servico.
	for point: Vector2 in [Vector2(77, 145), Vector2(192, 150), Vector2(250, 188), Vector2(72, 218), Vector2(103, 243), Vector2(144, 304), Vector2(176, 321), Vector2(321, 363)]:
		var stack: Node3D = _group("HarvestStack")
		for index: int in 3:
			_prop(stack, "SM_Prop_Hay_Bale_Round_01", Vector3(index * 2.3, 0, 0), index * 8)
		_prop(stack, "SM_Prop_Wood_Stack_01", Vector3(1, 0, 3), 90)
		place_if_free(rural, stack, point, "HarvestStack")
	# Deposito de entrega delimitado, com alas de armazenamento e patio central.
	_strip(rural, "DeliveryCompoundSoil", [Vector2(329, 383), Vector2(391, 383)], 30.0, Color(0.28, 0.23, 0.16), 0.028)
	_fence_line(rural, Vector2(329, 400), Vector2(392, 400))
	_fence_line(rural, Vector2(392, 367), Vector2(392, 400))
	_fence_line(rural, Vector2(329, 385), Vector2(329, 400))
	for point: Vector2 in [Vector2(380, 386), Vector2(342, 393)]:
		var warehouse: Node3D = _group("DepotWing")
		_prop(warehouse, "SM_Bld_Barn_03", Vector3.ZERO)
		place_if_free(rural, warehouse, point, "DepotWing")
	# Margem superior: pedras maiores e arbustos em grupos, fora de acessos.
	for index: int in range(1, Layout.RIVER_PATH.size() - 2):
		var start: Vector2 = Layout.RIVER_PATH[index]
		var end: Vector2 = Layout.RIVER_PATH[index + 1]
		var normal: Vector2 = (end - start).normalized().orthogonal()
		var margin: float = Layout.river_width(index) * 0.5
		for step: int in 4:
			for side: float in [-1, 1]:
				var point: Vector2 = start.lerp(end, (step + 0.35) / 4.0) + normal * side * (margin + 8.5 + (step % 2) * 3.0)
				if not Layout.inside_map(point) or Layout.on_secondary_path(point, 5.0) or _near_main_road(point, 12.0):
					continue
				var rock: MeshInstance3D = _prop(rural, "SM_Generic_Small_Rocks_03", Vector3(point.x, _height(point), point.y), index * 31 + step * 59, false)
				if rock != null:
					rock.scale = Vector3.ONE * 1.8
					rock.visibility_range_end = 600


## Comprimento util do modulo de cerca, usado como passo de referencia.
func _fence_module() -> float:
	var mesh: Mesh = _farm_mesh("SM_Prop_Fence_Wood_01")
	return 0.0 if mesh == null else maxf(mesh.get_aabb().size.x, 1.0)


## Volta fechada em torno do talhao. Um lado que cai sobre estrada, rio ou
## construcao recua para dentro antes de virar cerca: o contorno continua
## fechado em vez de perder o lado inteiro e deixar o canto no ar.
func _fence_ring(parent: Node, rect: Rect2) -> void:
	var module: float = _fence_module()
	if module <= 0.0:
		return
	var north: float = rect.position.y + _fence_setback(
		Vector2(rect.position.x, rect.position.y), Vector2(rect.end.x, rect.position.y), Vector2(0.0, 1.0), module)
	var south: float = rect.end.y - _fence_setback(
		Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.end.y), Vector2(0.0, -1.0), module)
	var west: float = rect.position.x + _fence_setback(
		Vector2(rect.position.x, rect.position.y), Vector2(rect.position.x, rect.end.y), Vector2(1.0, 0.0), module)
	var east: float = rect.end.x - _fence_setback(
		Vector2(rect.end.x, rect.position.y), Vector2(rect.end.x, rect.end.y), Vector2(-1.0, 0.0), module)
	if east - west < 4.0 or south - north < 4.0:
		return
	_fence_line(parent, Vector2(west, north), Vector2(east, north))
	_fence_line(parent, Vector2(west, south), Vector2(east, south))
	_fence_line(parent, Vector2(west, north), Vector2(west, south))
	_fence_line(parent, Vector2(east, north), Vector2(east, south))


## Quanto o lado precisa recuar para dentro para sair de cima da estrada, do
## rio ou de uma construcao. Zero quando o tracado original ja cabe.
func _fence_setback(start: Vector2, end: Vector2, inward: Vector2, module: float) -> float:
	var axis: Vector2 = (end - start).normalized()
	var length: float = start.distance_to(end)
	for back: int in FENCE_SETBACK_STEPS:
		var offset: Vector2 = inward * float(back)
		var covered: float = 0.0
		for run: Vector2 in _fence_runs(start + offset, axis, length, module):
			covered += run.y - run.x
		if covered >= length * 0.5:
			return float(back)
	return 0.0


## Cerca continua de `start` a `end`. O passo se ajusta ao vao real -- a linha
## fecha no canto em vez de parar no ultimo modulo inteiro -- e o trecho que
## cai sobre estrada, rio ou construcao vira abertura rematada por poste.
func _fence_line(parent: Node, start: Vector2, end: Vector2) -> void:
	var module: float = _fence_module()
	if module <= 0.0:
		return
	var axis: Vector2 = (end - start).normalized()
	var length: float = start.distance_to(end)
	for run: Vector2 in _fence_gate(_fence_runs(start, axis, length, module), length):
		_fence_run(parent, start, axis, run.x, run.y, module)


## Trechos livres da linha, em metros contados de `start`. Cada modulo e
## conferido no lugar onde ficaria, entao o bloqueio some junto com a peca.
func _fence_runs(start: Vector2, axis: Vector2, length: float, module: float) -> Array[Vector2]:
	var slots: int = maxi(1, int(round(length / module)))
	var step: float = length / float(slots)
	var runs: Array[Vector2] = []
	var open: float = -1.0
	for index: int in slots + 1:
		var free: bool = index < slots and _free_footprint(
			_fence_slot(start, axis, index * step, (index + 1) * step), 0.2)
		if free and open < 0.0:
			open = index * step
		elif not free and open >= 0.0:
			runs.append(Vector2(open, index * step))
			open = -1.0
	return runs


func _fence_slot(start: Vector2, axis: Vector2, from: float, to: float) -> Rect2:
	return Rect2(start + axis * from, Vector2.ZERO).expand(start + axis * to).grow(0.1)


## Entrada no meio da linha: larga onde passa maquina, estreita onde so passa
## gente. Lado curto fica fechado, senao a cerca vira dois pedacos soltos.
func _fence_gate(runs: Array[Vector2], length: float) -> Array[Vector2]:
	var gate: float = 0.0
	if length >= FENCE_GATE_WIDE_SIDE:
		gate = FENCE_GATE_WIDE
	elif length >= FENCE_GATE_NARROW_SIDE:
		gate = FENCE_GATE_NARROW
	if gate <= 0.0:
		return runs
	var from: float = (length - gate) * 0.5
	var to: float = (length + gate) * 0.5
	var opened: Array[Vector2] = []
	for run: Vector2 in runs:
		if run.y <= from or run.x >= to:
			opened.append(run)
			continue
		if run.x < from:
			opened.append(Vector2(run.x, from))
		if run.y > to:
			opened.append(Vector2(to, run.y))
	return opened


## Distribui os modulos dentro do trecho: o passo divide o vao em partes
## iguais, entao as pecas encostam e a ultima termina no fim do trecho.
func _fence_run(parent: Node, start: Vector2, axis: Vector2, from: float, to: float, module: float) -> void:
	var span: float = to - from
	if span < FENCE_MIN_RUN:
		return
	var pieces: int = maxi(1, int(round(span / module)))
	var piece: float = span / float(pieces)
	for index: int in pieces:
		_fence_piece(parent, start + axis * (from + index * piece),
			start + axis * (from + (index + 1) * piece), axis)
	_fence_post(parent, start + axis * from)
	_fence_post(parent, start + axis * to)


## Um modulo entre dois pontos: escala no proprio eixo para encostar na peca
## vizinha e inclina no sentido do declive para nao boiar na encosta.
func _fence_piece(parent: Node, from: Vector2, to: Vector2, axis: Vector2) -> void:
	var mesh: Mesh = _farm_mesh("SM_Prop_Fence_Wood_01")
	if mesh == null:
		return
	var bounds: AABB = mesh.get_aabb()
	var span: float = from.distance_to(to)
	var base: float = _height(from)
	var fence: MeshInstance3D = MeshInstance3D.new()
	fence.mesh = mesh
	fence.basis = Basis(Vector3.UP, -axis.angle()) \
		* Basis(Vector3.BACK, atan2(_height(to) - base, span)) \
		* Basis.from_scale(Vector3(span / bounds.size.x, 1.0, 1.0))
	fence.position = Vector3(from.x, base - FENCE_SINK, from.y) \
		- fence.basis * Vector3(bounds.position.x, bounds.position.y, bounds.get_center().z)
	fence.name = "ParcelFence%d" % parent.get_child_count()
	fence.set_meta("country_town_block", true)
	fence.layers = 512
	fence.material_override = load(FARM_MATERIAL) as Material
	fence.visibility_range_end = 600
	var body: StaticBody3D = StaticBody3D.new()
	var collider: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = bounds.size
	collider.shape = box
	collider.position = bounds.get_center()
	body.add_child(collider)
	fence.add_child(body)
	parent.add_child(fence)


## Remate das pontas: canto e batente de entrada ganham poste no lugar de uma
## tabua terminando no ar. Ponta compartilhada recebe um poste so.
func _fence_post(parent: Node, point: Vector2) -> void:
	for placed: Vector2 in _fence_posts:
		if placed.distance_to(point) < 0.6:
			return
	var post: MeshInstance3D = _prop(parent, "SM_Prop_Fence_Wood_Pole_01",
		Vector3(point.x, _height(point) - FENCE_SINK, point.y), 0.0, false)
	if post == null:
		return
	_fence_posts.append(point)
	post.visibility_range_end = 600.0


func _near_main_road(point: Vector2, distance: float) -> bool:
	for bridge: Vector2 in [Vector2(312.1, 167.46), Vector2(204.9, 298.48)]:
		if Rect2(bridge - Vector2(25, 6), Vector2(50, 12)).has_point(point):
			return true
	for segment: Dictionary in Layout.road_segments():
		if point.distance_to(Geometry2D.get_closest_point_to_segment(point, segment["start"], segment["end"])) < distance:
			return true
	return false


func _build_paths() -> void:
	var paths: Node3D = _group("SecondaryPaths")
	var lanes: Array[PackedVector2Array] = []
	var shoulders: Array[PackedVector2Array] = []
	for path: Dictionary in Layout.SECONDARY_PATHS:
		if path["urban"]:
			continue
		var points: Array = path["points"]
		for index: int in points.size() - 1:
			var start: Vector2 = points[index]
			var end: Vector2 = points[index + 1]
			var steps: int = ceili(start.distance_to(end))
			for step: int in steps:
				var a: Vector2 = start.lerp(end, float(step) / steps)
				var b: Vector2 = start.lerp(end, float(step + 1) / steps)
				lanes.append(Layout.Surface.rectangle(a, b, path["width"]))
				shoulders.append(Layout.Surface.rectangle(a, b, float(path["width"]) + 1.3))
		for point: Vector2 in points:
			lanes.append(Layout.Surface.disk(point, float(path["width"]) * 0.5))
			shoulders.append(Layout.Surface.disk(point, float(path["width"]) * 0.5 + 0.65))
	var main: Array[PackedVector2Array] = Layout.road_polygons(false) + Layout.road_polygons(true)
	Layout.Surface.build(paths, "RuralTrails", lanes, main, 0,
		Layout.Surface.material(Color(0.64, 0.42, 0.22)), true, _trail_height)
	var exclusion: Array[PackedVector2Array] = main + lanes + Layout.road_polygons(false, 1.1)
	Layout.Surface.build(paths, "TrailShoulders", shoulders, exclusion, 0,
		Layout.Surface.material(Color(0.44, 0.34, 0.21)), false, _shoulder_height)
	_save(paths, "Districts/SecondaryPaths.tscn")


func _trail_height(point: Vector2) -> float:
	return _height(point) + Layout.ROAD_PIECE_LIFT


func _shoulder_height(point: Vector2) -> float:
	return _height(point) + 0.015


func _build_wreck() -> void:
	# Apenas o asset visual existente, sem scripts, piloto ou coleta da nave.
	var wreck: Node3D = _group("CrashedSaucer")
	var mesh: Mesh = load("res://3dModelos/ET_Alien_Space_Ship.glb") as Mesh
	if mesh == null:
		_failed = true
		push_error("Malha da nave ausente")
		wreck.free()
		return
	var hull: MeshInstance3D = MeshInstance3D.new()
	hull.name = "BuriedHull"
	hull.mesh = mesh
	hull.layers = 512
	var bounds: AABB = mesh.get_aabb()
	var ratio: float = 19.0 / maxf(bounds.size.x, bounds.size.z)
	hull.rotation_degrees = Vector3(14, 28, -22)
	hull.scale = Vector3.ONE * ratio
	var tilted: AABB = hull.transform * bounds
	hull.position = Vector3(-tilted.get_center().x, -tilted.position.y - 1.4, -tilted.get_center().z)
	var metal: StandardMaterial3D = StandardMaterial3D.new()
	metal.albedo_color = Color(0.15, 0.13, 0.19)
	metal.metallic = 0.55
	metal.roughness = 0.72
	hull.set_surface_override_material(0, metal)
	var glow: StandardMaterial3D = StandardMaterial3D.new()
	glow.albedo_color = Color(0.24, 0.08, 0.45)
	glow.emission_enabled = true
	glow.emission = Color(0.32, 0.08, 0.72)
	glow.emission_energy_multiplier = 1.5
	if mesh.get_surface_count() > 3:
		hull.set_surface_override_material(3, glow)
	var body: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.shape = mesh.create_trimesh_shape()
	body.add_child(collision)
	hull.add_child(body)
	wreck.add_child(hull)
	_save(wreck, "Blocks/CrashedSaucer.tscn")


## Faixa nativa tessellada a cada metro, amostrando relevo nas duas bordas.
## Cantos compartilham secao em bissetriz; evita frestas e planos sobrepostos.
func _strip(parent: Node, label: String, points: Array, width: float, color: Color, lift: float) -> void:
	var centers: Array[Vector2] = []
	for index: int in points.size() - 1:
		var start: Vector2 = points[index]
		var end: Vector2 = points[index + 1]
		var steps: int = maxi(1, ceili(start.distance_to(end)))
		for step: int in steps:
			centers.append(start.lerp(end, float(step) / steps))
	centers.append(points.back())
	var edges: Array[Vector3] = []
	for index: int in centers.size():
		var before: Vector2 = centers[maxi(0, index - 1)]
		var after: Vector2 = centers[mini(centers.size() - 1, index + 1)]
		var normal: Vector2 = (after - before).normalized().orthogonal() * width * 0.5
		for side: float in [-1.0, 1.0]:
			var point: Vector2 = centers[index] + normal * side
			edges.append(Vector3(point.x, _height(point) + lift, point.y))
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index: int in centers.size() - 1:
		for corner: int in [0, 2, 1, 1, 2, 3]:
			var vertex: Vector3 = edges[index * 2 + corner]
			var variation: float = 0.94 + sin(vertex.x * 0.87 + vertex.z * 0.43) * 0.04 + cos(vertex.z * 2.13) * 0.02
			surface.set_color(Color(variation, variation, variation))
			surface.add_vertex(vertex)
	surface.generate_normals()
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = label
	node.mesh = surface.commit()
	node.layers = 32
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	node.material_override = material
	parent.add_child(node)


func _own_children(node: Node, owner_root: Node) -> void:
	for child: Node in node.get_children():
		child.owner = owner_root
		if child.scene_file_path.is_empty():
			_own_children(child, owner_root)


func _save(node: Node3D, relative: String) -> void:
	_own_children(node, node)
	var packed: PackedScene = PackedScene.new()
	if packed.pack(node) != OK or ResourceSaver.save(packed, BASE + relative) != OK:
		_failed = true
		push_error("Nao foi possivel salvar %s" % relative)
	else:
		print("Settlement: %s (%d elementos)" % [relative, node.get_child_count()])
	node.free()
