extends CanvasLayer

@onready var stars_label : Label = (
	$Interface/AlertPanel/MarginContainer/Content/StarsLabel
)
@onready var count_label : Label = (
	$Interface/AlertPanel/MarginContainer/Content/CountLabel
)
@onready var status_label : Label = (
	$Interface/AlertPanel/MarginContainer/Content/StatusLabel
)


func _ready() -> void:
	PhotoAlertSystem.photo_count_changed.connect(_on_photo_count_changed)
	_on_photo_count_changed(
		PhotoAlertSystem.get_photo_count(),
		PhotoAlertSystem.get_max_photo_count()
	)


func _process(_delta : float) -> void:
	var current_count : int = PhotoAlertSystem.get_photo_count()

	if current_count <= 0:
		status_label.text = "SEM EXPOSIÇÃO"
	elif PhotoAlertSystem.is_observed_by_photographer():
		status_label.text = "VOCÊ ESTÁ SENDO OBSERVADO"
	else:
		status_label.text = "OCULTO: REDUZ EM %ds" % ceili(
			PhotoAlertSystem.get_seconds_until_photo_decay()
		)


func _on_photo_count_changed(current_count : int, maximum_count : int) -> void:
	var stars_text : String = ""

	for star_index : int in range(maximum_count):
		stars_text += "★" if star_index < current_count else "☆"

		if star_index < maximum_count - 1:
			stars_text += "  "

	stars_label.text = stars_text
	count_label.text = "FOTOS  %d / %d" % [current_count, maximum_count]
