extends CanvasLayer

const ENVIRONMENT_GROUP : StringName = &"debug_environment_lighting"
const HOUSE_GROUP : StringName = &"debug_house_lighting"
const UFO_GROUP : StringName = &"ufo_lighting"
const DELIVERY_GROUP : StringName = &"debug_delivery_lighting"
const PLAYER_GROUP : StringName = &"debug_player"

@onready var overlay : Control = $Overlay
@onready var main_panel : VBoxContainer = (
	$Overlay/CenterContainer/MenuPanel/MarginContainer/MainPanel
)
@onready var lighting_panel : VBoxContainer = (
	$Overlay/CenterContainer/MenuPanel/MarginContainer/LightingPanel
)
@onready var lighting_button : Button = (
	$Overlay/CenterContainer/MenuPanel/MarginContainer/MainPanel/LightingButton
)
@onready var close_button : Button = (
	$Overlay/CenterContainer/MenuPanel/MarginContainer/MainPanel/CloseButton
)
@onready var god_mode_toggle : CheckButton = (
	$Overlay/CenterContainer/MenuPanel/MarginContainer/MainPanel/GodModeToggle
)
@onready var flight_mode_toggle : CheckButton = (
	$Overlay/CenterContainer/MenuPanel/MarginContainer/MainPanel/FlightModeToggle
)
@onready var back_button : Button = (
	$Overlay/CenterContainer/MenuPanel/MarginContainer/LightingPanel/BackButton
)
@onready var reset_button : Button = (
	$Overlay/CenterContainer/MenuPanel/MarginContainer/LightingPanel/ResetButton
)
@onready var quality_preset : OptionButton = (
	$Overlay/CenterContainer/MenuPanel/MarginContainer/LightingPanel/QualityPreset/Options
)
@onready var moon_toggle : CheckButton = (
	$Overlay/CenterContainer/MenuPanel/MarginContainer/LightingPanel/MoonToggle
)
@onready var sky_toggle : CheckButton = (
	$Overlay/CenterContainer/MenuPanel/MarginContainer/LightingPanel/SkyToggle
)
@onready var ambient_toggle : CheckButton = (
	$Overlay/CenterContainer/MenuPanel/MarginContainer/LightingPanel/AmbientToggle
)
@onready var fog_toggle : CheckButton = (
	$Overlay/CenterContainer/MenuPanel/MarginContainer/LightingPanel/FogToggle
)
@onready var house_toggle : CheckButton = (
	$Overlay/CenterContainer/MenuPanel/MarginContainer/LightingPanel/HouseToggle
)
@onready var ufo_toggle : CheckButton = (
	$Overlay/CenterContainer/MenuPanel/MarginContainer/LightingPanel/UFOToggle
)
@onready var moon_intensity : HSlider = (
	$Overlay/CenterContainer/MenuPanel/MarginContainer/LightingPanel/MoonIntensity/Slider
)
@onready var sky_intensity : HSlider = (
	$Overlay/CenterContainer/MenuPanel/MarginContainer/LightingPanel/SkyIntensity/Slider
)
@onready var ambient_intensity : HSlider = (
	$Overlay/CenterContainer/MenuPanel/MarginContainer/LightingPanel/AmbientIntensity/Slider
)
@onready var fog_intensity : HSlider = (
	$Overlay/CenterContainer/MenuPanel/MarginContainer/LightingPanel/FogIntensity/Slider
)
@onready var house_intensity : HSlider = (
	$Overlay/CenterContainer/MenuPanel/MarginContainer/LightingPanel/HouseIntensity/Slider
)
@onready var ufo_intensity : HSlider = (
	$Overlay/CenterContainer/MenuPanel/MarginContainer/LightingPanel/UFOIntensity/Slider
)
@onready var moon_value : Label = (
	$Overlay/CenterContainer/MenuPanel/MarginContainer/LightingPanel/MoonIntensity/Value
)
@onready var sky_value : Label = (
	$Overlay/CenterContainer/MenuPanel/MarginContainer/LightingPanel/SkyIntensity/Value
)
@onready var ambient_value : Label = (
	$Overlay/CenterContainer/MenuPanel/MarginContainer/LightingPanel/AmbientIntensity/Value
)
@onready var fog_value : Label = (
	$Overlay/CenterContainer/MenuPanel/MarginContainer/LightingPanel/FogIntensity/Value
)
@onready var house_value : Label = (
	$Overlay/CenterContainer/MenuPanel/MarginContainer/LightingPanel/HouseIntensity/Value
)
@onready var ufo_value : Label = (
	$Overlay/CenterContainer/MenuPanel/MarginContainer/LightingPanel/UFOIntensity/Value
)

