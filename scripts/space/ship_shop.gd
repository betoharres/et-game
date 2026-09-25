class_name ShipShop
extends Node3D

const HUD_THEME: Theme = preload("res://Materiais/hud_theme.tres")
const GAME_PROGRESS = preload("res://scripts/levels/game_progress.gd")
const UPGRADE_IDS: Array[StringName] = [&"movement", &"stamina", &"recovery"]
const UPGRADE_TITLES: Array[String] = ["PASSO CÓSMICO", "FÔLEGO EXTRA", "SEGUNDO FÔLEGO"]
const UPGRADE_DESCRIPTIONS: Array[String] = [
	"+10% velocidade por nível.", "+25 stamina máxima por nível.", "+25% recuperação de stamina por nível."
]
const REPAIR_COST: int = 1000
const OXYGEN_COST: int = 40
const OXYGEN_PURCHASE_SECONDS: float = 600.0
const SHIELD_COST: int = 180

@export_range(1.0, 5.0, 0.1) var interaction_radius: float = 3.0
var _opened: bool = false
var _character: CharacterBody3D
var _previous_mouse_mode: Input.MouseMode
var _previous_paused: bool = false
var _previous_movement_locked: bool = false
var _overlay: Control
var _status: Label
var _balance: Label
var _repair_button: Button
var _oxygen_button: Button
var _upgrade_buttons: Array[Button] = []
var _goggles_button: Button
var _shield_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("upgrade_stations")
	add_to_group("modal_interfaces")
	_build_interface()
	GlobalScore.money_changed.connect(_refresh)
	GlobalScore.upgrade_changed.connect(_refresh)
	_refresh()


func _input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if _opened:
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact"):
			close()
			get_viewport().set_input_as_handled()
		return
	if get_tree().paused or not event.is_action_pressed("interact"):
		return
	for candidate: Node in get_tree().get_nodes_in_group("players"):
		var character: CharacterBody3D = candidate as CharacterBody3D
		if character != null and open(character):
			get_viewport().set_input_as_handled()
			return


func _exit_tree() -> void:
	if _opened:
		close()


func reserves_interaction_for(character: Node3D) -> bool:
	if _opened:
		return character == _character
	return character != null and global_position.distance_squared_to(character.global_position) <= interaction_radius * interaction_radius


func is_open() -> bool:
	return _opened


func get_interaction_prompt(character: Node3D) -> String:
	if not reserves_interaction_for(character) or _opened:
		return ""
	return "[E] Nave / melhorias"


func open(character: CharacterBody3D) -> bool:
	if _opened or get_tree().paused or not reserves_interaction_for(character) or bool(character.get("_movement_locked")):
		return false
	_character = character
	_previous_mouse_mode = Input.mouse_mode
	_previous_paused = get_tree().paused
	_previous_movement_locked = bool(character.get("_movement_locked"))
	character.call("set_movement_locked", true)
	_opened = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_overlay.show()
	_status.text = "Melhorias, oxigênio e reparos duram nesta sessão."
	_refresh()
	return true


func close() -> void:
	if not _opened:
		return
	_overlay.hide()
	_opened = false
	if is_instance_valid(_character):
		_character.call("set_movement_locked", _previous_movement_locked)
	_character = null
	Input.mouse_mode = _previous_mouse_mode
	get_tree().paused = _previous_paused


func _buy_upgrade(index: int) -> void:
	var id: StringName = UPGRADE_IDS[index]
	if not GlobalScore.purchase_upgrade(id):
		_status.text = "Saldo insuficiente para essa melhoria."
		return
	_status.text = "%s instalada." % UPGRADE_TITLES[index]
	_refresh()


func _buy_oxygen() -> void:
	if not GlobalScore.spend_money(OXYGEN_COST):
		_status.text = "Saldo insuficiente para oxigênio."
		return
	GAME_PROGRESS.ship_oxygen_seconds = minf(
		GAME_PROGRESS.ship_oxygen_seconds + OXYGEN_PURCHASE_SECONDS,
		GAME_PROGRESS.oxygen_capacity_seconds
	)
	_status.text = "Oxigênio da nave reabastecido em 10 minutos."
	_refresh()


func _repair_ship() -> void:
	if not GlobalScore.spend_money(REPAIR_COST):
		_status.text = "Reparo custa $ %d. Saldo insuficiente." % REPAIR_COST
		return
	_status.text = "Reparo comprado. A liberacao da proxima fase ainda nao esta ativa."
	_refresh()


