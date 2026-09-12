class_name DebrisLocator
extends RefCounted

const DIRECTIONS : Array[String] = ["↑", "↗", "→", "↘", "↓", "↙", "←", "↖"]
const DISTANCE_BANDS : Array[float] = [120.0, 60.0, 25.0, 8.0]
const SECTOR_SIZE : float = PI / 4.0
const ANGULAR_MARGIN : float = PI / 30.0
const DISTANCE_MARGIN : float = 0.08

var _target_id : int = 0
var _sector : int = -1
var _strength : int = 0


static func scan(character : Node3D) -> Dictionary:
	return DebrisLocator.new().sample(character)


func reset() -> void:
	_target_id = 0
	_sector = -1
	_strength = 0


func sample(character : Node3D) -> Dictionary:
	if not is_instance_valid(character) or not character.is_inside_tree():
		return _no_signal()
	var nearest : AlienDebris = null
	var distance_squared : float = INF
	for node : Node in character.get_tree().get_nodes_in_group("alien_debris"):
		var debris : AlienDebris = node as AlienDebris
		if debris == null or debris.is_queued_for_deletion() or debris.state != AlienTechnologyItem.State.WORLD:
			continue
		var candidate_distance : float = character.global_position.distance_squared_to(debris.global_position)
		if candidate_distance < distance_squared:
			distance_squared = candidate_distance
			nearest = debris
	if nearest == null:
		return _no_signal()
	if nearest.get_instance_id() != _target_id:
		reset()
		_target_id = nearest.get_instance_id()
	var distance : float = sqrt(distance_squared)
	_update_strength(distance)
	var offset : Vector3 = nearest.global_position - character.global_position
	var up : Vector3 = character.global_basis.y.normalized()
	var forward : Vector3 = character.global_basis.z.slide(up).normalized()
	# +Z é a frente do ET; a direita visual é -X nesse referencial.
	var right : Vector3 = forward.cross(up).normalized()
	var angle : float = atan2(offset.dot(right), offset.dot(forward))
	# Zona morta nas bordas evita oscilação quando o ET está quase parado.
	if _sector < 0 or absf(wrapf(angle - float(_sector) * SECTOR_SIZE, -PI, PI)) > SECTOR_SIZE * 0.5 + ANGULAR_MARGIN:
		_sector = wrapi(roundi(angle / SECTOR_SIZE), 0, 8)
	# Saturação perto do objeto preserva a busca visual; altura não vira seta falsa.
	var nearby : bool = _strength == 5
	var directional : bool = not nearby and offset.slide(up).length_squared() > 1.0
	return {
		"strength": _strength,
		"direction": DIRECTIONS[_sector] if directional else "",
		"sector": _sector if directional else -1,
		"nearby": nearby,
	}


func _update_strength(distance : float) -> void:
	if _strength == 0:
		_strength = 1
		for threshold : float in DISTANCE_BANDS:
			if distance < threshold:
				_strength += 1
		return
	while _strength < 5 and distance < DISTANCE_BANDS[_strength - 1] * (1.0 - DISTANCE_MARGIN):
		_strength += 1
	while _strength > 1 and distance > DISTANCE_BANDS[_strength - 2] * (1.0 + DISTANCE_MARGIN):
		_strength -= 1


func _no_signal() -> Dictionary:
	reset()
	return {"strength": 0, "direction": "", "sector": -1, "nearby": false}
