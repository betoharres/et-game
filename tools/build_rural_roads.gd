extends SceneTree

## Tira o piso de terra das vias rurais: o chao visivel passa a ser o proprio
## terreno, que o material do Terrain3D ja pinta. So sobra piso nas cabeceiras
## de ponte, onde as rampas precisam dele. As marcas de roda que ficavam por
## cima sairam daqui: agora sao as curvas de `tools/build_tire_tracks.gd`.
const PRESET: String = "res://Materiais/rural_road_gentle.tres"
const BASE: String = "res://scenes/CountryTown/Districts/"
## Nos do piso antigo que somem: o terreno assume o lugar deles. `WheelTracks`
## era a fita gerada aqui, hoje substituida pelas marcas de pneu de autoria.
const RETIRED: Array[String] = ["RuralShoulders", "RuralTrails", "TrailShoulders", "WheelTracks"]
## Cabeceiras das duas pontes, com o raio em que o piso de terra continua.
const BRIDGE_ZONES: Array[Vector3] = [Vector3(318.18723, 167.46, 26.0), Vector3(204.9, 298.48, 26.0)]

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
	var profile: Resource = load(PRESET)
	if profile == null:
		push_error("Missing rural road profile; import the project first.")
		quit(1)
		return
	_terrain = Terrain3D.new()
	root.add_child(_terrain)
	_terrain.data_directory = "res://scenes/CountryTown/Terrain"
	if _terrain.data.get_region_count() == 0:
		push_error("Missing Country Town terrain regions; run build_country_town_terrain first.")
		quit(1)
		return
	profile.configure(BRIDGE_ZONES)
	var ground: Callable = Callable(self, "ground_height")
	for scene_name: String in ["RoadNetwork", "SecondaryPaths"]:
		var path: String = BASE + scene_name + ".tscn"
		var packed: PackedScene = load(path) as PackedScene
		if packed == null:
			push_error("Missing source road scene: " + path)
			quit(1)
			return
		var scene: Node = packed.instantiate()
		var bed: MeshInstance3D = scene.get_node_or_null("DirtRoadBed") as MeshInstance3D
		if bed != null:
			# A aba serve so de apoio fisico; o terreno fornece o visual da entrada.
			bed.visible = false
			var kept: int = profile.trim_apron(bed, ground)
			print("Bridge aprons on DirtRoadBed: %d triangles." % kept)
			if kept == 0:
				bed.free()
		for label: String in RETIRED:
			var retired: Node = scene.get_node_or_null(label)
			if retired != null:
				retired.free()
		var output: PackedScene = PackedScene.new()
		var result: Error = output.pack(scene)
		if result == OK:
			result = ResourceSaver.save(output, path)
		scene.free()
		if result != OK:
			push_error("Cannot save rural roads: " + path)
			quit(1)
			return
	print("Rural dirt floor removed; terrain is the floor, bridge aprons and asphalt kept.")
	quit()


## Altura do chao em um ponto do mapa, ou NAN fora das regioes do terreno.
func ground_height(point: Vector2) -> float:
	return _terrain.data.get_height(Vector3(point.x, 0.0, point.y))
