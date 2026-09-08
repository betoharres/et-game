extends SceneTree

## Assa as marcas de pneu (`scenes/Props/TireTrack3D.tscn`) dos distritos do
## Country Town contra o terreno atual, e aposenta o `WheelTracks` antigo: a
## marca da via rural passa a ser sempre uma Curve3D de autoria, editavel a mao.
##
## Sem `--reseed` a ferramenta so refaz a malha das marcas que ja existem na
## cena -- rode assim quando o relevo mudar ou depois de mexer numa curva sem o
## editor aberto. Com `--reseed` ela joga fora o no `TireTracks` e semeia tudo
## de novo a partir do layout, o que descarta qualquer curva editada a mao.
##
## A semeadura cobre as vias rurais com varias passagens paralelas -- uma bem
## marcada e as outras mais fracas e deslocadas, como veiculos que nao repetem
## exatamente o mesmo tracado -- e abre arcos de manobra em cada cruzamento e
## entrada, que e onde as rodas mais escrevem no chao.
const Layout: GDScript = preload("res://tools/build_country_town_layout.gd")
const TRACK_SCENE: String = "res://scenes/Props/TireTrack3D.tscn"
const BASE: String = "res://scenes/CountryTown/Districts/"
const HOLDER: String = "TireTracks"
const LEGACY: String = "WheelTracks"
const PRIMARY_SCENE: String = "RoadNetwork"
const SECONDARY_SCENE: String = "SecondaryPaths"
const SCENES: Array[String] = [PRIMARY_SCENE, SECONDARY_SCENE]

## Cabeceiras de ponte: ali o chao e o piso da rampa, nao o terreno em que a
## marca assenta, entao ela para antes.
const BRIDGE_ZONES: Array[Vector3] = [Vector3(318.18723, 167.46, 26.0), Vector3(204.9, 298.48, 26.0)]
## Passagens de cada via: a principal no eixo e as outras deslocadas e gastas.
const PASSES: Array[Dictionary] = [
	{"tag": "A", "lanes": 2, "offset": 0.0, "intensity": 0.85, "wander": 0.22},
	{"tag": "B", "lanes": 2, "offset": 1.35, "intensity": 0.5, "wander": 0.3},
	{"tag": "C", "lanes": 1, "offset": -1.9, "intensity": 0.38, "wander": 0.38},
]
## A terceira passagem so cabe em via larga; trilha estreita fica com duas.
const WIDE_ROUTE: float = 6.0
## Raio dos arcos de manobra abertos em cada cruzamento.
const JUNCTION_RADIUS: float = 6.5
## Um cruzamento so ganha arco entre bracos que formam curva de verdade: seguir
## reto ja e trabalho da marca da via.
const TURN_MIN: float = -0.78
const TURN_MAX: float = 0.72
const MAX_ARCS: int = 4
## Tolerancia para dois extremos serem o mesmo no da malha viaria.
const JOINT: float = 1.0
## Distancia em que a ponta de uma trilha conta como entrada de outra via.
const ENTRANCE: float = 5.0

var _terrain: Terrain3D
var _started: bool = false


## O Terrain3D so publica as regioes depois do primeiro quadro, como nos outros
## geradores do Country Town.
func _process(_delta: float) -> bool:
	if _started:
		return true
	_started = true
	_build()
	return true


func _build() -> void:
	var packed_track: PackedScene = load(TRACK_SCENE) as PackedScene
	if packed_track == null:
		push_error("Missing tire track scene: " + TRACK_SCENE)
		quit(1)
		return
	_terrain = Terrain3D.new()
	root.add_child(_terrain)
	_terrain.data_directory = "res://scenes/CountryTown/Terrain"
	if _terrain.data.get_region_count() == 0:
		push_error("Missing Country Town terrain regions; run build_country_town_terrain first.")
		quit(1)
		return
	var reseed: bool = _has_flag("--reseed")
	var plan: Dictionary = _plan()
	var ground: Callable = Callable(self, "ground_height")
	for scene_name: String in SCENES:
		var path: String = BASE + scene_name + ".tscn"
		var packed: PackedScene = load(path) as PackedScene
		if packed == null:
			push_error("Missing district scene: " + path)
			quit(1)
			return
		var scene: Node = packed.instantiate()
		root.add_child(scene)
		var changed: bool = _retire_legacy(scene, scene_name)
		changed = _seed(scene, scene_name, plan[scene_name], packed_track, reseed) or changed
		var baked: int = 0
		var triangles: int = 0
		for track: Node in _tracks(scene):
			# Amostra as ondulacoes de 1 m sem atravessar o centro dos sulcos.
			track.sample_step = minf(float(track.sample_step), 0.5)
			track.height_provider = ground
			track.bake()
			baked += 1
			var surface: MeshInstance3D = track.get_node_or_null("Surface") as MeshInstance3D
			if surface != null and surface.mesh != null:
				triangles += surface.mesh.get_faces().size() / 3
		if baked == 0 and not changed:
			print("%s: no tire tracks to bake." % scene_name)
			scene.free()
			continue
		print("%s: %d tire tracks baked, %d triangles." % [scene_name, baked, triangles])
		var output: PackedScene = PackedScene.new()
		var result: Error = output.pack(scene)
		if result == OK:
			result = ResourceSaver.save(output, path)
		scene.free()
		if result != OK:
			push_error("Cannot save tire tracks: " + path)
			quit(1)
			return
	print("Tire tracks baked over the current terrain.")
	quit()