var _tree_was_paused : bool = false
var _previous_mouse_mode : Input.MouseMode = Input.MOUSE_MODE_CAPTURED


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	overlay.visible = false
	_show_main_panel()

	lighting_button.pressed.connect(_show_lighting_panel)
	close_button.pressed.connect(_close_menu)
	god_mode_toggle.toggled.connect(_set_god_mode_enabled)
	flight_mode_toggle.toggled.connect(_set_flight_mode_enabled)
	back_button.pressed.connect(_show_main_panel)
	reset_button.pressed.connect(_enable_all_lighting)
	_populate_quality_preset()
	quality_preset.item_selected.connect(_set_quality_preset)
	moon_toggle.toggled.connect(_set_moon_enabled)
	sky_toggle.toggled.connect(_set_sky_enabled)
	ambient_toggle.toggled.connect(_set_ambient_enabled)
	fog_toggle.toggled.connect(_set_fog_enabled)
	house_toggle.toggled.connect(_set_house_enabled)
	ufo_toggle.toggled.connect(_set_ufo_enabled)
	moon_intensity.value_changed.connect(_set_moon_intensity)
	sky_intensity.value_changed.connect(_set_sky_intensity)
	ambient_intensity.value_changed.connect(_set_ambient_intensity)
	fog_intensity.value_changed.connect(_set_fog_intensity)
	house_intensity.value_changed.connect(_set_house_intensity)
	ufo_intensity.value_changed.connect(_set_ufo_intensity)


func _input(event : InputEvent) -> void:
	if event.is_action_pressed("debug_menu") and not event.is_echo():
		_set_menu_visible(not overlay.visible)
		get_viewport().set_input_as_handled()


func _set_menu_visible(should_show : bool) -> void:
	if overlay.visible == should_show:
		return

	overlay.visible = should_show
	if should_show:
		_tree_was_paused = get_tree().paused
		_previous_mouse_mode = Input.mouse_mode
		get_tree().paused = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_show_main_panel()
		_sync_toggles_from_world()
		lighting_button.grab_focus()
	else:
		get_tree().paused = _tree_was_paused
		Input.mouse_mode = _previous_mouse_mode


func _close_menu() -> void:
	_set_menu_visible(false)


func _show_main_panel() -> void:
	main_panel.visible = true
	lighting_panel.visible = false
	if overlay.visible:
		lighting_button.grab_focus()


func _show_lighting_panel() -> void:
	main_panel.visible = false
	lighting_panel.visible = true
	_sync_toggles_from_world()
	moon_toggle.grab_focus()


