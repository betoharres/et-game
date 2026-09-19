extends SceneTree

var _failed : bool = false
var _upgrade_notifications : int = 0
var _wallet : Node


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_wallet = root.get_node("GlobalScore")
	_wallet.connect("upgrade_changed", _on_upgrade_changed)
	_check(int(_wallet.get("money")) == 0, "Nova sessão começa sem dinheiro")
	_wallet.call("add_money", -10)
	_wallet.call("add_money", 0)
	_check(int(_wallet.get("money")) == 0, "Créditos negativos e zero são ignorados")
	_check(not bool(_wallet.call("spend_money", -1)), "Gasto negativo não cria dinheiro")
	_check(not bool(_wallet.call("spend_money", 0)), "Gasto zero não conta como compra")
	_check(not bool(_wallet.call("purchase_upgrade", &"unknown")), "Melhoria desconhecida é recusada")
	_wallet.call("add_money", 59)
	_check(not bool(_wallet.call("purchase_upgrade", &"movement")), "Saldo insuficiente recusa melhoria")
	_check(int(_wallet.get("money")) == 59 and _upgrade_notifications == 0, "Recusa preserva saldo e nível")

	var world : Node3D = Node3D.new()
	root.add_child(world)
	current_scene = world
	var packed : PackedScene = load("res://scenes/Player.tscn") as PackedScene
	var player : CharacterBody3D = packed.instantiate() as CharacterBody3D
	var base : Dictionary[StringName, float] = {}
	for property : StringName in [&"speed", &"sprint_speed", &"crouch_speed", &"max_stamina", &"stamina_recovery_per_second"]:
		base[property] = float(player.get(property))
	player.position = Vector3(0, 0, 1.6)
	world.add_child(player)
	player.set_physics_process(false)
	var totem : Node3D = (load("res://scenes/Farm/FarmUpgradeTotem.tscn") as PackedScene).instantiate() as Node3D
	world.add_child(totem)
	var pause_menu : Node = (load("res://scenes/Menu/PauseMenu.tscn") as PackedScene).instantiate()
	world.add_child(pause_menu)
	await process_frame

	_wallet.call("add_money", 1)
	_check(bool(_wallet.call("purchase_upgrade", &"movement")), "Saldo exato compra o primeiro nível")
	_check(int(_wallet.get("money")) == 0, "Compra desconta seu preço uma vez")
	_check(is_equal_approx(float(player.get("speed")), base[&"speed"] * 1.1), "Compra altera imediatamente o Player real")
	_check(_upgrade_notifications == 1, "Compra emite uma atualização de melhoria")

	_check(bool(totem.call("reserves_interaction_for", player)), "Totem reserva interação de jogador próximo")
	player.position.z = 8.0
	_check(not bool(totem.call("open", player)), "Totem distante não abre")
	player.position.z = 1.6
	player.call("set_movement_locked", true)
	_check(not bool(totem.call("open", player)), "Totem respeita bloqueio de movimento existente")
	_check(bool(player.get("_movement_locked")), "Recusa preserva bloqueio anterior")
	player.call("set_movement_locked", false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var previous_mouse_mode : Input.MouseMode = Input.mouse_mode
	print("MOUSE_RESTORE_SETUP|display=%s|requested=%d|observed=%d" % [DisplayServer.get_name(), Input.MOUSE_MODE_CAPTURED, previous_mouse_mode])
	if DisplayServer.get_name() != "headless":
		_check(previous_mouse_mode == Input.MOUSE_MODE_CAPTURED, "Janela real aceita captura do mouse antes de abrir loja")
	await _press(&"interact")
	_check(bool(totem.call("is_open")) and paused, "Interagir abre o totem e pausa o mundo")
	_check(bool(player.get("_movement_locked")), "Loja bloqueia controles do jogador")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Loja libera o mouse")
	_check(not bool(player.get("_pickup_requested")), "Interação da loja não solicita coleta")
	_check(String(totem.call("get_interaction_prompt", player)).is_empty(), "Loja aberta não exibe prompt de interação")
	var buttons : Array = totem.get("_buy_buttons") as Array
	(buttons[1] as Button).pressed.emit()
	_check(int(_wallet.get("money")) == 0 and int(_wallet.call("get_upgrade_level", &"stamina")) == 0, "Botão sem fundos preserva economia")
	var feedback : Label = totem.get("_feedback_label") as Label
	_check(feedback.text.contains("Faltam"), "Loja explica dinheiro insuficiente")
	_wallet.call("add_money", 1000)
	(buttons[1] as Button).pressed.emit()
	_check(int(_wallet.call("get_upgrade_level", &"stamina")) == 1, "Botão compra melhoria de stamina")
	_check(is_equal_approx(float(player.get("max_stamina")), base[&"max_stamina"] + 25.0), "Compra na loja aumenta stamina real")
	await _press(&"ui_cancel")
	_check(not bool(totem.call("is_open")) and not paused, "ESC fecha loja e retoma o mundo")
	_check(not bool(player.get("_movement_locked")), "Fechar restaura controle de movimento")
	_check(Input.mouse_mode == previous_mouse_mode, "Fechar restaura o modo real do mouse anterior à loja")
	_check(not (pause_menu.get_node("Overlay") as Control).visible, "Mesmo ESC não abre PauseMenu")

	world.move_child(pause_menu, 0)
	await _press(&"interact")
	await _press(&"ui_cancel")
	_check(not paused and not (pause_menu.get_node("Overlay") as Control).visible, "ESC também funciona com ordem inversa dos nós")
	await _press(&"ui_cancel")
	_check(paused and (pause_menu.get_node("Overlay") as Control).visible, "PauseMenu continua abrindo fora da loja")
	await _press(&"ui_cancel")
	_check(not paused, "PauseMenu continua fechando normalmente")

	for upgrade_id : StringName in [&"movement", &"stamina", &"recovery"]:
		while int(_wallet.call("get_upgrade_level", upgrade_id)) < 3:
			if not bool(_wallet.call("purchase_upgrade", upgrade_id)):
				_check(false, "Compra dos demais níveis cabe no saldo de teste")
				break
		var balance_before : int = int(_wallet.get("money"))
		_check(not bool(_wallet.call("purchase_upgrade", upgrade_id)), "Recusa quarto nível de %s" % upgrade_id)
		_check(int(_wallet.get("money")) == balance_before, "Teto preserva saldo de %s" % upgrade_id)
	_check(int(_wallet.get("money")) == 130, "Nove melhorias custam exatamente $ 930")
	_check(_upgrade_notifications == 9, "Cada nível adquirido notifica uma única vez")
	_check(not bool(_wallet.call("spend_money", 131)), "Não gasta acima do saldo")
	_check(bool(_wallet.call("spend_money", 10)) and int(_wallet.get("money")) == 120, "Gasto válido desconta valor exato")
	_wallet.call("add_money", 10)
	for _repeat : int in range(5):
		player.call("_apply_purchased_upgrades")
	_check_stats(player, base)
	player.set("stamina", 0.0)
	player.call("_update_stamina", 1.0, false)
	_check(is_equal_approx(float(player.get("stamina")), base[&"stamina_recovery_per_second"] * 1.75), "Recuperação aumentada é usada pela simulação de stamina")
	var next_player : CharacterBody3D = packed.instantiate() as CharacterBody3D
	next_player.position = Vector3(10, 0, 0)
	world.add_child(next_player)
	next_player.set_physics_process(false)
	_check_stats(next_player, base)
	_check(is_equal_approx(float(next_player.get("stamina")), float(next_player.get("max_stamina"))), "Novo Player herda melhorias e inicia com stamina completa")
	next_player.free()
	_check(bool(totem.call("open", player)), "Loja continua acessível com todas melhorias")
	for button : Button in buttons:
		_check(button.disabled and button.text == "MÁXIMO", "Loja indica teto e desativa recompra")
	totem.call("close")
	world.free()
	print("FARM_UPGRADES_TEST|%s" % ("FAIL" if _failed else "PASS"))
	quit(1 if _failed else 0)


func _check_stats(player : CharacterBody3D, base : Dictionary[StringName, float]) -> void:
	for property : StringName in [&"speed", &"sprint_speed", &"crouch_speed"]:
		_check(is_equal_approx(float(player.get(property)), base[property] * 1.3), "%s recebe +30%% sem acúmulo duplicado" % property)
	_check(is_equal_approx(float(player.get("max_stamina")), base[&"max_stamina"] + 75.0), "Stamina máxima recebe +75 sem acúmulo duplicado")
	_check(is_equal_approx(float(player.get("stamina_recovery_per_second")), base[&"stamina_recovery_per_second"] * 1.75), "Recuperação recebe +75% sem acúmulo duplicado")


func _press(action : StringName) -> void:
	var event : InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = true
	root.push_input(event)
	event = InputEventAction.new()
	event.action = action
	event.pressed = false
	root.push_input(event)
	await process_frame


func _on_upgrade_changed(_upgrade_id : StringName, _level : int) -> void:
	_upgrade_notifications += 1


func _check(condition : bool, label : String) -> void:
	print("CHECK|%s|%s" % ["PASS" if condition else "FAIL", label])
	_failed = _failed or not condition
