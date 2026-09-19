class_name FarmUpgradeTotem
extends Node3D

const HUD_THEME : Theme = preload("res://Materiais/hud_theme.tres")
const UPGRADE_IDS : Array[StringName] = [&"movement", &"stamina", &"recovery"]
const UPGRADE_TITLES : Array[String] = ["PASSO CÓSMICO", "FÔLEGO EXTRA", "SEGUNDO FÔLEGO"]
const UPGRADE_DESCRIPTIONS : Array[String] = [
	"+10% de velocidade ao andar, correr e agachar por nível.",
	"+25 de stamina máxima por nível.",
	"+25% de recuperação de stamina por nível."
]
const ACCENT : Color = Color(0.4, 0.95, 0.84)

@export_range(1.0, 4.0, 0.1) var interaction_radius : float = 2.3

var _opened : bool = false
var _character : CharacterBody3D = null
var _previous_mouse_mode : Input.MouseMode = Input.MOUSE_MODE_CAPTURED
var _previous_paused : bool = false
var _previous_movement_locked : bool = false
var _overlay : Control
var _balance_label : Label
var _feedback_label : Label
var _close_button : Button
var _level_labels : Array[Label] = []
var _buy_buttons : Array[Button] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("upgrade_stations")
	add_to_group("modal_interfaces")
	_build_interface()
	GlobalScore.money_changed.connect(_on_money_changed)
	GlobalScore.upgrade_changed.connect(_on_upgrade_changed)
	_refresh_interface()


func _input(event : InputEvent) -> void:
	if event.is_echo():
		return
	if _opened:
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact"):
			close()
			get_viewport().set_input_as_handled()
		return
	if get_tree().paused or not event.is_action_pressed("interact"):
		return
	for candidate : Node in get_tree().get_nodes_in_group("characters"):
		var character : CharacterBody3D = candidate as CharacterBody3D
		if character != null and open(character):
			get_viewport().set_input_as_handled()
			return


func _exit_tree() -> void:
	if _opened:
		close()


func is_open() -> bool:
	return _opened


func reserves_interaction_for(character : Node3D) -> bool:
	if _opened:
		return character == _character
	if character == null or not character.has_method("set_movement_locked"):
		return false
	if character.has_method("is_alive") and not bool(character.call("is_alive")):
		return false
	return global_position.distance_squared_to(character.global_position) <= interaction_radius * interaction_radius


func get_interaction_prompt(character : Node3D) -> String:
	if _opened or not reserves_interaction_for(character):
		return ""
	for event : InputEvent in InputMap.action_get_events("interact"):
		return "[%s] Melhorias" % event.as_text().replace(" (Physical)", "")
	return "[Interagir] Melhorias"


func open(character : CharacterBody3D) -> bool:
	if _opened or get_tree().paused or not reserves_interaction_for(character):
		return false
	# A chegada pelo feixe e as ações de carregar já são donas deste bloqueio.
	if bool(character.get("_movement_locked")):
		return false
	_character = character
	_previous_mouse_mode = Input.mouse_mode
	_previous_paused = get_tree().paused
	_previous_movement_locked = bool(_character.get("_movement_locked"))
	_character.call("set_movement_locked", true)
	_opened = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_overlay.show()
	_feedback_label.text = "Entregue os objetos no ponto de coleta para receber dinheiro."
	_feedback_label.modulate = Color(0.76, 0.82, 0.9)
	_refresh_interface()
	_close_button.grab_focus()
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


func _buy_upgrade(upgrade_id : StringName) -> void:
	if not _opened:
		return
	var cost : int = GlobalScore.get_upgrade_cost(upgrade_id)
	if cost < 0:
		_feedback_label.text = "Esta melhoria já está no nível máximo."
		return
	if not GlobalScore.purchase_upgrade(upgrade_id):
		_feedback_label.text = "Faltam $ %d. Entregue mais objetos no ponto de coleta." % (cost - GlobalScore.money)
		_feedback_label.modulate = Color(1.0, 0.67, 0.44)
		return
	var upgrade_index : int = UPGRADE_IDS.find(upgrade_id)
	_feedback_label.text = "%s instalada! Nível %d/3." % [UPGRADE_TITLES[upgrade_index], GlobalScore.get_upgrade_level(upgrade_id)]
	_feedback_label.modulate = ACCENT
	_refresh_interface()


func _on_money_changed(_balance : int) -> void:
	_refresh_interface()


