extends Control

@onready var menu_button_1 : Button = $ColorRect/MenuBar/VSeparator/MenuButton1
@onready var menu_button_2 : Button = $ColorRect/MenuBar/VSeparator/MenuButton2
@onready var menu_button_3 : Button = $ColorRect/MenuBar/VSeparator/MenuButton3
@onready var main_menu_container : Control = $ColorRect/MenuBar/VSeparator
@onready var menu_bar : Control = $ColorRect/MenuBar
@onready var game_title : Label = $ColorRect/Header/Title
@onready var menu_music : AudioStreamPlayer = $MenuMusic
@onready var menu_click : AudioStreamPlayer = $MenuClick
@onready var menu_atmosphere : Node = $ColorRect/MenuAtmosphere

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
var transition_started : bool = false
var button_base_positions : Dictionary = {}


func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	game_title.text = str(ProjectSettings.get_setting("application/config/name", "ETs"))
	menu_atmosphere.set_menu_state("play")
	_start_menu_music()

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
	menu_button_1.grab_focus.call_deferred()
	_setup_menu_motion()

	setup_resolutions()
	update_vsync_check_box()
	update_window_mode_button()
	update_keybind_buttons()
	_play_menu_intro()


# Main Menu

func _on_play_pressed() -> void:
	if transition_started:
		return
	transition_started = true
	menu_atmosphere.begin_launch()
	_play_click()
	var photo_alert_system : Node = get_node_or_null("/root/PhotoAlertSystem")
	if photo_alert_system != null:
		photo_alert_system.reset()
	_fade_out_and_call(func() -> void: get_tree().change_scene_to_file("res://scenes/world.tscn"))

func _on_options_pressed() -> void:
	_play_click()
	menu_atmosphere.set_menu_state("options")
	main_menu_container.visible = false
	options_panel.visible = true
	resolution_button.grab_focus.call_deferred()

func _on_exit_pressed() -> void:
	if transition_started:
		return
	transition_started = true
	menu_atmosphere.set_menu_state("exit")
	_play_click()
	_fade_out_and_call(func() -> void: get_tree().quit())

# Options Menu

func _on_options_back_pressed() -> void:
	_play_click()
	options_panel.visible = false
	main_menu_container.visible = true
	menu_button_2.grab_focus.call_deferred()

func _on_keybinds_pressed() -> void:
	_play_click()
	options_panel.visible = false
	keybinds_panel.visible = true
	forward_button.grab_focus.call_deferred()

# Keybinds Menu

func _on_keybinds_back_pressed() -> void:
	_play_click()
	keybinds_panel.visible = false
	options_panel.visible = true
	keybinds_button.grab_focus.call_deferred()


func _setup_menu_motion() -> void:
	var buttons : Array[Button] = [menu_button_1, menu_button_2, menu_button_3]
	for button : Button in buttons:
		button_base_positions[button] = button.position.x
		button.mouse_entered.connect(_on_menu_button_hover.bind(button, true))
		button.mouse_exited.connect(_on_menu_button_hover.bind(button, false))
		button.focus_entered.connect(_on_menu_button_hover.bind(button, true))
		button.focus_exited.connect(_on_menu_button_hover.bind(button, false))


func _on_menu_button_hover(button : Button, hovered : bool) -> void:
	if hovered:
		_set_atmosphere_state(button)
	var base_x : float = button_base_positions.get(button, button.position.x)
	var target_x : float = base_x + 4.0 if hovered else base_x
	var tween : Tween = create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "position:x", target_x, 0.15)


func _set_atmosphere_state(button : Button) -> void:
	if button == menu_button_1:
		menu_atmosphere.set_menu_state("play")
	elif button == menu_button_2:
		menu_atmosphere.set_menu_state("options")
	elif button == menu_button_3:
		menu_atmosphere.set_menu_state("exit")


func _play_menu_intro() -> void:
	var header : Control = $ColorRect/Header
	header.modulate.a = 0.0
	header.position.y += 10.0
	menu_bar.modulate.a = 0.0
	menu_bar.position.y += 10.0
	for button : Button in [menu_button_1, menu_button_2, menu_button_3]:
		button.modulate.a = 0.0
	var tween : Tween = create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(header, "modulate:a", 1.0, 0.28)
	tween.parallel().tween_property(header, "position:y", header.position.y - 10.0, 0.28)
	tween.tween_interval(0.08)
	tween.tween_property(menu_bar, "modulate:a", 1.0, 0.24)
	tween.parallel().tween_property(menu_bar, "position:y", menu_bar.position.y - 10.0, 0.24)
	for index : int in range(3):
		tween.tween_interval(0.035)
		tween.tween_property([menu_button_1, menu_button_2, menu_button_3][index], "modulate:a", 1.0, 0.16)

func _start_menu_music() -> void:
	var music_stream : AudioStreamMP3 = menu_music.stream as AudioStreamMP3
	if music_stream != null:
		music_stream.loop = true
	menu_music.volume_db = -32.0
	menu_music.play()
	var tween : Tween = create_tween()
	tween.tween_property(menu_music, "volume_db", -24.0, 0.8)


func _play_click() -> void:
	menu_click.stop()
	menu_click.play()


func _fade_out_and_call(callback : Callable) -> void:
	var tween : Tween = create_tween()
	tween.tween_property(menu_music, "volume_db", -60.0, 0.18)
	tween.tween_callback(callback)

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
