extends RigidBody3D


@export var item_id : String = "item"
@export var score_value : int = 10

var carried : bool = false
var carrier : Node3D = null

func pickup(player : Node3D) -> void:

	if carried:
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

	if not carried:
		return

	carried = false

	var world_position : Vector3 = global_position

	reparent(get_tree().current_scene)

	global_position = world_position

	freeze = false

	carrier = null