func _on_upgrade_changed(_upgrade_id : StringName, _level : int) -> void:
	_refresh_interface()


func _refresh_interface() -> void:
	_balance_label.text = "SEU DINHEIRO   $ %d" % GlobalScore.money
	for index : int in range(UPGRADE_IDS.size()):
		var upgrade_id : StringName = UPGRADE_IDS[index]
		var level : int = GlobalScore.get_upgrade_level(upgrade_id)
		var effect : String
		match upgrade_id:
			&"movement":
				effect = "+%d%% de velocidade" % (level * 10)
			&"stamina":
				effect = "+%d de stamina máxima" % (level * 25)
			&"recovery":
				effect = "+%d%% de recuperação" % (level * 25)
		_level_labels[index].text = "NÍVEL %d/3  ·  %s" % [level, effect]
		var cost : int = GlobalScore.get_upgrade_cost(upgrade_id)
		var button : Button = _buy_buttons[index]
		button.disabled = cost < 0
		if cost < 0:
			button.text = "MÁXIMO"
		elif GlobalScore.money < cost:
			button.text = "COMPRAR · $ %d\nFaltam $ %d" % [cost, cost - GlobalScore.money]
		else:
			button.text = "COMPRAR · $ %d" % cost


func _build_interface() -> void:
	var canvas : CanvasLayer = CanvasLayer.new()
	canvas.name = "UpgradeUI"
	canvas.layer = 95
	add_child(canvas)
	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.theme = HUD_THEME
	canvas.add_child(_overlay)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.hide()
	var backdrop : ColorRect = ColorRect.new()
	backdrop.color = Color(0.005, 0.012, 0.026, 0.86)
	_overlay.add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center : CenterContainer = CenterContainer.new()
	_overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel : PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(860, 0)
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.05, 0.075), ACCENT))
	center.add_child(panel)
	var margin : MarginContainer = MarginContainer.new()
	for side : String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	panel.add_child(margin)
	var content : VBoxContainer = VBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	margin.add_child(content)
	content.add_child(_label("TOTEM DE MELHORIAS", 32, ACCENT))
	content.add_child(_label("Objetos da Terra, tecnologia de outro mundo.", 19, Color(0.76, 0.82, 0.9)))
	_balance_label = _label("", 24, Color(1.0, 0.83, 0.43))
	content.add_child(_balance_label)
	for index : int in range(UPGRADE_IDS.size()):
		_add_upgrade_row(content, index)
	_feedback_label = _label("", 18, Color.WHITE)
	_feedback_label.custom_minimum_size.y = 52
	_feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_feedback_label)
	var footer : HBoxContainer = HBoxContainer.new()
	footer.add_theme_constant_override("separation", 24)
	content.add_child(footer)
	var session_label : Label = _label("Melhorias e dinheiro duram esta sessão.", 17, Color(0.62, 0.7, 0.79))
	session_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(session_label)
	_close_button = Button.new()
	_close_button.text = "VOLTAR"
	_close_button.custom_minimum_size = Vector2(152, 48)
	_close_button.add_theme_font_size_override("font_size", 19)
	_close_button.pressed.connect(close)
	footer.add_child(_close_button)


func _add_upgrade_row(parent : VBoxContainer, index : int) -> void:
	var panel : PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.04, 0.085, 0.11), Color(0.15, 0.3, 0.34)))
	parent.add_child(panel)
	var margin : MarginContainer = MarginContainer.new()
	for side : String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)
	var row : HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	margin.add_child(row)
	var details : VBoxContainer = VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 6)
	row.add_child(details)
	details.add_child(_label(UPGRADE_TITLES[index], 23, Color.WHITE))
	var description : Label = _label(UPGRADE_DESCRIPTIONS[index], 18, Color(0.76, 0.82, 0.9))
	description.custom_minimum_size.x = 510
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(description)
	var level_label : Label = _label("", 17, ACCENT)
	details.add_child(level_label)
	_level_labels.append(level_label)
	var button : Button = Button.new()
	button.custom_minimum_size = Vector2(214, 66)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", 18)
	button.pressed.connect(_buy_upgrade.bind(UPGRADE_IDS[index]))
	row.add_child(button)
	_buy_buttons.append(button)


func _label(value : String, font_size : int, color : Color) -> Label:
	var label : Label = Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _panel_style(background : Color, border : Color) -> StyleBoxFlat:
	var style : StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	return style
