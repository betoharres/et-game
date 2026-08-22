extends Node3D

@onready var plane : RigidBody3D = $".."
@onready var target_arm : Node3D = $"../AimTargetArm"

@export var rotation_speed : float = 5.0

func _ready() -> void:

	if plane == null:
		push_error("CameraArm: Plane not found.")
		return

	if target_arm == null:
		push_error("CameraArm: TargetArm not found.")
		return


func _process(delta : float) -> void:

	if plane == null or target_arm == null:
		return

	# Follow the plane's position only.
	global_position = plane.global_position

	# Follow the TargetArm's rotation.
	#global_rotation = global_rotation.lerp(
		#target_arm.global_rotation,
		#delta * rotation_speed
	#)
	# Lerp() fucks up on -180 to +180 transitions
	
	global_rotation.x = lerp_angle(
		global_rotation.x,
		target_arm.global_rotation.x,
		delta * rotation_speed
	)
	
	global_rotation.y = lerp_angle(
		global_rotation.y,
		target_arm.global_rotation.y,
		delta * rotation_speed
	)
	
	global_rotation.z = lerp_angle(
		global_rotation.z,
		target_arm.global_rotation.z,
		delta * rotation_speed
	)
