class_name MissionDialogueUI
extends CanvasLayer

## Falas sequenciais com duas respostas configuráveis na última fala.

signal accepted
signal declined

@onready var speaker_label : Label = (
	$Overlay/Center/Panel/Margin/Content/Speaker
)
@onready var body_label : Label = (
	$Overlay/Center/Panel/Margin/Content/Body
)
@onready var continue_button : Button = (
	$Overlay/Center/Panel/Margin/Content/Buttons/ContinueButton
)
@onready var accept_button : Button = (
	$Overlay/Center/Panel/Margin/Content/Buttons/AcceptButton
)
@onready var decline_button : Button = (
	$Overlay/Center/Panel/Margin/Content/Buttons/DeclineButton
)

var _lines : Array[String] = []
var _index : int = 0


func _ready() -> void:
	visible = false
	continue_button.pressed.connect(_advance)
	accept_button.pressed.connect(_on_accept_pressed)
	decline_button.pressed.connect(_on_decline_pressed)


func _unhandled_input(event : InputEvent) -> void:
	if not visible or not continue_button.visible:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		_advance()
		get_viewport().set_input_as_handled()


func open(
	speaker : String, lines : Array[String],
	accept_text : String = "Aceitar missão", decline_text : String = "Recusar"
) -> void:
	speaker_label.text = speaker
	accept_button.text = accept_text
	decline_button.text = decline_text
	_lines = lines
	_index = 0
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_line()


func close() -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _show_line() -> void:
	body_label.text = _lines[_index] if _index < _lines.size() else ""
	var is_last : bool = _index >= _lines.size() - 1
	continue_button.visible = not is_last
	accept_button.visible = is_last
	decline_button.visible = is_last
	if is_last:
		accept_button.grab_focus()
	else:
		continue_button.grab_focus()


func _advance() -> void:
	_index = mini(_index + 1, _lines.size() - 1)
	_show_line()


func _on_accept_pressed() -> void:
	if not visible:
		return
	close()
	accepted.emit()


func _on_decline_pressed() -> void:
	if not visible:
		return
	close()
	declined.emit()
