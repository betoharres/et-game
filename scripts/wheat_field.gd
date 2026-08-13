extends Node3D

@export var interaction_radius : float = 1.5
@export var bend_strength : float = 20.0
@export var vehicle_bend_multiplier : float = 10.0
@export var return_speed : float = 5.0

@export var wind_strength : float = 2.0
@export var wind_speed : float = 1.5

var wheat : Array[Node3D] = []
var original_rotations : Dictionary = {}


func _ready() -> void:
	for child in get_children():
		if child is Node3D:
			wheat.append(child)
			original_rotations[child] = child.rotation


func _process(delta : float) -> void:
	var characters : Array[Node] = get_tree().get_nodes_in_group("characters")
	var vehicles : Array[Node] = get_tree().get_nodes_in_group("vehicles")

	var time : float = Time.get_ticks_msec() / 1000.0

	for i in range(wheat.size()):
		var stalk : Node3D = wheat[i]

		if not is_instance_valid(stalk):
			continue

		var original_rotation : Vector3 = original_rotations[stalk]

		var strongest_bend : float = 0.0
		var strongest_direction : Vector3 = Vector3.ZERO

		# Characters

		for character in characters:
			if not character is CharacterBody3D:
				continue

			var direction : Vector3 = (
				stalk.global_position - character.global_position
			)

			direction.y = 0.0

			var distance : float = direction.length()

			if distance >= interaction_radius:
				continue

			var bend_amount : float = 1.0 - (
				distance / interaction_radius
			)

			bend_amount = bend_amount * bend_amount

			if bend_amount > strongest_bend:
				strongest_bend = bend_amount
				strongest_direction = direction.normalized()


		# Vehicles

		for vehicle in vehicles:
			if not vehicle is VehicleBody3D:
				continue

			var direction : Vector3 = (
				stalk.global_position - vehicle.global_position
			)

			direction.y = 0.0

			var distance : float = direction.length()

			if distance >= interaction_radius:
				continue

			var bend_amount : float = 1.0 - (
				distance * 1.5 / interaction_radius
			)

			bend_amount = bend_amount * bend_amount

			bend_amount *= vehicle_bend_multiplier

			if bend_amount > strongest_bend:
				strongest_bend = bend_amount
				strongest_direction = direction.normalized()


		var target_rotation : Vector3 = original_rotation

		if strongest_bend > 0.0:
			var local_direction : Vector3 = (
				stalk.global_transform.basis.inverse()
				* strongest_direction
			)

			target_rotation.x += (
				local_direction.z
				* strongest_bend
				* deg_to_rad(bend_strength)
			)

			target_rotation.z += (
				-local_direction.x
				* strongest_bend
				* deg_to_rad(bend_strength)
			)


		var wind_offset : float = (
			sin(time * wind_speed + i * 1.73)
			* wind_strength
		)

		target_rotation.x += deg_to_rad(wind_offset)

		stalk.rotation = stalk.rotation.lerp(
			target_rotation,
			delta * return_speed
		)
