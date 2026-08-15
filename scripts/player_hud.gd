extends CanvasLayer

@onready var health_label : Label = $Interface/StatusPanel/Status/HealthLabel
@onready var health_bar : ProgressBar = $Interface/StatusPanel/Status/HealthBar
@onready var stamina_label : Label = $Interface/StatusPanel/Status/StaminaLabel
@onready var stamina_bar : ProgressBar = $Interface/StatusPanel/Status/StaminaBar
@onready var defeat_menu : PanelContainer = $Interface/DefeatMenu
@onready var restart_button : Button = (
	$Interface/DefeatMenu/Content/RestartButton
)

var player : Node


func _ready() -> void:
	player = get_parent()

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


func _on_health_changed(current : float, maximum : float) -> void:
	health_bar.max_value = maximum
	health_bar.value = current
	health_label.text = "VIDA  %d / %d" % [roundi(current), roundi(maximum)]


func _on_stamina_changed(current : float, maximum : float) -> void:
	stamina_bar.max_value = maximum
	stamina_bar.value = current
	stamina_label.text = "STAMINA  %d / %d" % [
		roundi(current),
		roundi(maximum)
	]


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
