class_name NPCActivity
extends Marker3D

## Vagas explícitas: cada pessoa reserva um lugar antes de sair para ele.
@export var activity: StringName = &"observe"
@export var duration_min: float = 12.0
@export var duration_max: float = 30.0
@export var slots: PackedVector3Array = PackedVector3Array([Vector3.ZERO])
var _occupants: Dictionary[int, WeakRef] = {}


func reserve(actor: Node) -> int:
	for index: int in slots.size():
		if _occupants.has(index) and _occupants[index].get_ref() == actor:
			return index
	for index: int in slots.size():
		if not _occupants.has(index) or _occupants[index].get_ref() == null:
			_occupants[index] = weakref(actor)
			return index
	return -1


func release(actor: Node) -> void:
	for index: int in _occupants.keys():
		if _occupants[index].get_ref() == null or _occupants[index].get_ref() == actor:
			_occupants.erase(index)


func destination(index: int) -> Vector3:
	return to_global(slots[index])