func _sync_toggles_from_world() -> void:
	var environment : Node = _get_first_target(ENVIRONMENT_GROUP)
	var player : Node = _get_first_target(PLAYER_GROUP)
	_sync_quality_preset(environment)
	_sync_method_toggle(
		god_mode_toggle,
		player,
		&"is_debug_god_mode_enabled"
	)
	_sync_method_toggle(
		flight_mode_toggle,
		player,
		&"is_debug_flight_enabled"
	)
	_sync_method_toggle(
		moon_toggle,
		environment,
		&"is_debug_moon_enabled"
	)
	_sync_method_toggle(
		sky_toggle,
		environment,
		&"is_debug_sky_enabled"
	)
	_sync_method_toggle(
		ambient_toggle,
		environment,
		&"is_debug_ambient_enabled"
	)
	_sync_method_toggle(
		fog_toggle,
		environment,
		&"is_debug_fog_enabled"
	)
	_sync_group_toggle(
		house_toggle,
		HOUSE_GROUP,
		&"is_debug_lighting_enabled"
	)
	_sync_combined_group_toggle(
		ufo_toggle,
		[UFO_GROUP, DELIVERY_GROUP],
		&"is_debug_lighting_enabled"
	)
	_sync_method_intensity(
		moon_intensity,
		moon_value,
		environment,
		&"get_debug_moon_intensity"
	)
	_sync_method_intensity(
		sky_intensity,
		sky_value,
		environment,
		&"get_debug_sky_intensity"
	)
	_sync_method_intensity(
		ambient_intensity,
		ambient_value,
		environment,
		&"get_debug_ambient_intensity"
	)
	_sync_method_intensity(
		fog_intensity,
		fog_value,
		environment,
		&"get_debug_fog_intensity"
	)
	_sync_group_intensity(
		house_intensity,
		house_value,
		HOUSE_GROUP,
		&"get_debug_lighting_intensity"
	)
	_sync_combined_group_intensity(
		ufo_intensity,
		ufo_value,
		[UFO_GROUP, DELIVERY_GROUP],
		&"get_debug_lighting_intensity"
	)


func _sync_method_toggle(
	button : CheckButton,
	target : Node,
	getter : StringName
) -> void:
	var available : bool = target != null and target.has_method(getter)
	button.disabled = not available
	button.set_pressed_no_signal(
		bool(target.call(getter)) if available else false
	)


func _sync_group_toggle(
	button : CheckButton,
	group : StringName,
	getter : StringName
) -> void:
	var targets : Array[Node] = get_tree().get_nodes_in_group(group)
	var available : bool = not targets.is_empty()
	var enabled : bool = available
	for target : Node in targets:
		if not target.has_method(getter):
			available = false
			break
		enabled = enabled and bool(target.call(getter))
	button.disabled = not available
	button.set_pressed_no_signal(enabled if available else false)


func _sync_combined_group_toggle(
	button : CheckButton,
	groups : Array[StringName],
	getter : StringName
) -> void:
	var found_target : bool = false
	var enabled : bool = true
	for group : StringName in groups:
		for target : Node in get_tree().get_nodes_in_group(group):
			if not target.has_method(getter):
				continue
			found_target = true
			enabled = enabled and bool(target.call(getter))
	button.disabled = not found_target
	button.set_pressed_no_signal(enabled if found_target else false)


func _sync_method_intensity(
	slider : HSlider,
	value_label : Label,
	target : Node,
	getter : StringName
) -> void:
	var available : bool = target != null and target.has_method(getter)
	var intensity : float = float(target.call(getter)) if available else 0.0
	_sync_intensity_control(slider, value_label, intensity, available)


func _sync_group_intensity(
	slider : HSlider,
	value_label : Label,
	group : StringName,
	getter : StringName
) -> void:
	var available : bool = false
	var intensity : float = 0.0
	for target : Node in get_tree().get_nodes_in_group(group):
		if target.has_method(getter):
			available = true
			intensity = float(target.call(getter))
			break
	_sync_intensity_control(slider, value_label, intensity, available)


func _sync_combined_group_intensity(
	slider : HSlider,
	value_label : Label,
	groups : Array[StringName],
	getter : StringName
) -> void:
	var available : bool = false
	var intensity : float = 0.0
	for group : StringName in groups:
		for target : Node in get_tree().get_nodes_in_group(group):
			if target.has_method(getter):
				available = true
				intensity = float(target.call(getter))
				break
		if available:
			break
	_sync_intensity_control(slider, value_label, intensity, available)


func _sync_intensity_control(
	slider : HSlider,
	value_label : Label,
	intensity : float,
	available : bool
) -> void:
	slider.editable = available
	slider.set_value_no_signal(intensity)
	value_label.text = _format_intensity(intensity) if available else "--"


func _format_intensity(intensity : float) -> String:
	return "%d%%" % int(round(intensity * 100.0))


func _get_first_target(group : StringName) -> Node:
	return get_tree().get_first_node_in_group(group)


