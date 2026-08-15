extends Node3D


@onready var target_legL : Marker3D = $FootL
@onready var target_legR : Marker3D = $FootR

@onready var step_L : Marker3D = $StepL
@onready var step_R : Marker3D = $StepR


@export var step_distance : float = 0.5
@export var step_height : float = 0.2
@export var step_speed : float = 5.0
@export var minimum_walk_speed : float = 0.01


var stepping_L : bool = false
var stepping_R : bool = false

var step_start_L : Vector3
var step_start_R : Vector3

var step_target_L : Vector3
var step_target_R : Vector3

var step_progress_L : float = 0.0
var step_progress_R : float = 0.0


func _physics_process(delta : float) -> void:

	var parent_character : CharacterBody3D = get_parent() as CharacterBody3D

	if parent_character == null:
		return

	update_feet_IK(parent_character.velocity, delta)


func update_feet_IK(character_velocity : Vector3, delta : float) -> void:

	var horizontal_velocity : Vector3 = Vector3(
		character_velocity.x,
		0.0,
		character_velocity.z
	)

	var movement_speed : float = horizontal_velocity.length()

	if movement_speed < minimum_walk_speed:
		return


	var distance_L : float = (
		target_legL.global_position.distance_to(step_L.global_position)
	)

	var distance_R : float = (
		target_legR.global_position.distance_to(step_R.global_position)
	)


	# Start a step only when both feet are planted.

	if not stepping_L and not stepping_R:

		if distance_L > step_distance:

			stepping_L = true

			step_start_L = target_legL.position
			step_target_L = step_L.position

			step_progress_L = 0.0

		elif distance_R > step_distance:

			stepping_R = true

			step_start_R = target_legR.position
			step_target_R = step_R.position

			step_progress_R = 0.0


	# Left foot

	if stepping_L:

		step_progress_L += delta * step_speed

		step_progress_L = minf(
			step_progress_L,
			1.0
		)

		var t : float = step_progress_L

		var new_position : Vector3 = (
			step_start_L.lerp(
				step_target_L,
				t
			)
		)

		new_position.y += (
			sin(t * PI)
			* step_height
		)

		target_legL.position = new_position

		if step_progress_L >= 1.0:

			target_legL.position = step_target_L

			stepping_L = false


	# Right foot

	elif stepping_R:

		step_progress_R += delta * step_speed

		step_progress_R = minf(
			step_progress_R,
			1.0
		)

		var t : float = step_progress_R

		var new_position : Vector3 = (
			step_start_R.lerp(
				step_target_R,
				t
			)
		)

		new_position.y += (
			sin(t * PI)
			* step_height
		)

		target_legR.position = new_position

		if step_progress_R >= 1.0:

			target_legR.position = step_target_R

			stepping_R = false
