extends SceneTree

const BEHAVIOR: PackedScene = preload("res://scenes/NPCs/Behaviors/NPCBehaviorTree.tscn")

class FakePlayer:
	extends CharacterBody3D
	var visibility: float = 1.0

	func is_alive() -> bool:
		return true

	func get_stealth_visibility() -> float:
		return visibility

	func set_vision_contact(_source: Object, _contact: bool) -> void:
		pass


var failures: int = 0
var world: Node3D
var player: FakePlayer
var alert: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	alert = root.get_node("PhotoAlertSystem")
	alert.set_process(false)
	alert.reset()
	world = Node3D.new()
	root.add_child(world)
	player = FakePlayer.new()
	player.position = Vector3(1000, 0, 1000)
	player.add_to_group(&"characters")
	world.add_child(player)
	var npc: NPCActor = _actor(NPCActor.new(), Vector3.ZERO, 12.0, 40.0)
	var other: NPCActor = _actor(NPCActor.new(), Vector3(40, 0, 0), 30.8, 56.0)
	var civilian: NPCActor = NPCActor.new()
	civilian.reaction_mode = NPCActor.ReactionMode.FLEE
	_actor(civilian, Vector3(70, 0, 0), 14.0, 45.0)
	var police: PoliceNPC = _actor(PoliceNPC.new(), Vector3(90, 0, 0), 14.0, 45.0) as PoliceNPC
	await _frames(2)
	_check(is_equal_approx(police.walk_speed, 1.6) and is_equal_approx(police.alert_speed, 2.72), "Policial estático move 20% mais devagar")
	_check(is_equal_approx(police.vision.sight_distance, 9.8) and is_equal_approx(police.vision.sight_half_angle_degrees, 31.5), "Policial estático reduz alcance e ângulo 30%")
	_check(npc.get_awareness_state() == &"neutral", "Sem estrelas ou contato começa neutro")
	alert.register_photo()
	for enemy: NPCActor in [npc, other, police]:
		_check(enemy.get_awareness_state() == &"alert", "Uma estrela alerta todo inimigo")
		_check(is_equal_approx(enemy.vision.sight_distance, 21.0) and is_equal_approx(enemy.vision.sight_half_angle_degrees, 56.0), "Inimigos alertas compartilham mesmo cone 21 m/56°")
	player.visibility = 0.5
	_check(is_equal_approx(npc.vision.get_effective_sight_distance(), 10.5), "Cone efetivo compartilhado reflete camuflagem do jogador")
	player.visibility = 1.0
	_check(civilian.get_awareness_state() == &"neutral" and is_equal_approx(civilian.vision.sight_distance, 14.0), "Morador que foge preserva percepção sem alerta global")
	var late: NPCActor = _actor(NPCActor.new(), Vector3(110, 0, 0), 44.0, 80.0)
	_check(late.get_awareness_state() == &"alert" and is_equal_approx(late.vision.sight_distance, 21.0), "Inimigo criado durante alerta recebe cone comum")
	npc.vision.has_detected_player = true
	npc.vision.is_currently_visible = true
	npc.vision.has_last_seen_position = true
	npc.refresh_awareness()
	_check(npc.get_awareness_state() == &"pursuit", "Contato visual confirmado entra em perseguição")
	npc.vision.is_currently_visible = false
	npc.refresh_awareness()
	_check(npc.get_awareness_state() == &"alert", "Perder visão entra em alerta enquanto segue a última posição vista")
	npc.vision.is_currently_visible = true
	alert.reset()
	_check(npc.get_awareness_state() == &"pursuit", "Zerar estrelas preserva perseguição com contato visual")
	_check(is_equal_approx(npc.vision.sight_distance, 12.0) and is_equal_approx(other.vision.sight_distance, 30.8), "Sem estrelas restaura alcances individuais")
	npc.vision.suspend_contact()
	npc.refresh_awareness()
	_check(npc.get_awareness_state() == &"neutral", "Fim de contato sem memória retorna ao neutro")
	_test_hearing_boundaries(npc)
	await _test_investigation(npc)
	_test_ambient_noise(npc)
	print("Percepção NPC: %d falhas" % failures)
	world.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)


func _actor(actor: NPCActor, position: Vector3, distance: float, angle: float) -> NPCActor:
	actor.position = position
	actor.activity_distance = 0.0
	var navigation: NavigationAgent3D = NavigationAgent3D.new()
	navigation.name = "NavigationAgent3D"
	actor.add_child(navigation)
	var vision: NPCVision = NPCVision.new()
	vision.name = "NPCVision"
	vision.sight_distance = distance
	vision.sight_half_angle_degrees = angle
	actor.add_child(vision)
	var hearing: NPCHearing = NPCHearing.new()
	hearing.name = "NPCHearing"
	actor.add_child(hearing)
	var tree: BeehaveTree = BEHAVIOR.instantiate() as BeehaveTree
	tree.name = "NPCBehaviorTree"
	tree.enabled = false
	actor.add_child(tree)
	world.add_child(actor)
	vision.set_physics_process(false)
	hearing.set_physics_process(false)
	return actor


