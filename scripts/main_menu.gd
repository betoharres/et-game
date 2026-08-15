extends Control

@onready var menu_button_1 : Button = $ColorRect/MenuBar/VSeparator/MenuButton1
@onready var menu_button_2 : Button = $ColorRect/MenuBar/VSeparator/MenuButton2
@onready var menu_button_3 : Button = $ColorRect/MenuBar/VSeparator/MenuButton3

@onready var options_panel : Control = $ColorRect/MenuBar/OptionsPanel

@onready var resolution_button : OptionButton = $ColorRect/MenuBar/OptionsPanel/VBoxContainer/ResolutionButton
@onready var vsync_check_box : CheckBox = $ColorRect/MenuBar/OptionsPanel/VBoxContainer/VSyncButton
@onready var window_mode_button : Button = $ColorRect/MenuBar/OptionsPanel/VBoxContainer/WindowModeButton
@onready var keybinds_button : Button = $ColorRect/MenuBar/OptionsPanel/VBoxContainer/KeybindsButton
@onready var options_back_button : Button = $ColorRect/MenuBar/OptionsPanel/VBoxContainer/BackButton

@onready var keybinds_panel : Control = $ColorRect/MenuBar/KeybindsPanel
@onready var forward_button : Button = $ColorRect/MenuBar/KeybindsPanel/VBoxContainer/ForwardButton
@onready var backward_button : Button = $ColorRect/MenuBar/KeybindsPanel/VBoxContainer/BackwardButton
@onready var left_button : Button = $ColorRect/MenuBar/KeybindsPanel/VBoxContainer/LeftButton
@onready var right_button : Button = $ColorRect/MenuBar/KeybindsPanel/VBoxContainer/RightButton
@onready var keybinds_back_button : Button = $ColorRect/MenuBar/KeybindsPanel/VBoxContainer/BackButton


var rebinding_action : String = ""
var rebinding_button : Button = null


func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

	menu_button_1.pressed.connect(_on_play_pressed)
	menu_button_2.pressed.connect(_on_options_pressed)
	menu_button_3.pressed.connect(_on_exit_pressed)

	resolution_button.item_selected.connect(_on_resolution_selected)
	vsync_check_box.toggled.connect(_on_vsync_toggled)
	window_mode_button.pressed.connect(_on_window_mode_pressed)
	keybinds_button.pressed.connect(_on_keybinds_pressed)
	options_back_button.pressed.connect(_on_options_back_pressed)

	forward_button.pressed.connect(_on_forward_pressed)
	backward_button.pressed.connect(_on_backward_pressed)
	left_button.pressed.connect(_on_left_pressed)
	right_button.pressed.connect(_on_right_pressed)
	keybinds_back_button.pressed.connect(_on_keybinds_back_pressed)

	options_panel.visible = false
	keybinds_panel.visible = false

	setup_resolutions()
	update_vsync_check_box()
	update_window_mode_button()
	update_keybind_buttons()


# Main Menu

func _on_play_pressed() -> void:
	PhotoAlertSystem.reset()
	get_tree().change_scene_to_file("res://scenes/world.tscn")

func _on_options_pressed() -> void:
	options_panel.visible = true

func _on_exit_pressed() -> void:
	get_tree().quit()

# Options Menu

func _on_options_back_pressed() -> void:
	options_panel.visible = false

func _on_keybinds_pressed() -> void:
	options_panel.visible = false
	keybinds_panel.visible = true

# Keybinds Menu

func _on_keybinds_back_pressed() -> void:
	keybinds_panel.visible = false
	options_panel.visible = true

func _on_forward_pressed() -> void:
	start_rebinding("ui_up", forward_button)

func _on_backward_pressed() -> void:
	start_rebinding("ui_down", backward_button)

func _on_left_pressed() -> void:
	start_rebinding("ui_left", left_button)

func _on_right_pressed() -> void:
	start_rebinding("ui_right", right_button)

func start_rebinding(action_name : String, button : Button) -> void:
	rebinding_action = action_name
	rebinding_button = button

	button.text = "Press a key..."


func _input(event : InputEvent) -> void:
	if rebinding_action == "":
		return

	if event is InputEventKey and event.pressed and not event.echo:
		var key_event : InputEventKey = event

		InputMap.action_erase_events(rebinding_action)
		InputMap.action_add_event(rebinding_action, key_event)

		rebinding_action = ""
		rebinding_button = null

		update_keybind_buttons()


func update_keybind_buttons() -> void:
	forward_button.text = "Forward: " + get_action_key("ui_up")
	backward_button.text = "Backward: " + get_action_key("ui_down")
	left_button.text = "Left: " + get_action_key("ui_left")
	right_button.text = "Right: " + get_action_key("ui_right")


func get_action_key(action_name : String) -> String:
	var events : Array[InputEvent] = InputMap.action_get_events(action_name)

	if events.is_empty():
		return "Unbound"

	for event in events:
		if event is InputEventKey:
			return OS.get_keycode_string(event.keycode)

	return "Unbound"


# Resolution

func setup_resolutions() -> void:
	resolution_button.clear()

	resolution_button.add_item("1280 × 720")
	resolution_button.add_item("1600 × 900")
	resolution_button.add_item("1920 × 1080")
	resolution_button.add_item("2560 × 1440")
	resolution_button.add_item("3840 × 2160")

	var current_size : Vector2i = DisplayServer.window_get_size()
	var selected_index : int = 2

	for i in range(resolution_button.item_count):
		var resolution : Vector2i = get_resolution(i)

		if resolution == current_size:
			selected_index = i
			break

	resolution_button.select(selected_index)


func _on_resolution_selected(index : int) -> void:
	var resolution : Vector2i = get_resolution(index)

	DisplayServer.window_set_size(resolution)


func get_resolution(index : int) -> Vector2i:
	match index:
		0:
			return Vector2i(1280, 720)

		1:
			return Vector2i(1600, 900)

		2:
			return Vector2i(1920, 1080)

		3:
			return Vector2i(2560, 1440)

		4:
			return Vector2i(3840, 2160)

	return Vector2i(1920, 1080)


# V-Sync

func _on_vsync_toggled(enabled : bool) -> void:
	if enabled:
		DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_ENABLED
		)
	else:
		DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_DISABLED
		)


func update_vsync_check_box() -> void:
	var mode : int = DisplayServer.window_get_vsync_mode()

	vsync_check_box.button_pressed = (
		mode == DisplayServer.VSYNC_ENABLED
	)


# Window Mode

func _on_window_mode_pressed() -> void:
	var current_mode : int = DisplayServer.window_get_mode()

	if current_mode == DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_FULLSCREEN
		)
	else:
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_WINDOWED
		)

	update_window_mode_button()


func update_window_mode_button() -> void:
	var mode : int = DisplayServer.window_get_mode()

	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		window_mode_button.text = "Window Mode: Fullscreen"
	else:
		window_mode_button.text = "Window Mode: Windowed"
