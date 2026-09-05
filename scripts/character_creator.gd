extends Control

const FEATURE_DEFINITIONS : Array[Dictionary] = [
	{"key": "head_size", "label": "Tamanho da cabeça"},
	{"key": "belly_size", "label": "Tamanho da barriga"},
	{"key": "leg_length", "label": "Comprimento das pernas"},
	{"key": "arm_length", "label": "Comprimento dos braços"},
	{"key": "shoulder_width", "label": "Largura dos ombros"},
	{"key": "overall_height", "label": "Altura geral"},
	{"key": "eye_size", "label": "Tamanho dos olhos"},
]
const DEFAULT_PROFILE : Dictionary = {
	"head_size": 0.5,
	"belly_size": 0.5,
	"leg_length": 0.5,
	"arm_length": 0.5,
	"shoulder_width": 0.5,
	"overall_height": 0.5,
	"eye_size": 0.5,
}
const RANDOM_ANIMATION_INTERVAL : float = 5.0
const PREVIEW_ANIMATION_GROUPS : Array[Dictionary] = [
	{"label": "PARADO", "animations": [
		{"animation": &"idle", "label": "Parado"},
		{"animation": &"idle_variant_a", "label": "Variação tranquila"},
		{"animation": &"idle_variant_b", "label": "Variação inquieta"},
	]},
	{"label": "LOCOMOÇÃO", "animations": [
		{"animation": &"walk", "label": "Caminhando"},
		{"animation": &"run", "label": "Correndo"},
		{"animation": &"strafe_left_walk", "label": "Andando de lado"},
		{"animation": &"turn_left", "label": "Virando"},
	]},
	{"label": "AGACHADO", "animations": [
		{"animation": &"crouch_idle", "label": "Agachado parado"},
		{"animation": &"crouch_walk", "label": "Andando agachado"},
	]},
	{"label": "AÉREO", "animations": [
		{"animation": &"jump_start", "label": "Início do salto"},
		{"animation": &"jump", "label": "Saltando"},
		{"animation": &"fall", "label": "Caindo"},
		{"animation": &"land_hard", "label": "Pouso forte"},
	]},
	{"label": "REAÇÕES", "animations": [
		{"animation": &"stumble_forward", "label": "Tropeçando"},
		{"animation": &"hit_front", "label": "Levando impacto"},
	]},
	{"label": "INTERAÇÃO", "animations": [
		{"animation": &"pick_up_ground", "label": "Pegando objeto"},
		{"animation": &"carry_idle", "label": "Carregando parado"},
		{"animation": &"carry_walk", "label": "Carregando andando"},
	]},
]

@onready var preview_container : SubViewportContainer = %PreviewContainer
@onready var preview_pivot : Node3D = %PreviewPivot
@onready var proportions : SkeletonModifier3D = %CharacterProportions
@onready var sliders_container : VBoxContainer = %Sliders
@onready var animation_buttons_container : VBoxContainer = %AnimationButtons
@onready var animation_status : Label = %AnimationStatus
@onready var confirm_button : Button = %ConfirmButton
@onready var reset_button : Button = %ResetButton
@onready var random_button : Button = %RandomButton
@onready var back_button : Button = %BackButton
@onready var animation_player : AnimationPlayer = (
	preview_pivot.get_node("ET/AnimationPlayer") as AnimationPlayer
)
@onready var preview_camera : Camera3D = %PreviewCamera
@onready var menu_music : AudioStreamPlayer = %MenuMusic
@onready var menu_click : AudioStreamPlayer = %MenuClick

var _profile : Dictionary = DEFAULT_PROFILE.duplicate(true)
var _sliders : Dictionary = {}
var _value_labels : Dictionary = {}
var _dragging_preview : bool = false
var _manual_rotation_cooldown : float = 0.0
var _transition_started : bool = false
var _random : RandomNumberGenerator = RandomNumberGenerator.new()
var _selected_preview_animation : StringName = &"idle"
var _animation_button_group : ButtonGroup = ButtonGroup.new()
var _animation_buttons : Array[Button] = []
var _available_preview_animations : Array[StringName] = []
var _animation_labels : Dictionary = {}
var _random_animation_button : Button
var _random_animation_enabled : bool = true
var _random_animation_elapsed : float = 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_random.randomize()
	preview_camera.look_at(Vector3(0.0, 0.55, 0.0), Vector3.UP)
	_build_sliders()
	_build_animation_buttons()

	var appearance : Node = get_node_or_null("/root/CharacterAppearance")
	if appearance != null and appearance.has_method("get_profile"):
		_profile = appearance.call("get_profile") as Dictionary
	_set_controls_from_profile()
	_apply_preview()

	preview_container.gui_input.connect(_on_preview_gui_input)
	confirm_button.pressed.connect(_on_confirm_pressed)
	reset_button.pressed.connect(_on_reset_pressed)
	random_button.pressed.connect(_on_random_pressed)
	back_button.pressed.connect(_on_back_pressed)
	animation_player.animation_finished.connect(_on_preview_animation_finished)
	confirm_button.grab_focus.call_deferred()
	_choose_random_preview_animation()
	menu_music.play()


