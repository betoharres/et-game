extends Node3D

@export var interaction_radius : float = 1.5
@export var bend_strength : float = 25.0
@export var vehicle_bend_multiplier : float = 10.0
@export var return_speed : float = 5.0

@export var wind_strength : float = 1.0
@export var wind_speed : float = 1.5

var sunflowers : Array[Node3D] = []
var original_rotations : Dictionary = {}


func _ready() -> void:
	for child in get_children():
		if child is Node3D:
			sunflowers.append(child)
			original_rotations[child] = child.rotation


func _process(delta : float) -> void:
	var characters : Array[Node] = get_tree().get_nodes_in_group("characters")
	var vehicles : Array[Node] = get_tree().get_nodes_in_group("vehicles")

	var time : float = Time.get_ticks_msec() / 1000.0

	for i in range(sunflowers.size()):
		var sunflower : Node3D = sunflowers[i]

		if not is_instance_valid(sunflower):
			continue

		var original_rotation : Vector3 = original_rotations[sunflower]

		var strongest_bend : float = 0.0
		var strongest_direction : Vector3 = Vector3.ZERO


		# Characters

		for character in characters:
			if not character is CharacterBody3D:
				continue

			var direction : Vector3 = (
				sunflower.global_position
				- character.global_position
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
				sunflower.global_position
				- vehicle.global_position
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


		# Apply bending

		var target_rotation : Vector3 = original_rotation

		if strongest_bend > 0.0:
			var local_direction : Vector3 = (
				sunflower.global_transform.basis.inverse()
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


		# Wind

		var wind_offset : float = (
			sin(time * wind_speed + i * 1.73)
			* wind_strength
		)

		target_rotation.z += deg_to_rad(wind_offset)


		sunflower.rotation = sunflower.rotation.lerp(
			target_rotation,
			delta * return_speed
		)