func _set_environment_option(method : StringName, value : Variant) -> void:
	var environment : Node = _get_first_target(ENVIRONMENT_GROUP)
	if environment != null and environment.has_method(method):
		environment.call(method, value)


func _set_player_option(method : StringName, value : Variant) -> void:
	var player : Node = _get_first_target(PLAYER_GROUP)
	if player != null and player.has_method(method):
		player.call(method, value)


func _set_god_mode_enabled(enabled : bool) -> void:
	_set_player_option(&"set_debug_god_mode_enabled", enabled)


func _set_flight_mode_enabled(enabled : bool) -> void:
	_set_player_option(&"set_debug_flight_enabled", enabled)


func _set_group_option(
	group : StringName,
	method : StringName,
	value : Variant
) -> void:
	get_tree().call_group(group, method, value)


func _set_moon_enabled(enabled : bool) -> void:
	_set_environment_option(&"set_debug_moon_enabled", enabled)


func _set_sky_enabled(enabled : bool) -> void:
	_set_environment_option(&"set_debug_sky_enabled", enabled)


func _set_ambient_enabled(enabled : bool) -> void:
	_set_environment_option(&"set_debug_ambient_enabled", enabled)


func _populate_quality_preset() -> void:
	quality_preset.clear()
	quality_preset.add_item("Baixo", 0)
	quality_preset.add_item("Médio", 1)
	quality_preset.add_item("Alto", 2)


func _sync_quality_preset(environment : Node) -> void:
	var available : bool = environment != null and environment.has_method(
		&"get_quality_preset"
	)
	quality_preset.disabled = not available
	if available:
		quality_preset.select(
			clampi(int(environment.call(&"get_quality_preset")), 0, 2)
		)


func _set_quality_preset(index : int) -> void:
	_set_environment_option(&"set_quality_preset", index)
	_sync_toggles_from_world()


func _set_fog_enabled(enabled : bool) -> void:
	_set_environment_option(&"set_debug_fog_enabled", enabled)


func _set_house_enabled(enabled : bool) -> void:
	_set_group_option(HOUSE_GROUP, &"set_debug_lighting_enabled", enabled)


func _set_ufo_enabled(enabled : bool) -> void:
	_set_group_option(UFO_GROUP, &"set_debug_lighting_enabled", enabled)
	_set_group_option(DELIVERY_GROUP, &"set_debug_lighting_enabled", enabled)


func _set_moon_intensity(intensity : float) -> void:
	moon_value.text = _format_intensity(intensity)
	_set_environment_option(&"set_debug_moon_intensity", intensity)


func _set_sky_intensity(intensity : float) -> void:
	sky_value.text = _format_intensity(intensity)
	_set_environment_option(&"set_debug_sky_intensity", intensity)


func _set_ambient_intensity(intensity : float) -> void:
	ambient_value.text = _format_intensity(intensity)
	_set_environment_option(&"set_debug_ambient_intensity", intensity)


func _set_fog_intensity(intensity : float) -> void:
	fog_value.text = _format_intensity(intensity)
	_set_environment_option(&"set_debug_fog_intensity", intensity)


func _set_house_intensity(intensity : float) -> void:
	house_value.text = _format_intensity(intensity)
	_set_group_option(
		HOUSE_GROUP,
		&"set_debug_lighting_intensity",
		intensity
	)


func _set_ufo_intensity(intensity : float) -> void:
	ufo_value.text = _format_intensity(intensity)
	_set_group_option(UFO_GROUP, &"set_debug_lighting_intensity", intensity)
	_set_group_option(
		DELIVERY_GROUP,
		&"set_debug_lighting_intensity",
		intensity
	)


func _enable_all_lighting() -> void:
	_set_moon_enabled(true)
	_set_sky_enabled(true)
	_set_ambient_enabled(true)
	_set_fog_enabled(true)
	_set_house_enabled(true)
	_set_ufo_enabled(true)
	_set_moon_intensity(1.0)
	_set_sky_intensity(1.0)
	_set_ambient_intensity(1.0)
	_set_fog_intensity(1.0)
	_set_house_intensity(1.0)
	_set_ufo_intensity(1.0)
	_sync_toggles_from_world()
