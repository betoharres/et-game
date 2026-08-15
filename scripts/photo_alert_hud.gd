extends CanvasLayer

const ATTENTION_HOLD_SECONDS : float = 3.0
const ACTIVE_OPACITY : float = 1.0
const IDLE_OPACITY : float = 0.42

@onready var alert_panel : PanelContainer = $Interface/AlertPanel
@onready var stars_label : Label = (
	$Interface/AlertPanel/MarginContainer/Content/ObjectiveRow/StarsLabel
)
@onready var count_label : Label = (
	$Interface/AlertPanel/MarginContainer/Content/ObjectiveRow/CountLabel
)
@onready var status_label : Label = (
	$Interface/AlertPanel/MarginContainer/Content/StatusLabel
)
@onready var photo_feedback : AudioStreamPlayer = $PhotoFeedback

var _previous_count : int = -1
var _attention_timer : float = ATTENTION_HOLD_SECONDS
var _status_mode : StringName = &""
var _last_seconds : int = -1
var _pulse_tween : Tween = null


func _ready() -> void:
	PhotoAlertSystem.photo_count_changed.connect(_on_photo_count_changed)
	_on_photo_count_changed(
		PhotoAlertSystem.get_photo_count(),
		PhotoAlertSystem.get_max_photo_count()
	)


func _process(delta : float) -> void:
	_update_status()
	_attention_timer = maxf(_attention_timer - delta, 0.0)
	var target_opacity := (
		ACTIVE_OPACITY if _attention_timer > 0.0 else IDLE_OPACITY
	)
	alert_panel.modulate.a = move_toward(
		alert_panel.modulate.a,
		target_opacity,
		delta * 2.8
	)


func _on_photo_count_changed(current_count : int, maximum_count : int) -> void:
	var stars_text : String = ""
	for star_index : int in range(maximum_count):
		stars_text += "★" if star_index < current_count else "◇"
		if star_index < maximum_count - 1:
			stars_text += "  "

	stars_label.text = stars_text
	count_label.text = "%d / %d" % [current_count, maximum_count]

	if _previous_count >= 0 and current_count > _previous_count:
		photo_feedback.play()
		_play_update_pulse()
	_wake_panel()
	_previous_count = current_count


func _update_status() -> void:
	var current_count : int = PhotoAlertSystem.get_photo_count()
	var new_mode : StringName

	if current_count <= 0:
		new_mode = &"empty"
		status_label.text = "SEM REGISTRO"
	elif PhotoAlertSystem.is_observed_by_photographer():
		new_mode = &"observed"
		status_label.text = "OBSERVADO"
	else:
		new_mode = &"hidden"
		var seconds := ceili(PhotoAlertSystem.get_seconds_until_photo_decay())
		if seconds != _last_seconds:
			status_label.text = "OCULTO — %ds" % seconds
			_last_seconds = seconds

	if new_mode != _status_mode:
		_status_mode = new_mode
		_wake_panel()


func _wake_panel() -> void:
	_attention_timer = ATTENTION_HOLD_SECONDS
	alert_panel.modulate.a = ACTIVE_OPACITY


func _play_update_pulse() -> void:
	if _pulse_tween != null:
		_pulse_tween.kill()
	alert_panel.modulate = Color(1.2, 1.2, 1.2, 1.0)
	_pulse_tween = create_tween()
	_pulse_tween.tween_property(
		alert_panel,
		"modulate",
		Color.WHITE,
		0.2
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
