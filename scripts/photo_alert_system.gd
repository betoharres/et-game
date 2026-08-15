extends Node

signal photo_count_changed(current_count : int, maximum_count : int)
signal police_response_requested(photographer_id : int)
signal reporter_van_response_requested(photographer_id : int)
signal additional_photographers_requested(photographer_id : int)
signal mib_response_requested(photographer_id : int)

const MAX_PHOTO_COUNT : int = 3
const HIDDEN_SECONDS_PER_PHOTO : float = 30.0

var photo_count : int = 0
var hidden_time : float = 0.0
var _photographer_observation : Dictionary = {}


func _process(delta : float) -> void:
	if photo_count <= 0:
		hidden_time = 0.0
		return

	if is_observed_by_photographer():
		hidden_time = 0.0
		return

	hidden_time += delta

	while hidden_time >= HIDDEN_SECONDS_PER_PHOTO and photo_count > 0:
		hidden_time -= HIDDEN_SECONDS_PER_PHOTO
		_set_photo_count(photo_count - 1)


func register_photo(photographer_id : int = 0) -> int:
	hidden_time = 0.0

	if photo_count >= MAX_PHOTO_COUNT:
		return photo_count

	_set_photo_count(photo_count + 1)
	_activate_response_for_level(photo_count, photographer_id)
	return photo_count


func set_photographer_observing(
	photographer_id : int,
	is_observing : bool
) -> void:
	_photographer_observation[photographer_id] = is_observing

	if is_observing:
		hidden_time = 0.0


func unregister_photographer(photographer_id : int) -> void:
	_photographer_observation.erase(photographer_id)


func is_observed_by_photographer() -> bool:
	for observation : Variant in _photographer_observation.values():
		if bool(observation):
			return true

	return false


func get_photo_count() -> int:
	return photo_count


func get_max_photo_count() -> int:
	return MAX_PHOTO_COUNT


func get_seconds_until_photo_decay() -> float:
	if photo_count <= 0 or is_observed_by_photographer():
		return HIDDEN_SECONDS_PER_PHOTO

	return maxf(HIDDEN_SECONDS_PER_PHOTO - hidden_time, 0.0)


func reset() -> void:
	hidden_time = 0.0
	_photographer_observation.clear()
	_set_photo_count(0)


func request_police_response(photographer_id : int = 0) -> void:
	police_response_requested.emit(photographer_id)
	print(
		"PhotoAlertSystem: resposta policial solicitada pelo fotógrafo ",
		photographer_id,
		" (placeholder; nenhuma viatura criada)."
	)


func request_reporter_van_response(photographer_id : int = 0) -> void:
	reporter_van_response_requested.emit(photographer_id)
	print(
		"PhotoAlertSystem: van de reportagem solicitada pelo fotógrafo ",
		photographer_id,
		" (placeholder; nenhuma van criada)."
	)


func request_additional_photographers(photographer_id : int = 0) -> void:
	additional_photographers_requested.emit(photographer_id)
	print(
		"PhotoAlertSystem: fotógrafos adicionais solicitados por ",
		photographer_id,
		" (placeholder; nenhum NPC adicional criado)."
	)


func request_mib_response(photographer_id : int = 0) -> void:
	mib_response_requested.emit(photographer_id)
	print(
		"PhotoAlertSystem: resposta MIB solicitada pelo fotógrafo ",
		photographer_id,
		" (placeholder; nenhum agente criado)."
	)


func _set_photo_count(value : int) -> void:
	var new_count : int = clampi(value, 0, MAX_PHOTO_COUNT)

	if new_count == photo_count:
		return

	photo_count = new_count

	if photo_count <= 0:
		hidden_time = 0.0

	photo_count_changed.emit(photo_count, MAX_PHOTO_COUNT)


func _activate_response_for_level(level : int, photographer_id : int) -> void:
	match level:
		1:
			request_police_response(photographer_id)
		2:
			request_reporter_van_response(photographer_id)
			request_additional_photographers(photographer_id)
		3:
			request_mib_response(photographer_id)
