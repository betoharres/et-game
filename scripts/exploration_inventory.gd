extends Node

signal changed
signal feedback(message : String)

@export_range(1, 16) var capacity : int = 4

var items : Array[RigidBody3D] = []
var selected_slot : int = 0
var _slots : Array[RigidBody3D] = []


func item_at(slot : int) -> RigidBody3D:
	_slots.resize(capacity)
	return _slots[slot] if slot >= 0 and slot < capacity else null


func select_slot(slot : int) -> void:
	selected_slot = wrapi(slot, 0, capacity)
	changed.emit()


func cycle_slot(direction : int) -> void:
	select_slot(selected_slot + direction)


func drop_selected(player : Node3D) -> void:
	var item : RigidBody3D = item_at(selected_slot)
	if is_instance_valid(item):
		_drop_item(item, player)


func used_slots() -> int:
	var used : int = 0
	for item : RigidBody3D in items:
		if is_instance_valid(item):
			used += int(item.get("slot_cost"))
	return used


func store_item(item : RigidBody3D, player : Node3D) -> bool:
	if not item.has_method("store_in_inventory") or items.has(item):
		return false
	if bool(item.get("two_handed")):
		return false
	var cost : int = maxi(1, int(item.get("slot_cost")))
	if used_slots() + cost > capacity:
		feedback.emit("Sem espaço: este objeto precisa de %d slots." % cost)
		return false
	if not bool(item.call("store_in_inventory", player)):
		return false
	_slots.resize(capacity)
	var remaining : int = cost
	for slot : int in range(capacity):
		if not is_instance_valid(_slots[slot]):
			_slots[slot] = item
			remaining -= 1
			if remaining == 0:
				break
	items.append(item)
	item.tree_exiting.connect(_on_item_exiting.bind(item), CONNECT_ONE_SHOT)
	changed.emit()
	return true


func drop_last(player : Node3D) -> void:
	if items.is_empty():
		return
	_drop_item(items.back(), player)


func _drop_item(item : RigidBody3D, player : Node3D) -> void:
	# Reparentar em drop emite tree_exiting e remove a referência do inventário.
	item.global_position = player.global_position + player.global_basis.z * 1.2 + player.global_basis.y * 0.3
	item.call("drop")


func _on_item_exiting(item : RigidBody3D) -> void:
	items.erase(item)
	for slot : int in range(_slots.size()):
		if _slots[slot] == item:
			_slots[slot] = null
	changed.emit()
