extends RigidBody3D

@onready var target : Marker3D = $AimTargetArm/AimTarget
@onready var prop : MeshInstance3D = $SM_Veh_Plane_Stunt_01/SM_Veh_Plane_Stunt_01/SM_Veh_Plane_Stunt_01_Prop

# ============================================================
# ENGINE
# ============================================================

@export var engine_force : float = 15000.0


# ============================================================
# LIFT
# ============================================================
@export var lift_coefficient : float = 20.0


# ============================================================
# FLIGHT CONTROL
# ============================================================

@export var pitch_strength : float = 800.0
@export var roll_strength : float = 2000.0

@export var max_pitch_angle : float = 35.0
@export var max_roll_angle : float = 45.0


# ============================================================
# AUTO LEVEL
# ============================================================

@export var auto_level_strength : float = 5.0


func _physics_process(_delta : float) -> void:

	if target == null:
		return

	apply_engine()
	apply_lift()
	apply_roll()
	apply_pitch()
	

# ============================================================
# ENGINE
# ============================================================

func apply_engine() -> void:

	var forward : Vector3 = -global_transform.basis.z

	apply_central_force(
		forward * engine_force
	)
	
	prop.rotation.z += 0.9


# ============================================================
# LIFT
# ============================================================

func apply_lift() -> void:

	var forward_speed : float = -linear_velocity.dot(
		global_transform.basis.z
	)

	forward_speed = maxf(forward_speed, 0.0)

	apply_central_force(
		global_transform.basis.y * lift_coefficient
	)

	print("Velocity: ", linear_velocity," | Speed: ", linear_velocity.length(),
		" | Lift: ", global_transform.basis.y * lift_coefficient)

# ============================================================
# PITCH
# ============================================================

func apply_pitch() -> void:

	var targetMarker : Vector3 = get_aim_target_position()

	var direction : Vector3 = (
		targetMarker - global_position
	).normalized()

	# Convert target direction into plane-local space.

	var local_direction : Vector3 = (
		global_transform.basis.inverse()
		* direction
	)

	# Positive Y means target is above us.
	var pitch_error : float = asin(
		clampf(
			local_direction.y,
			-1.0,
			1.0
		)
	)

	pitch_error = clampf(
		pitch_error,
		-deg_to_rad(max_pitch_angle),
		deg_to_rad(max_pitch_angle)
	)

	# Local X rotation controls pitch.
	var pitch_torque : float = (
		-pitch_error
		* pitch_strength
	)

	apply_torque(
		global_transform.basis.x
		* pitch_torque
	)


# ============================================================
# ROLL
# ============================================================

func apply_roll() -> void:

	var targetMarker2 : Vector3 = get_aim_target_position()

	var direction : Vector3 = (
		targetMarker2 - global_position
	).normalized()

	# Convert target direction into plane-local space.

	var local_direction : Vector3 = (
		global_transform.basis.inverse()
		* direction
	)

	# Target is to the right/left of the aircraft.
	var horizontal_error : float = atan2(
		local_direction.x,
		-local_direction.z
	)

	horizontal_error = clampf(
		horizontal_error,
		-deg_to_rad(max_roll_angle),
		deg_to_rad(max_roll_angle)
	)

	# We want to bank toward the target.
	var target_roll : float = -horizontal_error

	# --------------------------------------------------------
	# Current roll
	# --------------------------------------------------------

	var current_up : Vector3 = global_transform.basis.y

	var roll_error : float = atan2(
		current_up.x,
		current_up.y
	)

	# --------------------------------------------------------
	# Roll control
	# --------------------------------------------------------

	var roll_torque : float = (
		target_roll
		- roll_error
	) * roll_strength

	apply_torque(
		global_transform.basis.z
		* roll_torque
	)

	# --------------------------------------------------------
	# Auto-level
	# --------------------------------------------------------

	# When the target is roughly straight ahead,
	# progressively return the aircraft toward level.

	var target_alignment : float = (
		1.0 - clampf(
			abs(horizontal_error) / deg_to_rad(45.0),
			0.0,
			1.0
		)
	)

	var level_torque : float = (
		-roll_error
		* auto_level_strength
		* target_alignment
	)

	apply_torque(
		global_transform.basis.z
		* level_torque
	)


# ============================================================
# AIM
# ============================================================

func get_aim_target_position() -> Vector3:

	return target.global_position
