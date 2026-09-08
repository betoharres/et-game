extends SceneTree

## Smoke test do sistema de NPCs com Beehave (fazendeiro), no padrão de
## tools/test_generic_npc_navigation.gd: sem malha de navegação bakeada,
## como no Country Town hoje, valida patrulha em linha reta, investigação de
## ruído e o ciclo perseguição -> busca -> retorno à rotina.

const FARMER_SCENE: PackedScene = preload("res://scenes/NPCs/Farmer.tscn")
const SETTLE_FRAMES: int = 5
const PATROL_FRAMES: int = 300
const NOISE_FRAMES: int = 90
const RETURN_FRAMES: int = 300
const SEE_FRAMES: int = 150
const LOSE_FRAMES: int = 300
const MINIMUM_PATROL_DISPLACEMENT: float = 1.0

class FakePlayer:
	extends CharacterBody3D
	var alive: bool = true

	func is_alive() -> bool:
		return alive

	func get_stealth_visibility() -> float:
		return 1.0

	func set_vision_contact(_source: Object, _contact: bool) -> void:
		pass


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world: Node3D = Node3D.new()
	root.add_child(world)

	var player: FakePlayer = FakePlayer.new()
	player.add_to_group(&"characters")
	player.position = Vector3(1000, 0, 0)
	world.add_child(player)

	var farmer: FarmerNPC = FARMER_SCENE.instantiate() as FarmerNPC
	farmer.patrol_points = [Vector3(0, 0, 0), Vector3(6, 0, 0)]
	farmer.patrol_wait_time_min = 0.2
	farmer.patrol_wait_time_max = 0.4
	farmer.position = Vector3(0, 0, 0)
	world.add_child(farmer)

	for i: int in range(SETTLE_FRAMES):
		await physics_frame

	farmer.search_duration = 1.0
	farmer.vision.lose_sight_after = 1.0

	# 1) Patrulha sem malha bakeada: deve degradar para linha reta e se mover.
	var start_position: Vector3 = farmer.global_position
	for i: int in range(PATROL_FRAMES):
		await physics_frame
	var patrol_displacement: float = start_position.distance_to(farmer.global_position)
	print("Patrulha - deslocamento: ", patrol_displacement)
	if patrol_displacement < MINIMUM_PATROL_DISPLACEMENT:
		push_error("Farmer nao se moveu na patrulha sem malha de navegacao bakeada.")
		quit(1)
		return

	# 2) Audição: um ruído próximo deve disparar investigação.
	var noise_position: Vector3 = farmer.global_position + Vector3(4, 0, 4)
	farmer.hearing.hear_noise(noise_position, 5.0)
	var investigated: bool = false
	for i: int in range(NOISE_FRAMES):
		await physics_frame
		if farmer.state == &"investigate":
			investigated = true
			break
	print("Investigou ruido ouvido: ", investigated)
	if not investigated:
		push_error("Farmer nao entrou em estado de investigacao ao ouvir ruido.")
		quit(1)
		return

	for i: int in range(RETURN_FRAMES):
		await physics_frame
		if farmer.state != &"investigate":
			break

	# 3) Visão: jogador visível e próximo deve disparar perseguição.
	player.global_position = farmer.global_position + Vector3(0, 0, 3)
	var chased: bool = false
	for i: int in range(SEE_FRAMES):
		await physics_frame
		if farmer.state == &"chase":
			chased = true
			break
	print("Perseguiu jogador visivel: ", chased)
	if not chased:
		push_error("Farmer nao perseguiu o jogador apos deteccao visual.")
		quit(1)
		return

	# 4) Perder o jogador de vista: deve procurar a última posição vista e
	# depois voltar sozinho à rotina (patrulha/trabalho parado).
	player.global_position = Vector3(3000, 0, 3000)
	var searched: bool = false
	var returned: bool = false
	for i: int in range(LOSE_FRAMES):
		await physics_frame
		if farmer.state == &"search":
			searched = true
		if searched and (farmer.state == &"patrol" or farmer.state == &"idle"):
			returned = true
			break
	print("Buscou a ultima posicao vista: ", searched)
	print("Retornou a rotina: ", returned)
	if not searched or not returned:
		push_error("Farmer nao completou o ciclo busca -> retorno a rotina.")
		quit(1)
		return

	print("OK: patrulha, audicao, perseguicao e busca/retorno a rotina funcionando.")
	quit(0)
