extends SceneTree

## Verifica o minimapa reutilizável (`scripts/vision_debug_map.gd`): se ele
## acha jogador, pontos de referência e atores com visão pelos grupos
## configurados, se o raio em metros escala a projeção, e se o Country Town
## está com o minimapa instanciado e configurado para o tamanho daquele mapa.

const MINIMAP_SCENE : PackedScene = preload("res://scenes/VisionDebugMap.tscn")
const FARMER_SCENE : PackedScene = preload("res://scenes/NPCs/Farmer.tscn")
const COUNTRY_TOWN_PATH : String = "res://scenes/CountryTown/CountryTown.tscn"
const SETTLE_FRAMES : int = 5
const LANDMARK_GROUP : StringName = &"test_landmarks"

class FakePlayer:
	extends CharacterBody3D

	func is_alive() -> bool:
		return true

	func get_stealth_visibility() -> float:
		return 1.0

	func set_vision_contact(_source : Object, _contact : bool) -> void:
		pass


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var failures : Array[String] = []

	failures.append_array(await _test_runtime_lookups())
	failures.append_array(_test_country_town_wiring())

	if not failures.is_empty():
		for failure : String in failures:
			push_error(failure)
		quit(1)
		return

	print("OK: minimapa acha jogador/POIs/NPCs, escala pelo raio e esta no Country Town.")
	quit(0)


## Monta uma cena sintética e confere o que o minimapa enxerga nela.
func _test_runtime_lookups() -> Array[String]:
	var failures : Array[String] = []

	var world : Node3D = Node3D.new()
	root.add_child(world)

	var player : FakePlayer = FakePlayer.new()
	player.add_to_group(&"characters")
	player.position = Vector3(10.0, 0.0, 20.0)
	world.add_child(player)

	for index : int in range(3):
		var landmark : Marker3D = Marker3D.new()
		landmark.name = "Landmark%d" % index
		landmark.add_to_group(LANDMARK_GROUP)
		landmark.position = Vector3(float(index) * 25.0, 0.0, 0.0)
		world.add_child(landmark)

	var farmer : NPCActor = FARMER_SCENE.instantiate() as NPCActor
	farmer.position = Vector3(30.0, 0.0, 20.0)
	world.add_child(farmer)

	var minimap : CanvasLayer = MINIMAP_SCENE.instantiate() as CanvasLayer
	var overlay : Control = minimap.get_node("Overlay") as Control
	overlay.set("world_radius", 100.0)
	overlay.set("landmark_group", LANDMARK_GROUP)
	root.add_child(minimap)

	for i : int in range(SETTLE_FRAMES):
		await physics_frame

	overlay.call("_refresh_scene_references")

	var found_player : Node3D = overlay.get("_player") as Node3D
	if found_player != player:
		failures.append("minimapa nao achou o jogador pelo grupo characters")

	var landmarks : Array = overlay.get("_landmarks") as Array
	if landmarks.size() != 3:
		failures.append(
			"minimapa achou %d pontos de referencia, esperado 3" % landmarks.size()
		)

	var actors : Array = overlay.get("_vision_actors") as Array
	if not actors.has(farmer):
		failures.append("minimapa nao achou o NPC com componente NPCVision")

	# O raio em metros precisa escalar a projeção: um ponto a 50 m deve cair na
	# metade do raio do círculo quando world_radius = 100.
	overlay.set("map_center", Vector2.ZERO)
	overlay.set("map_radius", 100.0)
	var far_point : Vector3 = player.global_position + Vector3(0.0, 0.0, -50.0)
	var projected : Vector2 = overlay.call("_world_to_map", far_point, player)
	if absf(projected.length() - 50.0) > 1.0:
		failures.append(
			"projecao errada: 50 m com world_radius 100 caiu em %.1f px (esperado ~50)"
			% projected.length()
		)

	# Um ator sem as propriedades esperadas não pode quebrar o desenho: em
	# GDScript `float(null)` e `bool(null)` são cast inválido, e os dois estilos
	# de NPC do projeto expõem nomes diferentes.
	var bare : Node3D = Node3D.new()
	if overlay.call("_read_number", bare, &"sight_distance") != 0.0:
		failures.append("_read_number nao devolveu 0.0 para propriedade ausente")
	if overlay.call("_read_flag", bare, &"has_visual_contact") != false:
		failures.append("_read_flag nao devolveu false para propriedade ausente")
	bare.free()

	print(
		"cena sintetica - jogador: ", found_player == player,
		" POIs: ", landmarks.size(),
		" atores com visao: ", actors.size(),
		" projecao 50m: ", snappedf(projected.length(), 0.1), " px"
	)

	minimap.queue_free()
	world.queue_free()
	await physics_frame
	return failures


## Confere a fiação no Country Town sem instanciar o mapa inteiro (pesado):
## lê o estado salvo da cena.
func _test_country_town_wiring() -> Array[String]:
	var failures : Array[String] = []

	var scene : PackedScene = load(COUNTRY_TOWN_PATH) as PackedScene
	var state : SceneState = scene.get_state()

	var has_minimap : bool = false
	var world_radius : float = 0.0
	var landmark_group : StringName = &""

	for node_index : int in range(state.get_node_count()):
		var node_name : String = state.get_node_name(node_index)
		if node_name == "Minimap":
			has_minimap = true
		if node_name != "Overlay":
			continue
		for property_index : int in range(state.get_node_property_count(node_index)):
			var property_name : String = state.get_node_property_name(
				node_index,
				property_index
			)
			var value : Variant = state.get_node_property_value(
				node_index,
				property_index
			)
			if property_name == "world_radius":
				world_radius = float(value)
			elif property_name == "landmark_group":
				landmark_group = StringName(value)

	if not has_minimap:
		failures.append("CountryTown.tscn nao instancia o minimapa")
	if world_radius < 100.0:
		failures.append(
			"CountryTown.tscn com world_radius %.0f - baixo demais para um mapa de 600x450 m"
			% world_radius
		)
	if landmark_group != &"country_town_poi":
		failures.append(
			"CountryTown.tscn nao ligou os POIs no minimapa (landmark_group=%s)"
			% landmark_group
		)

	print(
		"CountryTown - minimapa: ", has_minimap,
		" world_radius: ", world_radius,
		" landmark_group: ", landmark_group
	)
	return failures