## Altura do chao em um ponto do mapa, ou NAN fora das regioes do terreno.
func ground_height(point: Vector3) -> float:
	return _terrain.data.get_height(Vector3(point.x, 0.0, point.z))


func _has_flag(flag: String) -> bool:
	return OS.get_cmdline_args().has(flag) or OS.get_cmdline_user_args().has(flag)


func _tracks(node: Node) -> Array[Node]:
	var result: Array[Node] = []
	if node is TireTrack3D:
		result.append(node)
	for child: Node in node.get_children():
		result.append_array(_tracks(child))
	return result


## A fita gerada pelo perfil antigo sai de cena assim que as marcas assumem.
func _retire_legacy(scene: Node, scene_name: String) -> bool:
	var legacy: Node = scene.get_node_or_null(LEGACY)
	if legacy == null:
		return false
	legacy.free()
	print("%s: retired the old %s strip." % [scene_name, LEGACY])
	return true


# --- Semeadura ---------------------------------------------------------------

## As marcas de cada distrito, a partir do layout: passagens ao longo das vias
## rurais e arcos de manobra nos cruzamentos.
func _plan() -> Dictionary:
	var plan: Dictionary = {PRIMARY_SCENE: [], SECONDARY_SCENE: []}
	for route: Dictionary in _routes():
		var stretches: Array[PackedVector2Array] = _clip(route["points"])
		for index: int in stretches.size():
			for pass_data: Dictionary in PASSES:
				if float(route["width"]) < WIDE_ROUTE and str(pass_data["tag"]) == "C":
					continue
				plan[route["scene"]].append({
					"name": "%s%dPass%s" % [route["name"], index, pass_data["tag"]],
					"points": stretches[index],
					"lanes": int(pass_data["lanes"]),
					"offset": float(pass_data["offset"]) * (1.0 if index % 2 == 0 else -1.0),
					"intensity": float(pass_data["intensity"]),
					"wander": float(pass_data["wander"]),
					"step": 1.5,
					"seed": hash("%s%d%s" % [route["name"], index, pass_data["tag"]]) % 9973,
				})
	plan[PRIMARY_SCENE].append_array(_junction_plan(true))
	plan[SECONDARY_SCENE].append_array(_junction_plan(false))
	return plan


## Rotas rurais: as vias de terra da grade, unidas em polilinhas continuas, e as
## trilhas secundarias, que ja vem como polilinha.
func _routes() -> Array[Dictionary]:
	var routes: Array[Dictionary] = []
	var index: int = 0
	for polyline: PackedVector2Array in _chain(_dirt_segments()):
		routes.append({"name": "DirtRoad%d" % index, "points": polyline, "width": 8.0,
			"scene": PRIMARY_SCENE})
		index += 1
	for path: Dictionary in Layout.SECONDARY_PATHS:
		if path["urban"]:
			continue
		routes.append({"name": str(path["name"]), "points": PackedVector2Array(path["points"]),
			"width": float(path["width"]), "scene": SECONDARY_SCENE})
	return routes


## Trechos retos de terra da grade principal, cada um com os dois extremos.
func _dirt_segments() -> Array:
	var segments: Array = []
	var primary: Array[Dictionary] = Layout.road_segments()
	for index: int in primary.size():
		if str(Layout.ROAD_RUNS[index][0]).begins_with("dirt"):
			segments.append([primary[index]["start"], primary[index]["end"]])
	return segments


## Une os trechos retos em polilinhas: em cada ponta segue o vizinho mais
## alinhado, entao uma quina de 90 graus continua a mesma via em vez de virar
## duas marcas soltas que se encontram em L.
func _chain(segments: Array) -> Array[PackedVector2Array]:
	var used: Array[bool] = []
	used.resize(segments.size())
	var result: Array[PackedVector2Array] = []
	for index: int in segments.size():
		if used[index]:
			continue
		used[index] = true
		var chain: Array[Vector2] = [segments[index][0], segments[index][1]]
		_extend(chain, segments, used, true)
		_extend(chain, segments, used, false)
		result.append(PackedVector2Array(chain))
	return result