func _refresh(_value: Variant = null, _level: Variant = null) -> void:
	if not is_instance_valid(_balance):
		return
	_balance.text = "SALDO  $ %d     OXIGÊNIO DA NAVE  %s" % [GlobalScore.money, _format_time(GAME_PROGRESS.ship_oxygen_seconds)]
	for i: int in range(_upgrade_buttons.size()):
		var cost: int = GlobalScore.get_upgrade_cost(UPGRADE_IDS[i])
		_upgrade_buttons[i].text = "NÍVEL MÁXIMO" if cost < 0 else "MELHORAR · $ %d" % cost
		_upgrade_buttons[i].disabled = cost < 0 or GlobalScore.money < cost
	_oxygen_button.disabled = GAME_PROGRESS.ship_oxygen_seconds >= GAME_PROGRESS.oxygen_capacity_seconds or GlobalScore.money < OXYGEN_COST
	_oxygen_button.text = "OXIGÊNIO +10 MIN · $ %d" % OXYGEN_COST
	_repair_button.disabled = GlobalScore.money < REPAIR_COST
	_repair_button.text = "REPARAR NAVE · $ %d" % REPAIR_COST
	_goggles_button.text = "ÓCULOS DE RAIO X INSTALADOS" if GlobalScore.has_item("xray_goggles") else "COMPRAR ÓCULOS DE RAIO X · $ 500"
	_goggles_button.disabled = GlobalScore.has_item("xray_goggles") or GlobalScore.money < 500
	_shield_button.text = "ESCUDO DE ENERGIA · EM BREVE"
	_shield_button.disabled = true


func _build_interface() -> void:
	var canvas: CanvasLayer = CanvasLayer.new()
	canvas.layer = 95
	add_child(canvas)
	_overlay = Control.new()
	_overlay.theme = HUD_THEME
	canvas.add_child(_overlay)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.hide()
	var backdrop: ColorRect = ColorRect.new()
	backdrop.color = Color(0.005, 0.012, 0.026, 0.88)
	_overlay.add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center: CenterContainer = CenterContainer.new()
	_overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(800, 0)
	center.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)
	var content: VBoxContainer = VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	margin.add_child(content)
	content.add_child(_label("TERMINAL DA NAVE", 30))
	_balance = _label("", 20)
	content.add_child(_balance)
	for i: int in range(UPGRADE_IDS.size()):
		var button: Button = Button.new()
		button.custom_minimum_size.y = 48
		button.text = UPGRADE_TITLES[i] + " · " + UPGRADE_DESCRIPTIONS[i]
		button.pressed.connect(_buy_upgrade.bind(i))
		content.add_child(button)
		_upgrade_buttons.append(button)
	_repair_button = Button.new()
	_repair_button.custom_minimum_size.y = 52
	_repair_button.pressed.connect(_repair_ship)
	content.add_child(_repair_button)
	_oxygen_button = Button.new()
	_oxygen_button.custom_minimum_size.y = 48
	_oxygen_button.pressed.connect(_buy_oxygen)
	content.add_child(_oxygen_button)
	_goggles_button = Button.new()
	_goggles_button.custom_minimum_size.y = 48
	_goggles_button.pressed.connect(_buy_item.bind("xray_goggles", 500, "ÓCULOS DE RAIO X"))
	content.add_child(_goggles_button)
	_shield_button = Button.new()
	_shield_button.custom_minimum_size.y = 48
	_shield_button.text = "ESCUDO DE ENERGIA · EM BREVE"
	_shield_button.disabled = true
	content.add_child(_shield_button)
	_status = _label("", 17)
	content.add_child(_status)
	var close_button: Button = Button.new()
	close_button.text = "VOLTAR"
	close_button.pressed.connect(close)
	content.add_child(close_button)


func _buy_goggles() -> void:
	_buy_item("xray_goggles", 500, "ÓCULOS DE RAIO X")


func _buy_item(item_id: String, cost: int, title: String) -> void:
	if GlobalScore.has_item(item_id):
		_status.text = "%s já está instalado." % title
		return
	if not GlobalScore.spend_money(cost):
		_status.text = "%s custa $ %d." % [title, cost]
		return
	GlobalScore.add_item(item_id)
	if item_id == "xray_goggles":
		GlobalScore.xray_goggles_owned = true
		if is_instance_valid(_character):
			_character.call("grant_xray_goggles")
	_status.text = "%s instalado no inventário. B ativa o raio X." % title
	_refresh()


func _on_shield_requested() -> void:
	_status.text = "O escudo de energia ainda não está disponível."


func _label(value: String, size: int) -> Label:
	var label: Label = Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", size)
	return label


func _format_time(seconds: float) -> String:
	var total: int = ceili(seconds)
	return "%02d:%02d" % [total / 60, total % 60]
