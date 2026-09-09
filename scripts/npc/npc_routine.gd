class_name NPCRoutine
extends Node

## Circuito pessoal. Interrupções liberam a vaga, mas preservam o próximo destino.
@export var activity_paths: Array[NodePath] = []
@export var start_index: int = 0
@export var refuge_path: NodePath
var _activities: Array[NPCActivity] = []
var _current: NPCActivity
var _slot: int = -1
var _index: int = 0
var _remaining: float = -1.0
var _retry: float = 0.0
var _travel_time: float = 0.0
var _partner: NPCActor
var _social_timer: float = 0.0
@onready var actor: NPCActor = get_parent() as NPCActor


func _ready() -> void:
	for path: NodePath in activity_paths:
		var point: NPCActivity = get_node_or_null(path) as NPCActivity
		if point != null:
			_activities.append(point)
	_index = start_index % maxi(1, _activities.size())


func _exit_tree() -> void:
	interrupt()


func interrupt() -> void:
	_partner = null
	if is_instance_valid(_current):
		_current.release(actor)
	_current = null
	_slot = -1
	_remaining = -1.0
	_travel_time = 0.0


func tick(delta: float) -> void:
	if _activities.is_empty():
		actor.stop_moving()
		return
	_retry -= delta
	if _current == null:
		if _retry > 0.0:
			actor.stop_moving()
			return
		for offset: int in _activities.size():
			var candidate_index: int = (_index + offset) % _activities.size()
			var candidate: NPCActivity = _activities[candidate_index]
			var slot: int = candidate.reserve(actor)
			if slot >= 0:
				_current = candidate
				_slot = slot
				_index = candidate_index
				break
		if _current == null:
			_retry = randf_range(2.0, 5.0)
			actor.stop_moving()
			return
	if _remaining < 0.0:
		actor.set_state(&"patrol")
		_travel_time += delta
		var arrived: bool = actor.move_toward_point(_current.destination(_slot), actor.walk_speed)
		if actor.navigation_failed or _travel_time > 180.0:
			_advance()
			_retry = randf_range(2.0, 5.0)
			return
		if not arrived:
			return
		_remaining = randf_range(_current.duration_min, _current.duration_max)
	actor.set_state(_current.activity)
	actor.stop_moving()
	actor.face_direction(_current.global_basis.z)
	_social_timer -= delta
	if actor.can_socialize:
		_socialize()
	_remaining -= delta
	if _remaining <= 0.0:
		_advance()


func _socialize() -> void:
	if is_instance_valid(_partner) and _partner.routine != null and _partner.routine._remaining > 0.0 and actor.global_position.distance_to(_partner.global_position) < actor.chat_radius:
		actor.set_state(&"social")
		actor.face_direction(_partner.global_position - actor.global_position)
		return
	_partner = null
	if _social_timer > 0.0:
		return
	_social_timer = randf_range(4.0, 8.0)
	for candidate: Node in get_tree().get_nodes_in_group(&"npc_actors"):
		var other: NPCActor = candidate as NPCActor
		if other == actor or other == null or not other.can_socialize or other.routine == null:
			continue
		if other.routine._remaining <= 0.0 or is_instance_valid(other.routine._partner):
			continue
		if actor.global_position.distance_to(other.global_position) < actor.chat_radius:
			_partner = other
			other.routine._partner = actor
			break


func _advance() -> void:
	interrupt()
	_index = (_index + 1) % maxi(1, _activities.size())


func refuge(threat: Vector3) -> Vector3:
	var home: Node3D = get_node_or_null(refuge_path) as Node3D if not refuge_path.is_empty() else null
	if home != null and home.global_position.distance_to(threat) > 8.0:
		return home.global_position
	var best: Vector3 = actor.global_position
	var distance: float = best.distance_to(threat)
	for point: NPCActivity in _activities:
		if point.global_position.distance_to(threat) > distance:
			best = point.global_position
			distance = best.distance_to(threat)
	return best