func _process(delta : float) -> void:
	_manual_rotation_cooldown = maxf(0.0, _manual_rotation_cooldown - delta)
	if not _dragging_preview and _manual_rotation_cooldown <= 0.0:
		preview_pivot.rotate_y(delta * 0.16)
	if _random_animation_enabled and not _transition_started:
		_random_animation_elapsed += delta
		if _random_animation_elapsed >= RANDOM_ANIMATION_INTERVAL:
			_random_animation_elapsed = 0.0
			_choose_random_preview_animation()


func _unhandled_input(event : InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button : InputEventMouseButton = event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_LEFT and not mouse_button.pressed:
			_dragging_preview = false


func _build_sliders() -> void:
	for definition : Dictionary in FEATURE_DEFINITIONS:
		var key : String = String(definition["key"])
		var row : VBoxContainer = VBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		sliders_container.add_child(row)

		var header : HBoxContainer = HBoxContainer.new()
		row.add_child(header)
		var label : Label = Label.new()
		label.text = String(definition["label"])
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_color_override("font_color", Color(0.78, 0.9, 1.0))
		header.add_child(label)

		var value_label : Label = Label.new()
		value_label.custom_minimum_size.x = 52.0
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.add_theme_color_override("font_color", Color(0.27, 0.9, 1.0))
		header.add_child(value_label)

		var slider : HSlider = HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.01
		slider.custom_minimum_size.y = 26.0
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.tooltip_text = "%s: 0 a 100%%" % String(definition["label"])
		slider.value_changed.connect(_on_slider_changed.bind(key))
		row.add_child(slider)

		_sliders[key] = slider
		_value_labels[key] = value_label


func _set_controls_from_profile() -> void:
	for definition : Dictionary in FEATURE_DEFINITIONS:
		var key : String = String(definition["key"])
		var slider : HSlider = _sliders[key] as HSlider
		slider.set_value_no_signal(float(_profile.get(key, 0.5)))
		_update_value_label(key)


func _on_slider_changed(value : float, key : String) -> void:
	_profile[key] = clampf(value, 0.0, 1.0)
	_update_value_label(key)
	_apply_preview()


func _update_value_label(key : String) -> void:
	var value_label : Label = _value_labels[key] as Label
	value_label.text = "%d%%" % roundi(float(_profile.get(key, 0.5)) * 100.0)


func _apply_preview() -> void:
	proportions.call("set_profile", _profile, false)


func _build_animation_buttons() -> void:
	_random_animation_button = _create_animation_button("ALEATÓRIO  •  5s")
	_random_animation_button.tooltip_text = "Troca automaticamente a animação a cada 5 segundos."
	_random_animation_button.pressed.connect(_on_random_animation_pressed)
	animation_buttons_container.add_child(_random_animation_button)
	_random_animation_button.button_pressed = true

	for group_definition : Dictionary in PREVIEW_ANIMATION_GROUPS:
		var group_label : Label = Label.new()
		group_label.text = String(group_definition["label"])
		group_label.add_theme_color_override("font_color", Color(0.31, 0.79, 0.9))
		group_label.add_theme_font_size_override("font_size", 13)
		animation_buttons_container.add_child(group_label)

		var definitions : Array = group_definition["animations"] as Array
		for definition_variant : Variant in definitions:
			var definition : Dictionary = definition_variant as Dictionary
			var animation_name : StringName = StringName(String(definition["animation"]))
			if not animation_player.has_animation(animation_name):
				continue
			var label_text : String = String(definition["label"])
			var button : Button = _create_animation_button(label_text)
			button.tooltip_text = "Reproduzir %s" % label_text.to_lower()
			button.pressed.connect(_on_animation_button_pressed.bind(animation_name, button))
			animation_buttons_container.add_child(button)
			_available_preview_animations.append(animation_name)
			_animation_labels[animation_name] = label_text


func _create_animation_button(label_text : String) -> Button:
	var button : Button = Button.new()
	button.text = label_text
	button.custom_minimum_size.y = 38.0
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.toggle_mode = true
	button.button_group = _animation_button_group
	_animation_buttons.append(button)
	return button


func _on_random_animation_pressed() -> void:
	_random_animation_enabled = true
	_random_animation_elapsed = 0.0
	_play_click()
	_choose_random_preview_animation()


func _on_animation_button_pressed(animation_name : StringName, button : Button) -> void:
	_random_animation_enabled = false
	_random_animation_elapsed = 0.0
	_selected_preview_animation = animation_name
	button.button_pressed = true
	_play_click()
	_update_animation_status()
	_play_selected_animation()


func _choose_random_preview_animation() -> void:
	if _available_preview_animations.is_empty():
		return
	var next_animation : StringName = _available_preview_animations[
		_random.randi_range(0, _available_preview_animations.size() - 1)
	]
	if _available_preview_animations.size() > 1:
		while next_animation == _selected_preview_animation:
			next_animation = _available_preview_animations[
				_random.randi_range(0, _available_preview_animations.size() - 1)
			]
	_selected_preview_animation = next_animation
	_random_animation_button.button_pressed = true
	_update_animation_status()
	_play_selected_animation()


func _update_animation_status() -> void:
	var label_text : String = String(_animation_labels.get(
		_selected_preview_animation,
		String(_selected_preview_animation)
	))
	if _random_animation_enabled:
		animation_status.text = "Agora: %s  •  próxima em 5s" % label_text
	else:
		animation_status.text = "Agora: %s" % label_text


func _on_preview_animation_finished(animation_name : StringName) -> void:
	if animation_name == _selected_preview_animation and not _transition_started:
		_play_selected_animation.call_deferred()


func _on_preview_gui_input(event : InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button : InputEventMouseButton = event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_LEFT:
			_dragging_preview = mouse_button.pressed
			preview_container.accept_event()
		elif mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP:
			preview_camera.position.z = maxf(1.65, preview_camera.position.z - 0.12)
			preview_camera.look_at(Vector3(0.0, 0.55, 0.0), Vector3.UP)
			preview_container.accept_event()
		elif mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			preview_camera.position.z = minf(3.0, preview_camera.position.z + 0.12)
			preview_camera.look_at(Vector3(0.0, 0.55, 0.0), Vector3.UP)
			preview_container.accept_event()
	elif event is InputEventMouseMotion and _dragging_preview:
		var mouse_motion : InputEventMouseMotion = event as InputEventMouseMotion
		preview_pivot.rotate_y(-mouse_motion.relative.x * 0.012)
		_manual_rotation_cooldown = 2.5
		preview_container.accept_event()


func _on_reset_pressed() -> void:
	_play_click()
	_profile = DEFAULT_PROFILE.duplicate(true)
	_set_controls_from_profile()
	_apply_preview()


func _on_random_pressed() -> void:
	_play_click()
	for definition : Dictionary in FEATURE_DEFINITIONS:
		var key : String = String(definition["key"])
		# Most results stay readable; occasional values near an extreme keep the
		# random button playful and showcase the cartoony range.
		var value : float = _random.randf_range(0.12, 0.88)
		if _random.randf() < 0.22:
			value = _random.randf_range(0.0, 1.0)
		_profile[key] = value
	_set_controls_from_profile()
	_apply_preview()


func _on_confirm_pressed() -> void:
	if _transition_started:
		return
	_transition_started = true
	_set_buttons_disabled(true)
	_play_click()
	var appearance : Node = get_node_or_null("/root/CharacterAppearance")
	if appearance != null and appearance.has_method("set_profile"):
		appearance.call("set_profile", _profile, true)
	_fade_music()
	var scene_transition : Node = get_node("/root/SceneTransition")
	scene_transition.call("abduction_warp_to", "res://scenes/Space/Orbit.tscn")


func _on_back_pressed() -> void:
	if _transition_started:
		return
	_transition_started = true
	_set_buttons_disabled(true)
	_play_click()
	_fade_music()
	var scene_transition : Node = get_node("/root/SceneTransition")
	scene_transition.call("warp_to", "res://scenes/Menu/main_menu.tscn")


func _set_buttons_disabled(disabled : bool) -> void:
	confirm_button.disabled = disabled
	reset_button.disabled = disabled
	random_button.disabled = disabled
	back_button.disabled = disabled
	for button : Button in _animation_buttons:
		button.disabled = disabled


func _play_selected_animation() -> void:
	if animation_player.has_animation(_selected_preview_animation):
		animation_player.play(_selected_preview_animation)


func _play_click() -> void:
	menu_click.stop()
	menu_click.play()


func _fade_music() -> void:
	var tween : Tween = create_tween()
	tween.tween_property(menu_music, "volume_db", -60.0, 0.4)
