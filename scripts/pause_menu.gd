extends CanvasLayer

const REBIND_ACTIONS : Array[StringName] = [
	&"ui_up",
	&"ui_down",
	&"ui_left",
	&"ui_right",
	&"sprint",
	&"jump",
	&"crouch",
	&"interact",
	&"request_abduction",
	&"toggle_eye_light",
	&"debug_vision_map"
]

const REBIND_LABELS : Array[String] = [
	"Frente",
	"Trás",
	"Esquerda",
	"Direita",
	"Correr",
	"Pular",
	"Agachar",
	"Interagir",
	"Chamar nave",
	"Luz dos olhos",
	"Mini mapa"
]

@onready var overlay : Control = $Overlay
@onready var pause_buttons : VBoxContainer = (
	$Overlay/CenterContainer/MenuPanel/MarginContainer/PauseButtons
)
@onready var controls_panel : VBoxContainer = (
	$Overlay/CenterContainer/MenuPanel/MarginContainer/ControlsPanel
)
@onready var resume_button : Button = (
	$Overlay/CenterContainer/MenuPanel/MarginContainer/PauseButtons/ResumeButton
)
@onready var controls_button : Button = (
	$Overlay/CenterContainer/MenuPanel/MarginContainer/PauseButtons/ControlsButton
)
@onready var main_menu_button : Button = (
	$Overlay/CenterContainer/MenuPanel/MarginContainer/PauseButtons/MainMenuButton
)
@onready var exit_button : Button = (
	$Overlay/CenterContainer/MenuPanel/MarginContainer/PauseButtons/ExitButton
)
@onready var controls_back_button : Button = (
	$Overlay/CenterContainer/MenuPanel/MarginContainer/ControlsPanel/BackButton
)
@onready var action_buttons : Array[Button] = [
	$Overlay/CenterContainer/MenuPanel/MarginContainer/ControlsPanel/ForwardButton,
	$Overlay/CenterContainer/MenuPanel/MarginContainer/ControlsPanel/BackwardButton,
	$Overlay/CenterContainer/MenuPanel/MarginContainer/ControlsPanel/LeftButton,
	$Overlay/CenterContainer/MenuPanel/MarginContainer/ControlsPanel/RightButton,
	$Overlay/CenterContainer/MenuPanel/MarginContainer/ControlsPanel/SprintButton,
	$Overlay/CenterContainer/MenuPanel/MarginContainer/ControlsPanel/JumpButton,
	$Overlay/CenterContainer/MenuPanel/MarginContainer/ControlsPanel/CrouchButton,
	$Overlay/CenterContainer/MenuPanel/MarginContainer/ControlsPanel/InteractButton,
	$Overlay/CenterContainer/MenuPanel/MarginContainer/ControlsPanel/AbductionButton,
	$Overlay/CenterContainer/MenuPanel/MarginContainer/ControlsPanel/EyeLightButton,
	$Overlay/CenterContainer/MenuPanel/MarginContainer/ControlsPanel/DebugMapButton
]

var rebinding_action : StringName = &""
var rebinding_button : Button = null
var returning_to_menu : bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	overlay.visible = false
	pause_buttons.visible = true
	controls_panel.visible = false

	resume_button.pressed.connect(_resume_game)
	controls_button.pressed.connect(_show_controls)
	main_menu_button.pressed.connect(_back_to_main_menu)
	exit_button.pressed.connect(_exit_game)
	controls_back_button.pressed.connect(_show_pause_buttons)

	for index : int in range(REBIND_ACTIONS.size()):
		action_buttons[index].pressed.connect(
			_start_rebinding.bind(
				REBIND_ACTIONS[index],
				action_buttons[index]
			)
		)

	_update_control_buttons()


func _input(event : InputEvent) -> void:
	if returning_to_menu:
		return

	if rebinding_action != &"":
		_handle_rebinding_input(event)
		return

	if event.is_action_pressed("ui_cancel"):
		if overlay.visible and controls_panel.visible:
			_show_pause_buttons()
		else:
			_set_pause_visible(not overlay.visible)

		get_viewport().set_input_as_handled()


func _handle_rebinding_input(event : InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		rebinding_action = &""
		rebinding_button = null
		_update_control_buttons()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo:
		var key_event : InputEventKey = event.duplicate() as InputEventKey
		InputMap.action_erase_events(rebinding_action)
		InputMap.action_add_event(rebinding_action, key_event)
		rebinding_action = &""
		rebinding_button = null
		_update_control_buttons()
		get_viewport().set_input_as_handled()


func _set_pause_visible(should_pause : bool) -> void:
	overlay.visible = should_pause
	get_tree().paused = should_pause

	if should_pause:
		_show_pause_buttons()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		resume_button.grab_focus()
	else:
		rebinding_action = &""
		rebinding_button = null
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _resume_game() -> void:
	_set_pause_visible(false)


func _show_controls() -> void:
	pause_buttons.visible = false
	controls_panel.visible = true
	_update_control_buttons()
	action_buttons[0].grab_focus()


func _show_pause_buttons() -> void:
	rebinding_action = &""
	rebinding_button = null
	controls_panel.visible = false
	pause_buttons.visible = true
	_update_control_buttons()
	resume_button.grab_focus()


func _back_to_main_menu() -> void:
	if returning_to_menu:
		return
	returning_to_menu = true
	get_tree().paused = false
	overlay.visible = false
	var scene_transition : Node = get_node("/root/SceneTransition")
	scene_transition.warp_to("res://scenes/main_menu.tscn")


func _exit_game() -> void:
	get_tree().paused = false
	get_tree().quit()


func _start_rebinding(action : StringName, button : Button) -> void:
	rebinding_action = action
	rebinding_button = button
	button.text = "Pressione uma tecla..."


func _update_control_buttons() -> void:
	for index : int in range(REBIND_ACTIONS.size()):
		action_buttons[index].text = (
			REBIND_LABELS[index]
			+ ": "
			+ _get_action_key(REBIND_ACTIONS[index])
		)


func _get_action_key(action : StringName) -> String:
	var events : Array[InputEvent] = InputMap.action_get_events(action)

	for input_event : InputEvent in events:
		if input_event is InputEventKey:
			var key_event : InputEventKey = input_event as InputEventKey
			var keycode : Key = key_event.physical_keycode

			if keycode == KEY_NONE:
				keycode = key_event.keycode

			return OS.get_keycode_string(keycode)

	return "Sem tecla"
