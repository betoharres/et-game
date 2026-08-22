extends CanvasLayer

const ATTENTION_HOLD_SECONDS : float = 3.0
const ACTIVE_OPACITY : float = 1.0
const IDLE_OPACITY : float = 0.42
const STAR_FILLED : Texture2D = preload(
	"res://Texturas/ui/star_filled.png"
)
const STAR_EMPTY : Texture2D = preload(
	"res://Texturas/ui/star_empty.png"
)
const WATCH_ICON : Texture2D = preload(
	"res://Texturas/ui/watch.png"
)
const WARNING_ICON : Texture2D = preload(
	"res://Texturas/ui/warning.png"
)

@onready var alert_panel : PanelContainer = $Interface/AlertPanel
@onready var star_icons : Array[TextureRect] = [
	$Interface/AlertPanel/MarginContainer/Content/ObjectiveRow/Stars/Star1,
	$Interface/AlertPanel/MarginContainer/Content/ObjectiveRow/Stars/Star2,
	$Interface/AlertPanel/MarginContainer/Content/ObjectiveRow/Stars/Star3,
]
@onready var count_label : Label = (
	$Interface/AlertPanel/MarginContainer/Content/ObjectiveRow/CountLabel
)
@onready var status_label : Label = (
	$Interface/AlertPanel/MarginContainer/Content/StatusRow/StatusLabel
)
@onready var status_icon : TextureRect = (
	$Interface/AlertPanel/MarginContainer/Content/StatusRow/StatusIcon
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
	for star_index : int in range(star_icons.size()):
		var is_available := star_index < maximum_count
		var is_filled := star_index < current_count
		star_icons[star_index].visible = is_available
		star_icons[star_index].texture = STAR_FILLED if is_filled else STAR_EMPTY
		star_icons[star_index].self_modulate = (
			Color(1.0, 0.76, 0.22, 1.0)
			if is_filled
			else Color(0.42, 0.56, 0.7, 0.76)
		)
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
		status_icon.texture = WATCH_ICON
		status_icon.self_modulate = Color(0.55, 0.65, 0.76, 0.9)
	elif PhotoAlertSystem.is_observed_by_photographer():
		new_mode = &"observed"
		status_label.text = "OBSERVADO"
		status_icon.texture = WARNING_ICON
		status_icon.self_modulate = Color(1.0, 0.46, 0.24, 1.0)
	else:
		new_mode = &"hidden"
		status_icon.texture = WATCH_ICON
		status_icon.self_modulate = Color(0.35, 0.82, 1.0, 0.95)
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
