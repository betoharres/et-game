extends CanvasLayer

const STAMINA_HIDE_DELAY : float = 1.4
const IDLE_STATUS_OPACITY : float = 0.78
const LOW_ENERGY_RATIO : float = 0.2
const LOW_ENERGY_COLOR : Color = Color(1.0, 0.62, 0.35, 1.0)

@onready var status_panel : PanelContainer = $Interface/StatusPanel
@onready var health_bar : ProgressBar = (
	$Interface/StatusPanel/StatusMargin/StatusRows/HealthRow/HealthBar
)
@onready var health_value : Label = (
	$Interface/StatusPanel/StatusMargin/StatusRows/HealthRow/HealthValue
)
@onready var energy_bar : ProgressBar = (
	$Interface/StatusPanel/StatusMargin/StatusRows/EnergyRow/EnergyBar
)
@onready var energy_value : Label = (
	$Interface/StatusPanel/StatusMargin/StatusRows/EnergyRow/EnergyValue
)
@onready var stamina_row : HBoxContainer = (
	$Interface/StatusPanel/StatusMargin/StatusRows/StaminaRow
)
@onready var stamina_bar : ProgressBar = (
	$Interface/StatusPanel/StatusMargin/StatusRows/StaminaRow/StaminaBar
)
@onready var stamina_value : Label = (
	$Interface/StatusPanel/StatusMargin/StatusRows/StaminaRow/StaminaValue
)
@onready var damage_vignette : ColorRect = $Interface/DamageVignette
@onready var defeat_menu : PanelContainer = $Interface/DefeatMenu
@onready var restart_button : Button = (
	$Interface/DefeatMenu/Content/RestartButton
)

var _drop_prompt : Label
var _recovery_prompt : Label
var _pickup_prompt : Label
var _talk_prompt : Label
var _inventory_message : Label
var _inventory_message_time : float = 0.0
var _inventory_slots : HBoxContainer
var _inventory_feedback_tween : Tween
var player : Node
var _previous_health : float = -1.0
var _stamina_hide_timer : float = 0.0
var _stamina_tween : Tween = null
var _status_tween : Tween = null
var _damage_tween : Tween = null


func _ready() -> void:
	player = get_parent()
	stamina_row.visible = false

	if player == null:
		return

	_build_inventory_hud()
	_drop_prompt = _interaction_label(-132.0)
	_recovery_prompt = _interaction_label(-240.0)
	_pickup_prompt = _interaction_label(-166.0)
	_talk_prompt = _interaction_label(-166.0)
	_inventory_message = _interaction_label(-204.0)
	var locator : Control = preload("res://scenes/DebrisLocatorHUD.tscn").instantiate() as Control
	locator.character = player as Node3D
	$Interface.add_child(locator)
	locator.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	locator.offset_left = -176.0
	locator.offset_right = 176.0
	locator.offset_top = 24.0
	locator.offset_bottom = 168.0
	var mission_hud : Control = preload("res://scenes/MissionHUD.tscn").instantiate() as Control
	$Interface.add_child(mission_hud)
	mission_hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	mission_hud.offset_left = -344.0
	mission_hud.offset_right = -24.0
	mission_hud.offset_top = 24.0
	mission_hud.offset_bottom = 120.0
	player.connect("health_changed", _on_health_changed)
	player.connect("stamina_changed", _on_stamina_changed)
	player.connect("energy_changed", _on_energy_changed)
	player.connect("died", _on_player_died)
	restart_button.pressed.connect(_on_restart_pressed)

	_on_health_changed(
		float(player.call("get_health")),
		float(player.call("get_max_health"))
	)
	_on_stamina_changed(
		float(player.call("get_stamina")),
		float(player.call("get_max_stamina"))
	)
	_on_energy_changed(
		float(player.call("get_energy")),
		float(player.call("get_max_energy"))
	)


