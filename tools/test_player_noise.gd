extends SceneTree

const ScrapScript: Script = preload("res://scripts/spaceship_scraps.gd")

class ListenerProbe:
	extends Node
	var enemy: bool = true
	var accepts: bool = true
	var received: Array[Dictionary] = []

	func _ready() -> void:
		add_to_group(&"npc_hearing_listeners")

	func hear_sound(origin: Vector3, decibels: float, radius: float) -> bool:
		received.append({"origin": origin, "decibels": decibels, "radius": radius})
		return accepts

	func is_enemy_listener() -> bool:
		return enemy

var _failures: int = 0
var _events: Array[Dictionary] = []
var _world: Node3D
var _player: CharacterBody3D
var _noise: PlayerNoise


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	current_scene = _world
	var floor_body: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(200.0, 0.2, 200.0)
	collision.shape = shape
	collision.position.y = -0.1
	floor_body.add_child(collision)
	_world.add_child(floor_body)
	_player = (load("res://scenes/Player.tscn") as PackedScene).instantiate() as CharacterBody3D
	_world.add_child(_player)
	_noise = _player.get_node("PlayerNoise") as PlayerNoise
	_noise.noise_emitted.connect(_on_noise)
	await _frames(6)
	_check(_player.is_on_floor(), "Player real começa apoiado no chão")
	_check(absf(PlayerNoise.radius_for_decibels(22.0) - 1.2589) < 0.001,
		"Agachado continua detectável a aproximadamente 1,26 m")
	_check(absf(PlayerNoise.radius_for_decibels(26.0) - 1.9953) < 0.001,
		"Caminhada é silenciosa fora de aproximadamente 2 m")
	_check(absf(PlayerNoise.radius_for_decibels(44.0) - 15.8489) < 0.001,
		"Corrida alcança aproximadamente 15,85 m")
	_test_dispatch()
	await _test_movement()
	_test_inactive_states()
	await _test_pickup()
	_world.queue_free()
	await process_frame
	await process_frame
	print("PLAYER_NOISE_TEST|%s|%d falhas" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures else 0)


func _test_dispatch() -> void:
	var enemy_a: ListenerProbe = ListenerProbe.new()
	var enemy_b: ListenerProbe = ListenerProbe.new()
	var civilian: ListenerProbe = ListenerProbe.new()
	civilian.enemy = false
	_world.add_child(enemy_a)
	_world.add_child(enemy_b)
	_world.add_child(civilian)
	_events.clear()
	_noise.emit_noise(42.0)
	_check(_events.size() == 1 and bool(_events[0]["heard"]),
		"HUD recebe confirmação quando algum inimigo ouve")
	_check(enemy_a.received.size() == 1 and enemy_b.received.size() == 1
		and civilian.received.size() == 1, "Ruído é entregue a todos os sensores sem curto-circuito")
	_check(enemy_a.received[0]["origin"] == _player.global_position
		and enemy_a.received[0]["radius"] == _events[0]["radius"],
		"HUD e sensores recebem exatamente a mesma origem e raio")
	enemy_a.accepts = false
	enemy_b.accepts = false
	_noise.emit_noise(26.0)
	_check(not bool(_events.back()["heard"]), "Civil sozinho ouvindo não acusa inimigo no HUD")
	enemy_a.free()
	enemy_b.free()
	civilian.free()


func _test_movement() -> void:
	_events.clear()
	Input.action_press("ui_up")
	await _frames(50)
	_check(_count_level(26.0) > 0 and _count_level(44.0) == 0,
		"Caminhada real produz passos de 26 dB")
	_events.clear()
	Input.action_press("crouch")
	await _frames(50)
	_check(_count_level(22.0) > 0 and _count_level(44.0) == 0,
		"Movimento agachado real produz passos de 22 dB")
	Input.action_release("crouch")
	_events.clear()
	Input.action_press("sprint")
	await _frames(50)
	_check(_count_level(44.0) > 0, "Corrida real produz passos de 44 dB")
	Input.action_release("sprint")
	Input.action_release("ui_up")
	await _frames(30)
	_events.clear()
	await _frames(40)
	_check(_events.is_empty(), "Parado não produz passos")
	Input.action_press("jump")
	await _frames(2)
	Input.action_release("jump")
	_check(_count_level(42.0) == 1 and _player.velocity.y > 0.0,
		"Impulso de pulo aceito produz um evento de 42 dB")
	Input.action_press("jump")
	await _frames(2)
	Input.action_release("jump")
	_check(_count_level(42.0) == 1, "Pulo recusado no ar não produz outro ruído")
	_noise.update_motion(1.0, 7.0, false, true, false)
	_check(_events.size() == 1, "Movimento no ar não produz passos")
	await _frames(85)


