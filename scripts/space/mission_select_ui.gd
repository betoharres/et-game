class_name MissionSelectUI
extends CanvasLayer

## Terminal de selecao de fase mostrado pelo console da plataforma orbital.
## Le o catalogo de LevelDefinition e lista as fases disponiveis e bloqueadas.
##
## Adicionar uma fase nova nao toca este script: basta um LevelDefinition.tres
## novo dentro do LevelCatalog.

signal level_chosen(level : LevelDefinition)
signal closed

const CATALOG_PATH : String = "res://scenes/Space/Levels/level_catalog.tres"

const LOCKED_COLOR : Color = Color(0.5, 0.55, 0.62, 1.0)
const AVAILABLE_COLOR : Color = Color(0.42, 0.92, 1.0, 1.0)

var _catalog : LevelCatalog
var _level_buttons : Array[Button] = []
var _selected_level : LevelDefinition = null

@onready var level_list : VBoxContainer = (
	$Overlay/Center/Panel/Margin/Columns/LevelColumn/ListPanel/ListMargin/LevelList
)
@onready var title_label : Label = (
	$Overlay/Center/Panel/Margin/Columns/BriefingColumn/Title
)
@onready var briefing_label : Label = (
	$Overlay/Center/Panel/Margin/Columns/BriefingColumn/Briefing
)
@onready var go_button : Button = (
	$Overlay/Center/Panel/Margin/Columns/BriefingColumn/GoButton
)
@onready var close_button : Button = (
	$Overlay/Center/Panel/Margin/Columns/BriefingColumn/CloseButton
)


func _ready() -> void:
	visible = false
	_catalog = load(CATALOG_PATH) as LevelCatalog
	_build_level_list()
	go_button.pressed.connect(_on_go_pressed)
	close_button.pressed.connect(close)
	_show_selection(null)


func _unhandled_input(event : InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for button : Button in _level_buttons:
		button.button_pressed = false
	_show_selection(null)
	for button : Button in _level_buttons:
		button.grab_focus()
		break


func close() -> void:
	if not visible:
		return
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


func _build_level_list() -> void:
	for child : Node in level_list.get_children():
		child.queue_free()
	_level_buttons.clear()

	if _catalog == null:
		return

	for level : LevelDefinition in _catalog.levels:
		if level == null:
			continue
		var button : Button = Button.new()
		button.custom_minimum_size = Vector2(0, 46)
		button.toggle_mode = true
		button.text = level.display_name
		button.modulate = AVAILABLE_COLOR if level.can_launch() else LOCKED_COLOR
		button.pressed.connect(_on_level_button_pressed.bind(level, button))
		level_list.add_child(button)
		_level_buttons.append(button)


func _on_level_button_pressed(level : LevelDefinition, pressed_button : Button) -> void:
	for button : Button in _level_buttons:
		button.button_pressed = button == pressed_button
	_show_selection(level)


func _show_selection(level : LevelDefinition) -> void:
	_selected_level = level

	if level == null:
		title_label.text = "SELECIONE UMA FASE"
		briefing_label.text = "O radar da plataforma aponta para os sinais mapeados na superficie."
		go_button.disabled = true
		return

	title_label.text = level.display_name
	if not level.available:
		briefing_label.text = level.locked_reason
	elif not level.can_launch():
		briefing_label.text = "Cena da fase nao configurada."
	else:
		briefing_label.text = level.briefing
	go_button.disabled = not level.can_launch()


func _on_go_pressed() -> void:
	if _selected_level == null or not _selected_level.can_launch():
		return
	level_chosen.emit(_selected_level)