func _process(delta : float) -> void:
	if _stamina_hide_timer <= 0.0:
		return

	_stamina_hide_timer = maxf(_stamina_hide_timer - delta, 0.0)
	if _stamina_hide_timer <= 0.0:
		_hide_stamina_row()


func _on_health_changed(current : float, maximum : float) -> void:
	health_bar.max_value = maximum
	health_bar.value = current
	health_value.text = str(roundi(current))

	if _previous_health >= 0.0 and current < _previous_health:
		_play_damage_feedback()
	_previous_health = current


func _on_stamina_changed(current : float, maximum : float) -> void:
	stamina_bar.max_value = maximum
	stamina_bar.value = current
	stamina_value.text = str(roundi(current))

	if current < maximum - 0.01:
		_stamina_hide_timer = 0.0
		_show_stamina_row()
	else:
		_stamina_hide_timer = STAMINA_HIDE_DELAY


func _on_energy_changed(current : float, maximum : float) -> void:
	energy_bar.max_value = maximum
	energy_bar.value = current
	energy_value.text = str(roundi(current))
	energy_bar.modulate = (
		LOW_ENERGY_COLOR
		if maximum > 0.0 and current / maximum <= LOW_ENERGY_RATIO
		else Color.WHITE
	)


func _show_stamina_row() -> void:
	if _stamina_tween != null:
		_stamina_tween.kill()
	stamina_row.visible = true
	_stamina_tween = create_tween()
	_stamina_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_stamina_tween.tween_property(stamina_row, "modulate:a", 1.0, 0.16)


func _hide_stamina_row() -> void:
	if not stamina_row.visible:
		return

	if _stamina_tween != null:
		_stamina_tween.kill()
	_stamina_tween = create_tween()
	_stamina_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_stamina_tween.tween_property(stamina_row, "modulate:a", 0.0, 0.2)
	_stamina_tween.tween_callback(stamina_row.hide)