func _extend(chain: Array[Vector2], segments: Array, used: Array[bool], forward: bool) -> void:
	while true:
		var tip: Vector2 = chain[chain.size() - 1] if forward else chain[0]
		var behind: Vector2 = chain[chain.size() - 2] if forward else chain[1]
		var heading: Vector2 = (tip - behind).normalized()
		var best: int = -1
		var best_alignment: float = -1.0
		var best_far: Vector2 = Vector2.ZERO
		for index: int in segments.size():
			if used[index]:
				continue
			for side: int in 2:
				var near: Vector2 = segments[index][side]
				var far: Vector2 = segments[index][1 - side]
				if near.distance_to(tip) > JOINT:
					continue
				var alignment: float = heading.dot((far - near).normalized())
				if alignment > best_alignment:
					best_alignment = alignment
					best = index
					best_far = far
		if best < 0 or best_alignment < -0.2:
			return
		used[best] = true
		if forward:
			chain.append(best_far)
		else:
			chain.insert(0, best_far)


## Corta os pedacos que entram numa cabeceira de ponte. Rota que nao encosta em
## nenhuma sai inteira, com os vertices originais: e neles que as alcas
## Catmull-Rom arredondam as quinas.
func _clip(points: PackedVector2Array) -> Array[PackedVector2Array]:
	var curve: Curve2D = Curve2D.new()
	for point: Vector2 in points:
		curve.add_point(point)
	var length: float = curve.get_baked_length()
	var steps: int = maxi(2, int(round(length / 3.0)))
	var stretches: Array[PackedVector2Array] = []
	var current: PackedVector2Array = PackedVector2Array()
	var touched: bool = false
	for index: int in steps + 1:
		var point: Vector2 = curve.sample_baked(length * float(index) / float(steps))
		if _blocked(point):
			touched = true
			if current.size() > 1:
				stretches.append(current)
			current = PackedVector2Array()
			continue
		current.append(point)
	if not touched:
		return [points] as Array[PackedVector2Array]
	if current.size() > 1:
		stretches.append(current)
	return stretches


func _blocked(point: Vector2) -> bool:
	for zone: Vector3 in BRIDGE_ZONES:
		if point.distance_to(Vector2(zone.x, zone.y)) < zone.z:
			return true
	return false


## Arcos de manobra dos cruzamentos e entradas. `primary` separa os nos que
## envolvem uma via principal dos que so juntam trilhas.
func _junction_plan(primary: bool) -> Array:
	var plan: Array = []
	var index: int = 0
	for node: Dictionary in _junctions():
		index += 1
		if bool(node["primary"]) != primary:
			continue
		var origin: Vector2 = node["point"]
		var arms: Array = node["arms"]
		var arcs: int = 0
		for first: int in arms.size():
			for second: int in range(first + 1, arms.size()):
				if arcs >= MAX_ARCS:
					break
				var a: Vector2 = arms[first]
				var b: Vector2 = arms[second]
				var turn: float = a.dot(b)
				if turn < TURN_MIN or turn > TURN_MAX:
					continue
				# O ponto do meio puxa a curva para dentro do cruzamento: e a
				# linha que a roda faz ao cortar a esquina.
				var middle: Vector2 = (a + b).normalized() * JUNCTION_RADIUS * 0.5
				plan.append({
					"name": "Junction%02dArc%d" % [index, arcs],
					"points": PackedVector2Array([
						origin + a * JUNCTION_RADIUS,
						origin + a * JUNCTION_RADIUS * 0.55 + middle * 0.4,
						origin + middle,
						origin + b * JUNCTION_RADIUS * 0.55 + middle * 0.4,
						origin + b * JUNCTION_RADIUS]),
					"lanes": 2,
					"offset": 0.35 if arcs % 2 == 0 else -0.35,
					"intensity": 0.62,
					"wander": 0.12,
					"step": 0.8,
					"seed": hash("junction%d-%d" % [index, arcs]) % 9973,
				})
				arcs += 1
	return plan


