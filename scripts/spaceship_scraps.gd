extends RigidBody3D


@export var item_id : String = "item"
@export var score_value : int = 10

var carried : bool = false
var carrier : Node3D = null
var being_abducted : bool = false

func pickup(player : Node3D) -> void:

	if carried or being_abducted:
		return

	carried = true
	carrier = player

	freeze = true

	reparent(player)

	var hand_target : Marker3D = (
		player.get_node("IKtargetContainer/HandR")
	)
	if hand_target:
		position = hand_target.position
	else:
		position = Vector3(0.0,1.0,1.0)
	
func drop() -> void:

	if not carried or being_abducted:
		return

	carried = false

	var world_position : Vector3 = global_position

	reparent(get_tree().current_scene)

	global_position = world_position

	freeze = false

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