func _play_damage_feedback() -> void:
	if _damage_tween != null:
		_damage_tween.kill()
	_set_vignette_intensity(0.34)
	health_bar.modulate = Color(1.0, 0.45, 0.45, 1.0)
	_damage_tween = create_tween()
	_damage_tween.set_parallel(true)
	_damage_tween.tween_method(
		_set_vignette_intensity,
		0.34,
		0.0,
		0.55
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_damage_tween.tween_property(
		health_bar,
		"modulate",
		Color.WHITE,
		0.28
	)

	if _status_tween != null:
		_status_tween.kill()
	status_panel.modulate.a = 1.0
	_status_tween = create_tween()
	_status_tween.tween_interval(0.65)
	_status_tween.tween_property(
		status_panel,
		"modulate:a",
		IDLE_STATUS_OPACITY,
		0.22
	)


func _set_vignette_intensity(value : float) -> void:
	var vignette_material : ShaderMaterial = damage_vignette.material as ShaderMaterial
	if vignette_material != null:
		vignette_material.set_shader_parameter("intensity", value)


func _on_player_died() -> void:
	defeat_menu.visible = true
	restart_button.grab_focus.call_deferred()


func _on_restart_pressed() -> void:
	restart_button.disabled = true
	PhotoAlertSystem.reset()
	var reload_error : Error = get_tree().reload_current_scene()

	if reload_error != OK:
		restart_button.disabled = false
		push_error("Could not restart the current scene: %s" % reload_error)


func _build_inventory_hud() -> void:
	_inventory_slots = HBoxContainer.new()
	$Interface.add_child(_inventory_slots)
	_inventory_slots.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_inventory_slots.offset_left = -143.0
	_inventory_slots.offset_right = 143.0
	_inventory_slots.offset_top = -96.0
	_inventory_slots.offset_bottom = -32.0
	_inventory_slots.add_theme_constant_override("separation", 10)
	_inventory_slots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for index : int in range(4):
		var slot : Panel = Panel.new()
		slot.custom_minimum_size = Vector2(64.0, 64.0)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_inventory_slots.add_child(slot)
		var caption : Label = Label.new()
		caption.name = "Caption"
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		caption.add_theme_font_size_override("font_size", 12)
		slot.add_child(caption)
		caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	player.connect("exploration_inventory_changed", _refresh_inventory)
	player.connect("exploration_inventory_feedback", _show_inventory_feedback)
	_refresh_inventory()


func _refresh_inventory() -> void:
	var inventory : Node = player.get_node("ExplorationInventory")
	for index : int in range(_inventory_slots.get_child_count()):
		var slot : Panel = _inventory_slots.get_child(index) as Panel
		var item : RigidBody3D = inventory.call("item_at", index) as RigidBody3D
		var occupied : bool = is_instance_valid(item)
		var caption : Label = slot.get_node("Caption") as Label
		caption.text = "%d\n%s" % [index + 1, str(item.get("display_name")) if occupied else "—"]
		var selected : bool = index == int(inventory.get("selected_slot"))
		var style : StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = Color(0.12, 0.32, 0.37, 0.92) if occupied else Color(0.025, 0.035, 0.045, 0.72)
		style.border_color = Color(0.65, 0.95, 1.0) if selected else Color(0.45, 0.55, 0.6, 0.45)
		style.set_border_width_all(2 if selected else 1)
		style.set_corner_radius_all(4)
		slot.add_theme_stylebox_override("panel", style)


func _show_inventory_feedback(message : String) -> void:
	_inventory_message.text = message
	_inventory_message_time = 3.0
	if _inventory_feedback_tween != null:
		_inventory_feedback_tween.kill()
	_inventory_slots.modulate = Color(1.0, 0.35, 0.3)
	_inventory_feedback_tween = create_tween()
	_inventory_feedback_tween.tween_property(_inventory_slots, "modulate", Color.WHITE, 0.35)


func _interaction_label(top : float) -> Label:
	var label : Label = Label.new()
	$Interface.add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	label.offset_left = -330.0
	label.offset_right = 330.0
	label.offset_top = top
	label.offset_bottom = top + 36.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	return label


func _physics_process(delta : float) -> void:
	if not is_instance_valid(player) or _pickup_prompt == null:
		return
	_inventory_message_time = maxf(0.0, _inventory_message_time - delta)
	_inventory_message.visible = _inventory_message_time > 0.0
	var inventory : Node = player.get_node("ExplorationInventory")
	var selected : RigidBody3D = inventory.call("item_at", int(inventory.get("selected_slot"))) as RigidBody3D
	var held : RigidBody3D = player.get("carried_item") as RigidBody3D
	var drop_target : RigidBody3D = held if is_instance_valid(held) else selected
	_drop_prompt.text = "[%s] Largar - %s" % [_interaction_key("drop_item"), str(drop_target.get("display_name"))] if is_instance_valid(drop_target) else ""
	_recovery_prompt.text = ""
	for zone : Node in get_tree().get_nodes_in_group("recovery_zones"):
		if bool(zone.call("contains_position", player.global_position)):
			_recovery_prompt.text = "ÁREA DE COLETA - " + str(zone.get("status_text"))
			break
	var item : RigidBody3D = player.call("get_pickup_candidate") as RigidBody3D
	_pickup_prompt.text = ""
	if item != null and not Input.is_action_pressed("crouch"):
		_pickup_prompt.text = "[%s] Coletar — %s" % [_interaction_key(), str(item.get("display_name"))]
	_talk_prompt.text = ""
	if item == null:
		for npc : Node in get_tree().get_nodes_in_group("dialogue_sources"):
			if bool(npc.call("is_player_nearby")):
				_talk_prompt.text = "[%s] Falar" % _interaction_key()
				break


func _interaction_key(action : StringName = &"interact") -> String:
	for event : InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key : InputEventKey = event as InputEventKey
			return OS.get_keycode_string(key.physical_keycode if key.physical_keycode != 0 else key.keycode)
		if event is InputEventMouseButton:
			return event.as_text()
	return "Interagir"