func _test_inactive_states() -> void:
	_events.clear()
	paused = true
	_noise.update_motion(1.0, 7.0, true, true, false)
	_noise.emit_jump_noise()
	_check(_events.is_empty(), "Jogo pausado não produz ruído")
	paused = false
	_player.set_physics_process(false)
	_noise.update_motion(1.0, 7.0, true, true, false)
	_noise.emit_jump_noise()
	_check(_events.is_empty(), "Jogador desativado ao entrar no veículo não emite sons próprios")
	_player.set_physics_process(true)
	_player.call("set_movement_locked", true)
	_noise.update_motion(1.0, 7.0, true, true, false)
	_check(_events.is_empty(), "Movimento bloqueado não produz passos")
	_player.call("set_movement_locked", false)
	_player.set("_fall_state", 1)
	_noise.update_motion(1.0, 7.0, true, true, false)
	_check(_events.is_empty(), "Jogador incapacitado não produz passos")
	_player.set("_fall_state", 0)
	_player.set("_is_dead", true)
	_noise.emit_jump_noise()
	_check(_events.is_empty(), "Jogador morto não emite sons próprios")
	_player.set("_is_dead", false)
	_player.set("_debug_flight_enabled", true)
	_noise.update_motion(1.0, 7.0, true, true, false)
	_check(_events.is_empty(), "Voo de depuração não produz passos")
	_player.set("_debug_flight_enabled", false)


func _test_pickup() -> void:
	var full_inventory_item: RigidBody3D = _make_item(4, false)
	_events.clear()
	_player.set("_pickup_requested", true)
	await _frames(2)
	_check(full_inventory_item.get("carrier") == _player and _count_level(46.0) == 1,
		"Coleta confirmada no inventário produz um ruído de 46 dB")
	var refused_item: RigidBody3D = _make_item(1, false)
	_events.clear()
	_player.set("_pickup_requested", true)
	await _frames(2)
	_check(refused_item.get("carrier") == null and _events.is_empty(),
		"Inventário cheio recusa coleta sem gerar ruído")
	refused_item.free()
	var large_item: RigidBody3D = _make_item(1, true)
	_player.set("_pickup_requested", true)
	await _frames(2)
	_check(large_item.get("carrier") == _player and _count_level(46.0) == 1,
		"Coleta confirmada com duas mãos também produz um ruído")
	_events.clear()
	_player.set("_pickup_requested", true)
	await _frames(2)
	_check(_events.is_empty(), "Mãos ocupadas não repetem ruído de roubo")


func _make_item(slot_cost: int, two_handed: bool) -> RigidBody3D:
	var item: RigidBody3D = ScrapScript.new() as RigidBody3D
	item.set("slot_cost", slot_cost)
	item.set("two_handed", two_handed)
	item.freeze = true
	item.collision_layer = 0
	item.collision_mask = 0
	_world.add_child(item)
	item.global_position = _player.global_position + Vector3(0.6, 0.5, 0.0)
	item.add_to_group(&"pickup_items")
	return item


func _on_noise(origin: Vector3, decibels: float, radius: float, heard: bool) -> void:
	_events.append({"origin": origin, "decibels": decibels, "radius": radius, "heard": heard})


func _count_level(decibels: float) -> int:
	var count: int = 0
	for event: Dictionary in _events:
		if is_equal_approx(float(event["decibels"]), decibels):
			count += 1
	return count


func _frames(count: int) -> void:
	for _frame: int in count:
		await physics_frame
		await process_frame


func _check(condition: bool, message: String) -> void:
	if condition:
		print("CHECK|PASS|%s" % message)
	else:
		_failures += 1
		push_error("CHECK|FAIL|%s" % message)
