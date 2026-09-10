extends RigidBody3D


@export var item_id : String = "item"
@export var score_value : int = 10
@export var display_name : String = "Destroço"
@export_range(1, 4) var slot_cost : int = 1
@export var two_handed : bool = false

var _saved_collision_layer : int = 0
var _saved_collision_mask : int = 0
var _stored : bool = false

var carried : bool = false
var carrier : Node3D = null
var being_abducted : bool = false

func pickup(player : Node3D) -> void:

	if carried or being_abducted:
		return

	carried = true
	carrier = player

	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_saved_collision_layer = collision_layer
	_saved_collision_mask = collision_mask
	collision_layer = 0
	collision_mask = 0

	reparent(player)

	var hand_target : Marker3D = player.get_node_or_null("IKtargetContainer/HandR") as Marker3D
	if two_handed and player.has_node("CarrySocket"):
		position = player.get_node("CarrySocket").position
		rotation = Vector3.ZERO
	elif hand_target:
		position = hand_target.position
	else:
		position = Vector3(0.0, 1.0, 1.0)
	
func drop() -> void:

	if not carried or being_abducted:
		return

	carried = false

	var world_position : Vector3 = global_position

	reparent(get_tree().current_scene)

	global_position = world_position

	freeze = false
	collision_layer = _saved_collision_layer
	collision_mask = _saved_collision_mask
	if _stored:
		show()
		_stored = false

	carrier = null


func is_available_for_abduction() -> bool:
	return not carried and not being_abducted


func begin_abduction() -> bool:
	if not is_available_for_abduction():
		return false

	being_abducted = true
	freeze = true
	remove_from_group("pickup_items")
	return true


func store_in_inventory(player : Node3D) -> bool:
	if two_handed or carried or being_abducted:
		return false
	pickup(player)
	_stored = true
	hide()
	return true