## Nos da malha rural: encontros de tres ou mais bracos, incluindo a ponta de
## uma trilha que morre no meio de outra via.
func _junctions() -> Array[Dictionary]:
	var segments: Array[Dictionary] = _rural_segments()
	var nodes: Dictionary = {}
	for segment: Dictionary in segments:
		_add_arm(nodes, segment["a"], (segment["b"] - segment["a"]).normalized(), segment["primary"])
		_add_arm(nodes, segment["b"], (segment["a"] - segment["b"]).normalized(), segment["primary"])
	for segment: Dictionary in segments:
		for tip: Vector2 in [segment["a"], segment["b"]]:
			for other: Dictionary in segments:
				if str(other["route"]) == str(segment["route"]):
					continue
				var closest: Vector2 = Geometry2D.get_closest_point_to_segment(tip, other["a"], other["b"])
				if closest.distance_to(tip) > ENTRANCE:
					continue
				if closest.distance_to(other["a"]) < JOINT or closest.distance_to(other["b"]) < JOINT:
					continue
				var shared: bool = bool(other["primary"]) or bool(segment["primary"])
				_add_arm(nodes, closest, (other["a"] - closest).normalized(), shared)
				_add_arm(nodes, closest, (other["b"] - closest).normalized(), shared)
				_add_arm(nodes, closest, (tip - closest).normalized(), shared)
	var result: Array[Dictionary] = []
	for node: Dictionary in nodes.values():
		if node["arms"].size() < 3 or _blocked(node["point"]):
			continue
		result.append(node)
	return result


## Registra um braco num no, juntando pontos vizinhos e direcoes repetidas.
func _add_arm(nodes: Dictionary, point: Vector2, direction: Vector2, primary: bool) -> void:
	var key: String = "%d:%d" % [roundi(point.x / JOINT), roundi(point.y / JOINT)]
	if not nodes.has(key):
		nodes[key] = {"point": point, "arms": [], "primary": false}
	var node: Dictionary = nodes[key]
	node["primary"] = bool(node["primary"]) or primary
	for arm: Vector2 in node["arms"]:
		if arm.dot(direction) > 0.96:
			return
	node["arms"].append(direction)


## Todos os trechos retos rurais, com a rota de origem e se ela e principal.
func _rural_segments() -> Array[Dictionary]:
	var segments: Array[Dictionary] = []
	var index: int = 0
	for polyline: PackedVector2Array in _chain(_dirt_segments()):
		for step: int in polyline.size() - 1:
			segments.append({"a": polyline[step], "b": polyline[step + 1],
				"route": "dirt%d" % index, "primary": true})
		index += 1
	for path: Dictionary in Layout.SECONDARY_PATHS:
		if path["urban"]:
			continue
		var points: Array = path["points"]
		for step: int in points.size() - 1:
			segments.append({"a": points[step], "b": points[step + 1],
				"route": str(path["name"]), "primary": false})
	return segments


## Instancia as marcas planejadas. Sem `--reseed`, um distrito que ja tem marcas
## fica intocado: as curvas editadas a mao mandam mais que o plano.
func _seed(scene: Node, scene_name: String, specs: Array, packed_track: PackedScene, reseed: bool) -> bool:
	var holder: Node = scene.get_node_or_null(HOLDER)
	if holder != null and not reseed:
		return false
	if holder != null:
		holder.free()
	if specs.is_empty():
		return false
	var group: Node3D = Node3D.new()
	group.name = HOLDER
	scene.add_child(group)
	group.owner = scene
	for spec: Dictionary in specs:
		var track: Node = packed_track.instantiate()
		track.name = str(spec["name"])
		group.add_child(track)
		# O `Surface` nasce no bake e herda esta posse, entao ele e salvo junto.
		track.owner = scene
		var points: PackedVector2Array = spec["points"]
		track.position = Vector3(points[0].x, 0.0, points[0].y)
		track.curve = _curve(points, track.position)
		track.lanes = int(spec["lanes"])
		track.lane_offset = float(spec["offset"])
		track.intensity = float(spec["intensity"])
		track.lateral_wander = float(spec["wander"])
		track.sample_step = float(spec["step"])
		track.random_seed = int(spec["seed"])
	print("%s: seeded %d tire tracks." % [scene_name, specs.size()])
	return true


## Curva suave pelos pontos, com as alcas Catmull-Rom: a marca acompanha a
## trilha sem as quinas retas da polilinha original.
func _curve(points: PackedVector2Array, origin: Vector3) -> Curve3D:
	var curve: Curve3D = Curve3D.new()
	var local: Array[Vector3] = []
	for point: Vector2 in points:
		local.append(Vector3(point.x, 0.0, point.y) - origin)
	for index: int in local.size():
		var previous: Vector3 = local[maxi(index - 1, 0)]
		var next: Vector3 = local[mini(index + 1, local.size() - 1)]
		var handle: Vector3 = (next - previous) / 6.0
		curve.add_point(local[index], -handle, handle)
	return curve
