extends CanvasLayer

const STAMINA_HIDE_DELAY : float = 1.4
const IDLE_STATUS_OPACITY : float = 0.78

@onready var status_panel : PanelContainer = $Interface/StatusPanel
@onready var health_bar : ProgressBar = (
	$Interface/StatusPanel/StatusMargin/StatusRows/HealthRow/HealthBar
)
@onready var health_value : Label = (
	$Interface/StatusPanel/StatusMargin/StatusRows/HealthRow/HealthValue
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

	player.connect("health_changed", _on_health_changed)
	player.connect("stamina_changed", _on_stamina_changed)
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
	var vignette_material := damage_vignette.material as ShaderMaterial
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
