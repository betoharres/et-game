extends Node

signal photo_count_changed(current_count : int, maximum_count : int)
signal incident_reported(world_position : Vector3)
signal police_response_requested(photographer_id : int)
signal swat_response_requested(source_id : int)
signal reporter_van_response_requested(photographer_id : int)
signal additional_photographers_requested(photographer_id : int)
signal mib_response_requested(photographer_id : int)

const MAX_PHOTO_COUNT : int = 3
const HIDDEN_SECONDS_PER_PHOTO : float = 30.0

@export_range(0, 3) var stars_per_photo : int = 1
@export_range(0, 3) var stars_per_theft : int = 1
@export_range(1.0, 300.0, 1.0) var hidden_seconds_per_star : float = HIDDEN_SECONDS_PER_PHOTO

var photo_count : int = 0
var hidden_time : float = 0.0
var _photographer_observation : Dictionary = {}
var _pursuer_observation : Dictionary[int, bool] = {}
var _reported_thefts : Dictionary[int, bool] = {}


func _process(delta : float) -> void:
	if photo_count <= 0:
		hidden_time = 0.0
		return

	if is_observed():
		hidden_time = 0.0
		return

	hidden_time += delta

	var decay_seconds : float = maxf(hidden_seconds_per_star, 1.0)
	while hidden_time >= decay_seconds and photo_count > 0:
		hidden_time -= decay_seconds
		_set_photo_count(photo_count - 1)


func register_photo(photographer_id : int = 0, world_position : Vector3 = Vector3.INF) -> int:
	return _register_incident(stars_per_photo, photographer_id, world_position)


func register_theft(item : Node3D, world_position : Vector3) -> int:
	if not is_instance_valid(item) or _reported_thefts.has(item.get_instance_id()):
		return photo_count
	_reported_thefts[item.get_instance_id()] = true
	return _register_incident(stars_per_theft, item.get_instance_id(), world_position)


func _register_incident(stars : int, source_id : int, world_position : Vector3) -> int:
	if stars <= 0:
		return photo_count
	hidden_time = 0.0
	if world_position.is_finite():
		incident_reported.emit(world_position)
	var previous_count : int = photo_count
	_set_photo_count(photo_count + stars)
	for level : int in range(previous_count + 1, photo_count + 1):
		_activate_response_for_level(level, source_id)
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


func set_pursuer_observing(pursuer_id : int, observing : bool) -> void:
	if observing:
		_pursuer_observation[pursuer_id] = true
		hidden_time = 0.0
	else:
		_pursuer_observation.erase(pursuer_id)


func is_observed() -> bool:
	return is_observed_by_photographer() or not _pursuer_observation.is_empty()


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
	if photo_count <= 0 or is_observed():
		return hidden_seconds_per_star

	return maxf(hidden_seconds_per_star - hidden_time, 0.0)


func reset() -> void:
	hidden_time = 0.0
	_photographer_observation.clear()
	_pursuer_observation.clear()
	_reported_thefts.clear()
	_set_photo_count(0)


func request_police_response(photographer_id : int = 0) -> void:
	police_response_requested.emit(photographer_id)


func request_reporter_van_response(photographer_id : int = 0) -> void:
	reporter_van_response_requested.emit(photographer_id)


func request_additional_photographers(photographer_id : int = 0) -> void:
	additional_photographers_requested.emit(photographer_id)


func request_mib_response(photographer_id : int = 0) -> void:
	mib_response_requested.emit(photographer_id)


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
			swat_response_requested.emit(photographer_id)
			request_reporter_van_response(photographer_id)
			request_additional_photographers(photographer_id)
		3:
			request_mib_response(photographer_id)
