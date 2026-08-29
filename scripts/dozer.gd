extends Node3D

# Keep files only while subscrition is active
@onready var trackL : MeshInstance3D = $SM_Veh_Bulldozer_01/SM_Veh_Bulldozer_01/SM_Veh_Bulldozer_01_Track_l
@onready var trackR : MeshInstance3D = $SM_Veh_Bulldozer_01/SM_Veh_Bulldozer_01/SM_Veh_Bulldozer_01_Track_r

@onready var wheel1L : MeshInstance3D = $SM_Veh_Bulldozer_01/SM_Veh_Bulldozer_01/SM_Veh_Bulldozer_01_Track_Wheel_rl
@onready var wheel2L : MeshInstance3D = $SM_Veh_Bulldozer_01/SM_Veh_Bulldozer_01/SM_Veh_Bulldozer_01_Track_Wheel_ml
@onready var wheel3L : MeshInstance3D = $SM_Veh_Bulldozer_01/SM_Veh_Bulldozer_01/SM_Veh_Bulldozer_01_Track_Wheel_fl

@onready var wheel1R : MeshInstance3D = $SM_Veh_Bulldozer_01/SM_Veh_Bulldozer_01/SM_Veh_Bulldozer_01_Track_Wheel_rr
@onready var wheel2R : MeshInstance3D = $SM_Veh_Bulldozer_01/SM_Veh_Bulldozer_01/SM_Veh_Bulldozer_01_Track_Wheel_mr
@onready var wheel3R : MeshInstance3D = $SM_Veh_Bulldozer_01/SM_Veh_Bulldozer_01/SM_Veh_Bulldozer_01_Track_Wheel_fr

@export var track_speed : float = 1.0

func _physics_process(delta : float) -> void:

	var forward_input : float = Input.get_axis("ui_down", "ui_up")
	var steering_input : float = Input.get_axis("ui_left", "ui_right")

	var left_power : float = 0.0
	var right_power : float = 0.0

	# --------------------------------------------------------
	# Moving forward / backward
	# --------------------------------------------------------

	if abs(forward_input) > 0.0:
		var direction : float = sign(forward_input)

		left_power = (forward_input + steering_input * direction) / 2.0
		right_power = (forward_input - steering_input * direction) / 2.0

	# --------------------------------------------------------
	# Pivot turning
	# --------------------------------------------------------

	elif abs(steering_input) > 0.0:

		left_power = steering_input / 2.0
		right_power = -steering_input / 2.0
		
	# --------------------------------------------------------
	# Track materials
	# --------------------------------------------------------

	var matL : StandardMaterial3D = (
		trackL.get_surface_override_material(0)
		as StandardMaterial3D
	)

	var matR : StandardMaterial3D = (
		trackR.get_surface_override_material(0)
		as StandardMaterial3D
	)

	# --------------------------------------------------------
	# Animate tracks
	# --------------------------------------------------------

	if matL:
		matL.uv1_offset.y += (left_power * track_speed * delta)
		wheel1L.rotation.x += (left_power / 0.590) * delta
		wheel2L.rotation.x += (left_power / 0.431) * delta
		wheel3L.rotation.x += (left_power / 0.604) * delta
		
	if matR:
		matR.uv1_offset.y += (right_power * track_speed * delta)
		wheel1R.rotation.x += (right_power / 0.590) * delta
		wheel2R.rotation.x += (right_power / 0.431) * delta
		wheel3R.rotation.x += (right_power / 0.604) * delta
