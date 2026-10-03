extends "res://scripts/space/ship_shop.gd"

var _session: Node3D


func _ready() -> void:
	_session = get_parent().get_parent() as Node3D
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("upgrade_stations")
	add_to_group("modal_interfaces")
	_build_interface()
	_session.team_state_changed.connect(_refresh)
	_refresh()


func reserves_interaction_for(character: Node3D) -> bool:
	return character != null and character.get_world_3d() == get_world_3d() and bool(character.call("is_local_player")) and bool(character.call("is_alive")) and super.reserves_interaction_for(character)


func open(character: CharacterBody3D) -> bool:
	if _opened or not reserves_interaction_for(character) or bool(character.get("_movement_locked")):
		return false
	_character = character
	_previous_mouse_mode = Input.mouse_mode
	_previous_movement_locked = bool(character.get("_movement_locked"))
	character.call("set_movement_locked", true)
	_opened = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_overlay.show()
	_status.text = "Saldo da equipe. Repare a nave e reúna todos aqui para partir."
	_refresh()
	return true


func close() -> void:
	if not _opened:
		return
	_overlay.hide()
	_opened = false
	if is_instance_valid(_character):
		_character.call("set_movement_locked", _previous_movement_locked or not _character.is_alive())
	_character = null
	Input.mouse_mode = _previous_mouse_mode


func _buy_upgrade(index: int) -> void:
	_session.call("request_terminal_action", UPGRADE_IDS[index])


func _buy_item(item_id: String, _cost: int, _title: String) -> void:
	_session.call("request_terminal_action", StringName(item_id))


func _buy_radon() -> void:
	_session.call("request_terminal_action", &"radon")


func _repair_ship() -> void:
	_session.call("request_terminal_action", &"repair")


func _go_to_next_level() -> void:
	_session.call("request_terminal_action", &"launch")


func show_result(message: String) -> void:
	_status.text = message


func _refresh(_value: Variant = null, _level: Variant = null) -> void:
	if not is_instance_valid(_balance):
		return
	var peer_id: int = _session.multiplayer.get_unique_id()
	var money: int = int(_session.get("team_money"))
	var repaired: bool = bool(_session.get("ship_repaired"))
	_balance.text = "EQUIPE $ %d · FASE %d · RADON %s" % [money, int(_session.get("mission_round")), _format_time(float(_session.get("team_radon")))]
	for index: int in UPGRADE_IDS.size():
		var cost: int = int(_session.call("get_purchase_cost", peer_id, UPGRADE_IDS[index]))
		_upgrade_buttons[index].text = "%s · $ %d" % [UPGRADE_TITLES[index], cost] if cost > 0 else UPGRADE_TITLES[index] + " · MÁXIMO"
		_upgrade_buttons[index].disabled = cost <= 0 or money < cost
	_repair_button.text = "NAVE REPARADA" if repaired else "REPARAR NAVE · $ %d" % REPAIR_COST
	_repair_button.disabled = repaired or money < REPAIR_COST
	_next_level_button.disabled = not repaired or _session.get("mission_phase") != &"collecting"
	_radon_button.text = "RADON +10 MIN · $ %d" % RADON_COST
	_radon_button.disabled = money < RADON_COST or float(_session.get("team_radon")) >= GAME_PROGRESS.radon_capacity_seconds
	var equipment: Array[Button] = [_goggles_button, _shield_button, _watch_button]
	var ids: Array[StringName] = [&"xray_goggles", &"energy_shield", &"predator_watch"]
	for index: int in ids.size():
		var cost: int = int(_session.call("get_purchase_cost", peer_id, ids[index]))
		equipment[index].disabled = cost <= 0 or money < cost
		equipment[index].text = "%s · $ %d" % [str(ids[index]).replace("_", " ").capitalize(), cost] if cost > 0 else str(ids[index]) + " · INSTALADO"
