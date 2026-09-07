extends SceneTree

## Percorre o ciclo do F4 - desligado, velocidade, velocidade e voo, desligado -
## acionando a acao do Input Map, e cobra que nenhum toque abra painel nem pause
## o jogo: os modos agora sao um atalho direto, sem menu.

var _failed : bool = false


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed : PackedScene = load("res://scenes/Player.tscn") as PackedScene
	var player : Node = packed.instantiate()
	root.add_child(player)
	await process_frame
	player.set_physics_process(false)
	var debug_menu : Node = (
		load("res://scenes/Menu/DebugMenu.tscn") as PackedScene
	).instantiate()
	root.add_child(debug_menu)
	await process_frame
	var overlay : Control = debug_menu.get_node("Overlay") as Control

	player.set("health", 42.0)
	player.set("stamina", 3.0)
	await _press_modes_action()
	_check(bool(player.call("is_debug_god_mode_enabled")), "First press enables speed mode")
	_check(
		not bool(player.call("is_debug_flight_enabled")),
		"First press leaves flight off"
	)
	_check(not overlay.visible, "First press opens no menu")
	_check(not paused, "First press does not pause the game")
	_check(
		is_equal_approx(
			float(player.call("get_health")),
			float(player.call("get_max_health"))
		),
		"Speed mode restores health"
	)
	_check(
		is_equal_approx(
			float(player.call("get_stamina")),
			float(player.call("get_max_stamina"))
		),
		"Speed mode restores stamina"
	)

	player.call("take_damage", 999.0, Vector3.FORWARD, 5.0)
	_check(
		is_equal_approx(
			float(player.call("get_health")),
			float(player.call("get_max_health"))
		),
		"Speed mode blocks lethal damage"
	)
	_check(
		is_equal_approx(
			float(player.call("_get_movement_speed")),
			float(player.get("speed")) * 5.0
		),
		"Speed mode multiplies movement speed by five"
	)

	await _press_modes_action()
	var body : CharacterBody3D = player as CharacterBody3D
	_check(bool(player.call("is_debug_flight_enabled")), "Second press enables flight")
	_check(
		body.motion_mode == CharacterBody3D.MOTION_MODE_FLOATING,
		"Flight mode disables grounded motion"
	)
	_check(
		bool(player.call("is_debug_god_mode_enabled"))
		and bool(player.call("is_debug_flight_enabled")),
		"Speed and flight modes coexist"
	)
	_check(not overlay.visible, "Second press opens no menu")
	var starting_height : float = body.global_position.y
	Input.action_press("jump")
	player.set_physics_process(true)
	for _frame : int in 5:
		await physics_frame
	player.set_physics_process(false)
	Input.action_release("jump")
	_check(
		body.global_position.y > starting_height + 0.01,
		"Flight mode moves upward without gravity"
	)

	await _press_modes_action()
	_check(
		not bool(player.call("is_debug_god_mode_enabled"))
		and not bool(player.call("is_debug_flight_enabled")),
		"Third press turns both modes off"
	)
	_check(
		body.motion_mode == CharacterBody3D.MOTION_MODE_GROUNDED,
		"Leaving flight restores grounded motion"
	)

	player.call("take_damage", 10.0)
	_check(
		is_equal_approx(
			float(player.call("get_health")),
			float(player.call("get_max_health")) - 10.0
		),
		"Damage returns after the modes are off"
	)

	print("PLAYER_DEBUG_MODES_TEST|%s" % ["FAIL" if _failed else "PASS"])
	quit(1 if _failed else 0)


## Um toque na tecla dos modos, pelo mesmo caminho do jogo: a acao do Input Map
## chega ao `_unhandled_input` do DebugMenu.
func _press_modes_action() -> void:
	var press : InputEventAction = InputEventAction.new()
	press.action = &"debug_player_modes"
	press.pressed = true
	root.push_input(press)
	var release : InputEventAction = InputEventAction.new()
	release.action = &"debug_player_modes"
	release.pressed = false
	root.push_input(release)
	await process_frame


func _check(condition : bool, label : String) -> void:
	print("CHECK|%s|%s" % ["PASS" if condition else "FAIL", label])
	_failed = _failed or not condition
