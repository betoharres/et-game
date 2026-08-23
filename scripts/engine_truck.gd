extends Node3D

@onready var engine : MeshInstance3D = $SM_Veh_Pickup_01_Engine
@onready var hood : MeshInstance3D = $SM_Veh_Pickup_01_Hood

var stolen : bool = false
var open : bool = false

func open_hood() -> void:
	if open == false:
		hood.rotation_degrees.x = lerp_angle(0.0, 33.0, 1.0)
		open = true
	elif open == true:
		hood.rotation_degrees.x = lerp_angle(33.0, 0.0, 1.0)
		open = false

func steal_engine() -> void:
	if open == true:
		if stolen == false:
			engine.visible = false
			stolen = true
			print("Os ETs conseguiram o motor.")
		elif stolen == true:
			return
	elif open == false:
		return

func try_open_hood() -> void:
	var characters : Array[Node] = get_tree().get_nodes_in_group("characters")

	var closest_player : CharacterBody3D = null
	var closest_distance : float = 4.0

	for character in characters:
		if not character is CharacterBody3D:
			continue

		var distance : float = global_position.distance_to(	character.global_position)

		if distance < closest_distance:
			closest_distance = distance
			closest_player = character

	if closest_player == null:
		return

	open_hood()
	steal_engine()