func _test_hearing_boundaries(npc: NPCActor) -> void:
	_check(not npc.hearing.hear_sound(Vector3(5.1, 0, 0), 34.0, 5.0), "Som fora do círculo não é ouvido")
	_check(not npc.hearing.has_pending_noise(), "Som inaudível não cria memória")
	_check(npc.hearing.hear_sound(Vector3(5, 7, 0), 34.0, 5.0), "Limite horizontal do círculo coincide com audição")
	_check(npc.hearing.pending_noise_position.is_equal_approx(Vector3(5, 7, 0)), "Audição guarda origem real em 3D")
	_check(npc.get_awareness_state() == &"alert", "Ouvir muda neutro para alerta")
	npc.hearing.consume_noise()
	npc.refresh_awareness()
	_check(npc.get_awareness_state() == &"neutral", "Memória consumida sem investigação permite neutro")
	_check(not npc.hearing.hear_sound(Vector3.ZERO, 34.0, 0.0), "Som com alcance zero não é ouvido")
	npc.hearing.process_mode = Node.PROCESS_MODE_DISABLED
	_check(not npc.hearing.hear_sound(Vector3.ZERO, 34.0, 5.0), "Sensor suspenso não confirma audição")
	npc.hearing.process_mode = Node.PROCESS_MODE_INHERIT


func _test_investigation(npc: NPCActor) -> void:
	var tree: BeehaveTree = npc.get_node("NPCBehaviorTree") as BeehaveTree
	npc.investigate_wait_time = 0.2
	var first: Vector3 = Vector3(6, 0, 0)
	var next: Vector3 = Vector3(-4, 0, 0)
	npc.vision.last_seen_position = Vector3(0, 0, 15)
	npc.vision.has_last_seen_position = true
	npc.hearing.hear_sound(first, 40.0, 10.0)
	tree.enabled = true
	await _frames(30)
	_check(npc.state == &"investigate" and npc.global_position.x > 0.4, "NPC percorre origem do som em vez da memória visual antiga")
	_check(npc.hearing.investigating_noise and not npc.hearing.has_pending_noise(), "Investigação persiste após consumir evento no ramo reativo")
	npc.hearing.hear_sound(next, 40.0, 10.0)
	await _frames(2)
	_check(npc.hearing.investigation_position.is_equal_approx(next), "Novo som atualiza destino durante investigação")
	player.global_position = Vector3(0, 0, 100)
	await _frames(20)
	_check((npc.get("_motion_target") as Vector3).is_equal_approx(next), "Jogador invisível se move sem arrastar destino do ruído")
	var completed: bool = false
	for frame: int in range(240):
		await physics_frame
		if not npc.hearing.investigating_noise and npc.state != &"investigate":
			completed = true
			break
	_check(completed and npc.global_position.distance_to(next) < 1.0, "NPC chega ao novo som e termina investigação")
	await _frames(2)
	_check(npc.get_awareness_state() == &"neutral", "Busca concluída sem estrelas retorna ao neutro")
	tree.enabled = false


func _test_ambient_noise(npc: NPCActor) -> void:
	player.global_position = npc.global_position + Vector3(1, 0, 0)
	player.velocity = Vector3(5, 0, 0)
	var explicit_noise: Node = Node.new()
	explicit_noise.name = "PlayerNoise"
	player.add_child(explicit_noise)
	npc.hearing.call("_scan_ambient_noise")
	_check(not npc.hearing.has_pending_noise(), "Passos explícitos não recebem audição duplicada por velocidade")
	var vehicle: RigidBody3D = RigidBody3D.new()
	vehicle.position = npc.global_position + Vector3(2, 0, 0)
	vehicle.linear_velocity = Vector3(4, 0, 0)
	vehicle.add_to_group(&"vehicles")
	world.add_child(vehicle)
	npc.hearing.call("_scan_ambient_noise")
	_check(npc.hearing.has_pending_noise(), "Motor em movimento preserva audição legada")
	npc.hearing.consume_noise()
	npc.hearing.hear_noise(npc.global_position + Vector3(12, 0, 0), 2.0)
	_check(npc.hearing.has_pending_noise(), "Contrato hear_noise preserva multiplicador de alcance")


func _frames(count: int) -> void:
	for frame: int in range(count):
		await physics_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
