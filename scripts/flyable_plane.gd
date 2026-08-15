extends RigidBody3D

# ============================================================
# Aim target
# ============================================================

@onready var aim_target_arm : Node3D = $AimTargetArm

@export var aim_mouse_sensitivity : float = 0.003
@export var aim_pitch_min : float = -60.0
@export var aim_pitch_max : float = 60.0

var aim_yaw : float = 0.0
var aim_pitch : float = 0.0


# ============================================================
# Nodes
# ============================================================

@onready var camera_arm : Node3D = $CameraArm
@onready var camera : Camera3D = $CameraArm/Camera3D
@onready var aim_target : Marker3D = $AimTargetArm/AimTarget


# ============================================================
# Engine
# ============================================================

@export var engine_force : float = 1500.0


# ============================================================
# Flight
# ============================================================

@export var pitch_speed : float = 1.5
@export var yaw_speed : float = 1.0
@export var roll_speed : float = 2.0

@export var rotation_response : float = 3.0


# ============================================================
# Camera
# ============================================================

@export var camera_distance : float = 12.0
@export var camera_height : float = 3.0

@export var camera_smooth_speed : float = 5.0


# ============================================================
# Physics
# ============================================================

@export var gravity_strength : float = 1.0


# ============================================================
# Main loop
# ============================================================

func _ready() -> void:

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
func _input(event : InputEvent) -> void:

	if event is InputEventMouseMotion:

		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:

			var mouse_motion : Vector2 = event.relative

			aim_yaw -= mouse_motion.x * aim_mouse_sensitivity
			aim_pitch -= mouse_motion.y * aim_mouse_sensitivity

			aim_pitch = clampf(
				aim_pitch,
				deg_to_rad(aim_pitch_min),
				deg_to_rad(aim_pitch_max)
			)

	if event.is_action_pressed("ui_cancel"):

		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta : float) -> void:

	update_aim(delta)

	update_flight(delta)

	update_camera(delta)


# ============================================================
# AIM
# ============================================================

func update_aim(delta : float) -> void:

	aim_target_arm.global_position = global_position

	var target_rotation : Vector3 = Vector3(
		aim_pitch,
		global_rotation.y + aim_yaw,
		0.0
	)

	aim_target_arm.global_rotation = aim_target_arm.global_rotation.lerp(
		target_rotation,
		delta * 10.0
	)

func get_aim_target_position() -> Vector3:

	return aim_target.global_position


# ============================================================
# FLIGHT
# ============================================================

func update_flight(delta : float) -> void:

	var target_position : Vector3 = get_aim_target_position()

	var flight_input : Vector3 = calculate_flight_input(target_position)

	apply_flight_physics(flight_input, delta)


func calculate_flight_input(target_position : Vector3) -> Vector3:

	var direction : Vector3 = (target_position - global_position).normalized()

	# Convert the desired world direction into the plane's
	# local coordinate system.

	var local_direction : Vector3 = (global_transform.basis.inverse()
	 * direction)

	# --------------------------------------------------------
	# Yaw
	# --------------------------------------------------------

	var yaw_input : float = (atan2(local_direction.x,-local_direction.z))

	# --------------------------------------------------------
	# Pitch
	# --------------------------------------------------------

	var pitch_input : float = (
		-asin(clampf(local_direction.y,-1.0,1.0))
		)

	# --------------------------------------------------------
	# Roll
	# --------------------------------------------------------
	#
	# For now, roll is based on yaw input.
	# This gives us a simple banking behavior.
	#

	var roll_input : float = -yaw_input


	return Vector3(
		pitch_input,
		yaw_input,
		roll_input
	)


func apply_flight_physics(flight_input : Vector3,delta : float) -> void:

	# --------------------------------------------------------
	# Engine
	# --------------------------------------------------------

	var forward : Vector3 = -global_transform.basis.z

	apply_central_force(forward * engine_force)


	# --------------------------------------------------------
	# Target angular velocity
	# --------------------------------------------------------

	var target_angular_velocity : Vector3 = Vector3(
		flight_input.x * pitch_speed,
		flight_input.y * yaw_speed,
		flight_input.z * roll_speed
	)


	# Convert local angular velocity to world space.

	var world_angular_velocity : Vector3 = (
		global_transform.basis
		* target_angular_velocity
	)


	angular_velocity = angular_velocity.lerp(
		world_angular_velocity,
		delta * rotation_response
	)


# ============================================================
# CAMERA
# ============================================================

func update_camera(delta : float) -> void:

	var desired_position : Vector3 = (
		global_position
		+ global_transform.basis.z * camera_distance
		+ Vector3.UP * camera_height
	)

	camera_arm.global_position = camera_arm.global_position.lerp(
		desired_position,
		delta * camera_smooth_speed
	)

	# Camera looks toward the plane.

	camera_arm.look_at(
		global_position,
		Vector3.UP
	)
